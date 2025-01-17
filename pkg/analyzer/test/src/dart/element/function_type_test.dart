// Copyright (c) 2018, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/src/dart/element/element.dart';
import 'package:analyzer/src/dart/element/member.dart';
import 'package:analyzer/src/dart/element/type.dart';
import 'package:analyzer/src/generated/resolver.dart';
import 'package:analyzer/src/generated/testing/test_type_provider.dart';
import 'package:test/test.dart';
import 'package:test_reflective_loader/test_reflective_loader.dart';

import '../../../generated/elements_types_mixin.dart';

main() {
  defineReflectiveSuite(() {
    defineReflectiveTests(FunctionTypeTest);
  });
}

DynamicTypeImpl get dynamicType => DynamicTypeImpl.instance;

VoidTypeImpl get voidType => VoidTypeImpl.instance;

Element getBaseElement(Element e) {
  if (e is Member) {
    return e.baseElement;
  } else {
    return e;
  }
}

@reflectiveTest
class FunctionTypeTest with ElementsTypesMixin {
  final TypeProvider typeProvider = TestTypeProvider();

  InterfaceType get intType => typeProvider.intType;

  ClassElement get listElement => typeProvider.listElement;

  ClassElement get mapElement => typeProvider.mapElement;

  InterfaceType get objectType => typeProvider.objectType;

  void basicChecks(FunctionType f,
      {element,
      displayName: 'dynamic Function()',
      returnType,
      namedParameterTypes: isEmpty,
      normalParameterNames: isEmpty,
      normalParameterTypes: isEmpty,
      optionalParameterNames: isEmpty,
      optionalParameterTypes: isEmpty,
      parameters: isEmpty,
      typeFormals: isEmpty,
      typeArguments: isEmpty,
      typeParameters: isEmpty,
      name: isNull}) {
    // DartType properties
    expect(f.displayName, displayName, reason: 'displayName');
    expect(f.element, element, reason: 'element');
    expect(f.name, name, reason: 'name');
    // ParameterizedType properties
    expect(f.typeArguments, typeArguments, reason: 'typeArguments');
    expect(f.typeParameters, typeParameters, reason: 'typeParameters');
    // FunctionType properties
    expect(f.namedParameterTypes, namedParameterTypes,
        reason: 'namedParameterTypes');
    expect(f.normalParameterNames, normalParameterNames,
        reason: 'normalParameterNames');
    expect(f.normalParameterTypes, normalParameterTypes,
        reason: 'normalParameterTypes');
    expect(f.optionalParameterNames, optionalParameterNames,
        reason: 'optionalParameterNames');
    expect(f.optionalParameterTypes, optionalParameterTypes,
        reason: 'optionalParameterTypes');
    expect(f.parameters, parameters, reason: 'parameters');
    expect(f.returnType, returnType ?? same(dynamicType), reason: 'returnType');
    expect(f.typeFormals, typeFormals, reason: 'typeFormals');
  }

  GenericTypeAliasElementImpl genericTypeAliasElement(
    String name, {
    List<ParameterElement> parameters: const [],
    DartType returnType,
    List<TypeParameterElement> typeParameters: const [],
    List<TypeParameterElement> innerTypeParameters: const [],
  }) {
    var aliasElement = GenericTypeAliasElementImpl(name, 0);
    aliasElement.typeParameters = typeParameters;

    var functionElement = GenericFunctionTypeElementImpl.forOffset(0);
    aliasElement.function = functionElement;
    functionElement.typeParameters = innerTypeParameters;
    functionElement.parameters = parameters;
    functionElement.returnType = returnType;

    return aliasElement;
  }

  DartType listOf(DartType elementType) => listElement.instantiate(
        typeArguments: [elementType],
        nullabilitySuffix: NullabilitySuffix.star,
      );

  DartType mapOf(DartType keyType, DartType valueType) =>
      mapElement.instantiate(
        typeArguments: [keyType, valueType],
        nullabilitySuffix: NullabilitySuffix.star,
      );

