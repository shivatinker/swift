// RUN: %target-run-simple-swift(-Xfrontend -sil-verify-all -enable-experimental-feature BuiltinModule -enable-experimental-feature BitwiseCopyable -Xfrontend -disable-availability-checking) | %FileCheck %s

// REQUIRES: executable_test

// Execute an unaligned load of SIMD16<UInt8> which retroactively conforms directly to BitwiseCopyable.

extension SIMD16 : @retroactive _BitwiseCopyable {}

func doit() {
  let bytes: [UInt8] = Array(repeating: 0, count: 64)
  bytes.withUnsafeBufferPointer { bytes in
      let rawBytes = UnsafeRawPointer(bytes.baseAddress!) + 1
      let vector = rawBytes.myLoadUnaligned(as: SIMD16<UInt8>.self)
      //CHECK: SIMD16<UInt8>(0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
      blackhole(vector)
  }
}

import Builtin

extension UnsafeRawPointer {
  @inlinable
  @_alwaysEmitIntoClient
  public func myLoadUnaligned<T : _BitwiseCopyable>(
    fromByteOffset offset: Int = 0,
    as type: T.Type
  ) -> T {
    return Builtin.loadRaw((self + offset)._rawValue)
  }
}

doit()

@_silgen_name("blackhole")
@inline(never)
@_semantics("optimize.sil.specialize.generic.never")
func blackhole<T>(_ t: T) {
  print(t) 
}
