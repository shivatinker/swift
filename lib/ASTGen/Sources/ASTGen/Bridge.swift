//===--- Bridge.swift -----------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2022-2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

import ASTBridging
import BasicBridging
import SwiftSyntax

protocol BridgedNullable: ExpressibleByNilLiteral {
  associatedtype RawPtr
  init(raw: RawPtr?)
}
extension BridgedNullable {
  public init(nilLiteral: ()) {
    self.init(raw: nil)
  }
}

extension BridgedSourceLoc: BridgedNullable {}
extension BridgedIdentifier: BridgedNullable {}
extension BridgedNullableExpr: BridgedNullable {}
extension BridgedNullableStmt: BridgedNullable {}
extension BridgedNullableTypeRepr: BridgedNullable {}
extension BridgedNullablePattern: BridgedNullable {}
extension BridgedNullableGenericParamList: BridgedNullable {}
extension BridgedNullableTrailingWhereClause: BridgedNullable {}
extension BridgedNullableParameterList: BridgedNullable {}

/// Protocol that declares that there's a "Nullable" variation of the type.
///
/// E.g. BridgedExpr vs BridgedNullableExpr.
protocol BridgedHasNullable {
  associatedtype Nullable: BridgedNullable
  var raw: Nullable.RawPtr { get }
}
extension Optional where Wrapped: BridgedHasNullable {
  /// Convert an Optional to Nullable variation of the wrapped type.
  var asNullable: Wrapped.Nullable {
    Wrapped.Nullable(raw: self?.raw)
  }
}

extension BridgedStmt: BridgedHasNullable {
  typealias Nullable = BridgedNullableStmt
}
extension BridgedExpr: BridgedHasNullable {
  typealias Nullable = BridgedNullableExpr
}
extension BridgedTypeRepr: BridgedHasNullable {
  typealias Nullable = BridgedNullableTypeRepr
}
extension BridgedGenericParamList: BridgedHasNullable {
  typealias Nullable = BridgedNullableGenericParamList
}
extension BridgedTrailingWhereClause: BridgedHasNullable {
  typealias Nullable = BridgedNullableTrailingWhereClause
}
extension BridgedParameterList: BridgedHasNullable {
  typealias Nullable = BridgedNullableParameterList
}

public extension BridgedSourceLoc {
  /// Form a source location at the given absolute position in `buffer`.
  init(
    at position: AbsolutePosition,
    in buffer: UnsafeBufferPointer<UInt8>
  ) {
    precondition(position.utf8Offset >= 0 && position.utf8Offset <= buffer.count)
    self = BridgedSourceLoc(raw: buffer.baseAddress!).advanced(by: position.utf8Offset)
  }
}

extension BridgedSourceRange {
  @inline(__always)
  init(startToken: TokenSyntax, endToken: TokenSyntax, in astgen: ASTGenVisitor) {
    self.init(start: startToken.bridgedSourceLoc(in: astgen), end: endToken.bridgedSourceLoc(in: astgen))
  }
}

extension String {
  init(bridged: BridgedStringRef) {
    self.init(
      decoding: UnsafeBufferPointer(start: bridged.data, count: bridged.count),
      as: UTF8.self
    )
  }

  mutating func withBridgedString<R>(_ body: (BridgedStringRef) throws -> R) rethrows -> R {
    try withUTF8 { buffer in
      try body(BridgedStringRef(data: buffer.baseAddress, count: buffer.count))
    }
  }
}

/// Allocate a copy of the given string as a null-terminated UTF-8 string.
func allocateBridgedString(
  _ string: String
) -> BridgedStringRef {
  var string = string
  return string.withUTF8 { utf8 in
    let ptr = UnsafeMutablePointer<UInt8>.allocate(
      capacity: utf8.count + 1
    )
    if let baseAddress = utf8.baseAddress {
      ptr.initialize(from: baseAddress, count: utf8.count)
    }

    // null terminate, for client's convenience.
    ptr[utf8.count] = 0

    return BridgedStringRef(data: ptr, count: utf8.count)
  }
}

