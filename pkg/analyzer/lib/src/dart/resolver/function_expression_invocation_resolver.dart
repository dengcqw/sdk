// Copyright (c) 2020, the Dart project authors. Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:analyzer/error/listener.dart';
import 'package:analyzer/src/dart/ast/ast.dart';
import 'package:analyzer/src/dart/element/type.dart';
import 'package:analyzer/src/dart/resolver/extension_member_resolver.dart';
import 'package:analyzer/src/dart/resolver/invocation_inference_helper.dart';
import 'package:analyzer/src/dart/resolver/type_property_resolver.dart';
import 'package:analyzer/src/error/codes.dart';
import 'package:analyzer/src/generated/element_type_provider.dart';
import 'package:analyzer/src/generated/resolver.dart';
import 'package:meta/meta.dart';

/// Helper for resolving [FunctionExpressionInvocation]s.
class FunctionExpressionInvocationResolver {
  final ResolverVisitor _resolver;
  final ElementTypeProvider _elementTypeProvider;
  final TypePropertyResolver _typePropertyResolver;
  final InvocationInferenceHelper _inferenceHelper;

  FunctionExpressionInvocationResolver({
    @required ResolverVisitor resolver,
    @required ElementTypeProvider elementTypeProvider,
  })  : _resolver = resolver,
        _elementTypeProvider = elementTypeProvider,
        _typePropertyResolver = resolver.typePropertyResolver,
        _inferenceHelper = resolver.inferenceHelper;

  ErrorReporter get _errorReporter => _resolver.errorReporter;

  ExtensionMemberResolver get _extensionResolver => _resolver.extensionResolver;

  void resolve(FunctionExpressionInvocationImpl node) {
    var rawType = _resolveCallElement(node);

    if (rawType == null) {
      _setExplicitTypeArgumentTypes(node);
      _resolveArguments(node);
      node.staticInvokeType = DynamicTypeImpl.instance;
      node.staticType = DynamicTypeImpl.instance;
      return;
    }

    _inferenceHelper.resolveFunctionExpressionInvocation(
      node: node,
      rawType: rawType,
    );

    var returnType = _inferenceHelper.computeInvokeReturnType(
      node.staticInvokeType,
      isNullAware: false,
    );
    _inferenceHelper.recordStaticType(node, returnType);
  }

  void _resolveArguments(FunctionExpressionInvocationImpl node) {
    node.argumentList.accept(_resolver);
  }

  FunctionType _resolveCallElement(FunctionExpressionInvocation node) {
    Expression function = node.function;

    if (function is ExtensionOverride) {
      var result = _extensionResolver.getOverrideMember(
        function,
        FunctionElement.CALL_METHOD_NAME,
      );
      var callElement = result.getter;
      node.staticElement = callElement;

      if (callElement == null) {
        _errorReporter.reportErrorForNode(
          CompileTimeErrorCode.INVOCATION_OF_EXTENSION_WITHOUT_CALL,
          function,
          [function.extensionName.name],
        );
        return null;
      }

      if (callElement.isStatic) {
        _errorReporter.reportErrorForNode(
          CompileTimeErrorCode.EXTENSION_OVERRIDE_ACCESS_TO_STATIC_MEMBER,
          node.argumentList,
        );
      }

      return _elementTypeProvider.getExecutableType(callElement);
    }

    var receiverType = function.staticType;
    if (receiverType is FunctionType) {
      return receiverType;
    }

    if (receiverType is InterfaceType) {
      var result = _typePropertyResolver.resolve(
        receiver: function,
        receiverType: receiverType,
        name: FunctionElement.CALL_METHOD_NAME,
        receiverErrorNode: function,
        nameErrorNode: function,
      );
      var callElement = result.getter;

      if (callElement?.kind != ElementKind.METHOD) {
        return null;
      }

      node.staticElement = callElement;
      return _elementTypeProvider.getExecutableType(callElement);
    }

    return null;
  }

  /// Inference cannot be done, we still want to fill type argument types.
  static void _setExplicitTypeArgumentTypes(
    FunctionExpressionInvocationImpl node,
  ) {
    var typeArguments = node.typeArguments;
    if (typeArguments != null) {
      node.typeArgumentTypes = typeArguments.arguments
          .map((typeArgument) => typeArgument.type)
          .toList();
    } else {
      node.typeArgumentTypes = const <DartType>[];
    }
  }
}
