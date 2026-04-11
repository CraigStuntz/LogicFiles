import Foundation

/// Identifies an AudioUnit plugin by its component triple.
///
/// Consumers can use this as a dictionary key to build external parameter-name
/// lookup tables without baking plugin-specific knowledge into the library.
public struct PluginIdentifier: Hashable, Codable, Sendable {
  /// Four-byte manufacturer code, stored as an integer (e.g. 0x6170706c = "appl").
  public let manufacturer: Int
  /// AU plugin type code (e.g. 0x61756d75 = "aumu" for instruments).
  public let type: Int
  /// AU plugin subtype code identifying the specific plugin.
  public let subtype: Int

  /// Creates a plugin identifier from the three AudioUnit component codes.
  ///
  /// - Parameters:
  ///   - manufacturer: Four-byte manufacturer code as an integer.
  ///   - type: AU plugin type code.
  ///   - subtype: AU plugin subtype code.
  public init(manufacturer: Int, type: Int, subtype: Int) {
    self.manufacturer = manufacturer
    self.type = type
    self.subtype = subtype
  }
}
