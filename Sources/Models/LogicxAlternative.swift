import Foundation

/// A single alternative within a `.logicx` bundle.
///
/// Each alternative is a complete snapshot of the project state, stored in a numbered
/// subdirectory under `Alternatives/` (e.g. `000/`, `001/`).
///
/// See also: [LOGICX_FORMAT.md](LOGICX_FORMAT.md) for detailed format specification.
public struct LogicxAlternative: Codable, Sendable {
  /// The core project data (arrangement, tracks, plugins) as an opaque binary blob.
  /// The chunk-based binary format is not yet parsed.
  public var projectData: Data
  /// Song metadata (tempo, key, sample rate, track count, etc.).
  public var metaData: LogicxMetaData
  /// Window/editor display state.
  public var displayState: LogicxDisplayState
  /// NSKeyedArchiver display settings archive.
  public var displayStateArchive: KeyedArchive
  /// Thumbnail screenshot of the project window (JPEG), if present.
  public var windowImage: Data?

  /// Load an alternative from a directory on disk.
  ///
  /// - Parameter url: The file URL of the alternative directory (e.g. `.../Alternatives/000/`).
  /// - Throws: `LogicxAlternativeError` if required files are missing.
  public init(contentsOf url: URL) throws {
    let projectDataURL = url.appendingPathComponent("ProjectData")
    guard FileManager.default.fileExists(atPath: projectDataURL.path) else {
      throw LogicxAlternativeError.missingProjectData
    }
    self.projectData = try Data(contentsOf: projectDataURL)

    let metaDataURL = url.appendingPathComponent("MetaData.plist")
    guard FileManager.default.fileExists(atPath: metaDataURL.path) else {
      throw LogicxAlternativeError.missingMetaData
    }
    self.metaData = try LogicxMetaData(data: Data(contentsOf: metaDataURL))

    let displayStateURL = url.appendingPathComponent("DisplayState.plist")
    guard FileManager.default.fileExists(atPath: displayStateURL.path) else {
      throw LogicxAlternativeError.missingDisplayState
    }
    self.displayState = try LogicxDisplayState(data: Data(contentsOf: displayStateURL))

    let displayStateArchiveURL = url.appendingPathComponent("DisplayStateArchive")
    guard FileManager.default.fileExists(atPath: displayStateArchiveURL.path) else {
      throw LogicxAlternativeError.missingDisplayStateArchive
    }
    self.displayStateArchive = try KeyedArchive(data: Data(contentsOf: displayStateArchiveURL))

    let windowImageURL = url.appendingPathComponent("WindowImage.jpg")
    if FileManager.default.fileExists(atPath: windowImageURL.path) {
      self.windowImage = try Data(contentsOf: windowImageURL)
    } else {
      self.windowImage = nil
    }
  }

  /// Write the alternative to a directory on disk.
  ///
  /// Creates the directory and any subdirectories if they do not exist.
  ///
  /// - Parameter url: The file URL where the alternative directory should be written.
  public func write(to url: URL) throws {
    if !FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    try projectData.write(to: url.appendingPathComponent("ProjectData"))
    try metaData.data().write(to: url.appendingPathComponent("MetaData.plist"))
    try displayState.data().write(to: url.appendingPathComponent("DisplayState.plist"))
    try displayStateArchive.data().write(to: url.appendingPathComponent("DisplayStateArchive"))

    if let windowImage {
      try windowImage.write(to: url.appendingPathComponent("WindowImage.jpg"))
    }

    // Recreate the Undo Data.nosync directory (may be empty).
    let undoDir = url.appendingPathComponent("Undo Data.nosync")
    if !FileManager.default.fileExists(atPath: undoDir.path) {
      try FileManager.default.createDirectory(at: undoDir, withIntermediateDirectories: true)
    }
  }
}

/// Errors thrown when loading an alternative directory.
public enum LogicxAlternativeError: Error {
  /// The required `ProjectData` file is missing.
  case missingProjectData
  /// The required `MetaData.plist` file is missing.
  case missingMetaData
  /// The required `DisplayState.plist` file is missing.
  case missingDisplayState
  /// The required `DisplayStateArchive` file is missing.
  case missingDisplayStateArchive
}
