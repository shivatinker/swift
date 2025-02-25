//===----------------------------------------------------------------------===//
//
// This source file is part of the Swift.org open source project
//
// Copyright (c) 2022 - 2023 Apple Inc. and the Swift project authors
// Licensed under Apache License v2.0 with Runtime Library Exception
//
// See https://swift.org/LICENSE.txt for license information
// See https://swift.org/CONTRIBUTORS.txt for the list of Swift project authors
//
//===----------------------------------------------------------------------===//

#ifndef SWIFT_IDE_IDEBRIDGING
#define SWIFT_IDE_IDEBRIDGING

#include "swift/Basic/BasicBridging.h"

#ifdef USED_IN_CPP_SOURCE
#include "swift/Basic/SourceLoc.h"
#include "llvm/ADT/Optional.h"
#include "llvm/CAS/CASReference.h"
#include <vector>
#endif

enum class LabelRangeType {
  None,

  /// `foo([a: ]2) or .foo([a: ]String)`
  CallArg,

  /// `func([a b]: Int)`
  Param,

  /// `subscript([a a]: Int)`
  NoncollapsibleParam,

  /// `#selector(foo.func([a]:))`
  Selector,
};

enum class ResolvedLocContext { Default, Selector, Comment, StringLiteral };

#ifdef USED_IN_CPP_SOURCE
struct ResolvedLoc {
  /// The range of the call's base name.
  swift::CharSourceRange range;

  // FIXME: (NameMatcher) We should agree on whether `labelRanges` contains the
  // colon or not
  /// The range of the labels.
  ///
  /// What the label range contains depends on the `labelRangeType`:
  /// - Labels of calls span from the label name (excluding trivia) to the end
  ///   of the colon's trivia.
  /// - Declaration labels contain the first name and the second name, excluding
  ///   the trivia on their sides
  /// - For function arguments that don't have a label, this is an empty range
  ///   that points to the start of the argument (exculding trivia).
  std::vector<swift::CharSourceRange> labelRanges;

  /// The in index in `labelRanges` that belongs to the first trailing closure
  /// or `llvm::None` if there is no trailing closure.
  llvm::Optional<unsigned> firstTrailingLabel;

  LabelRangeType labelType;

  /// Whether the location is in an active `#if` region or not.
  bool isActive;

  ResolvedLocContext context;

  ResolvedLoc(swift::CharSourceRange range,
              std::vector<swift::CharSourceRange> labelRanges,
              llvm::Optional<unsigned> firstTrailingLabel,
              LabelRangeType labelType, bool isActive,
              ResolvedLocContext context);

  ResolvedLoc();
};

#endif // USED_IN_CPP_SOURCE

/// An opaque, heap-allocated `ResolvedLoc`.
///
/// This type is manually memory managed. The creator of the object needs to
/// ensure that `takeUnbridged` is called to free the memory.
struct BridgedResolvedLoc {
  /// Opaque pointer to `ResolvedLoc`.
  void *resolvedLoc;

  /// This consumes `labelRanges` by calling `takeUnbridged` on it.
  SWIFT_NAME(
      "init(range:labelRanges:firstTrailingLabel:labelType:isActive:context:)")
  BridgedResolvedLoc(BridgedCharSourceRange range,
                     BridgedCharSourceRangeVector labelRanges,
                     unsigned firstTrailingLabel, LabelRangeType labelType,
                     bool isActive, ResolvedLocContext context);

#ifdef USED_IN_CPP_SOURCE
  ResolvedLoc takeUnbridged() {
    ResolvedLoc *resolvedLocPtr = static_cast<ResolvedLoc *>(resolvedLoc);
    ResolvedLoc unbridged = *resolvedLocPtr;
    delete resolvedLocPtr;
    return unbridged;
  }
#endif
};

/// A heap-allocated `std::vector<ResoledLoc>` that can be represented by an
/// opaque pointer value.
///
/// This type is manually memory managed. The creator of the object needs to
/// ensure that `takeUnbridged` is called to free the memory.
class BridgedResolvedLocVector {
  /// Opaque pointer to `std::vector<ResolvedLoc>`
  void *vector;

public:
  BridgedResolvedLocVector();

  /// Create a `BridgedResolvedLocVector` from an opaque value obtained from
  /// `getOpaqueValue`.
  BridgedResolvedLocVector(void *opaqueValue);

  /// This consumes `Loc`, calling `takeUnbridged` on it.
  SWIFT_NAME("append(_:)")
  void push_back(BridgedResolvedLoc Loc);

#ifdef USED_IN_CPP_SOURCE
  std::vector<ResolvedLoc> takeUnbridged() {
    std::vector<ResolvedLoc> *vectorPtr =
        static_cast<std::vector<ResolvedLoc> *>(vector);
    std::vector<ResolvedLoc> unbridged = *vectorPtr;
    delete vectorPtr;
    return unbridged;
  }
#endif

  SWIFT_IMPORT_UNSAFE
  void *getOpaqueValue() const;
};

#ifdef __cplusplus
extern "C" {
#endif

/// Entry point to run the NameMatcher written in swift-syntax.
/// 
/// - Parameters:
///   - sourceFilePtr: A pointer to an `ExportedSourceFile`, used to access the
///     syntax tree
///   - locations: Pointer to a buffer of `BridgedSourceLoc` that should be
///     resolved by the name matcher.
///   - locationsCount: Number of elements in `locations`.
/// - Returns: The opaque value of a `BridgedResolvedLocVector`.
void *swift_SwiftIDEUtilsBridging_runNameMatcher(const void *sourceFilePtr,
                                                 BridgedSourceLoc *locations,
                                                 size_t locationsCount);
#ifdef __cplusplus
}
#endif

#endif
