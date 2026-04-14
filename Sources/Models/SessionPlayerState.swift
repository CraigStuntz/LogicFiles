import Foundation

// MARK: - Public types

/// The selected Session Player character and settings for one track.
///
/// Extracted from the `genInstDrummerBaseModel.state` JSON embedded in `ProjectData`.
/// Despite the internal "drummer" naming, this applies to all Session Player types
/// (Piano, Bass, Drummer, etc.).
public struct SessionPlayerTrackState: Codable, Sendable {
  /// The track's unique identifier (key in the `drummerModelTrackStates` dictionary).
  public var trackID: UUID
  /// Display name of the selected character (e.g. `"Acoustic Piano - Arpeggiated"`).
  public var characterIdentifier: String
  /// Internal persistent type identifier (e.g. `"Type_AcousticPianoV2"`).
  public var characterTypeIdentifier: String
  /// Whether the track uses a Producer Kit drum kit.
  public var isUsingProducerKit: Bool
}

/// Musical parameters for a Session Player region preset.
///
/// Common parameters shared across all Session Player types. The full parameter
/// set varies by character type; only the most widely applicable fields are
/// modelled here.
public struct SessionPlayerParameters: Codable, Sendable {
  /// Overall performance intensity (0–127).
  public var intensity: Double?
  /// Velocity range / dynamics (0–127).
  public var dynamics: Double?
  /// Timing humanization amount (0–100).
  public var humanize: Double?
  /// Swing amount (0–100).
  public var swing: Double?
  /// Rhythm complexity (0–100).
  public var rComp: Double?
  /// Melodic complexity (0–100).
  public var mComp: Double?
  /// Fill density (0–100).
  public var fillsAmount: Double?
  /// Pattern variation index (1–4).
  public var variation: Double?

}

/// A Session Player region preset embedded in `ProjectData`.
///
/// Each generated Session Player region stores its preset configuration as JSON
/// directly in the binary `ProjectData` file. One `SessionPlayerPreset` corresponds
/// to one such region.
public struct SessionPlayerPreset: Codable, Sendable {
  /// Preset display name (e.g. `"Power Ballad"`).
  public var name: String
  /// Character the preset belongs to (e.g. `"Acoustic Piano - Arpeggiated"`).
  public var characterIdentifier: String
  /// Unique preset file identifier (e.g. `"Acoustic Piano - Arpeggiated - Power Ballad.dpst"`).
  public var uniqueIdentifier: String
  /// Internal region type (e.g. `"Type_AcousticPianoV2"`).
  public var regionType: String
  /// Preset type (e.g. `"TypeFactoryPreset"`).
  public var type: String
  /// Musical parameters for this preset.
  public var parameters: SessionPlayerParameters

  private enum CodingKeys: String, CodingKey {
    case name = "Name"
    case characterIdentifier = "CharacterIdentifier"
    case uniqueIdentifier = "UniqueIdentifier"
    case type = "Type"
    case parameters = "Parameters"
  }

  /// The `RegionType` key lives on the outer object, not inside `Preset`.
  /// Supplied separately during extraction.
  public init(from decoder: Decoder) throws {
    let c = try decoder.container(keyedBy: CodingKeys.self)
    name = try c.decode(String.self, forKey: .name)
    characterIdentifier = try c.decode(String.self, forKey: .characterIdentifier)
    uniqueIdentifier = try c.decode(String.self, forKey: .uniqueIdentifier)
    type = try c.decode(String.self, forKey: .type)
    parameters = try c.decode(SessionPlayerParameters.self, forKey: .parameters)
    regionType = ""  // set after init from outer object
  }

  fileprivate init(
    name: String, characterIdentifier: String, uniqueIdentifier: String,
    regionType: String, type: String, parameters: SessionPlayerParameters
  ) {
    self.name = name
    self.characterIdentifier = characterIdentifier
    self.uniqueIdentifier = uniqueIdentifier
    self.regionType = regionType
    self.type = type
    self.parameters = parameters
  }
}

// MARK: - LogicxAlternative extraction

