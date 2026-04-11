# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-04-11

### Added

- `Pst`: parse and round-trip Logic Pro preset files (`.pst`); fixed binary format with 24-byte `GAMETSPP` header and packed IEEE 754 float payload.
- `Aupreset`: parse and round-trip AU preset files (`.aupreset`); plist-based with typed fields (`name`, `manufacturer`, `type`, `subtype`, `version`, `payload`) and preservation of unknown keys.
- `Cst`: parse and round-trip channel strip settings files (`.cst`); delegates to `Pst` or `Aupreset` internally; exposes `PluginSetting` categorising instruments, MIDI FX, and audio FX.
- `Patch`: load and write Logic Pro patch bundles (`.patch` directory bundles); enumerates contained channel strip files and parses bundle metadata.
- `KeyedArchive`: decode NSKeyedArchiver plists embedded in channel strip payloads, including `MAKeyboardLayer` environment-layer keyboard zone settings.
- `PayloadAnalyzer`: heuristic scanner for float parameter regions in binary payloads using the `0xcaf24971` sentinel value.
- `PluginIdentifier`: typed AudioUnit component triple (type / subtype / manufacturer) usable as a `Dictionary` key.
- `PresetDetection`: lightweight detection of nested preset formats (emagic, chunked, unknown) without full parsing.
- All public types conform to `Codable` and `Sendable`.
- Requires Swift 6.2+ and targets macOS 13+ / iOS 16+.

[Unreleased]: https://github.com/CraigStuntz/LogicFiles/compare/0.1.0...HEAD
[0.1.0]: https://github.com/CraigStuntz/LogicFiles/releases/tag/0.1.0
