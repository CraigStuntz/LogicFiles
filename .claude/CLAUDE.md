# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
swift build                        # Build the library
swift test                         # Run all tests
```

## Logic Pro File Types
These are documented in the `*.md` files in @Sources/Models. We should attempt to keep our knowledge of the Logic Pro file formats (from the actual examples in @Tests/Resources/examples) up to date in these `.md` files and we should base code decsions on the contents of these files. If we find a case where, for example, a test does not pass because we have added a new example, we should first update the appropriate `.md` file with the new information from the new example, and then fix the code and docstrings within the code. 

## Architecture

Swift SPM library (`Sources/`) targeting macOS 13+ and iOS 16+, using Swift 6 language mode. All source types are value-type `struct`s.

**Core protocols:** Defined in `Sources/Models/LogicFile.swift`:
- `LogicFile` — defines `pathExtension` and extension matching, implemented by all file types.
- `LogicFileData: LogicFile` — adds `init(data:) throws` and `func data() throws -> Data` for flat-file types (not `Patch`, which is a bundle).

**File types:**
- `Pst` — Logic Pro Preset files; fixed binary format: 24-byte GAMETSPP header + payload of packed IEEE 754 floats. `init(data:)` throws `PstParseError` if the magic string is absent.
- `Aupreset` — AU Preset files; parses a plist into typed fields (`name`, `manufacturer`, `type`, `subtype`, `version`, `payload`, and optional plugin-specific keys); `data()` reconstructs via `PropertyListSerialization`.
- `Cst` — Channel Strip files; internally a `Pst` or `Aupreset` depending on content; exposes a `PluginSetting` enum categorizing instruments, MIDI FX, and audio FX.
- `Patch` — Patch bundles (directory bundles with `.patch` extension); enumerates contained files and delegates to the appropriate type per file. Uses `init(contentsOf:)` / `write(to:)` instead of `init(data:)` / `data()`.

**Utilities:**
- `PayloadAnalyzer` — scans binary payloads for float parameter regions using the sentinel `0xcaf24971`.
- `PlistHelper` — thin wrappers around `PropertyListSerialization`.

**Primary invariant:** `init(data:)` followed by `data()` must produce byte-for-byte identical output. Tests enforce this with `Data` equality assertions on real fixtures in `Tests/Resources/`.

## Testing

Uses Swift Testing framework (`@Test` macros, `#expect()`). Fixtures live in `Tests/Resources/` and are declared as `.copy` resources in `Package.swift` so they're accessible via `Bundle.module`.

Key test file: `ExamplesRoundTripTests.swift` — runs round-trip verification against real-world Logic Pro files in `Tests/Resources/examples/`.

When adding new format support or modifying serialization, always add or update a round-trip test using a real binary fixture.

## Terminology

Logic Pro has two overlapping but distinct taxonomies — be precise:

- **Track types** (what kind of track in the arrange window): Audio, MIDI, Pattern, Session Player. Pattern and Session Player tracks are MIDI under the hood.
- **Channel strip types** (how Logic categorizes CST files on disk): **Track** (for audio tracks), **Instrument** (for MIDI, Pattern, and Session Player tracks), **Bus**, **Output**. These match the subfolder names under `~/Music/Audio Music Apps/Channel Strip Settings/`.

In code and comments, use "Track channel strip" / "Instrument channel strip" when describing the *kind of CST file*, and "audio track" / "MIDI track" etc. when describing the *Logic track* that produced it.

## Key Design Decisions

- **Codable is supplemental** — all types conform to `Codable` for JSON interop, but binary serialization uses hand-written `data()` methods, not `Codable`.
- **Preserve unknowns** — for plist-based types (`Aupreset`, `PatchData`), the full parsed plist dict is stored privately and re-serialized by `data()`, so unknown keys survive the round-trip even before they are modeled as typed properties.
- **If a decision is unspecified, prioritize reproducible, well-tested code over clever optimizations.**
- **If anything is unclear about exact-byte compatibility, stop and ask before implementing.**
