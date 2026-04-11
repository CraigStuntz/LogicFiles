import Foundation

enum PayloadAccessError: Error {
  case offsetOutOfRange(offset: Int, payloadSize: Int)
}

/// Reads a little-endian IEEE 754 float at `byteOffset` in `payload`.
func readFloat(from payload: Data, at byteOffset: Int) throws -> Float {
  guard byteOffset >= 0, byteOffset + 4 <= payload.count else {
    throw PayloadAccessError.offsetOutOfRange(offset: byteOffset, payloadSize: payload.count)
  }
  return payload.withUnsafeBytes { ptr in
    ptr.load(fromByteOffset: byteOffset, as: Float.self)
  }
}

/// Returns a copy of `payload` with 4 bytes at `byteOffset` replaced by `value` as a little-endian float.
func writingFloat(_ value: Float, into payload: Data, at byteOffset: Int) throws -> Data {
  guard byteOffset >= 0, byteOffset + 4 <= payload.count else {
    throw PayloadAccessError.offsetOutOfRange(offset: byteOffset, payloadSize: payload.count)
  }
  var copy = payload
  var le = value.bitPattern.littleEndian
  withUnsafeBytes(of: &le) { copy.replaceSubrange(byteOffset..<(byteOffset + 4), with: $0) }
  return copy
}