extension LogicxAlternative {
  /// Returns the Session Player track states embedded in `ProjectData`.
  ///
  /// Scans the raw binary for the `genInstDrummerBaseModel.state` JSON object
  /// and returns one entry per Session Player track. Returns an empty array for
  /// projects with no Session Player tracks.
  public func sessionPlayerTrackStates() -> [SessionPlayerTrackState] {
    for obj in projectData.embeddedJSONObjects() {
      guard
        let wrapper = obj["genInstDrummerBaseModel.state"] as? [String: Any],
        let trackStates = wrapper["drummerModelTrackStates"] as? [String: Any]
      else { continue }

      return trackStates.compactMap { key, value -> SessionPlayerTrackState? in
        guard
          let uuid = UUID(uuidString: key),
          let state = value as? [String: Any],
          let character = state["selectedCharacterIdentifier"] as? String,
          let typeID = state["selectedPersistentCharacterTypeIdentifier"] as? String
        else { return nil }
        let producerKit = state["isUsingProducerKit"] as? Bool ?? false
        return SessionPlayerTrackState(
          trackID: uuid,
          characterIdentifier: character,
          characterTypeIdentifier: typeID,
          isUsingProducerKit: producerKit
        )
      }
    }
    return []
  }

  /// Returns the Session Player region presets embedded in `ProjectData`.
  ///
  /// Each generated Session Player region stores its preset as a JSON object in
  /// the binary `ProjectData`. Returns one entry per region that has been
  /// generated; returns an empty array for projects with no Session Player regions.
  public func sessionPlayerPresets() -> [SessionPlayerPreset] {
    var results: [SessionPlayerPreset] = []
    for obj in projectData.embeddedJSONObjects() {
      guard
        let presetDict = obj["Preset"] as? [String: Any],
        let regionType = obj["RegionType"] as? String,
        let name = presetDict["Name"] as? String,
        let character = presetDict["CharacterIdentifier"] as? String,
        let uid = presetDict["UniqueIdentifier"] as? String,
        let type = presetDict["Type"] as? String,
        let paramsDict = presetDict["Parameters"] as? [String: Any]
      else { continue }

      let paramsData = (try? JSONSerialization.data(withJSONObject: paramsDict)) ?? Data()
      let parameters =
        (try? JSONDecoder().decode(SessionPlayerParameters.self, from: paramsData))
        ?? SessionPlayerParameters()

      results.append(
        SessionPlayerPreset(
          name: name,
          characterIdentifier: character,
          uniqueIdentifier: uid,
          regionType: regionType,
          type: type,
          parameters: parameters
        ))
    }
    return results
  }
}

// MARK: - Internal JSON scanning

extension Data {
  /// Scans the receiver for embedded UTF-8 JSON objects and returns any that
  /// parse successfully as `[String: Any]`. Used to extract Session Player data
  /// from the binary `ProjectData` file.
  func embeddedJSONObjects() -> [[String: Any]] {
    var results: [[String: Any]] = []
    var i = startIndex
    let end = endIndex
    while i < end {
      // Look for the start of a JSON object: opening brace followed by a quote.
      let next = index(after: i)
      guard self[i] == UInt8(ascii: "{"), next < end, self[next] == UInt8(ascii: "\"") else {
        i = next
        continue
      }
      guard let (slice, after) = jsonObjectSlice(from: i) else {
        i = next
        continue
      }
      if let obj = try? JSONSerialization.jsonObject(with: slice) as? [String: Any] {
        results.append(obj)
      }
      i = after
    }
    return results
  }

  /// Brace-counts from `start` to find a complete JSON object, respecting
  /// string literals and escape sequences. Returns the slice and the index
  /// immediately after the closing brace, or `nil` if the data is truncated.
  private func jsonObjectSlice(from start: Index) -> (Data, Index)? {
    var depth = 0
    var inString = false
    var escape = false
    var i = start
    while i < endIndex {
      let b = self[i]
      let next = index(after: i)
      if escape {
        escape = false
      } else if b == UInt8(ascii: "\\") && inString {
        escape = true
      } else if b == UInt8(ascii: "\"") {
        inString.toggle()
      } else if !inString {
        if b == UInt8(ascii: "{") {
          depth += 1
        } else if b == UInt8(ascii: "}") {
          depth -= 1
          if depth == 0 {
            return (subdata(in: start..<next), next)
          }
        }
      }
      i = next
    }
    return nil
  }
}

