// Copyright (c) 2019, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:meta/meta.dart';

/// [AssignedVariables] is a helper class capable of computing the set of
/// variables that are potentially written to, and potentially captured by
/// closures, at various locations inside the code being analyzed.  This class
/// should be used prior to running flow analysis, to compute the sets of
/// variables to pass in to flow analysis.
///
/// This class is intended to be used in two phases.  In the first phase, the
/// client should traverse the source code recursively, making calls to
/// [beginNode] and [endNode] to indicate the constructs in which writes should
/// be tracked, and calls to [write] to indicate when a write is encountered.
/// The order of visiting is not important provided that nesting is respected.
/// This phase is called the "pre-traversal" because it should happen prior to
/// flow analysis.
///
/// Then, in the second phase, the client may make queries using
/// [capturedAnywhere], [writtenInNode], and [capturedInNode].
///
/// We use the term "node" to refer generally to a loop statement, switch
/// statement, try statement, loop collection element, local function, or
/// closure.
class AssignedVariables<Node, Variable> {
  /// Mapping from a node to the set of local variables that are potentially
  /// written to within that node.
  final Map<Node, Set<Variable>> _writtenInNode = {};

  /// Mapping from a node to the set of local variables for which a potential
  /// write is captured by a local function or closure inside that node.
  final Map<Node, Set<Variable>> _capturedInNode = {};

  /// Set of local variables that are potentially written to anywhere in the
  /// code being analyzed.
  final Set<Variable> _writtenAnywhere = {};

  /// Set of local variables for which a potential write is captured by a local
  /// function or closure anywhere in the code being analyzed.
  final Set<Variable> _capturedAnywhere = {};

  /// Stack of sets accumulating variables that are potentially written to.
  ///
  /// A set is pushed onto the stack when a node is entered, and popped when
  /// a node is left.
  final List<Set<Variable>> _writtenStack = [new Set<Variable>.identity()];

  /// Stack of sets accumulating variables that are declared.
  ///
  /// A set is pushed onto the stack when a node is entered, and popped when
  /// a node is left.
  final List<Set<Variable>> _declaredStack = [new Set<Variable>.identity()];

  /// Stack of sets accumulating variables for which a potential write is
  /// captured by a local function or closure.
  ///
  /// A set is pushed onto the stack when a node is entered, and popped when
  /// a node is left.
  final List<Set<Variable>> _capturedStack = [new Set<Variable>.identity()];

  AssignedVariables();

  /// This method should be called during pre-traversal, to mark the start of a
  /// loop statement, switch statement, try statement, loop collection element,
  /// local function, or closure which might need to be queried later.
  ///
  /// [isClosure] should be true if the node is a local function or closure.
  ///
  /// The span between the call to [beginNode] and [endNode] should cover any
  /// statements and expressions that might be crossed by a backwards jump.  So
  /// for instance, in a "for" loop, the condition, updaters, and body should be
  /// covered, but the initializers should not.  Similarly, in a switch
  /// statement, the body of the switch statement should be covered, but the
  /// switch expression should not.
  void beginNode() {
    _writtenStack.add(new Set<Variable>.identity());
    _declaredStack.add(new Set<Variable>.identity());
    _capturedStack.add(new Set<Variable>.identity());
  }

  /// This method should be called during pre-traversal, to indicate that the
  /// declaration of a variable has been found.
  ///
  /// It is not required for the declaration to be seen prior to its use (this
  /// is to allow for error recovery in the analyzer).
  void declare(Variable variable) {
    _declaredStack.last.add(variable);
  }

  /// This method should be called during pre-traversal, to mark the end of a
  /// loop statement, switch statement, try statement, loop collection element,
  /// local function, or closure which might need to be queried later.
  ///
  /// [isClosure] should be true if the node is a local function or closure.
  ///
  /// See [beginNode] for more details.
  void endNode(Node node, {bool isClosure: false}) {
    Set<Variable> declaredInThisNode = _declaredStack.removeLast();
    Set<Variable> writtenInThisNode = _writtenStack.removeLast()
      ..removeAll(declaredInThisNode);
    Set<Variable> capturedInThisNode = _capturedStack.removeLast()
      ..removeAll(declaredInThisNode);
    _writtenInNode[node] = writtenInThisNode;
    _capturedInNode[node] = capturedInThisNode;
    _writtenStack.last.addAll(writtenInThisNode);
    _capturedStack.last.addAll(capturedInThisNode);
    if (isClosure) {
      _capturedStack.last.addAll(writtenInThisNode);
      _capturedAnywhere.addAll(writtenInThisNode);
    }
  }

  /// Call this after visiting the code to be analyzed, to check invariants.
  void finish() {
    assert(() {
      assert(_writtenStack.length == 1);
      assert(_declaredStack.length == 1);
      assert(_capturedStack.length == 1);
      Set<Variable> writtenInThisNode = _writtenStack.last;
      Set<Variable> declaredInThisNode = _declaredStack.last;
      Set<Variable> capturedInThisNode = _capturedStack.last;
      Set<Variable> undeclaredWrites =
          writtenInThisNode.difference(declaredInThisNode);
      assert(undeclaredWrites.isEmpty,
          'Variables written to but not declared: $undeclaredWrites');
      Set<Variable> undeclaredCaptures =
          capturedInThisNode.difference(declaredInThisNode);
      assert(undeclaredCaptures.isEmpty,
          'Variables captured but not declared: $undeclaredCaptures');
      return true;
    }());
  }

  /// This method should be called during pre-traversal, to mark a write to a
  /// variable.
  void write(Variable variable) {
    _writtenStack.last.add(variable);
    _writtenAnywhere.add(variable);
  }

  /// Queries the set of variables for which a potential write is captured by a
  /// local function or closure inside the [node].
  Set<Variable> _getCapturedInNode(Node node) {
    return _capturedInNode[node] ??
        (throw new StateError('No information for $node'));
  }

  /// Queries the set of variables that are potentially written to inside the
  /// [node].
  Set<Variable> _getWrittenInNode(Node node) {
    return _writtenInNode[node] ??
        (throw new StateError('No information for $node'));
  }
}

/// Extension of [AssignedVariables] intended for use in tests.  This class
/// exposes the results of the analysis so that they can be tested directly.
/// Not intended to be used by clients of flow analysis.
class AssignedVariablesForTesting<Node, Variable>
    extends AssignedVariables<Node, Variable> {
  final Map<Node, Set<Variable>> _declaredInNode = {};

  Set<Variable> get capturedAnywhere => _capturedAnywhere;

  Set<Variable> get declaredAtTopLevel => _declaredStack.first;

  Set<Variable> get writtenAnywhere => _writtenAnywhere;

  Set<Variable> capturedInNode(Node node) => _getCapturedInNode(node);

  Set<Variable> declaredInNode(Node node) =>
      _declaredInNode[node] ??
      (throw new StateError('No information for $node'));

  @override
  void endNode(Node node, {bool isClosure: false}) {
    _declaredInNode[node] = _declaredStack.last;
    super.endNode(node, isClosure: isClosure);
  }

  bool isTracked(Node node) => _writtenInNode.containsKey(node);

  Set<Variable> writtenInNode(Node node) => _getWrittenInNode(node);
}