  test_synthetic() {
    FunctionType f = new FunctionTypeImpl.synthetic(dynamicType, [], [],
        nullabilitySuffix: NullabilitySuffix.star);
    basicChecks(f, element: isNull);
  }

  test_synthetic_instantiate() {
    // T Function<T>(T x)
    var t = typeParameter('T');
    var x = requiredParameter(name: 'x', type: typeParameterType(t));
    FunctionType f = new FunctionTypeImpl.synthetic(
        typeParameterType(t), [t], [x],
        nullabilitySuffix: NullabilitySuffix.star);
    FunctionType instantiated = f.instantiate([objectType]);
    basicChecks(instantiated,
        element: isNull,
        displayName: 'Object Function(Object)',
        returnType: same(objectType),
        normalParameterNames: ['x'],
        normalParameterTypes: [same(objectType)],
        parameters: hasLength(1));
  }

  test_synthetic_instantiate_argument_length_mismatch() {
    // dynamic Function<T>()
    var t = typeParameter('T');
    FunctionType f = new FunctionTypeImpl.synthetic(dynamicType, [t], [],
        nullabilitySuffix: NullabilitySuffix.star);
    expect(() => f.instantiate([]), throwsA(new TypeMatcher<ArgumentError>()));
  }

  test_synthetic_instantiate_no_type_formals() {
    FunctionType f = new FunctionTypeImpl.synthetic(dynamicType, [], [],
        nullabilitySuffix: NullabilitySuffix.star);
    expect(f.instantiate([]), same(f));
  }

  test_synthetic_instantiate_share_parameters() {
    // T Function<T>(int x)
    var t = typeParameter('T');
    var x = requiredParameter(name: 'x', type: intType);
    FunctionType f = new FunctionTypeImpl.synthetic(
        typeParameterType(t), [t], [x],
        nullabilitySuffix: NullabilitySuffix.star);
    FunctionType instantiated = f.instantiate([objectType]);
    basicChecks(instantiated,
        element: isNull,
        displayName: 'Object Function(int)',
        returnType: same(objectType),
        normalParameterNames: ['x'],
        normalParameterTypes: [same(intType)],
        parameters: same(f.parameters));
  }

  test_synthetic_namedParameter() {
    var p = namedParameter(name: 'x', type: objectType);
    FunctionType f = new FunctionTypeImpl.synthetic(dynamicType, [], [p],
        nullabilitySuffix: NullabilitySuffix.star);
    basicChecks(f,
        element: isNull,
        displayName: 'dynamic Function({x: Object})',
        namedParameterTypes: {'x': same(objectType)},
        parameters: hasLength(1));
    expect(f.parameters[0].isNamed, isTrue);
    expect(f.parameters[0].name, 'x');
    expect(f.parameters[0].type, same(objectType));
  }

  test_synthetic_normalParameter() {
    var p = requiredParameter(name: 'x', type: objectType);
    FunctionType f = new FunctionTypeImpl.synthetic(dynamicType, [], [p],
        nullabilitySuffix: NullabilitySuffix.star);
    basicChecks(f,
        element: isNull,
        displayName: 'dynamic Function(Object)',
        normalParameterNames: ['x'],
        normalParameterTypes: [same(objectType)],
        parameters: hasLength(1));
    expect(f.parameters[0].isRequiredPositional, isTrue);
    expect(f.parameters[0].name, 'x');
    expect(f.parameters[0].type, same(objectType));
  }

  test_synthetic_optionalParameter() {
    var p = positionalParameter(name: 'x', type: objectType);
    FunctionType f = new FunctionTypeImpl.synthetic(dynamicType, [], [p],
        nullabilitySuffix: NullabilitySuffix.star);
    basicChecks(f,
        element: isNull,
        displayName: 'dynamic Function([Object])',
        optionalParameterNames: ['x'],
        optionalParameterTypes: [same(objectType)],
        parameters: hasLength(1));
    expect(f.parameters[0].isOptionalPositional, isTrue);
    expect(f.parameters[0].name, 'x');
    expect(f.parameters[0].type, same(objectType));
  }

