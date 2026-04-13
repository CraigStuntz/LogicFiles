import Foundation

/// Maps a Logic Pro file type to its canonical URL path extension.
///
/// This protocol allows code to avoid hard-coded extension strings like "cst"
/// and instead refer to the file type directly.
public protocol LogicFile {
  /// The canonical lowercase URL path extension for this file type.
  static var pathExtension: String { get }
}

extension LogicFile {
  /// The canonical path extension prefixed with a dot.
  public static var pathExtensionWithDot: String { ".\(pathExtension)" }

  /// Case-insensitive matching for this file type's path extension.
  public static func matches(pathExtension ext: String) -> Bool {
    ext.lowercased() == pathExtension.lowercased()
  }
}

/// A Logic Pro file type whose content is represented as a flat `Data` blob.
///
/// Conforming types support round-trip fidelity: `init(data:)` followed by `data()`
/// must produce byte-for-byte identical output.
public protocol LogicFileData: LogicFile {
  /// Initialize from raw file bytes.
  init(data: Data) throws

  /// Serialize back to raw file bytes.
  func data() throws -> Data
}

/// A Logic Pro file type whose content is stored as a directory bundle on disk.
///
/// Conforming types support round-trip fidelity: `init(contentsOf:)` followed by `write(to:)`
/// must produce byte-for-byte identical output.
///
/// - Note: Use `LogicFileData` for flat-file types. Bundle types (`.patch`, `.logicx`) conform here.
public protocol LogicFileBundle: LogicFile {
  /// Load the bundle from a directory URL on disk.
  init(contentsOf url: URL) throws

  /// Write the bundle to a directory URL on disk.
  func write(to url: URL) throws
}