/// Implementation of flow analysis to be shared between the analyzer and the
/// front end.
///
/// The client should create one instance of this class for every method, field,
/// or top level variable to be analyzed, and call the appropriate methods
/// while visiting the code for type inference.
abstract class FlowAnalysis<Node, Statement extends Node, Expression, Variable,
    Type> {
  factory FlowAnalysis(TypeOperations<Variable, Type> typeOperations,
      AssignedVariables<Node, Variable> assignedVariables) {
    return new _FlowAnalysisImpl(typeOperations, assignedVariables);
  }

  /// Return `true` if the current state is reachable.
  bool get isReachable;

  /// Call this method after visiting an "as" expression.
  ///
  /// [subExpression] should be the expression to which the "as" check was
  /// applied.  [type] should be the type being checked.
  void asExpression_end(Expression subExpression, Type type);

  /// Call this method after visiting the condition part of an assert statement
  /// (or assert initializer).
  ///
  /// [condition] should be the assert statement's condition.
  ///
  /// See [assert_begin] for more information.
  void assert_afterCondition(Expression condition);

  /// Call this method before visiting the condition part of an assert statement
  /// (or assert initializer).
  ///
  /// The order of visiting an assert statement with no "message" part should
  /// be:
  /// - Call [assert_begin]
  /// - Visit the condition
  /// - Call [assert_afterCondition]
  /// - Call [assert_end]
  ///
  /// The order of visiting an assert statement with a "message" part should be:
  /// - Call [assert_begin]
  /// - Visit the condition
  /// - Call [assert_afterCondition]
  /// - Visit the message
  /// - Call [assert_end]
  void assert_begin();

  /// Call this method after visiting an assert statement (or assert
  /// initializer).
  ///
  /// See [assert_begin] for more information.
  void assert_end();

  /// Call this method when visiting a boolean literal expression.
  void booleanLiteral(Expression expression, bool value);

  /// Call this method upon reaching the ":" part of a conditional expression
  /// ("?:").  [thenExpression] should be the expression preceding the ":".
  void conditional_elseBegin(Expression thenExpression);

  /// Call this method when finishing the visit of a conditional expression
  /// ("?:").  [elseExpression] should be the expression preceding the ":", and
  /// [conditionalExpression] should be the whole conditional expression.
  void conditional_end(
      Expression conditionalExpression, Expression elseExpression);

  /// Call this method upon reaching the "?" part of a conditional expression
  /// ("?:").  [condition] should be the expression preceding the "?".
  void conditional_thenBegin(Expression condition);

  /// Call this method before visiting the body of a "do-while" statement.
  /// [doStatement] should be the same node that was passed to
  /// [AssignedVariables.endNode] for the do-while statement.
  void doStatement_bodyBegin(Statement doStatement);

  /// Call this method after visiting the body of a "do-while" statement, and
  /// before visiting its condition.
  void doStatement_conditionBegin();

  /// Call this method after visiting the condition of a "do-while" statement.
  /// [condition] should be the condition of the loop.
  void doStatement_end(Expression condition);

  /// Call this method just after visiting a binary `==` or `!=` expression.
  void equalityOp_end(Expression wholeExpression, Expression rightOperand,
      {bool notEqual = false});

  /// Call this method just after visiting the left hand side of a binary `==`
  /// or `!=` expression.
  void equalityOp_rightBegin(Expression leftOperand);

  /// This method should be called at the conclusion of flow analysis for a top
  /// level function or method.  Performs assertion checks.
  void finish();

  /// Call this method just before visiting the body of a conventional "for"
  /// statement or collection element.  See [for_conditionBegin] for details.
  ///
  /// If a "for" statement is being entered, [node] is an opaque representation
  /// of the loop, for use as the target of future calls to [handleBreak] or
  /// [handleContinue].  If a "for" collection element is being entered, [node]
  /// should be `null`.
  ///
  /// [condition] is an opaque representation of the loop condition; it is
  /// matched against expressions passed to previous calls to determine whether
  /// the loop condition should cause any promotions to occur.  If [condition]
  /// is null, the condition is understood to be empty (equivalent to a
  /// condition of `true`).
  void for_bodyBegin(Statement node, Expression condition);

  /// Call this method just before visiting the condition of a conventional
  /// "for" statement or collection element.
  ///
  /// Note that a conventional "for" statement is a statement of the form
  /// `for (initializers; condition; updaters) body`.  Statements of the form
  /// `for (variable in iterable) body` should use [forEach_bodyBegin].  Similar
  /// for "for" collection elements.
  ///
  /// The order of visiting a "for" statement or collection element should be:
  /// - Visit the initializers.
  /// - Call [for_conditionBegin].
  /// - Visit the condition.
  /// - Call [for_bodyBegin].
  /// - Visit the body.
  /// - Call [for_updaterBegin].
  /// - Visit the updaters.
  /// - Call [for_end].
  ///
  /// [node] should be the same node that was passed to
  /// [AssignedVariables.endNode] for the for statement.
  void for_conditionBegin(Node node);

  /// Call this method just after visiting the updaters of a conventional "for"
  /// statement or collection element.  See [for_conditionBegin] for details.
  void for_end();

  /// Call this method just before visiting the updaters of a conventional "for"
  /// statement or collection element.  See [for_conditionBegin] for details.
  void for_updaterBegin();

  /// Call this method just before visiting the body of a "for-in" statement or
  /// collection element.
  ///
  /// The order of visiting a "for-in" statement or collection element should
  /// be:
  /// - Visit the iterable expression.
  /// - Call [forEach_bodyBegin].
  /// - Visit the body.
  /// - Call [forEach_end].
  ///
  /// [node] should be the same node that was passed to
  /// [AssignedVariables.endNode] for the for statement.
  void forEach_bodyBegin(Node node, Variable loopVariable);

  /// Call this method just before visiting the body of a "for-in" statement or
  /// collection element.  See [forEach_bodyBegin] for details.
  void forEach_end();

  /// Call this method just before visiting the body of a function expression or
  /// local function.
  ///
  /// [node] should be the same node that was passed to
  /// [AssignedVariables.endNode] for the function expression.
  void functionExpression_begin(Node node);

  /// Call this method just after visiting the body of a function expression or
  /// local function.
  void functionExpression_end();

  /// Call this method when visiting a break statement.  [target] should be the
  /// statement targeted by the break.
  void handleBreak(Statement target);

  /// Call this method when visiting a continue statement.  [target] should be
  /// the statement targeted by the continue.
  void handleContinue(Statement target);

  /// Register the fact that the current state definitely exists, e.g. returns
  /// from the body, throws an exception, etc.
  ///
  /// Should also be called if a subexpression's type is Never.
  void handleExit();

  /// Call this method after visiting the RHS of an if-null expression ("??")
  /// or if-null assignment ("??=").
  ///
  /// Note: for an if-null assignment, the call to [write] should occur before
  /// the call to [ifNullExpression_end] (since the write only occurs if the
  /// read resulted in a null value).
  void ifNullExpression_end();

  /// Call this method after visiting the LHS of an if-null expression ("??")
  /// or if-null assignment ("??=").
  void ifNullExpression_rightBegin();

  /// Call this method after visiting the "then" part of an if statement, and
  /// before visiting the "else" part.
  void ifStatement_elseBegin();

  /// Call this method after visiting an if statement.
  void ifStatement_end(bool hasElse);

  /// Call this method after visiting the condition part of an if statement.
  /// [condition] should be the if statement's condition.
  ///
  /// The order of visiting an if statement with no "else" part should be:
  /// - Visit the condition
  /// - Call [ifStatement_thenBegin]
  /// - Visit the "then" statement
  /// - Call [ifStatement_end], passing `false` for `hasElse`.
  ///
  /// The order of visiting an if statement with an "else" part should be:
  /// - Visit the condition
  /// - Call [ifStatement_thenBegin]
  /// - Visit the "then" statement
  /// - Call [ifStatement_elseBegin]
  /// - Visit the "else" statement
  /// - Call [ifStatement_end], passing `true` for `hasElse`.
  void ifStatement_thenBegin(Expression condition);

  /// Register an initialized declaration of the given [variable] in the current
  /// state.  Should also be called for function parameters.
  void initialize(Variable variable);

  /// Return whether the [variable] is definitely assigned in the current state.
  bool isAssigned(Variable variable);

  /// Call this method after visiting the LHS of an "is" expression.
  ///
  /// [isExpression] should be the complete expression.  [subExpression] should
  /// be the expression to which the "is" check was applied.  [isNot] should be
  /// a boolean indicating whether this is an "is" or an "is!" expression.
  /// [type] should be the type being checked.
  void isExpression_end(
      Expression isExpression, Expression subExpression, bool isNot, Type type);

  /// Call this method after visiting the RHS of a logical binary operation
  /// ("||" or "&&").
  /// [wholeExpression] should be the whole logical binary expression.
  /// [rightOperand] should be the RHS.  [isAnd] should indicate whether the
  /// logical operator is "&&" or "||".
  void logicalBinaryOp_end(Expression wholeExpression, Expression rightOperand,
      {@required bool isAnd});

  /// Call this method after visiting the LHS of a logical binary operation
  /// ("||" or "&&").
  /// [rightOperand] should be the LHS.  [isAnd] should indicate whether the
  /// logical operator is "&&" or "||".
  void logicalBinaryOp_rightBegin(Expression leftOperand,
      {@required bool isAnd});

  /// Call this method after visiting a logical not ("!") expression.
  /// [notExpression] should be the complete expression.  [operand] should be
  /// the subexpression whose logical value is being negated.
  void logicalNot_end(Expression notExpression, Expression operand);

  /// Call this method just after visiting a non-null assertion (`x!`)
  /// expression.
  void nonNullAssert_end(Expression operand);

  /// Call this method after visiting an expression using `?.`.
  void nullAwareAccess_end();

  /// Call this method after visiting a null-aware operator such as `?.`,
  /// `?..`, `?.[`, or `?..[`.
  ///
  /// [target] should be the expression just before the null-aware operator, or
  /// `null` if the null-aware access starts a cascade section.
  ///
  /// Note that [nullAwareAccess_end] should be called after the conclusion
  /// of any null-shorting that is caused by the `?.`.  So, for example, if the
  /// code being analyzed is `x?.y?.z(x)`, [nullAwareAccess_rightBegin] should
  /// be called once upon reaching each `?.`, but [nullAwareAccess_end] should
  /// not be called until after processing the method call to `z(x)`.
  void nullAwareAccess_rightBegin(Expression target);

  /// Call this method when encountering an expression that is a `null` literal.
  void nullLiteral(Expression expression);

  /// Call this method just after visiting a parenthesized expression.
  ///
  /// This is only necessary if the implementation uses a different [Expression]
  /// object to represent a parenthesized expression and its contents.
  void parenthesizedExpression(
      Expression outerExpression, Expression innerExpression);

  /// Retrieves the type that the [variable] is promoted to, if the [variable]
  /// is currently promoted.  Otherwise returns `null`.
  ///
  /// For testing only.  Please use [variableRead] instead.
  @visibleForTesting
  Type promotedType(Variable variable);

  /// Call this method just before visiting one of the cases in the body of a
  /// switch statement.  See [switchStatement_expressionEnd] for details.
  ///
  /// [hasLabel] indicates whether the case has any labels.
  ///
  /// [node] should be the same node that was passed to
  /// [AssignedVariables.endNode] for the switch statement.
  void switchStatement_beginCase(bool hasLabel, Node node);

  /// Call this method just after visiting the body of a switch statement.  See
  /// [switchStatement_expressionEnd] for details.
  ///
  /// [hasDefault] indicates whether the switch statement had a "default" case.
  void switchStatement_end(bool hasDefault);

  /// Call this method just after visiting the expression part of a switch
  /// statement.
  ///
  /// The order of visiting a switch statement should be:
  /// - Visit the switch expression.
  /// - Call [switchStatement_expressionEnd].
  /// - For each switch case (including the default case, if any):
  ///   - Call [switchStatement_beginCase].
  ///   - Visit the case.
  /// - Call [switchStatement_end].
  void switchStatement_expressionEnd(Statement switchStatement);

  /// Call this method just before visiting the body of a "try/catch" statement.
  ///
  /// The order of visiting a "try/catch" statement should be:
  /// - Call [tryCatchStatement_bodyBegin]
  /// - Visit the try block
  /// - Call [tryCatchStatement_bodyEnd]
  /// - For each catch block:
  ///   - Call [tryCatchStatement_catchBegin]
  ///   - Call [initialize] for the exception and stack trace variables
  ///   - Visit the catch block
  ///   - Call [tryCatchStatement_catchEnd]
  /// - Call [tryCatchStatement_end]
  ///
  /// The order of visiting a "try/catch/finally" statement should be:
  /// - Call [tryFinallyStatement_bodyBegin]
  /// - Call [tryCatchStatement_bodyBegin]
  /// - Visit the try block
  /// - Call [tryCatchStatement_bodyEnd]
  /// - For each catch block:
  ///   - Call [tryCatchStatement_catchBegin]
  ///   - Call [initialize] for the exception and stack trace variables
  ///   - Visit the catch block
  ///   - Call [tryCatchStatement_catchEnd]
  /// - Call [tryCatchStatement_end]
  /// - Call [tryFinallyStatement_finallyBegin]
  /// - Visit the finally block
  /// - Call [tryFinallyStatement_end]
  void tryCatchStatement_bodyBegin();

  /// Call this method just after visiting the body of a "try/catch" statement.
  /// See [tryCatchStatement_bodyBegin] for details.
  ///
  /// [body] should be the same node that was passed to
  /// [AssignedVariables.endNode] for the "try" part of the try/catch statement.
  void tryCatchStatement_bodyEnd(Node body);

  /// Call this method just before visiting a catch clause of a "try/catch"
  /// statement.  See [tryCatchStatement_bodyBegin] for details.
  ///
  /// [exceptionVariable] should be the exception variable declared by the catch
  /// clause, or `null` if there is no exception variable.  Similar for
  /// [stackTraceVariable].
  void tryCatchStatement_catchBegin(
      Variable exceptionVariable, Variable stackTraceVariable);

  /// Call this method just after visiting a catch clause of a "try/catch"
  /// statement.  See [tryCatchStatement_bodyBegin] for details.
  void tryCatchStatement_catchEnd();

  /// Call this method just after visiting a "try/catch" statement.  See
  /// [tryCatchStatement_bodyBegin] for details.
  void tryCatchStatement_end();

  /// Call this method just before visiting the body of a "try/finally"
  /// statement.
  ///
  /// The order of visiting a "try/finally" statement should be:
  /// - Call [tryFinallyStatement_bodyBegin]
  /// - Visit the try block
  /// - Call [tryFinallyStatement_finallyBegin]
  /// - Visit the finally block
  /// - Call [tryFinallyStatement_end]
  ///
  /// See [tryCatchStatement_bodyBegin] for the order of visiting a
  /// "try/catch/finally" statement.
  void tryFinallyStatement_bodyBegin();

  /// Call this method just after visiting a "try/finally" statement.
  /// See [tryFinallyStatement_bodyBegin] for details.
  ///
  /// [finallyBlock] should be the same node that was passed to
  /// [AssignedVariables.endNode] for the "finally" part of the try/finally
  /// statement.
  void tryFinallyStatement_end(Node finallyBlock);

  /// Call this method just before visiting the finally block of a "try/finally"
  /// statement.  See [tryFinallyStatement_bodyBegin] for details.
  ///
  /// [body] should be the same node that was passed to
  /// [AssignedVariables.endNode] for the "try" part of the try/finally
  /// statement.
  void tryFinallyStatement_finallyBegin(Node body);

  /// Call this method when encountering an expression that reads the value of
  /// a variable.
  ///
  /// If the variable's type is currently promoted, the promoted type is
  /// returned.  Otherwise `null` is returned.
  Type variableRead(Expression expression, Variable variable);

  /// Call this method after visiting the condition part of a "while" statement.
  /// [whileStatement] should be the full while statement.  [condition] should
  /// be the condition part of the while statement.
  void whileStatement_bodyBegin(Statement whileStatement, Expression condition);

  /// Call this method before visiting the condition part of a "while"
  /// statement.
  ///
  /// [node] should be the same node that was passed to
  /// [AssignedVariables.endNode] for the while statement.
  void whileStatement_conditionBegin(Node node);

  /// Call this method after visiting a "while" statement.
  void whileStatement_end();

  /// Register write of the given [variable] in the current state.
  void write(Variable variable);
}

