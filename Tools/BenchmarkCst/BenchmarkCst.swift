import Foundation
import LogicFiles

// Loads every file in Fuzz/Corpus/cst and runs Cst.init(data:) on each in a
// tight loop for `duration` seconds. Build release and profile with Instruments.
//
// Usage:
//   swift build -c release --target BenchmarkCst
//   instruments -t "Time Profiler" -D /tmp/cst_profile.trace \
//     .build/arm64-apple-macosx/release/BenchmarkCst

let duration: Double = 10

guard
  let repoRoot = URL(string: #filePath)?
    .deletingLastPathComponent()  // BenchmarkCst/
    .deletingLastPathComponent()  // Tools/
    .deletingLastPathComponent()  // repo root
else {
  fatalError("Cannot resolve repo root from \(#filePath)")
}

let corpusURL = repoRoot.appendingPathComponent("Fuzz/Corpus/cst")
let files =
  (try? FileManager.default.contentsOfDirectory(
    at: corpusURL,
    includingPropertiesForKeys: nil
  )) ?? []

guard !files.isEmpty else {
  fatalError("No corpus files found at \(corpusURL.path)")
}

let corpus: [Data] = files.compactMap { try? Data(contentsOf: $0) }
print("Loaded \(corpus.count) corpus files. Running for \(Int(duration))s…")

var iterations = 0
let deadline = Date().addingTimeInterval(duration)
while Date() < deadline {
  for data in corpus {
    _ = try? Cst(data: data)
    iterations += 1
  }
}

print("Done: \(iterations) iterations (\(iterations / Int(duration)) iter/s)")