  test_synthetic_returnType() {
    FunctionType f = new FunctionTypeImpl.synthetic(objectType, [], [],
        nullabilitySuffix: NullabilitySuffix.star);
    basicChecks(f,
        element: isNull,
        displayName: 'Object Function()',
        returnType: same(objectType));
  }

  @deprecated
  test_synthetic_substitute() {
    // Map<T, U> Function<U extends T>(T x, U y)
    var t = typeParameter('T');
    var u = typeParameter('U', bound: typeParameterType(t));
    var x = requiredParameter(name: 'x', type: typeParameterType(t));
    var y = requiredParameter(name: 'y', type: typeParameterType(u));
    FunctionType f = new FunctionTypeImpl.synthetic(
        mapOf(typeParameterType(t), typeParameterType(u)), [u], [x, y],
        nullabilitySuffix: NullabilitySuffix.star);
    FunctionType substituted =
        f.substitute2([objectType], [typeParameterType(t)]);
    var uSubstituted = substituted.typeFormals[0];
    basicChecks(substituted,
        element: isNull,
        displayName: 'Map<Object, U> Function<U extends Object>(Object, U)',
        returnType: mapOf(objectType, typeParameterType(uSubstituted)),
        typeFormals: [uSubstituted],
        normalParameterNames: ['x', 'y'],
        normalParameterTypes: [
          same(objectType),
          typeParameterType(uSubstituted)
        ],
        parameters: hasLength(2));
  }

  @deprecated
  test_synthetic_substitute_argument_length_mismatch() {
    // dynamic Function()
    var t = typeParameter('T');
    FunctionType f = new FunctionTypeImpl.synthetic(dynamicType, [], [],
        nullabilitySuffix: NullabilitySuffix.star);
    expect(() => f.substitute2([], [typeParameterType(t)]),
        throwsA(new TypeMatcher<ArgumentError>()));
  }

  @deprecated
  test_synthetic_substitute_unchanged() {
    // dynamic Function<U>(U x)
    var t = typeParameter('T');
    var u = typeParameter('U');
    var x = requiredParameter(name: 'x', type: typeParameterType(u));
    FunctionType f = new FunctionTypeImpl.synthetic(dynamicType, [u], [x],
        nullabilitySuffix: NullabilitySuffix.star);
    FunctionType substituted =
        f.substitute2([objectType], [typeParameterType(t)]);
    expect(substituted, same(f));
  }

  test_synthetic_typeFormals() {
    var t = typeParameter('T');
    FunctionType f = new FunctionTypeImpl.synthetic(
        typeParameterType(t), [t], [],
        nullabilitySuffix: NullabilitySuffix.star);
    basicChecks(f,
        element: isNull,
        displayName: 'T Function<T>()',
        returnType: typeParameterType(t),
        typeFormals: [same(t)]);
  }
}

class MockCompilationUnitElement implements CompilationUnitElement {
  const MockCompilationUnitElement();

  @override
  get enclosingElement => const MockLibraryElement();

  noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

class MockFunctionTypedElement implements FunctionTypedElement {
  @override
  final List<ParameterElement> parameters;

  @override
  final DartType returnType;

  @override
  final List<TypeParameterElement> typeParameters;

  @override
  final Element enclosingElement;

  MockFunctionTypedElement(
      {this.parameters: const [],
      DartType returnType,
      this.typeParameters: const [],
      this.enclosingElement: const MockCompilationUnitElement()})
      : returnType = returnType ?? dynamicType;

  MockFunctionTypedElement.withNullReturn(
      {this.parameters: const [],
      this.typeParameters: const [],
      this.enclosingElement: const MockCompilationUnitElement()})
      : returnType = null;

  noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}

class MockLibraryElement implements LibraryElement {
  const MockLibraryElement();

  @override
  get enclosingElement => null;

  noSuchMethod(Invocation invocation) {
    return super.noSuchMethod(invocation);
  }
}
