import Foundation

/// Format of a preset blob nested inside a file's payload.
public enum NestedPresetFormat: Codable, Sendable {
  /// Magic-string format (GAMETSPP/PPSTEMAG header)
  case emagic
  /// Chunk-based format (4-byte ID + 4-byte length + payload)
  case chunked
  /// Unknown or unrecognized format
  case unknown
}

/// Lightweight detection result for an embedded preset blob.
public struct PresetDetection: Codable, Sendable {
  /// The detected nested preset format.
  public let format: NestedPresetFormat
  /// The magic string or chunk ID found at the start of the blob, if any.
  public let magic: String?
  /// The total size of the preset blob in bytes.
  public let size: Int

  /// Creates a detection result.
  ///
  /// - Parameters:
  ///   - format: The detected nested preset format.
  ///   - magic: The magic string or chunk ID, if detected.
  ///   - size: The total size of the preset blob in bytes.
  public init(format: NestedPresetFormat, magic: String? = nil, size: Int = 0) {
    self.format = format
    self.magic = magic
    self.size = size
  }
}
