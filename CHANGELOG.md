# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

* `PatchData`, `LogicxMetaData`, `LogicxDisplayState`, `LogicxProjectInformation` — eliminated a redundant `PropertyListDecoder` pass that could crash on certain malformed binary plists accepted by `PropertyListSerialization`. Typed fields are now extracted directly from the already-parsed dictionary. Found via libFuzzer coverage-guided fuzz testing.

### Added

* Fuzz testing infrastructure — 8 libFuzzer-based fuzz targets (one per `Data`-based `init`) under `Tools/Fuzz*/`, with a `run-fuzzers.sh` driver script. Seeded from existing test fixtures for coverage-guided mutation.

### Changed

* `Cst.plugins: [CstPlugin]` — replaces `replacePlugin(at:with:presetName:)`, `presetName(at:)`, and `pluginCount`. Each slot is now a `CstPlugin` value with a `setting: PluginSetting` and a `presetName: String?` (the full filename Logic Pro displays, e.g. `"Access Codes.pst"`). Mutate directly: `cst.plugins[0].setting = donor.instrument!`. `init(cloningStructureOf:replacingPluginsWith:)` now takes `[CstPlugin]` instead of `[PluginSetting]`.
* All public model properties are now `var` — read a file from disk, mutate properties, and call `data()` or `write(to:)` to write changes back. `Patch` properties (`rootChannelStrip`, `additionalChannelStrips`, `patchData`) are plain `var` with no extra bookkeeping; changes are picked up when `write(to:)` serializes each component. For plist-backed types, `didSet` observers keep the underlying plist dictionary in sync with typed-property mutations: `Aupreset` always re-serializes from the updated dictionary (`format` is `var` but is not a plist key and has no `didSet`); `PatchData`, `LogicxMetaData`, `LogicxDisplayState`, and `LogicxProjectInformation` also retain the original raw bytes and return them verbatim from `data()` for unmodified files to guarantee byte-for-byte round-trip fidelity; only a mutation triggers re-serialization from the updated dictionary.
* `PatchChannelSettings` — all surface-settings properties are now `var`. Because `PatchChannelSettings` is a value type embedded in `PatchData.channels`, assign the modified copy back (`patchData.channels[i] = updated`) to propagate changes; the `channels` `didSet` re-encodes each entry via an internal `toPlistDict()` method so that `PatchData.data()` reflects the update.
* `LogicxMetaData`, `LogicxDisplayState`, `LogicxProjectInformation` — plist dictionary and stored original bytes are now mutable; a `subscript(key: String) -> Any?` setter updates a key in the underlying plist and discards the stored original bytes so that `data()` re-serializes from the modified dictionary rather than returning the unmodified file.
* `Logicx.init(contentsOf:)` — now auto-detects both the package format (`.logicx` bundle) and the folder format (plain directory with `.musicapps-project-folder` marker). Pass either URL and the correct format is loaded.
* `Logicx.write(to:)` — renamed to `write(to:as:)` with a new `LogicxStorageFormat` parameter (`.bundle` or `.folder`, default `.bundle`). The no-argument `write(to:)` still exists to satisfy `LogicFileBundle` and writes as a bundle.

### Added

