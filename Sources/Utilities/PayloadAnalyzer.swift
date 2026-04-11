import Foundation

/// A candidate region of IEEE 754 float parameters found within a PST payload.
public struct ParameterRegion: Sendable {
  /// Byte offset where this region starts within the payload.
  public let start: Int
  /// Number of floats in the analysis window.
  public let floatCount: Int
  /// Number of floats that appear to be sensible parameter values (finite and < 1000).
  public let sensibleCount: Int
  /// The float values sampled from this region.
  public let sampleValues: [Float]

  /// Creates a parameter region.
  ///
  /// - Parameters:
  ///   - start: Byte offset where this region starts.
  ///   - floatCount: Number of floats in the window.
  ///   - sensibleCount: Number of sensible float values found.
  ///   - sampleValues: The sampled float values.
  public init(start: Int, floatCount: Int, sensibleCount: Int, sampleValues: [Float]) {
    self.start = start
    self.floatCount = floatCount
    self.sensibleCount = sensibleCount
    self.sampleValues = sampleValues
  }
}

/// Errors thrown during payload analysis.
public enum PayloadAnalysisError: Error {
  /// The payload is too short (fewer than 4 bytes) to contain any float parameters.
  case insufficientData
}

/// Scans binary payloads for candidate regions of IEEE 754 float parameters.
///
/// Uses a sliding-window heuristic to identify byte ranges that likely contain
/// plugin parameter data, filtering out sentinel patterns that mark unused slots.
public struct PayloadAnalyzer {
  /// Sentinel pattern (`0xcaf24971`) observed in several PSTs marking unused/empty slots.
  public static let sentinel: UInt32 = 0xcaf2_4971

  /// Scan a PST payload for candidate parameter regions.
  /// - Parameters:
  ///   - payload: data (usually after the 24-byte PST header)
  ///   - windowFloats: how many floats form a candidate block to check
  /// - Returns: array of ParameterRegion candidates
  public static func analyze(payload: Data, windowFloats: Int = 8) throws -> [ParameterRegion] {
    guard payload.count >= 4 else { throw PayloadAnalysisError.insufficientData }

    var regions: [ParameterRegion] = []
    let maxStart = max(0, payload.count - (windowFloats * 4))

    for start in stride(from: 0, through: maxStart, by: 4) {
      var pattern: [Float] = []
      var sensible = 0
      var sentinelCount = 0

      for i in 0..<windowFloats {
        let off = start + (i * 4)
        let u = payload.withUnsafeBytes { $0.load(fromByteOffset: off, as: UInt32.self) }
        if u == PayloadAnalyzer.sentinel {
          sentinelCount += 1
        }
        let f = (try? readFloat(from: payload, at: off)) ?? Float.nan
        pattern.append(f)
        if f.isFinite && abs(f) < 1000 { sensible += 1 }
      }

      // Heuristic: candidate if most values are sensible and not all sentinel
      if sensible >= max(2, windowFloats - 2) && sentinelCount < windowFloats {
        let region = ParameterRegion(
          start: start, floatCount: windowFloats, sensibleCount: sensible, sampleValues: pattern)
        regions.append(region)
      }
    }

    // Deduplicate by start
    var seen = Set<Int>()
    let deduped = regions.filter { r in
      if seen.contains(r.start) { return false }
      seen.insert(r.start)
      return true
    }

    return deduped
  }
}
