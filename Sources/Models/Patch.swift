import Foundation

/// Represents a Logic Pro Patch file (directory bundle).
///
/// A Patch bundle is a directory with a `.patch` extension containing exactly:
/// - `#Root.cst` — the root channel strip (required)
/// - Zero or more additional `.cst` files — for summing stacks
/// - `data.plist` — channel strip surface settings (Pan, Fader, Sends, etc.)
///
/// See also: [PATCH_FORMAT.md](PATCH_FORMAT.md) for detailed format specification.
public struct Patch: Codable, Sendable, LogicFile {
  /// The canonical lowercase URL path extension for patch bundles.
  public static let pathExtension = "patch"

  /// The root channel strip (`#Root.cst`).
  public let rootChannelStrip: Cst
  /// Additional channel strips, keyed by filename (including `.cst` extension).
  /// Non-empty only for summing stacks.
  public let additionalChannelStrips: [String: Cst]
  /// Channel strip surface settings parsed from `data.plist`.
  public let patchData: PatchData

  /// Load a patch bundle from disk.
  ///
  /// - Parameter url: The file URL of the `.patch` bundle directory.
  /// - Throws: `PatchError` if the bundle is missing required files.
  public init(contentsOf url: URL) throws {
    guard FileManager.default.fileExists(atPath: url.path) else {
      throw PatchError.directoryNotFound
    }

    let rootURL = url.appendingPathComponent("#Root.cst")
    guard FileManager.default.fileExists(atPath: rootURL.path) else {
      throw PatchError.missingRootChannelStrip
    }
    rootChannelStrip = try Cst(data: Data(contentsOf: rootURL))

    let plistURL = url.appendingPathComponent("data.plist")
    guard FileManager.default.fileExists(atPath: plistURL.path) else {
      throw PatchError.missingDataPlist
    }
    patchData = try PatchData(data: Data(contentsOf: plistURL))

    let enumerator = FileManager.default.enumerator(
      at: url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
    guard let enumerator else {
      throw PatchError.failedToEnumerate
    }
    var additional: [String: Cst] = [:]
    for case let fileURL as URL in enumerator {
      var isDir: ObjCBool = false
      guard FileManager.default.fileExists(atPath: fileURL.path, isDirectory: &isDir),
        !isDir.boolValue
      else { continue }
      let filename = fileURL.lastPathComponent
      guard filename != "#Root.cst", filename.lowercased().hasSuffix(".cst") else { continue }
      additional[filename] = try Cst(data: Data(contentsOf: fileURL))
    }
    additionalChannelStrips = additional
  }

  /// Write the patch bundle to disk.
  ///
  /// If the directory already exists, files from a previous write that are no longer
  /// part of this patch (e.g. removed channel strips) will **not** be deleted.
  /// Callers should remove the directory first if a clean write is needed.
  ///
  /// - Parameter url: The file URL where the `.patch` bundle directory should be written.
  public func write(to url: URL) throws {
    if !FileManager.default.fileExists(atPath: url.path) {
      try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    try rootChannelStrip.data().write(to: url.appendingPathComponent("#Root.cst"))
    for (filename, cst) in additionalChannelStrips {
      try cst.data().write(to: url.appendingPathComponent(filename))
    }
    try patchData.data().write(to: url.appendingPathComponent("data.plist"))
  }
}

/// Errors thrown when loading a patch bundle.
public enum PatchError: Error {
  /// The patch bundle directory does not exist at the given URL.
  case directoryNotFound
  /// The file manager failed to enumerate the bundle's contents.
  case failedToEnumerate
  /// The required `#Root.cst` file is missing from the bundle.
  case missingRootChannelStrip
  /// The required `data.plist` file is missing from the bundle.
  case missingDataPlist
}