* `SessionPlayerTrackState` — character name, internal type ID, and Producer Kit flag for one Session Player track; extracted from the `genInstDrummerBaseModel.state` JSON embedded in `ProjectData`.
* `SessionPlayerParameters` — musical parameters (intensity, dynamics, humanize, swing, rhythm complexity, melodic complexity, fill density, variation) shared across Session Player preset types.
* `SessionPlayerPreset` — preset name, character, unique identifier, region type, and parameters for one generated Session Player region; extracted from the region-level JSON embedded in `ProjectData`.
* `LogicxAlternative.sessionPlayerTrackStates() -> [SessionPlayerTrackState]` — returns all Session Player track states found in `ProjectData`; returns an empty array for alternatives with no generated regions.
* `LogicxAlternative.sessionPlayerPresets() -> [SessionPlayerPreset]` — returns one entry per generated Session Player region found in `ProjectData`; returns an empty array for alternatives with no generated regions.
* `LogicxStorageFormat` — new enum with cases `.bundle` (macOS directory bundle, the default) and `.folder` (plain project folder with `.logicx` sub-bundle).
* `Logicx.audioFilesURL: URL?` — URL of the `Audio Files` directory on disk after loading; `nil` when constructed programmatically or when audio files are referenced externally.
* `LogicxProjectInformation.hasProjectFolder: Bool` — decoded from the `HasProjectFolder` plist key; `false` for bundle format projects, `true` for folder format.
* `Logicx` — new bundle type for Logic Pro project files (`.logicx`); conforms to `LogicFileBundle`, `Codable`, `Sendable`. Loads and writes the full bundle structure including project information, alternatives, and media directories. Format insights informed by [logicx-analyzer](https://github.com/geoffmyers/logicx-analyzer/) by Geoff Myers.
* `LogicxAlternative` — represents a single alternative within a `.logicx` bundle, composing `LogicxMetaData`, `LogicxDisplayState`, `KeyedArchive` (display state archive), opaque `ProjectData`, and optional `WindowImage.jpg`.
* `LogicxProjectInformation` — typed wrapper for `Resources/ProjectInformation.plist` with `bundleVersion`, `lastSavedFrom`, and `variantNames` fields; preserves unknown keys for round-trip fidelity.
* `LogicxMetaData` — typed wrapper for per-alternative `MetaData.plist` with tempo, sample rate, key, time signature, and track count fields.
* `LogicxDisplayState` — typed wrapper for per-alternative `DisplayState.plist` with `displayDataVersion` and `screensetCurrSlot` fields.
* `LogicFileBundle` — new protocol for Logic Pro file types stored as directory bundles on disk; mirrors `LogicFileData` but uses `init(contentsOf:) throws` / `write(to:) throws` instead of `Data`-based init/serialization. `Patch` and `Logicx` now conform.
* `AudioInput` — new struct representing a selected hardware audio input (mono or stereo), with `inputIndex` and `isStereo` properties.
* `Cst.audioInput: AudioInput?` — reads the audio input selector byte from the OCuA header marker `00 80 00 80`; returns `nil` for instrument/bus strips and all standalone `.cst` files examined.
* `PatchChannelSettings.inputIsStereo: Bool?` — decodes the `Channel_inputIsStereo` key from the patch `data.plist`; `nil` for non-audio channel strips.
* `PatchChannelSettings.audioInput: AudioInput?` — synthesizes an `AudioInput` from `inputIndex` and `inputIsStereo`; returns `nil` for bus inputs and instrument/MIDI channel strips.

## [0.1.0] - 2026-04-11

### Added

* File types
  - `Pst`: load and write Logic Pro preset files (`.pst`); fixed binary format with 24-byte `GAMETSPP` header and packed IEEE 754 float payload.
  - `Aupreset`: load and write AU preset files (`.aupreset`); plist-based with typed fields (`name`, `manufacturer`, `type`, `subtype`, `version`, `payload`) and preservation of unknown keys.
  - `Cst`: load and write channel strip settings files (`.cst`) containing `Pst` or `Aupreset` plugins internally; exposes `PluginSetting` categorising instruments, MIDI FX, and audio FX.
  - `Patch`: load and write Logic Pro patch bundles (`.patch` directory bundles); enumerates contained channel strip files and parses bundle metadata.
* Data types
  - `KeyedArchive`: decode NSKeyedArchiver plists embedded in channel strip payloads, including `MAKeyboardLayer` environment-layer keyboard zone settings.
  - `PayloadAnalyzer`: heuristic scanner for float parameter regions in binary payloads using the `0xcaf24971` sentinel value.
  - `PluginIdentifier`: typed AudioUnit component triple (type / subtype / manufacturer) usable as a `Dictionary` key.
  - `PresetDetection`: lightweight detection of nested preset formats (emagic, chunked, unknown) without full parsing.
  - All public types conform to `Codable` and `Sendable`.
* Requires Swift 6.2+ and targets macOS 13+ / iOS 16+.

[Unreleased]: https://github.com/CraigStuntz/LogicFiles/compare/0.1.0...HEAD
[0.1.0]: https://github.com/CraigStuntz/LogicFiles/releases/tag/0.1.0
