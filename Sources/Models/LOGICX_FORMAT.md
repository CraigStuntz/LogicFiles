# Logic Pro `.logicx` Project Format

## Overview

`.logicx` files are Logic Pro project bundles (macOS directory bundles with a `.logicx`
extension). They contain the full project — arrangement, automation, bounce files, and
embedded channel strip / preset data.

The bundle structure and `ProjectData` chunk tags documented here were informed in part
by [logicx-analyzer](https://github.com/geoffmyers/logicx-analyzer/) by Geoff Myers.

Logic Pro can save projects in two formats, selectable in the Save dialog:
- **Package** — a single `.logicx` macOS bundle (appears as one file in Finder).
- **Folder** — a plain directory (no extension) containing a `.logicx` sub-bundle.

Both formats support the same content; the difference is structural only. Audio files
may be embedded in the project or referenced externally in both formats.

## Bundle Structure (Package format)

A `.logicx` bundle is a directory with the following hierarchy:

```
Project.logicx/
  Resources/
    ProjectInformation.plist     — project-level metadata
  Alternatives/
    000/                         — first alternative (default)
      ProjectData                — binary project data (arrangement, tracks, plugins)
      MetaData.plist             — song metadata (tempo, key, sample rate, etc.)
      DisplayState.plist         — window/editor layout state
      DisplayStateArchive        — NSKeyedArchiver binary plist of display settings
      WindowImage.jpg            — thumbnail screenshot of the project window
      Undo Data.nosync/          — undo history (not synced to cloud)
    001/                         — second alternative (if present)
      ...
  Media/
    Audio Files/                 — audio files used by the project
```

Projects can have multiple **alternatives** — numbered subdirectories under
`Alternatives/` (e.g. `000/`, `001/`). Each alternative is a complete snapshot
of the project state. The variant names are recorded in
`ProjectInformation.plist`.

## Project Folder Structure (Folder format)

When saved as a folder, the project is a plain directory (no `.logicx` extension)
containing a `.logicx` sub-bundle alongside a marker file and a top-level
`Audio Files/` directory:

```
Project/                              — outer folder; no extension
  .musicapps-project-folder           — empty marker file; identifies this as a project folder
  Audio Files/                        — audio files (at the outer level, not inside the bundle)
  Project.logicx/                     — inner .logicx bundle (named <folder-name>.logicx)
    Resources/
      ProjectInformation.plist        — HasProjectFolder = true in this format
    Alternatives/
      000/
        ...                           — same structure as the bundle format
```

Key differences from the bundle format:
- The outer directory has **no extension**.
- A `.musicapps-project-folder` **marker file** (empty) is present at the root.
- `Audio Files/` is at the **outer folder level**, not inside `Media/` within the bundle.
- `HasProjectFolder` in `ProjectInformation.plist` is `true`.
- The inner `.logicx` bundle has **no `Media/` directory**.

## `Resources/ProjectInformation.plist`

Binary plist with project-level metadata.

| Key | Type | Description | Example |
|-----|------|-------------|---------|
| `BundleVersion` | Integer | Format version | `2` |
| `LastSavedFrom` | String | Application and version that last saved | `"Logic Pro 12.0.1 (6590)"` |
| `HasProjectFolder` | Boolean | Whether a project folder exists | `false` |
| `projectAssetFlags` | Integer | Asset configuration flags | `8265` |
| `VariantNames` | Dictionary | Maps alternative index (string) to name | `{"0": "Project"}` |
| `VariantNamesV2` | Dictionary | Same mapping with template tokens | `{"0": "{PROJECT_NAME}"}` |
| `WasOnceSavedFromLPX` | Boolean | Whether the project was ever saved from Logic Pro X | `true` |

## `Alternatives/NNN/MetaData.plist`

Binary plist with per-alternative song metadata.

| Key | Type | Description | Example |
|-----|------|-------------|---------|
| `BeatsPerMinute` | Number | Project tempo in BPM | `120` |
| `SampleRate` | Integer | Audio sample rate in Hz | `48000` |
| `SongKey` | String | Musical key | `"C"` |
| `SongGenderKey` | String | Mode (major/minor) | `"major"` |
| `SignatureKey` | Integer | Internal key signature index | `7` |
| `SongSignatureNumerator` | Integer | Time signature numerator | `4` |
| `SongSignatureDenominator` | Integer | Time signature denominator | `4` |
| `NumberOfTracks` | Integer | Track count | `1` |
| `Version` | Integer | Metadata format version | `3` |
| `FrameRateIndex` | Integer | Video frame rate index | `1` |
| `SurroundFormatIndex` | Integer | Surround format | `5` |
| `SurroundModeIndex` | Integer | Surround mode | `0` |
| `HasARAPlugins` | Boolean | Whether ARA plugins are used | `false` |
| `HasGrid` | Boolean | Whether Live Loops grid is active | `false` |
| `isTimeCodeBased` | Boolean | Whether project uses timecode | `false` |
| `AudioFiles` | Array | Referenced audio file paths | `[]` |
| `SamplerInstrumentsFiles` | Array | Sampler instrument file paths | `[]` |
| `QuicksamplerFiles` | Array | Quick Sampler file paths | `[]` |
| `ImpulsResponsesFiles` | Array | Impulse response file paths | `[]` |
| `UltrabeatFiles` | Array | Ultrabeat file paths | `[]` |
| `PlaybackFiles` | Array | Playback file paths | `[]` |
| `UnusedAudioFiles` | Array | Unused audio file paths | `[]` |

## `Alternatives/NNN/DisplayState.plist`

Binary plist containing window layout and editor state. Keys include screen set
configurations, inspector widths, transport bar settings, and per-editor user data.
Structure is complex and not yet modeled as typed fields — preserved as an opaque
plist for round-trip fidelity.

## `Alternatives/NNN/DisplayStateArchive`

NSKeyedArchiver binary plist (same format as `KeyedArchive` in this library).
Contains archived display settings. Begins with `bplist00` magic.

## `Alternatives/NNN/ProjectData`

Binary file containing the core project data: arrangement, tracks, automation,
channel strips, plugin settings, and MIDI data.

### Known characteristics

- **Header magic:** `0x2347c0ab`
- **Chunk-based format** with reversed FourCC markers (similar to IFF/RIFF but with
  reversed tag names):

| Chunk tag | Reversed | Purpose |
|-----------|----------|---------|
| `karT` | Track | Track definitions |
| `qeSM` | SMeq | MIDI sequence data |
| `qSvE` | EvSq | Event sequence data |
| `tSnI` | InSt | Instrument definitions |
| `tSxT` | TxSt | Text style definitions (score) |
| `MroC` | CorM | Core MIDI data |
| `gRuA` | AuRg | Audio region data |
| `LFUA` / `lFuA` | AUFL | Audio file references |

- **Not yet parsed** — stored as opaque `Data` for round-trip fidelity.
- **Embedded JSON objects** are present for Session Player data and can be
  extracted by scanning for `{"` byte sequences and brace-counting to find
  complete JSON objects. See [Session Player JSON](#session-player-json) below.

## Session Player JSON

`ProjectData` embeds UTF-8 JSON objects for Session Player (Drummer, Piano, Bass, etc.)
configuration. These are not chunk-delimited; they appear inline in the binary and can
be extracted by scanning for `{"` sequences and brace-matching.

### Track state (`genInstDrummerBaseModel.state`)

Present in virtually all projects (Logic writes it even when no Session Player tracks
are visible). Structure:

```json
{
  "genInstDrummerBaseModel.state": {
    "drummerModelTrackStates": {
      "<track-UUID>": {
        "selectedCharacterIdentifier": "Acoustic Drummer - Pop Rock",
        "selectedPersistentCharacterTypeIdentifier": "Type_AcousticDrummerV2",
        "isUsingProducerKit": false,
        "keepDrumKitWhenChangingDrummer": false,
        "keepSettingsWhenChangingDrummer": false,
        "parametersWhereChangedAfterCharacterRecall": false,
        "stateVersion": 3
      }
    },
    "autoSelectRegions": false,
    "stateVersion": 1
  },
  "stateVersion": 5
}
```

| Field | Description |
|-------|-------------|
| `drummerModelTrackStates` | Dictionary keyed by track UUID; one entry per Session Player track |
| `selectedCharacterIdentifier` | Display name (e.g. `"Acoustic Piano - Arpeggiated"`) |
| `selectedPersistentCharacterTypeIdentifier` | Internal type ID (e.g. `"Type_AcousticPianoV2"`) |
| `isUsingProducerKit` | Whether the track uses a Producer Kit drum kit |

### Region preset

One object per generated Session Player region:

```json
{
  "RegionType": "Type_AcousticPianoV2",
  "Preset": {
    "Name": "Power Ballad",
    "CharacterIdentifier": "Acoustic Piano - Arpeggiated",
    "UniqueIdentifier": "Acoustic Piano - Arpeggiated - Power Ballad.dpst",
    "Type": "TypeFactoryPreset",
    "Parameters": {
      "intensity": 46,
      "dynamics": 112,
      "humanize": 28,
      "rComp": 67
    }
  }
}
```

| Field | Description |
|-------|-------------|
| `RegionType` | Internal character type ID (same as `selectedPersistentCharacterTypeIdentifier`) |
| `Name` | Preset display name |
| `CharacterIdentifier` | Character display name |
| `UniqueIdentifier` | Preset filename (`.dpst` extension) |
| `Type` | `"TypeFactoryPreset"` for built-in presets |
| `Parameters` | Musical parameters; keys vary by character type |

**Common `Parameters` keys:**

| Key | Range | Description |
|-----|-------|-------------|
| `intensity` | 0–127 | Overall performance intensity |
| `dynamics` | 0–127 | Velocity range / dynamics |
| `humanize` | 0–100 | Timing humanization |
| `swing` | 0–100 | Swing amount |
| `rComp` | 0–100 | Rhythm complexity |
| `mComp` | 0–100 | Melodic complexity |
| `fillsAmount` | 0–100 | Fill density |
| `variation` | 1–4 | Pattern variation index |

## `Alternatives/NNN/WindowImage.jpg`

JPEG screenshot of the Logic Pro window at the time of the last save. Optional —
may not be present in all projects.

## `Alternatives/NNN/Undo Data.nosync/`

Directory containing undo history. The `.nosync` suffix prevents iCloud from
syncing this data. May be empty.

## `Media/Audio Files/`

Directory containing audio files used by the project. May be empty if the project
uses no audio or references audio from external locations.
