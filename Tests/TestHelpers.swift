import Foundation

@testable import LogicFiles

/// Resolve a test resource URL by name, extension, and optional subdirectory under `examples/`.
///
/// Tries `Bundle.module` first, then falls back to `#file`-relative lookup for workspace runs.
/// Pass `nil` for `subdirectory` to look up top-level resources (e.g. RS2.pst).
func testResourceURL(
  _ name: String,
  extension ext: String,
  subdirectory: String? = nil,
  caller: String = #file
) -> URL? {
  let bundleSubdir = subdirectory.map { "examples/\($0)" }
  if let url = Bundle.module.url(forResource: name, withExtension: ext, subdirectory: bundleSubdir)
  {
    return url
  }
  let thisFile = URL(fileURLWithPath: caller)
  let base = thisFile.deletingLastPathComponent()
  let url: URL
  if let subdirectory {
    url = base.appendingPathComponent("Resources/examples/\(subdirectory)/\(name).\(ext)")
  } else {
    url = base.appendingPathComponent("Resources/\(name).\(ext)")
  }
  guard FileManager.default.fileExists(atPath: url.path) else { return nil }
  return url
}

/// Resolve a test resource URL, requiring it to exist.
func requireTestResourceURL(
  _ name: String,
  extension ext: String,
  subdirectory: String? = nil,
  caller: String = #file
) -> URL {
  guard let url = testResourceURL(name, extension: ext, subdirectory: subdirectory, caller: caller)
  else {
    let location = subdirectory.map { "examples/\($0)" } ?? "Resources"
    fatalError("\(name).\(ext) not found in \(location)")
  }
  return url
}