/// Alternate implementation of [FlowAnalysis] that prints out inputs and output
/// at the API boundary, for assistance in debugging.
class FlowAnalysisDebug<Node, Statement extends Node, Expression, Variable,
    Type> implements FlowAnalysis<Node, Statement, Expression, Variable, Type> {
  _FlowAnalysisImpl<Node, Statement, Expression, Variable, Type> _wrapped;

  bool _exceptionOccurred = false;

  factory FlowAnalysisDebug(TypeOperations<Variable, Type> typeOperations,
      AssignedVariables<Node, Variable> assignedVariables) {
    print('FlowAnalysisDebug()');
    return new FlowAnalysisDebug._(
        new _FlowAnalysisImpl(typeOperations, assignedVariables));
  }

  FlowAnalysisDebug._(this._wrapped);

  @override
  bool get isReachable =>
      _wrap('isReachable', () => _wrapped.isReachable, isQuery: true);

  @override
  void asExpression_end(Expression subExpression, Type type) {
    _wrap('asExpression_end($subExpression, $type)',
        () => _wrapped.asExpression_end(subExpression, type));
  }

  @override
  void assert_afterCondition(Expression condition) {
    _wrap('assert_afterCondition($condition)',
        () => _wrapped.assert_afterCondition(condition));
  }

  @override
  void assert_begin() {
    _wrap('assert_begin()', () => _wrapped.assert_begin());
  }

  @override
  void assert_end() {
    _wrap('assert_end()', () => _wrapped.assert_end());
  }

  @override
  void booleanLiteral(Expression expression, bool value) {
    _wrap('booleanLiteral($expression, $value)',
        () => _wrapped.booleanLiteral(expression, value));
  }

  @override
  void conditional_elseBegin(Expression thenExpression) {
    _wrap('conditional_elseBegin($thenExpression',
        () => _wrapped.conditional_elseBegin(thenExpression));
  }

  @override
  void conditional_end(
      Expression conditionalExpression, Expression elseExpression) {
    _wrap('conditional_end($conditionalExpression, $elseExpression',
        () => _wrapped.conditional_end(conditionalExpression, elseExpression));
  }

  @override
  void conditional_thenBegin(Expression condition) {
    _wrap('conditional_thenBegin($condition)',
        () => _wrapped.conditional_thenBegin(condition));
  }

  @override
  void doStatement_bodyBegin(Statement doStatement) {
    return _wrap('doStatement_bodyBegin($doStatement)',
        () => _wrapped.doStatement_bodyBegin(doStatement));
  }

  @override
  void doStatement_conditionBegin() {
    return _wrap('doStatement_conditionBegin()',
        () => _wrapped.doStatement_conditionBegin());
  }

  @override
  void doStatement_end(Expression condition) {
    return _wrap('doStatement_end($condition)',
        () => _wrapped.doStatement_end(condition));
  }

  @override
  void equalityOp_end(Expression wholeExpression, Expression rightOperand,
      {bool notEqual = false}) {
    _wrap(
        'equalityOp_end($wholeExpression, $rightOperand, notEqual: $notEqual)',
        () => _wrapped.equalityOp_end(wholeExpression, rightOperand,
            notEqual: notEqual));
  }

  @override
  void equalityOp_rightBegin(Expression leftOperand) {
    _wrap('equalityOp_rightBegin($leftOperand)',
        () => _wrapped.equalityOp_rightBegin(leftOperand));
  }

  @override
  void finish() {
    if (_exceptionOccurred) {
      print('finish() (skipped)');
    } else {
      print('finish()');
      _wrapped.finish();
    }
  }

  @override
  void for_bodyBegin(Statement node, Expression condition) {
    _wrap('for_bodyBegin($node, $condition)',
        () => _wrapped.for_bodyBegin(node, condition));
  }

  @override
  void for_conditionBegin(Node node) {
    _wrap('for_conditionBegin($node)', () => _wrapped.for_conditionBegin(node));
  }

  @override
  void for_end() {
    _wrap('for_end()', () => _wrapped.for_end());
  }

  @override
  void for_updaterBegin() {
    _wrap('for_updaterBegin()', () => _wrapped.for_updaterBegin());
  }

  @override
  void forEach_bodyBegin(Node node, Variable loopVariable) {
    return _wrap('forEach_bodyBegin($node, $loopVariable)',
        () => _wrapped.forEach_bodyBegin(node, loopVariable));
  }

  @override
  void forEach_end() {
    return _wrap('forEach_end()', () => _wrapped.forEach_end());
  }

  @override
  void functionExpression_begin(Node node) {
    _wrap('functionExpression_begin($node)',
        () => _wrapped.functionExpression_begin(node));
  }

  @override
  void functionExpression_end() {
    _wrap('functionExpression_end()', () => _wrapped.functionExpression_end());
  }

  @override
  void handleBreak(Statement target) {
    _wrap('handleBreak($target)', () => _wrapped.handleBreak(target));
  }

  @override
  void handleContinue(Statement target) {
    _wrap('handleContinue($target)', () => _wrapped.handleContinue(target));
  }

  @override
  void handleExit() {
    _wrap('handleExit()', () => _wrapped.handleExit());
  }

  @override
  void ifNullExpression_end() {
    return _wrap(
        'ifNullExpression_end()', () => _wrapped.ifNullExpression_end());
  }

  @override
  void ifNullExpression_rightBegin() {
    return _wrap('ifNullExpression_rightBegin()',
        () => _wrapped.ifNullExpression_rightBegin());
  }

  @override
  void ifStatement_elseBegin() {
    return _wrap(
        'ifStatement_elseBegin()', () => _wrapped.ifStatement_elseBegin());
  }

  @override
  void ifStatement_end(bool hasElse) {
    _wrap('ifStatement_end($hasElse)', () => _wrapped.ifStatement_end(hasElse));
  }

  @override
  void ifStatement_thenBegin(Expression condition) {
    _wrap('ifStatement_thenBegin($condition)',
        () => _wrapped.ifStatement_thenBegin(condition));
  }

  @override
  void initialize(Variable variable) {
    _wrap('initialize($variable)', () => _wrapped.initialize(variable));
  }

  @override
  bool isAssigned(Variable variable) {
    return _wrap('isAssigned($variable)', () => _wrapped.isAssigned(variable),
        isQuery: true);
  }

  @override
  void isExpression_end(Expression isExpression, Expression subExpression,
      bool isNot, Type type) {
    _wrap(
        'isExpression_end($isExpression, $subExpression, $isNot, $type)',
        () => _wrapped.isExpression_end(
            isExpression, subExpression, isNot, type));
  }

  @override
  void logicalBinaryOp_end(Expression wholeExpression, Expression rightOperand,
      {@required bool isAnd}) {
    _wrap(
        'logicalBinaryOp_end($wholeExpression, $rightOperand, isAnd: $isAnd)',
        () => _wrapped.logicalBinaryOp_end(wholeExpression, rightOperand,
            isAnd: isAnd));
  }

  @override
  void logicalBinaryOp_rightBegin(Expression leftOperand,
      {@required bool isAnd}) {
    _wrap('logicalBinaryOp_rightBegin($leftOperand, isAnd: $isAnd)',
        () => _wrapped.logicalBinaryOp_rightBegin(leftOperand, isAnd: isAnd));
  }

  @override
  void logicalNot_end(Expression notExpression, Expression operand) {
    return _wrap('logicalNot_end($notExpression, $operand)',
        () => _wrapped.logicalNot_end(notExpression, operand));
  }

  @override
  void nonNullAssert_end(Expression operand) {
    return _wrap('nonNullAssert_end($operand)',
        () => _wrapped.nonNullAssert_end(operand));
  }

  @override
  void nullAwareAccess_end() {
    _wrap('nullAwareAccess_end()', () => _wrapped.nullAwareAccess_end());
  }

  @override
  void nullAwareAccess_rightBegin(Expression target) {
    _wrap('nullAwareAccess_rightBegin($target)',
        () => _wrapped.nullAwareAccess_rightBegin(target));
  }

  @override
  void nullLiteral(Expression expression) {
    _wrap('nullLiteral($expression)', () => _wrapped.nullLiteral(expression));
  }

  @override
  void parenthesizedExpression(
      Expression outerExpression, Expression innerExpression) {
    _wrap(
        'parenthesizedExpression($outerExpression, $innerExpression)',
        () =>
            _wrapped.parenthesizedExpression(outerExpression, innerExpression));
  }

  @override
  Type promotedType(Variable variable) {
    return _wrap(
        'promotedType($variable)', () => _wrapped.promotedType(variable),
        isQuery: true);
  }

  @override
  void switchStatement_beginCase(bool hasLabel, Node node) {
    _wrap('switchStatement_beginCase($hasLabel, $node)',
        () => _wrapped.switchStatement_beginCase(hasLabel, node));
  }

  @override
  void switchStatement_end(bool hasDefault) {
    _wrap('switchStatement_end($hasDefault)',
        () => _wrapped.switchStatement_end(hasDefault));
  }

  @override
  void switchStatement_expressionEnd(Statement switchStatement) {
    _wrap('switchStatement_expressionEnd($switchStatement)',
        () => _wrapped.switchStatement_expressionEnd(switchStatement));
  }

  @override
  void tryCatchStatement_bodyBegin() {
    return _wrap('tryCatchStatement_bodyBegin()',
        () => _wrapped.tryCatchStatement_bodyBegin());
  }

  @override
  void tryCatchStatement_bodyEnd(Node body) {
    return _wrap('tryCatchStatement_bodyEnd($body)',
        () => _wrapped.tryCatchStatement_bodyEnd(body));
  }

  @override
  void tryCatchStatement_catchBegin(
      Variable exceptionVariable, Variable stackTraceVariable) {
    return _wrap(
        'tryCatchStatement_catchBegin($exceptionVariable, $stackTraceVariable)',
        () => _wrapped.tryCatchStatement_catchBegin(
            exceptionVariable, stackTraceVariable));
  }

  @override
  void tryCatchStatement_catchEnd() {
    return _wrap('tryCatchStatement_catchEnd()',
        () => _wrapped.tryCatchStatement_catchEnd());
  }

  @override
  void tryCatchStatement_end() {
    return _wrap(
        'tryCatchStatement_end()', () => _wrapped.tryCatchStatement_end());
  }

  @override
  void tryFinallyStatement_bodyBegin() {
    return _wrap('tryFinallyStatement_bodyBegin()',
        () => _wrapped.tryFinallyStatement_bodyBegin());
  }

  @override
  void tryFinallyStatement_end(Node finallyBlock) {
    return _wrap('tryFinallyStatement_end($finallyBlock)',
        () => _wrapped.tryFinallyStatement_end(finallyBlock));
  }

  @override
  void tryFinallyStatement_finallyBegin(Node body) {
    return _wrap('tryFinallyStatement_finallyBegin($body)',
        () => _wrapped.tryFinallyStatement_finallyBegin(body));
  }

  @override
  Type variableRead(Expression expression, Variable variable) {
    return _wrap('variableRead($expression, $variable)',
        () => _wrapped.variableRead(expression, variable),
        isQuery: true, isPure: false);
  }

  @override
  void whileStatement_bodyBegin(
      Statement whileStatement, Expression condition) {
    return _wrap('whileStatement_bodyBegin($whileStatement, $condition)',
        () => _wrapped.whileStatement_bodyBegin(whileStatement, condition));
  }

  @override
  void whileStatement_conditionBegin(Node node) {
    return _wrap('whileStatement_conditionBegin($node)',
        () => _wrapped.whileStatement_conditionBegin(node));
  }

  @override
  void whileStatement_end() {
    return _wrap('whileStatement_end()', () => _wrapped.whileStatement_end());
  }

  @override
  void write(Variable variable) {
    _wrap('write($variable)', () => _wrapped.write(variable));
  }

  T _wrap<T>(String description, T callback(),
      {bool isQuery: false, bool isPure}) {
    isPure ??= isQuery;
    print(description);
    T result;
    try {
      result = callback();
    } catch (e, st) {
      print('  => EXCEPTION $e');
      print('    ' + st.toString().replaceAll('\n', '\n    '));
      _exceptionOccurred = true;
      rethrow;
    }
    if (!isPure) {
      _wrapped._dumpState();
    }
    if (isQuery) {
      print('  => $result');
    }
    return result;
  }
}

