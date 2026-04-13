# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

* `LogicFileBundle` — new protocol for Logic Pro file types stored as directory bundles on disk; mirrors `LogicFileData` but uses `init(contentsOf:) throws` / `write(to:) throws` instead of `Data`-based init/serialization. `Patch` now conforms.
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
