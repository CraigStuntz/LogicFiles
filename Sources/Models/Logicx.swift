import Foundation

/// The on-disk storage format for a Logic Pro project.
public enum LogicxStorageFormat: Sendable {
  /// A macOS directory bundle with a `.logicx` extension. Audio files live at
  /// `{bundle}/Media/Audio Files/`. This is the default.
  case bundle
  /// A plain folder (no extension) containing a `.logicx` sub-bundle and a
  /// `.musicapps-project-folder` marker file. Audio files live at `{folder}/Audio Files/`.
  case folder
}

/// Represents a Logic Pro project file (directory bundle).
///
/// A `.logicx` bundle is a directory containing:
/// - `Resources/ProjectInformation.plist` — project-level metadata (required)
/// - `Alternatives/NNN/` — one or more alternative directories, each a complete
///   project snapshot (required, at least one)
/// - `Media/Audio Files/` — audio files used by the project (may be empty)
///
/// Projects may also be saved as a **project folder**: a plain directory (no `.logicx`
/// extension) that contains a `.logicx` sub-bundle alongside a `.musicapps-project-folder`
/// marker file and a top-level `Audio Files/` directory.
///
/// `init(contentsOf:)` auto-detects both formats. Pass the outer folder URL for the folder
/// format, or the `.logicx` bundle URL for the bundle format.
///
/// Conforms to `LogicFileBundle`; use `init(contentsOf:)` to load and `write(to:as:)` to save.
///
/// See also: [LOGICX_FORMAT.md](LOGICX_FORMAT.md) for detailed format specification.
public struct Logicx: Sendable, LogicFileBundle {
  /// The canonical lowercase URL path extension for logicx bundles.
  public static let pathExtension = "logicx"

  /// Project-level information from `Resources/ProjectInformation.plist`.
  public var projectInformation: LogicxProjectInformation
  /// Per-alternative project data, keyed by directory name (e.g. "000").
  public var alternatives: [String: LogicxAlternative]
  /// URL of the `Audio Files` directory for this project, if present on disk.
  /// `nil` when the project is constructed programmatically rather than loaded from disk,
  /// or when no `Audio Files` directory exists (audio files referenced externally).
  public var audioFilesURL: URL?

  /// Load a logicx project from disk.
  ///
  /// Accepts either format:
  /// - A `.logicx` bundle directory (bundle format).
  /// - A plain project folder containing a `.logicx` sub-bundle (folder format), detected
  ///   by the presence of a `.musicapps-project-folder` marker file.
  ///
  /// - Parameter url: The file URL of the `.logicx` bundle or outer project folder.
  /// - Throws: `LogicxError` if the bundle is missing required files or directories.
  public init(contentsOf url: URL) throws {
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw LogicxError.directoryNotFound
    }

    let markerURL = url.appendingPathComponent(".musicapps-project-folder")
    let isFolderFormat = FileManager.default.fileExists(atPath: markerURL.path)

    let bundleURL: URL
    let candidateAudioURL: URL

    if isFolderFormat {
      let innerName = url.lastPathComponent + "." + Logicx.pathExtension
      bundleURL = url.appendingPathComponent(innerName)
      candidateAudioURL = url.appendingPathComponent("Audio Files")
    } else {
      bundleURL = url
      candidateAudioURL = url.appendingPathComponent("Media").appendingPathComponent("Audio Files")
    }

    guard FileManager.default.fileExists(atPath: bundleURL.path) else {
      throw LogicxError.directoryNotFound
    }

    let resourcesURL = bundleURL.appendingPathComponent("Resources")
    let projectInfoURL = resourcesURL.appendingPathComponent("ProjectInformation.plist")
    guard FileManager.default.fileExists(atPath: projectInfoURL.path) else {
      throw LogicxError.missingProjectInformation
    }
    self.projectInformation = try LogicxProjectInformation(
      data: Data(contentsOf: projectInfoURL))

    let alternativesURL = bundleURL.appendingPathComponent("Alternatives")
    guard FileManager.default.fileExists(atPath: alternativesURL.path) else {
      throw LogicxError.missingAlternatives
    }