/// An instance of the [FlowModel] class represents the information gathered by
/// flow analysis at a single point in the control flow of the function or
/// method being analyzed.
///
/// Instances of this class are immutable, so the methods below that "update"
/// the state actually leave `this` unchanged and return a new state object.
@visibleForTesting
class FlowModel<Variable, Type> {
  /// Indicates whether this point in the control flow is reachable.
  final bool reachable;

  /// For each variable being tracked by flow analysis, the variable's model.
  ///
  /// Flow analysis has no awareness of scope, so variables that are out of
  /// scope are retained in the map until such time as their declaration no
  /// longer dominates the control flow.  So, for example, if a variable is
  /// declared inside the `then` branch of an `if` statement, and the `else`
  /// branch of the `if` statement ends in a `return` statement, then the
  /// variable remains in the map after the `if` statement ends, even though the
  /// variable is not in scope anymore.  This should not have any effect on
  /// analysis results for error-free code, because it is an error to refer to a
  /// variable that is no longer in scope.
  final Map<Variable, VariableModel<Type> /*!*/ > variableInfo;

  /// Variable model for variables that have never been seen before.
  final VariableModel<Type> _freshVariableInfo;

  /// Creates a state object with the given [reachable] status.  All variables
  /// are assumed to be unpromoted and already assigned, so joining another
  /// state with this one will have no effect on it.
  FlowModel(bool reachable)
      : this._(
          reachable,
          const {},
        );

  FlowModel._(this.reachable, this.variableInfo)
      : _freshVariableInfo = new VariableModel.fresh() {
    assert(() {
      for (VariableModel<Type> value in variableInfo.values) {
        assert(value != null);
      }
      return true;
    }());
  }

  /// Gets the info for the given [variable], creating it if it doesn't exist.
  VariableModel<Type> infoFor(Variable variable) =>
      variableInfo[variable] ?? _freshVariableInfo;

  /// Updates the state to indicate that the given [variable] has been
  /// determined to contain a non-null value.
  ///
  /// TODO(paulberry): should this method mark the variable as definitely
  /// assigned?  Does it matter?
  FlowModel<Variable, Type> markNonNullable(
      TypeOperations<Variable, Type> typeOperations, Variable variable) {
    VariableModel<Type> info = infoFor(variable);
    if (info.writeCaptured) return this;
    Type previousType = info.promotedType;
    previousType ??= typeOperations.variableType(variable);
    Type type = typeOperations.promoteToNonNull(previousType);
    if (typeOperations.isSameType(type, previousType)) return this;
    return _updateVariableInfo(variable, info.withPromotedType(type));
  }

  /// Updates the state to indicate that the given [variable] has been
  /// determined to satisfy the given [type], e.g. as a consequence of an `is`
  /// expression as the condition of an `if` statement.
  ///
  /// Note that the state is only changed if [type] is a subtype of the
  /// variable's previous (possibly promoted) type.
  ///
  /// TODO(paulberry): if the type is non-nullable, should this method mark the
  /// variable as definitely assigned?  Does it matter?
  FlowModel<Variable, Type> promote(
    TypeOperations<Variable, Type> typeOperations,
    Variable variable,
    Type type,
  ) {
    VariableModel<Type> info = infoFor(variable);
    if (info.writeCaptured) return this;
    Type previousType = info.promotedType;
    previousType ??= typeOperations.variableType(variable);

    Type newType = typeOperations.tryPromoteToType(type, previousType);
    if (newType == null || typeOperations.isSameType(newType, previousType)) {
      return this;
    }
    return _updateVariableInfo(variable, info.withPromotedType(newType));
  }

  /// Updates the state to indicate that the given [writtenVariables] are no
  /// longer promoted; they are presumed to have their declared types.
  ///
  /// This is used at the top of loops to conservatively cancel the promotion of
  /// variables that are modified within the loop, so that we correctly analyze
  /// code like the following:
  ///
  ///     if (x is int) {
  ///       x.isEven; // OK, promoted to int
  ///       while (true) {
  ///         x.isEven; // ERROR: promotion lost
  ///         x = 'foo';
  ///       }
  ///     }
  ///
  /// Note that a more accurate analysis would be to iterate to a fixed point,
  /// and only remove promotions if it can be shown that they aren't restored
  /// later in the loop body.  If we switch to a fixed point analysis, we should
  /// be able to remove this method.
  FlowModel<Variable, Type> removePromotedAll(
      Iterable<Variable> writtenVariables,
      Iterable<Variable> capturedVariables) {
    Map<Variable, VariableModel<Type>> newVariableInfo;
    for (Variable variable in writtenVariables) {
      VariableModel<Type> info = infoFor(variable);
      if (info.promotedType != null) {
        (newVariableInfo ??= new Map<Variable, VariableModel<Type>>.from(
            variableInfo))[variable] = info.withPromotedType(null);
      }
    }
    for (Variable variable in capturedVariables) {
      VariableModel<Type> info = variableInfo[variable];
      if (info == null) {
        (newVariableInfo ??= new Map<Variable, VariableModel<Type>>.from(
                variableInfo))[variable] =
            new VariableModel<Type>(null, false, true);
      } else if (!info.writeCaptured) {
        (newVariableInfo ??= new Map<Variable, VariableModel<Type>>.from(
            variableInfo))[variable] = info.writeCapture();
      }
    }
    if (newVariableInfo == null) return this;
    return new FlowModel<Variable, Type>._(reachable, newVariableInfo);
  }

