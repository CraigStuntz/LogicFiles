import Foundation

/// The selected hardware audio input for a channel strip.
///
/// Logic Pro's internal encoding reserves values 1–8 for mono inputs and values 9+ for
/// stereo pairs. The conversion formula is inferred from two confirmed data points:
/// raw `0x01` (mono Input 1) and `0x09` (stereo In 1-2). Other values follow the same
/// pattern but have not been verified against real Logic Pro files. If you observe a
/// raw value that produces an unexpected result, please open an issue with the raw byte
/// and the Logic Pro version used to create the file.
///
/// - Note: As of this writing, non-nil values have only been observed in CST files
///   embedded inside a `.patch` bundle. Standalone `.cst` files always return `nil`
///   from ``Cst/audioInput`` in all examined examples.
public struct AudioInput: Equatable, Codable, Sendable {
  /// 0-indexed hardware input number within the mono or stereo group.
  ///
  /// For mono inputs: 0 = "Input 1", 1 = "Input 2", etc.
  /// For stereo pairs: 0 = "In 1-2", 1 = "In 3-4", etc.
  public let inputIndex: Int
  /// `true` for a stereo input pair, `false` for a single mono input.
  public let isStereo: Bool

  public init(inputIndex: Int, isStereo: Bool) {
    self.inputIndex = inputIndex
    self.isStereo = isStereo
  }

  /// Initialize from the raw byte found in the OCuA header.
  /// Returns `nil` for the no-input sentinels (`0x00`, `0x0c`).
  init?(rawValue: UInt8) {
    switch rawValue {
    case 0, 0x0c:
      return nil
    case 1...8:
      inputIndex = Int(rawValue) - 1
      isStereo = false
    default:  // ≥ 9; 0x0c already handled above
      inputIndex = Int(rawValue) - 9
      isStereo = true
    }
  }
}