    let altContents = try FileManager.default.contentsOfDirectory(
      at: alternativesURL, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])

    var alts: [String: LogicxAlternative] = [:]
    for altDir in altContents {
      var isDir: ObjCBool = false
      guard FileManager.default.fileExists(atPath: altDir.path, isDirectory: &isDir),
        isDir.boolValue
      else { continue }
      let name = altDir.lastPathComponent
      alts[name] = try LogicxAlternative(contentsOf: altDir)
    }

    guard !alts.isEmpty else {
      throw LogicxError.missingAlternatives
    }
    self.alternatives = alts

    var isDir: ObjCBool = false
    if FileManager.default.fileExists(atPath: candidateAudioURL.path, isDirectory: &isDir),
      isDir.boolValue
    {
      self.audioFilesURL = candidateAudioURL
    } else {
      self.audioFilesURL = nil
    }
  }

  /// Write the logicx project to disk as a `.logicx` bundle (the default format).
  ///
  /// Satisfies `LogicFileBundle`. For the folder format use `write(to:as:)` explicitly.
  public func write(to url: URL) throws {
    try write(to: url, as: .bundle)
  }

  /// Write the logicx project to disk in the specified storage format.
  ///
  /// - Parameters:
  ///   - url: The file URL where the project should be written.
  ///   - format: The on-disk storage format. Defaults to `.bundle`.
  ///
  /// If the directory already exists, files from a previous write that are no longer part
  /// of this project will **not** be deleted. Remove the directory first for a clean write.
  public func write(to url: URL, as format: LogicxStorageFormat = .bundle) throws {
    switch format {
    case .bundle:
      try writeBundleContents(to: url, includeMediaDirectory: true)
    case .folder:
      if !FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
      }
      // Marker file (empty)
      let markerURL = url.appendingPathComponent(".musicapps-project-folder")
      if !FileManager.default.fileExists(atPath: markerURL.path) {
        try Data().write(to: markerURL)
      }
      // Audio Files/ at the outer level
      let audioURL = url.appendingPathComponent("Audio Files")
      if !FileManager.default.fileExists(atPath: audioURL.path) {
        try FileManager.default.createDirectory(at: audioURL, withIntermediateDirectories: true)
      }
      // Inner .logicx bundle (no Media/Audio Files/ inside)
      let innerName = url.lastPathComponent + "." + Logicx.pathExtension
      try writeBundleContents(
        to: url.appendingPathComponent(innerName), includeMediaDirectory: false)
    }
  }

  private func writeBundleContents(to url: URL, includeMediaDirectory: Bool) throws {
    if !FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    // Resources/ProjectInformation.plist
    let resourcesURL = url.appendingPathComponent("Resources")
    if !FileManager.default.fileExists(atPath: resourcesURL.path) {
      try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
    }
    try projectInformation.data().write(
      to: resourcesURL.appendingPathComponent("ProjectInformation.plist"))

    // Alternatives/NNN/
    let alternativesURL = url.appendingPathComponent("Alternatives")
    if !FileManager.default.fileExists(atPath: alternativesURL.path) {
      try FileManager.default.createDirectory(
        at: alternativesURL, withIntermediateDirectories: true)
    }
    for (name, alternative) in alternatives {
      try alternative.write(to: alternativesURL.appendingPathComponent(name))
    }

    // Media/Audio Files/ (bundle format only)
    if includeMediaDirectory {
      let audioFilesURL =
        url
        .appendingPathComponent("Media")
        .appendingPathComponent("Audio Files")
      if !FileManager.default.fileExists(atPath: audioFilesURL.path) {
        try FileManager.default.createDirectory(
          at: audioFilesURL, withIntermediateDirectories: true)
      }
    }
  }
}

extension Logicx: Codable {
  private enum CodingKeys: String, CodingKey {
    case projectInformation, alternatives
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.projectInformation = try container.decode(
      LogicxProjectInformation.self, forKey: .projectInformation)
    self.alternatives = try container.decode(
      [String: LogicxAlternative].self, forKey: .alternatives)
    self.audioFilesURL = nil
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(projectInformation, forKey: .projectInformation)
    try container.encode(alternatives, forKey: .alternatives)
  }
}

/// Errors thrown when loading a logicx bundle.
public enum LogicxError: Error {
  /// The logicx bundle directory does not exist at the given URL.
  case directoryNotFound
  /// The required `Resources/ProjectInformation.plist` is missing.
  case missingProjectInformation
  /// The `Alternatives/` directory is missing or contains no valid alternatives.
  case missingAlternatives
}