  /// Updates the state to reflect a control path that is known to have
  /// previously passed through some [other] state.
  ///
  /// Approximately, this method forms the union of the definite assignments and
  /// promotions in `this` state and the [other] state.  More precisely:
  ///
  /// The control flow path is considered reachable if both this state and the
  /// other state are reachable.  Variables are considered definitely assigned
  /// if they were definitely assigned in either this state or the other state.
  /// Variable type promotions are taken from this state, unless the promotion
  /// in the other state is more specific, and the variable is "safe".  A
  /// variable is considered safe if there is no chance that it was assigned
  /// more recently than the "other" state.
  ///
  /// This is used after a `try/finally` statement to combine the promotions and
  /// definite assignments that occurred in the `try` and `finally` blocks
  /// (where `this` is the state from the `finally` block and `other` is the
  /// state from the `try` block).  Variables that are assigned in the `finally`
  /// block are considered "unsafe" because the assignment might have cancelled
  /// the effect of any promotion that occurred inside the `try` block.
  FlowModel<Variable, Type> restrict(
      TypeOperations<Variable, Type> typeOperations,
      FlowModel<Variable, Type> other,
      Set<Variable> unsafe) {
    bool newReachable = reachable && other.reachable;

    Map<Variable, VariableModel<Type>> newVariableInfo =
        <Variable, VariableModel<Type>>{};
    bool variableInfoMatchesThis = true;
    bool variableInfoMatchesOther = true;
    for (MapEntry<Variable, VariableModel<Type>> entry
        in variableInfo.entries) {
      Variable variable = entry.key;
      VariableModel<Type> thisModel = entry.value;
      VariableModel<Type> otherModel = other.infoFor(variable);
      VariableModel<Type> restricted = thisModel.restrict(
          typeOperations, otherModel, unsafe.contains(variable));
      if (!identical(restricted, _freshVariableInfo)) {
        newVariableInfo[variable] = restricted;
      }
      if (!identical(restricted, thisModel)) variableInfoMatchesThis = false;
      if (!identical(restricted, otherModel)) variableInfoMatchesOther = false;
    }
    for (MapEntry<Variable, VariableModel<Type>> entry
        in other.variableInfo.entries) {
      Variable variable = entry.key;
      if (variableInfo.containsKey(variable)) continue;
      VariableModel<Type> thisModel = _freshVariableInfo;
      VariableModel<Type> otherModel = entry.value;
      VariableModel<Type> restricted = thisModel.restrict(
          typeOperations, otherModel, unsafe.contains(variable));
      if (!identical(restricted, _freshVariableInfo)) {
        newVariableInfo[variable] = restricted;
      }
      if (!identical(restricted, thisModel)) variableInfoMatchesThis = false;
      if (!identical(restricted, otherModel)) variableInfoMatchesOther = false;
    }
    assert(variableInfoMatchesThis ==
        _variableInfosEqual(newVariableInfo, variableInfo));
    assert(variableInfoMatchesOther ==
        _variableInfosEqual(newVariableInfo, other.variableInfo));
    if (variableInfoMatchesThis) {
      newVariableInfo = variableInfo;
    } else if (variableInfoMatchesOther) {
      newVariableInfo = other.variableInfo;
    }

    return _identicalOrNew(this, other, newReachable, newVariableInfo);
  }

  /// Updates the state to indicate whether the control flow path is
  /// [reachable].
  FlowModel<Variable, Type> setReachable(bool reachable) {
    if (this.reachable == reachable) return this;

    return new FlowModel<Variable, Type>._(reachable, variableInfo);
  }

  @override
  String toString() => '($reachable, $variableInfo)';

  /// Updates the state to indicate that an assignment was made to the given
  /// [variable].  The variable is marked as definitely assigned, and any
  /// previous type promotion is removed.
  ///
  /// TODO(paulberry): allow for writes that preserve type promotions.
  FlowModel<Variable, Type> write(Variable variable) {
    VariableModel<Type> infoForVar = infoFor(variable);
    VariableModel<Type> newInfoForVar = infoForVar.write();
    if (identical(newInfoForVar, infoForVar)) return this;
    return _updateVariableInfo(variable, newInfoForVar);
  }

  /// Returns a new [FlowModel] where the information for [variable] is replaced
  /// with [model].
  FlowModel<Variable, Type> _updateVariableInfo(
      Variable variable, VariableModel<Type> model) {
    Map<Variable, VariableModel<Type>> newVariableInfo =
        new Map<Variable, VariableModel<Type>>.from(variableInfo);
    newVariableInfo[variable] = model;
    return new FlowModel<Variable, Type>._(reachable, newVariableInfo);
  }

  /// Forms a new state to reflect a control flow path that might have come from
  /// either `this` or the [other] state.
  ///
  /// The control flow path is considered reachable if either of the input
  /// states is reachable.  Variables are considered definitely assigned if they
  /// were definitely assigned in both of the input states.  Variable promotions
  /// are kept only if they are common to both input states; if a variable is
  /// promoted to one type in one state and a subtype in the other state, the
  /// less specific type promotion is kept.
  static FlowModel<Variable, Type> join<Variable, Type>(
    TypeOperations<Variable, Type> typeOperations,
    FlowModel<Variable, Type> first,
    FlowModel<Variable, Type> second,
  ) {
    if (first == null) return second;
    if (second == null) return first;

    if (first.reachable && !second.reachable) return first;
    if (!first.reachable && second.reachable) return second;

    bool newReachable = first.reachable || second.reachable;
    Map<Variable, VariableModel<Type>> newVariableInfo =
        FlowModel.joinVariableInfo(
            typeOperations, first.variableInfo, second.variableInfo);

    return FlowModel._identicalOrNew(
        first, second, newReachable, newVariableInfo);
  }

  /// Joins two "variable info" maps.  See [join] for details.
  @visibleForTesting
  static Map<Variable, VariableModel<Type>> joinVariableInfo<Variable, Type>(
    TypeOperations<Variable, Type> typeOperations,
    Map<Variable, VariableModel<Type>> first,
    Map<Variable, VariableModel<Type>> second,
  ) {
    if (identical(first, second)) return first;
    if (first.isEmpty || second.isEmpty) return const {};

    Map<Variable, VariableModel<Type>> result =
        <Variable, VariableModel<Type>>{};
    bool alwaysFirst = true;
    bool alwaysSecond = true;
    for (MapEntry<Variable, VariableModel<Type>> entry in first.entries) {
      Variable variable = entry.key;
      VariableModel<Type> secondModel = second[variable];
      if (secondModel == null) {
        alwaysFirst = false;
      } else {
        VariableModel<Type> joined =
            VariableModel.join<Type>(typeOperations, entry.value, secondModel);
        result[variable] = joined;
        if (!identical(joined, entry.value)) alwaysFirst = false;
        if (!identical(joined, secondModel)) alwaysSecond = false;
      }
    }

    if (alwaysFirst) return first;
    if (alwaysSecond && result.length == second.length) return second;
    if (result.isEmpty) return const {};
    return result;
  }

  /// Creates a new [FlowModel] object, unless it is equivalent to either
  /// [first] or [second], in which case one of those objects is re-used.
  static FlowModel<Variable, Type> _identicalOrNew<Variable, Type>(
      FlowModel<Variable, Type> first,
      FlowModel<Variable, Type> second,
      bool newReachable,
      Map<Variable, VariableModel<Type>> newVariableInfo) {
    if (first.reachable == newReachable &&
        identical(first.variableInfo, newVariableInfo)) {
      return first;
    }
    if (second.reachable == newReachable &&
        identical(second.variableInfo, newVariableInfo)) {
      return second;
    }

    return new FlowModel<Variable, Type>._(newReachable, newVariableInfo);
  }

  /// Determines whether the given "variableInfo" maps are equivalent.
  ///
  /// The equivalence check is shallow; if two variables' models are not
  /// identical, we return `false`.
  static bool _variableInfosEqual<Variable, Type>(
      Map<Variable, VariableModel<Type>> p1,
      Map<Variable, VariableModel<Type>> p2) {
    if (p1.length != p2.length) return false;
    if (!p1.keys.toSet().containsAll(p2.keys)) return false;
    for (MapEntry<Variable, VariableModel<Type>> entry in p1.entries) {
      VariableModel<Type> p1Value = entry.value;
      VariableModel<Type> p2Value = p2[entry.key];
      if (!identical(p1Value, p2Value)) {
        return false;
      }
    }
    return true;
  }
}

/// Operations on types, abstracted from concrete type interfaces.
abstract class TypeOperations<Variable, Type> {
  /// Returns `true` if [type1] and [type2] are the same type.
  bool isSameType(Type type1, Type type2);

  /// Return `true` if the [leftType] is a subtype of the [rightType].
  bool isSubtypeOf(Type leftType, Type rightType);

  /// Returns the non-null promoted version of [type].
  ///
  /// Note that some types don't have a non-nullable version (e.g.
  /// `FutureOr<int?>`), so [type] may be returned even if it is nullable.
  Type /*!*/ promoteToNonNull(Type type);

  /// Tries to promote to the first type from the second type, and returns the
  /// promoted type if it succeeds, otherwise null.
  Type tryPromoteToType(Type to, Type from);

  /// Return the static type of the given [variable].
  Type variableType(Variable variable);
}

/// An instance of the [VariableModel] class represents the information gathered
/// by flow analysis for a single variable at a single point in the control flow
/// of the function or method being analyzed.
///
/// Instances of this class are immutable, so the methods below that "update"
/// the state actually leave `this` unchanged and return a new state object.
@visibleForTesting
class VariableModel<Type> {
  /// The type that the variable has been promoted to, or `null` if the variable
  /// is not promoted.
  final Type promotedType;

  /// Indicates whether the variable has definitely been assigned.
  final bool assigned;

  /// Indicates whether the variable has been write captured.
  final bool writeCaptured;

  VariableModel(this.promotedType, this.assigned, this.writeCaptured) {
    assert(!writeCaptured || promotedType == null,
        "Write-captured variables can't be promoted");
  }

  /// Creates a [VariableModel] representing a variable that's never been seen
  /// before.
  VariableModel.fresh()
      : promotedType = null,
        assigned = false,
        writeCaptured = false;

  @override
  bool operator ==(Object other) {
    return other is VariableModel<Type> &&
        this.promotedType == other.promotedType &&
        this.assigned == other.assigned &&
        this.writeCaptured == other.writeCaptured;
  }

  /// Returns an updated model reflect a control path that is known to have
  /// previously passed through some [other] state.  See [FlowModel.restrict]
  /// for details.
  VariableModel<Type> restrict(TypeOperations<Object, Type> typeOperations,
      VariableModel<Type> otherModel, bool unsafe) {
    Type thisType = promotedType;
    Type otherType = otherModel.promotedType;
    bool newAssigned = assigned || otherModel.assigned;
    bool newWriteCaptured = writeCaptured || otherModel.writeCaptured;
    if (!unsafe) {
      if (otherType != null &&
          (thisType == null ||
              typeOperations.isSubtypeOf(otherType, thisType))) {
        return _identicalOrNew(
            this, otherModel, otherType, newAssigned, newWriteCaptured);
      }
    }
    return _identicalOrNew(
        this, otherModel, thisType, newAssigned, newWriteCaptured);
  }

  @override
  String toString() {
    List<String> parts = [];
    if (promotedType != null) {
      parts.add('promotedType: $promotedType');
    }
    if (assigned) {
      parts.add('assigned: true');
    }
    if (writeCaptured) {
      parts.add('writeCaptured: true');
    }
    return 'VariableModel(${parts.join(', ')})';
  }

  /// Returns a new [VariableModel] where the promoted type is replaced with
  /// [promotedType].
  VariableModel<Type> withPromotedType(Type promotedType) =>
      new VariableModel<Type>(promotedType, assigned, writeCaptured);