@_cdecl("swift_ASTGen_freeBridgedString")
public func freeBridgedString(bridged: BridgedStringRef) {
  bridged.data?.deallocate()
}

extension BridgedStringRef {
  var isEmptyInitialized: Bool {
    return self.data == nil && self.count == 0
  }
}

extension SyntaxProtocol {
  /// Obtains the bridged start location of the node excluding leading trivia in the source buffer provided by `astgen`
  ///
  /// - Parameter astgen: The visitor providing the source buffer.
  @inline(__always)
  func bridgedSourceLoc(in astgen: ASTGenVisitor) -> BridgedSourceLoc {
    return BridgedSourceLoc(at: self.positionAfterSkippingLeadingTrivia, in: astgen.base)
  }
}

extension Optional where Wrapped: SyntaxProtocol {
  /// Obtains the bridged start location of the node excluding leading trivia in the source buffer provided by `astgen`.
  ///
  /// - Parameter astgen: The visitor providing the source buffer.
  @inline(__always)
  func bridgedSourceLoc(in astgen: ASTGenVisitor) -> BridgedSourceLoc {
    guard let self else {
      return nil
    }

    return self.bridgedSourceLoc(in: astgen)
  }
}

extension TokenSyntax {
  /// Obtains a bridged, `ASTContext`-owned copy of this token's text.
  ///
  /// - Parameter astgen: The visitor providing the `ASTContext`.
  @inline(__always)
  func bridgedIdentifier(in astgen: ASTGenVisitor) -> BridgedIdentifier {
    var text = self.text
    return text.withBridgedString { bridged in
      astgen.ctx.getIdentifier(bridged)
    }
  }

  /// Obtains a bridged, `ASTContext`-owned copy of this token's text, and its bridged start location in the
  /// source buffer provided by `astgen`.
  ///
  /// - Parameter astgen: The visitor providing the `ASTContext` and source buffer.
  @inline(__always)
  func bridgedIdentifierAndSourceLoc(in astgen: ASTGenVisitor) -> (BridgedIdentifier, BridgedSourceLoc) {
    return (self.bridgedIdentifier(in: astgen), self.bridgedSourceLoc(in: astgen))
  }

  /// Obtains a bridged, `ASTContext`-owned copy of this token's text, and its bridged start location in the
  /// source buffer provided by `astgen`.
  ///
  /// - Parameter astgen: The visitor providing the `ASTContext` and source buffer.
  @inline(__always)
  func bridgedIdentifierAndSourceLoc(in astgen: ASTGenVisitor) -> BridgedIdentifierAndSourceLoc {
    let (name, nameLoc) = self.bridgedIdentifierAndSourceLoc(in: astgen)
    return .init(name: name, nameLoc: nameLoc)
  }
}

extension Optional<TokenSyntax> {
  /// Obtains a bridged, `ASTContext`-owned copy of this token's text.
  ///
  /// - Parameter astgen: The visitor providing the `ASTContext`.
  @inline(__always)
  func bridgedIdentifier(in astgen: ASTGenVisitor) -> BridgedIdentifier {
    guard let self else {
      return nil
    }

    return self.bridgedIdentifier(in: astgen)
  }

  /// Obtains a bridged, `ASTContext`-owned copy of this token's text, and its bridged start location in the
  /// source buffer provided by `astgen` excluding leading trivia.
  ///
  /// - Parameter astgen: The visitor providing the `ASTContext` and source buffer.
  @inline(__always)
  func bridgedIdentifierAndSourceLoc(in astgen: ASTGenVisitor) -> (BridgedIdentifier, BridgedSourceLoc) {
    guard let self else {
      return (nil, nil)
    }

    return self.bridgedIdentifierAndSourceLoc(in: astgen)
  }
}