  /// Returns a new [VariableModel] reflecting the fact that the variable was
  /// just written to.
  VariableModel<Type> write() {
    if (promotedType == null && assigned) return this;
    return new VariableModel<Type>(null, true, writeCaptured);
  }

  /// Returns a new [VariableModel] reflecting the fact that the variable has
  /// been write-captured.
  VariableModel<Type> writeCapture() {
    return new VariableModel<Type>(null, assigned, true);
  }

  /// Joins two variable models.  See [FlowModel.join] for details.
  static VariableModel<Type> join<Type>(
      TypeOperations<Object, Type> typeOperations,
      VariableModel<Type> first,
      VariableModel<Type> second) {
    Type firstType = first.promotedType;
    Type secondType = second.promotedType;
    Type newPromotedType;
    if (identical(firstType, secondType)) {
      newPromotedType = firstType;
    } else if (firstType == null || secondType == null) {
      newPromotedType = null;
    } else if (typeOperations.isSubtypeOf(firstType, secondType)) {
      newPromotedType = secondType;
    } else if (typeOperations.isSubtypeOf(secondType, firstType)) {
      newPromotedType = firstType;
    } else {
      newPromotedType = null;
    }
    bool newAssigned = first.assigned && second.assigned;
    bool newWriteCaptured = first.writeCaptured || second.writeCaptured;
    return _identicalOrNew(
        first, second, newPromotedType, newAssigned, newWriteCaptured);
  }

  /// Creates a new [VariableModel] object, unless it is equivalent to either
  /// [first] or [second], in which case one of those objects is re-used.
  static VariableModel<Type> _identicalOrNew<Type>(
      VariableModel<Type> first,
      VariableModel<Type> second,
      Type newPromotedType,
      bool newAssigned,
      bool newWriteCaptured) {
    if (identical(first.promotedType, newPromotedType) &&
        first.assigned == newAssigned &&
        first.writeCaptured == newWriteCaptured) {
      return first;
    } else if (identical(second.promotedType, newPromotedType) &&
        second.assigned == newAssigned &&
        second.writeCaptured == newWriteCaptured) {
      return second;
    } else {
      return new VariableModel<Type>(
          newPromotedType, newAssigned, newWriteCaptured);
    }
  }
}

/// [_FlowContext] representing an assert statement or assert initializer.
class _AssertContext<Variable, Type> extends _SimpleContext<Variable, Type> {
  /// Flow models associated with the condition being asserted.
  _ExpressionInfo<Variable, Type> _conditionInfo;

  _AssertContext(FlowModel<Variable, Type> previous) : super(previous);

  @override
  String toString() =>
      '_AssertContext(previous: $_previous, conditionInfo: $_conditionInfo)';
}

/// [_FlowContext] representing a language construct that branches on a boolean
/// condition, such as an `if` statement, conditional expression, or a logical
/// binary operator.
class _BranchContext<Variable, Type> extends _FlowContext {
  /// Flow models associated with the condition being branched on.
  final _ExpressionInfo<Variable, Type> _conditionInfo;

  _BranchContext(this._conditionInfo);

  @override
  String toString() => '_BranchContext(conditionInfo: $_conditionInfo)';
}

/// [_FlowContext] representing a language construct that can be targeted by
/// `break` or `continue` statements, such as a loop or switch statement.
class _BranchTargetContext<Variable, Type> extends _FlowContext {
  /// Accumulated flow model for all `break` statements seen so far, or `null`
  /// if no `break` statements have been seen yet.
  FlowModel<Variable, Type> _breakModel;

  /// Accumulated flow model for all `continue` statements seen so far, or
  /// `null` if no `continue` statements have been seen yet.
  FlowModel<Variable, Type> _continueModel;

  @override
  String toString() => '_BranchTargetContext(breakModel: $_breakModel, '
      'continueModel: $_continueModel)';
}

/// [_FlowContext] representing a conditional expression.
class _ConditionalContext<Variable, Type>
    extends _BranchContext<Variable, Type> {
  /// Flow models associated with the value of the conditional expression in the
  /// circumstance where the "then" branch is taken.
  _ExpressionInfo<Variable, Type> _thenInfo;

  _ConditionalContext(_ExpressionInfo<Variable, Type> conditionInfo)
      : super(conditionInfo);

  @override
  String toString() => '_ConditionalContext(conditionInfo: $_conditionInfo, '
      'thenInfo: $_thenInfo)';
}

/// A collection of flow models representing the possible outcomes of evaluating
/// an expression that are relevant to flow analysis.
class _ExpressionInfo<Variable, Type> {
  /// The state after the expression evaluates, if we don't care what it
  /// evaluates to.
  final FlowModel<Variable, Type> _after;

  /// The state after the expression evaluates, if it evaluates to `true`.
  final FlowModel<Variable, Type> _ifTrue;

  /// The state after the expression evaluates, if it evaluates to `false`.
  final FlowModel<Variable, Type> _ifFalse;

  _ExpressionInfo(this._after, this._ifTrue, this._ifFalse);

  @override
  String toString() =>
      '_ExpressionInfo(after: $_after, _ifTrue: $_ifTrue, ifFalse: $_ifFalse)';
}

class _FlowAnalysisImpl<Node, Statement extends Node, Expression, Variable,
    Type> implements FlowAnalysis<Node, Statement, Expression, Variable, Type> {
  /// The [TypeOperations], used to access types, and check subtyping.
  final TypeOperations<Variable, Type> typeOperations;

  /// Stack of [_FlowContext] objects representing the statements and
  /// expressions that are currently being visited.
  final List<_FlowContext> _stack = [];

  /// The mapping from [Statement]s that can act as targets for `break` and
  /// `continue` statements (i.e. loops and switch statements) to the to their
  /// context information.
  final Map<Statement, _BranchTargetContext<Variable, Type>>
      _statementToContext = {};

  FlowModel<Variable, Type> _current;

  /// The most recently visited expression for which an [_ExpressionInfo] object
  /// exists, or `null` if no expression has been visited that has a
  /// corresponding [_ExpressionInfo] object.
  Expression _expressionWithInfo;

  /// If [_expressionWithInfo] is not `null`, the [_ExpressionInfo] object
  /// corresponding to it.  Otherwise `null`.
  _ExpressionInfo<Variable, Type> _expressionInfo;

  int _functionNestingLevel = 0;

  final AssignedVariables<Node, Variable> _assignedVariables;

  _FlowAnalysisImpl(this.typeOperations, this._assignedVariables) {
    _current = new FlowModel<Variable, Type>(true);
  }

  @override
  bool get isReachable => _current.reachable;

  @override
  void asExpression_end(Expression subExpression, Type type) {
    _ExpressionInfo<Variable, Type> subExpressionInfo =
        _getExpressionInfo(subExpression);
    Variable variable;
    if (subExpressionInfo is _VariableReadInfo<Variable, Type>) {
      variable = subExpressionInfo._variable;
    } else {
      return;
    }
    _current = _current.promote(typeOperations, variable, type);
  }

  @override
  void assert_afterCondition(Expression condition) {
    _AssertContext<Variable, Type> context =
        _stack.last as _AssertContext<Variable, Type>;
    _ExpressionInfo<Variable, Type> conditionInfo = _expressionEnd(condition);
    context._conditionInfo = conditionInfo;
    _current = conditionInfo._ifFalse;
  }

  @override
  void assert_begin() {
    _stack.add(new _AssertContext<Variable, Type>(_current));
  }

  @override
  void assert_end() {
    _AssertContext<Variable, Type> context =
        _stack.removeLast() as _AssertContext<Variable, Type>;
    _current = _join(context._previous, context._conditionInfo._ifTrue);
  }

  @override
  void booleanLiteral(Expression expression, bool value) {
    FlowModel<Variable, Type> unreachable = _current.setReachable(false);
    _storeExpressionInfo(
        expression,
        value
            ? new _ExpressionInfo(_current, _current, unreachable)
            : new _ExpressionInfo(_current, unreachable, _current));
  }

  @override
  void conditional_elseBegin(Expression thenExpression) {
    _ConditionalContext<Variable, Type> context =
        _stack.last as _ConditionalContext<Variable, Type>;
    context._thenInfo = _expressionEnd(thenExpression);
    _current = context._conditionInfo._ifFalse;
  }

  @override
  void conditional_end(
      Expression conditionalExpression, Expression elseExpression) {
    _ConditionalContext<Variable, Type> context =
        _stack.removeLast() as _ConditionalContext<Variable, Type>;
    _ExpressionInfo<Variable, Type> thenInfo = context._thenInfo;
    _ExpressionInfo<Variable, Type> elseInfo = _expressionEnd(elseExpression);
    _storeExpressionInfo(
        conditionalExpression,
        new _ExpressionInfo(
            _join(thenInfo._after, elseInfo._after),
            _join(thenInfo._ifTrue, elseInfo._ifTrue),
            _join(thenInfo._ifFalse, elseInfo._ifFalse)));
  }

  @override
  void conditional_thenBegin(Expression condition) {
    _ExpressionInfo<Variable, Type> conditionInfo = _expressionEnd(condition);
    _stack.add(new _ConditionalContext(conditionInfo));
    _current = conditionInfo._ifTrue;
  }

  @override
  void doStatement_bodyBegin(Statement doStatement) {
    Iterable<Variable> loopAssigned =
        _assignedVariables._getWrittenInNode(doStatement);
    Iterable<Variable> loopCaptured =
        _assignedVariables._getCapturedInNode(doStatement);
    _BranchTargetContext<Variable, Type> context =
        new _BranchTargetContext<Variable, Type>();
    _stack.add(context);
    _current = _current.removePromotedAll(loopAssigned, loopCaptured);
    _statementToContext[doStatement] = context;
  }

  @override
  void doStatement_conditionBegin() {
    _BranchTargetContext<Variable, Type> context =
        _stack.last as _BranchTargetContext<Variable, Type>;
    _current = _join(_current, context._continueModel);
  }

  @override
  void doStatement_end(Expression condition) {
    _BranchTargetContext<Variable, Type> context =
        _stack.removeLast() as _BranchTargetContext<Variable, Type>;
    _current = _join(_expressionEnd(condition)._ifFalse, context._breakModel);
  }

  @override
  void equalityOp_end(Expression wholeExpression, Expression rightOperand,
      {bool notEqual = false}) {
    _BranchContext<Variable, Type> context =
        _stack.removeLast() as _BranchContext<Variable, Type>;
    _ExpressionInfo<Variable, Type> lhsInfo = context._conditionInfo;
    _ExpressionInfo<Variable, Type> rhsInfo = _getExpressionInfo(rightOperand);
    Variable variable;
    if (lhsInfo is _NullInfo<Variable, Type> &&
        rhsInfo is _VariableReadInfo<Variable, Type>) {
      variable = rhsInfo._variable;
    } else if (rhsInfo is _NullInfo<Variable, Type> &&
        lhsInfo is _VariableReadInfo<Variable, Type>) {
      variable = lhsInfo._variable;
    } else {
      return;
    }
    FlowModel<Variable, Type> ifNotNull =
        _current.markNonNullable(typeOperations, variable);
    _storeExpressionInfo(
        wholeExpression,
        notEqual
            ? new _ExpressionInfo(_current, ifNotNull, _current)
            : new _ExpressionInfo(_current, _current, ifNotNull));
  }

  @override
  void equalityOp_rightBegin(Expression leftOperand) {
    _stack.add(
        new _BranchContext<Variable, Type>(_getExpressionInfo(leftOperand)));
  }

  @override
  void finish() {
    assert(_stack.isEmpty);
  }

  @override
  void for_bodyBegin(Statement node, Expression condition) {
    _ExpressionInfo<Variable, Type> conditionInfo = condition == null
        ? new _ExpressionInfo(_current, _current, _current.setReachable(false))
        : _expressionEnd(condition);
    _WhileContext<Variable, Type> context =
        new _WhileContext<Variable, Type>(conditionInfo);
    _stack.add(context);
    if (node != null) {
      _statementToContext[node] = context;
    }
    _current = conditionInfo._ifTrue;
  }

  @override
  void for_conditionBegin(Node node) {
    Iterable<Variable> loopAssigned =
        _assignedVariables._getWrittenInNode(node);
    Iterable<Variable> loopCaptured =
        _assignedVariables._getCapturedInNode(node);
    _current = _current.removePromotedAll(loopAssigned, loopCaptured);
  }

  @override
  void for_end() {
    _WhileContext<Variable, Type> context =
        _stack.removeLast() as _WhileContext<Variable, Type>;
    // Tail of the stack: falseCondition, break
    FlowModel<Variable, Type> breakState = context._breakModel;
    FlowModel<Variable, Type> falseCondition = context._conditionInfo._ifFalse;

    _current = _join(falseCondition, breakState);
  }

  @override
  void for_updaterBegin() {
    _WhileContext<Variable, Type> context =
        _stack.last as _WhileContext<Variable, Type>;
    _current = _join(_current, context._continueModel);
  }

  @override
  void forEach_bodyBegin(Node node, Variable loopVariable) {
    Iterable<Variable> loopAssigned =
        _assignedVariables._getWrittenInNode(node);
    Iterable<Variable> loopCaptured =
        _assignedVariables._getCapturedInNode(node);
    _SimpleStatementContext<Variable, Type> context =
        new _SimpleStatementContext<Variable, Type>(_current);
    _stack.add(context);
    _current = _current.removePromotedAll(loopAssigned, loopCaptured);
    if (loopVariable != null) {
      _current = _current.write(loopVariable);
    }
  }

  @override
  void forEach_end() {
    _SimpleStatementContext<Variable, Type> context =
        _stack.removeLast() as _SimpleStatementContext<Variable, Type>;
    _current = _join(_current, context._previous);
  }

  @override
  void functionExpression_begin(Node node) {
    Iterable<Variable> writeCaptured =
        _assignedVariables._getWrittenInNode(node);
    ++_functionNestingLevel;
    _current = _current.removePromotedAll(const [], writeCaptured);
    _stack.add(new _SimpleContext(_current));
    _current = _current.removePromotedAll(_assignedVariables._writtenAnywhere,
        _assignedVariables._capturedAnywhere);
  }

  @override
  void functionExpression_end() {
    --_functionNestingLevel;
    assert(_functionNestingLevel >= 0);
    _SimpleContext<Variable, Type> context =
        _stack.removeLast() as _SimpleContext<Variable, Type>;
    _current = context._previous;
  }

  @override
  void handleBreak(Statement target) {
    _BranchTargetContext<Variable, Type> context = _statementToContext[target];
    if (context != null) {
      context._breakModel = _join(context._breakModel, _current);
    }
    _current = _current.setReachable(false);
  }

  @override
  void handleContinue(Statement target) {
    _BranchTargetContext<Variable, Type> context = _statementToContext[target];
    if (context != null) {
      context._continueModel = _join(context._continueModel, _current);
    }
    _current = _current.setReachable(false);
  }

  @override
  void handleExit() {
    _current = _current.setReachable(false);
  }

  @override
  void ifNullExpression_end() {
    _SimpleContext<Variable, Type> context =
        _stack.removeLast() as _SimpleContext<Variable, Type>;
    _current = _join(_current, context._previous);
  }

  @override
  void ifNullExpression_rightBegin() {
    _stack.add(new _SimpleContext<Variable, Type>(_current));
  }

  @override
  void ifStatement_elseBegin() {
    _IfContext<Variable, Type> context =
        _stack.last as _IfContext<Variable, Type>;
    context._afterThen = _current;
    _current = context._conditionInfo._ifFalse;
  }

  @override
  void ifStatement_end(bool hasElse) {
    _IfContext<Variable, Type> context =
        _stack.removeLast() as _IfContext<Variable, Type>;
    FlowModel<Variable, Type> afterThen;
    FlowModel<Variable, Type> afterElse;
    if (hasElse) {
      afterThen = context._afterThen;
      afterElse = _current;
    } else {
      afterThen = _current; // no `else`, so `then` is still current
      afterElse = context._conditionInfo._ifFalse;
    }
    _current = _join(afterThen, afterElse);
  }

  @override
  void ifStatement_thenBegin(Expression condition) {
    _ExpressionInfo<Variable, Type> conditionInfo = _expressionEnd(condition);
    _stack.add(new _IfContext(conditionInfo));
    _current = conditionInfo._ifTrue;
  }

  @override
  void initialize(Variable variable) {
    _current = _current.write(variable);
  }

  @override
  bool isAssigned(Variable variable) {
    return _current.infoFor(variable).assigned;
  }

  @override
  void isExpression_end(Expression isExpression, Expression subExpression,
      bool isNot, Type type) {
    _ExpressionInfo<Variable, Type> subExpressionInfo =
        _getExpressionInfo(subExpression);
    Variable variable;
    if (subExpressionInfo is _VariableReadInfo<Variable, Type>) {
      variable = subExpressionInfo._variable;
    } else {
      return;
    }
    FlowModel<Variable, Type> promoted =
        _current.promote(typeOperations, variable, type);
    _storeExpressionInfo(
        isExpression,
        isNot
            ? new _ExpressionInfo(_current, _current, promoted)
            : new _ExpressionInfo(_current, promoted, _current));
  }

  @override
  void logicalBinaryOp_end(Expression wholeExpression, Expression rightOperand,
      {@required bool isAnd}) {
    _BranchContext<Variable, Type> context =
        _stack.removeLast() as _BranchContext<Variable, Type>;
    _ExpressionInfo<Variable, Type> rhsInfo = _expressionEnd(rightOperand);

    FlowModel<Variable, Type> trueResult;
    FlowModel<Variable, Type> falseResult;
    if (isAnd) {
      trueResult = rhsInfo._ifTrue;
      falseResult = _join(context._conditionInfo._ifFalse, rhsInfo._ifFalse);
    } else {
      trueResult = _join(context._conditionInfo._ifTrue, rhsInfo._ifTrue);
      falseResult = rhsInfo._ifFalse;
    }
    _storeExpressionInfo(
        wholeExpression,
        new _ExpressionInfo(
            _join(trueResult, falseResult), trueResult, falseResult));
  }

  @override
  void logicalBinaryOp_rightBegin(Expression leftOperand,
      {@required bool isAnd}) {
    _ExpressionInfo<Variable, Type> conditionInfo = _expressionEnd(leftOperand);
    _stack.add(new _BranchContext<Variable, Type>(conditionInfo));
    _current = isAnd ? conditionInfo._ifTrue : conditionInfo._ifFalse;
  }

  @override
  void logicalNot_end(Expression notExpression, Expression operand) {
    _ExpressionInfo<Variable, Type> conditionInfo = _expressionEnd(operand);
    _storeExpressionInfo(
        notExpression,
        new _ExpressionInfo(conditionInfo._after, conditionInfo._ifFalse,
            conditionInfo._ifTrue));
  }

  @override
  void nonNullAssert_end(Expression operand) {
    _ExpressionInfo<Variable, Type> operandInfo = _getExpressionInfo(operand);
    if (operandInfo is _VariableReadInfo<Variable, Type>) {
      _current =
          _current.markNonNullable(typeOperations, operandInfo._variable);
    }
  }

  @override
  void nullAwareAccess_end() {
    _SimpleContext<Variable, Type> context =
        _stack.removeLast() as _SimpleContext<Variable, Type>;
    _current = _join(_current, context._previous);
  }

  @override
  void nullAwareAccess_rightBegin(Expression target) {
    _stack.add(new _SimpleContext<Variable, Type>(_current));
    if (target != null) {
      _ExpressionInfo<Variable, Type> targetInfo = _getExpressionInfo(target);
      if (targetInfo is _VariableReadInfo<Variable, Type>) {
        _current =
            _current.markNonNullable(typeOperations, targetInfo._variable);
      }
    }
  }

  @override
  void nullLiteral(Expression expression) {
    _storeExpressionInfo(expression, new _NullInfo(_current));
  }

  @override
  void parenthesizedExpression(
      Expression outerExpression, Expression innerExpression) {
    if (identical(_expressionWithInfo, innerExpression)) {
      _expressionWithInfo = outerExpression;
    }
  }

  @override
  Type promotedType(Variable variable) {
    return _current.infoFor(variable).promotedType;
  }

  @override
  void switchStatement_beginCase(bool hasLabel, Node node) {
    Iterable<Variable> notPromoted = _assignedVariables._getWrittenInNode(node);
    Iterable<Variable> captured = _assignedVariables._getCapturedInNode(node);
    _SimpleStatementContext<Variable, Type> context =
        _stack.last as _SimpleStatementContext<Variable, Type>;
    if (hasLabel) {
      _current = context._previous.removePromotedAll(notPromoted, captured);
    } else {
      _current = context._previous;
    }
  }

  @override
  void switchStatement_end(bool hasDefault) {
    _SimpleStatementContext<Variable, Type> context =
        _stack.removeLast() as _SimpleStatementContext<Variable, Type>;
    FlowModel<Variable, Type> breakState = context._breakModel;

    // It is allowed to "fall off" the end of a switch statement, so join the
    // current state to any breaks that were found previously.
    breakState = _join(breakState, _current);

    // And, if there is an implicit fall-through default, join it to any breaks.
    if (!hasDefault) breakState = _join(breakState, context._previous);

    _current = breakState;
  }

  @override
  void switchStatement_expressionEnd(Statement switchStatement) {
    _SimpleStatementContext<Variable, Type> context =
        new _SimpleStatementContext<Variable, Type>(_current);
    _stack.add(context);
    _statementToContext[switchStatement] = context;
  }

  @override
  void tryCatchStatement_bodyBegin() {
    _stack.add(new _TryContext<Variable, Type>(_current));
  }

  @override
  void tryCatchStatement_bodyEnd(Node body) {
    Iterable<Variable> assignedInBody =
        _assignedVariables._getWrittenInNode(body);
    Iterable<Variable> capturedInBody =
        _assignedVariables._getCapturedInNode(body);
    _TryContext<Variable, Type> context =
        _stack.last as _TryContext<Variable, Type>;
    FlowModel<Variable, Type> beforeBody = context._previous;
    FlowModel<Variable, Type> beforeCatch =
        beforeBody.removePromotedAll(assignedInBody, capturedInBody);
    context._beforeCatch = beforeCatch;
    context._afterBodyAndCatches = _current;
  }

  @override
  void tryCatchStatement_catchBegin(
      Variable exceptionVariable, Variable stackTraceVariable) {
    _TryContext<Variable, Type> context =
        _stack.last as _TryContext<Variable, Type>;
    _current = context._beforeCatch;
    if (exceptionVariable != null) {
      _current = _current.write(exceptionVariable);
    }
    if (stackTraceVariable != null) {
      _current = _current.write(stackTraceVariable);
    }
  }

  @override
  void tryCatchStatement_catchEnd() {
    _TryContext<Variable, Type> context =
        _stack.last as _TryContext<Variable, Type>;
    context._afterBodyAndCatches =
        _join(context._afterBodyAndCatches, _current);
  }

  @override
  void tryCatchStatement_end() {
    _TryContext<Variable, Type> context =
        _stack.removeLast() as _TryContext<Variable, Type>;
    _current = context._afterBodyAndCatches;
  }

  @override
  void tryFinallyStatement_bodyBegin() {
    _stack.add(new _TryContext<Variable, Type>(_current));
  }

  @override
  void tryFinallyStatement_end(Node finallyBlock) {
    Iterable<Variable> assignedInFinally =
        _assignedVariables._getWrittenInNode(finallyBlock);
    _TryContext<Variable, Type> context =
        _stack.removeLast() as _TryContext<Variable, Type>;
    _current = _current.restrict(
        typeOperations, context._afterBodyAndCatches, assignedInFinally);
  }

  @override
  void tryFinallyStatement_finallyBegin(Node body) {
    Iterable<Variable> assignedInBody =
        _assignedVariables._getWrittenInNode(body);
    Iterable<Variable> capturedInBody =
        _assignedVariables._getCapturedInNode(body);
    _TryContext<Variable, Type> context =
        _stack.last as _TryContext<Variable, Type>;
    context._afterBodyAndCatches = _current;
    _current = _join(_current,
        context._previous.removePromotedAll(assignedInBody, capturedInBody));
  }

  @override
  Type variableRead(Expression expression, Variable variable) {
    _storeExpressionInfo(expression, new _VariableReadInfo(_current, variable));
    return _current.infoFor(variable).promotedType;
  }

  @override
  void whileStatement_bodyBegin(
      Statement whileStatement, Expression condition) {
    _ExpressionInfo<Variable, Type> conditionInfo = _expressionEnd(condition);
    _WhileContext<Variable, Type> context =
        new _WhileContext<Variable, Type>(conditionInfo);
    _stack.add(context);
    _statementToContext[whileStatement] = context;
    _current = conditionInfo._ifTrue;
  }

  @override
  void whileStatement_conditionBegin(Node node) {
    Iterable<Variable> loopAssigned =
        _assignedVariables._getWrittenInNode(node);
    Iterable<Variable> loopCaptured =
        _assignedVariables._getCapturedInNode(node);
    _current = _current.removePromotedAll(loopAssigned, loopCaptured);
  }

  @override
  void whileStatement_end() {
    _WhileContext<Variable, Type> context =
        _stack.removeLast() as _WhileContext<Variable, Type>;
    _current = _join(context._conditionInfo._ifFalse, context._breakModel);
  }

  @override
  void write(Variable variable) {
    assert(
        _assignedVariables._writtenAnywhere.contains(variable),
        "Variable is written to, but was not included in "
        "_variablesWrittenAnywhere: $variable");
    _current = _current.write(variable);
  }

  void _dumpState() {
    print('  current: $_current');
    print('  expressionWithInfo: $_expressionWithInfo');
    print('  expressionInfo: $_expressionInfo');
    print('  stack:');
    for (_FlowContext stackEntry in _stack.reversed) {
      print('    $stackEntry');
    }
  }

  /// Gets the [_ExpressionInfo] associated with the [expression] (which should
  /// be the last expression that was traversed).  If there is no
  /// [_ExpressionInfo] associated with the [expression], then a fresh
  /// [_ExpressionInfo] is created recording the current flow analysis state.
  _ExpressionInfo<Variable, Type> _expressionEnd(Expression expression) =>
      _getExpressionInfo(expression) ??
      new _ExpressionInfo(_current, _current, _current);

  /// Gets the [_ExpressionInfo] associated with the [expression] (which should
  /// be the last expression that was traversed).  If there is no
  /// [_ExpressionInfo] associated with the [expression], then `null` is
  /// returned.
  _ExpressionInfo<Variable, Type> _getExpressionInfo(Expression expression) {
    if (identical(expression, _expressionWithInfo)) {
      _ExpressionInfo<Variable, Type> expressionInfo = _expressionInfo;
      _expressionInfo = null;
      return expressionInfo;
    } else {
      return null;
    }
  }

  FlowModel<Variable, Type> _join(
          FlowModel<Variable, Type> first, FlowModel<Variable, Type> second) =>
      FlowModel.join(typeOperations, first, second);

  /// Associates [expression], which should be the most recently visited
  /// expression, with the given [expressionInfo] object, and updates the
  /// current flow model state to correspond to it.
  void _storeExpressionInfo(
      Expression expression, _ExpressionInfo<Variable, Type> expressionInfo) {
    _expressionWithInfo = expression;
    _expressionInfo = expressionInfo;
    _current = expressionInfo._after;
  }
}

/// Base class for objects representing constructs in the Dart programming
/// language for which flow analysis information needs to be tracked.
abstract class _FlowContext {}

/// [_FlowContext] representing an `if` statement.
class _IfContext<Variable, Type> extends _BranchContext<Variable, Type> {
  /// Flow model associated with the state of program execution after the `if`
  /// statement executes, in the circumstance where the "then" branch is taken.
  FlowModel<Variable, Type> _afterThen;

  _IfContext(_ExpressionInfo<Variable, Type> conditionInfo)
      : super(conditionInfo);

  @override
  String toString() =>
      '_IfContext(conditionInfo: $_conditionInfo, afterThen: $_afterThen)';
}

/// [_ExpressionInfo] representing a `null` literal.
class _NullInfo<Variable, Type> implements _ExpressionInfo<Variable, Type> {
  @override
  final FlowModel<Variable, Type> _after;

  _NullInfo(this._after);

  @override
  FlowModel<Variable, Type> get _ifFalse => _after;

  @override
  FlowModel<Variable, Type> get _ifTrue => _after;
}

/// [_FlowContext] representing a language construct for which flow analysis
/// must store a flow model state to be retrieved later, such as a `try`
/// statement, function expression, or "if-null" (`??`) expression.
class _SimpleContext<Variable, Type> extends _FlowContext {
  /// The stored state.  For a `try` statement, this is the state from the
  /// beginning of the `try` block.  For a function expression, this is the
  /// state at the point the function expression was created.  For an "if-null"
  /// expression, this is the state after execution of the expression before the
  /// `??`.
  final FlowModel<Variable, Type> _previous;

  _SimpleContext(this._previous);

  @override
  String toString() => '_SimpleContext(previous: $_previous)';
}

/// [_FlowContext] representing a language construct that can be targeted by
/// `break` or `continue` statements, and for which flow analysis must store a
/// flow model state to be retrieved later.  Examples include "for each" and
/// `switch` statements.
class _SimpleStatementContext<Variable, Type>
    extends _BranchTargetContext<Variable, Type> {
  /// The stored state.  For a "for each" statement, this is the state after
  /// evaluation of the iterable.  For a `switch` statement, this is the state
  /// after evaluation of the switch expression.
  final FlowModel<Variable, Type> _previous;

  _SimpleStatementContext(this._previous);

  @override
  String toString() => '_SimpleStatementContext(breakModel: $_breakModel, '
      'continueModel: $_continueModel, previous: $_previous)';
}

/// [_FlowContext] representing a try statement.
class _TryContext<Variable, Type> extends _SimpleContext<Variable, Type> {
  /// If the statement is a "try/catch" statement, the flow model representing
  /// program state at the top of any `catch` block.
  FlowModel<Variable, Type> _beforeCatch;

  /// If the statement is a "try/catch" statement, the accumulated flow model
  /// representing program state after the `try` block or one of the `catch`
  /// blocks has finished executing.  If the statement is a "try/finally"
  /// statement, the flow model representing program state after the `try` block
  /// has finished executing.
  FlowModel<Variable, Type> _afterBodyAndCatches;

  _TryContext(FlowModel<Variable, Type> previous) : super(previous);

  @override
  String toString() =>
      '_TryContext(previous: $_previous, beforeCatch: $_beforeCatch, '
      'afterBodyAndCatches: $_afterBodyAndCatches)';
}

/// [_ExpressionInfo] representing an expression that reads the value of a
/// variable.
class _VariableReadInfo<Variable, Type>
    implements _ExpressionInfo<Variable, Type> {
  @override
  final FlowModel<Variable, Type> _after;

  /// The variable that is being read.
  final Variable _variable;

  _VariableReadInfo(this._after, this._variable);

  @override
  FlowModel<Variable, Type> get _ifFalse => _after;

  @override
  FlowModel<Variable, Type> get _ifTrue => _after;

  @override
  String toString() =>
      '_VariableReadInfo(after: $_after, variable: $_variable)';
}

/// [_FlowContext] representing a `while` loop (or a C-style `for` loop, which
/// is functionally similar).
class _WhileContext<Variable, Type>
    extends _BranchTargetContext<Variable, Type> {
  /// Flow models associated with the loop condition.
  final _ExpressionInfo<Variable, Type> _conditionInfo;

  _WhileContext(this._conditionInfo);

  @override
  String toString() => '_WhileContext(breakModel: $_breakModel, '
      'continueModel: $_continueModel, conditionInfo: $_conditionInfo)';
}
