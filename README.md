# LogicFiles

A Swift library for reading and writing [Apple Logic Pro](https://www.apple.com/logic-pro/) 
file formats: `.cst`, `.aupreset`, `.pst`, and `.patch`. Also! This project 
represents the only in-depth documentation of 
these file formats I've found anywhere on the web. I would be _delighted_ to be 
wrong about this; please open an issue and tell me if you know of any!

Notably absent: This library has no support for `.logicx`, the Logic Pro project 
format. A `.logicx` file is just a bundle, however, and this project might be 
helpful if you need to read those, anyway!

Requires macOS 13+ / iOS 16+, Swift 6 language mode. Built with Swift Package 
Manager. Tests are in [Swift Testing](https://github.com/swiftlang/swift-testing).

MIT licensed.

## Build

```bash
swift build                        # Build the library and CLI tool
swift test                         # Run all tests
swift run logicfiles info <file>   # Run the CLI tool
```

## Supported file types

| Type | Extension | Notes |
|------|-----------|-------|
| [Aupreset](Sources/Models/AUPRESET_FORMAT.md) | `.aupreset` | AU Preset; wraps a binary or XML plist |
| [Cst](Sources/Models/CST_FORMAT.md) | `.cst` | Channel Strip; contains ordered plugin settings |
| [Patch](Sources/Models/PATCH_FORMAT.md) | `.patch` | Patch bundle (directory); delegates per contained file type |
| [Pst](Sources/Models/PST_FORMAT.md) | `.pst` | Logic Pro Preset; fixed binary format with GAMETSPP header. Nested payloads may use emagic, chunked, or raw sub-formats (see `tryParsePreset()`) |

## Usage

### Protocols

All file types conform to `LogicFile`, which defines `pathExtension` and extension matching:

```swift
Cst.pathExtension           // "cst"
Cst.pathExtensionWithDot    // ".cst"
Cst.matches(pathExtension: "CST")  // true (case-insensitive)
```

Flat file types (`Pst`, `Aupreset`, `Cst`) also conform to `LogicFileData`, which adds
`init(data:) throws` for parsing and `func data() throws -> Data` for serialization.

Bundle types (`Patch`) conform to `LogicFileBundle`, which adds
`init(contentsOf:) throws` for loading and `func write(to:) throws` for saving.

### Reading a file

```swift
import LogicFiles

// Read a Channel Strip file and inspect its plugins
let data = try Data(contentsOf: cstFileURL)
let cst = try Cst(data: data)

print(cst.instrument)       // PluginSetting? — the instrument plugin, if any
print(cst.midiPlugins)      // [PluginSetting] — MIDI effects chain
print(cst.audioFxPlugins)   // [PluginSetting] — audio effects chain
print(cst.pluginCount)      // Int — total number of plugins

// Read an AU Preset file
let auData = try Data(contentsOf: aupresetFileURL)
let aupreset = try Aupreset(data: auData)

print(aupreset.format)      // .xml or .binary
print(aupreset.payload)     // Data? — the raw plugin parameter blob

// Read a Patch bundle (directory)
let patch = try Patch(contentsOf: patchURL)
print(patch.rootChannelStrip)          // Cst
print(patch.additionalChannelStrips)   // [String: Cst] — for summing stacks
print(patch.patchData)                 // PatchData — fader, pan, sends, etc.
```

### Writing a file

```swift
// Parse a file, modify it, write it back
let aupreset = try Aupreset(data: try Data(contentsOf: inputURL))
// aupreset.name, .manufacturer, .payload, etc. are all available
try (try aupreset.data()).write(to: outputURL)

// Write a Patch bundle to a new location
let patch = try Patch(contentsOf: inputURL)
try patch.write(to: outputURL)
```

Round-trip fidelity is a core invariant: `init(data:)` followed by `data()` produces byte-for-byte identical output.

### PluginSetting

Each plugin in a `.cst` is represented as a `PluginSetting` enum:

| Case | Description |
|------|-------------|
| `.pst(Pst)` | Logic Pro's native binary preset format |
| `.aupreset(Aupreset)` | AudioUnit preset (plist-based) |
| `.keyedArchive(KeyedArchive)` | NSKeyedArchiver blob; system/metadata block (e.g., layer configuration) |
| `.unknown(Data)` | Unrecognized format, preserved verbatim for round-trip fidelity |

### Replacing and cloning plugins

The `Cst` type supports in-place plugin replacement and structural cloning:

```swift
// Replace the instrument in a channel strip
var cst = try Cst(data: try Data(contentsOf: baseURL))
let donor = try Cst(data: try Data(contentsOf: donorURL))
cst.replacePlugin(at: 0, with: donor.instrument!)
try (try cst.data()).write(to: outputURL)

// Optionally set the preset name that Logic displays
cst.replacePlugin(at: 0, with: donor.instrument!, presetName: "My Preset")

// Read the preset name Logic displays for a plugin slot
let name = cst.presetName(at: 0)  // String?
```

For building new CSTs that Logic will accept, clone an existing file's structure
(OCuA header, UUIDs, metadata) while substituting different plugins:

```swift
// Clone template's structure, replace its plugins
let template = try Cst(data: try Data(contentsOf: templateURL))
let plugins = [template.instrument].compactMap { $0 }
    + template.midiPlugins + template.audioFxPlugins
let cloned = Cst(cloningStructureOf: template, replacingPluginsWith: plugins)
```

To build a CST entirely from scratch (without cloning an existing file):

```swift
let fromScratch = try Cst(
    instrument: somePluginSetting,
    midiPlugins: [],
    audioFxPlugins: [fxPlugin1, fxPlugin2]
)
```

### Environment Layer settings

MIDI track channel strips may include the key/velocity limit and transpose
settings from the Logic Pro Environment (Key Limit, Velocity Limit, Transpose,
No Transpose, multi-timbral mode). Audio track channel strips do not have these
settings. "Layer" here refers to the Logic Pro Environment Layer — a legacy
organizational concept for grouping Environment objects.

```swift
let cst = try Cst(data: try Data(contentsOf: cstURL))
if let layer = cst.environmentLayer {
    print(layer.lowNote, layer.highNote)         // note range (0–127)
    print(layer.lowVelocity, layer.highVelocity) // velocity range
    print(layer.transpose)                       // semitones
    print(layer.noTranspose)                     // bypass transpose
    print(layer.multitimbralEnabled)             // multi-timbral mode
    print(layer.keyboardIndex)                   // layer index

    // Key scaling and velocity response curves
    for point in layer.keyScalingGraph {         // [MAGraphPoint]
        print(point.x, point.y, point.isCurve, point.isStep)
    }
}
```

### Reading and writing parameters

Parameters are accessed by byte offset within the plugin payload. The library provides
the mechanism; consumers supply the semantics (what each offset means for a given plugin).

```swift
// Read a float parameter at a specific byte offset
let pst = try Pst(data: try Data(contentsOf: pstURL))
let value = pst[byteOffset: 48]   // Float

// Write a parameter via subscript
var modified = pst
modified[byteOffset: 48] = 0.75
try (try modified.data()).write(to: outputURL)

// Same API works on Aupreset and PluginSetting
var au = try Aupreset(data: try Data(contentsOf: auURL))
au[byteOffset: 0] = 1.0
```

### Identifying plugins

`PluginIdentifier` holds the AudioUnit component triple (manufacturer, type, subtype).
Use it as a key for external parameter-name lookup tables.

```swift
let au = try Aupreset(data: try Data(contentsOf: auURL))
let id = au.pluginIdentifier  // PluginIdentifier (Hashable, Codable)

// PluginSetting also exposes the identifier (nil for PST/unknown formats)
let cst = try Cst(data: try Data(contentsOf: cstURL))
if let id = cst.instrument?.pluginIdentifier {
    // look up parameter names in your own table keyed by id
}
```

### PatchData

`PatchData` describes the patch-level settings stored in `Data.plist` inside a `.patch` bundle.
It includes version info and per-channel settings:

```swift
let patch = try Patch(contentsOf: patchURL)
let pd = patch.patchData

print(pd.versionPatches)            // Int
for ch in pd.channels {             // [PatchChannelSettings]
    print(ch.filename)              // CST filename within the bundle
    print(ch.uuid)                  // UUID
    print(ch.name)                  // display name
    print(ch.isRoot)                // true for the root channel strip
    print(ch.isMuted, ch.isSolo)    // mute/solo state
    print(ch.instrID)               // instrument ID
    print(ch.outputIndex, ch.outputIsBus, ch.outputIsStereo)
    print(ch.inputIndex, ch.inputIsBus)
    print(ch.receiveChannel)        // MIDI receive channel
    print(ch.seqColorIndex)         // track color
    print(ch.trackIcon)             // track icon index
    print(ch.userDidModifySmartControls)
    print(ch.sends)                 // [PatchSend]
}
```

## Examples

### Find all channel strips that use a specific plugin

```swift
import LogicFiles

let cstDir = URL(fileURLWithPath: NSHomeDirectory())
    .appendingPathComponent("Music/Audio Music Apps/Channel Strip Settings/Instrument")

let fm = FileManager.default
let cstFiles = try fm.contentsOfDirectory(at: cstDir, includingPropertiesForKeys: nil)
    .filter { Cst.matches(pathExtension: $0.pathExtension) }

for url in cstFiles {
    let cst = try Cst(data: Data(contentsOf: url))
    if let id = cst.instrument?.pluginIdentifier,
       id.subtype == 0x616C6368 {  // "alch" — Alchemy
        print("\(url.lastPathComponent): Alchemy, \(cst.audioFxPlugins.count) FX")
    }
}
```

### Swap the instrument from one channel strip into another

Take a donor's instrument (e.g., an Alchemy patch) and drop it into a base channel
strip that has the effects chain you want to keep:

```swift
var base = try Cst(data: Data(contentsOf: baseURL))
let donor = try Cst(data: Data(contentsOf: donorURL))

base.replacePlugin(at: 0, with: donor.instrument!, presetName: "My Alchemy Pad")
try (try base.data()).write(to: outputURL)
// outputURL now has donor's instrument + base's MIDI FX and audio FX
```

### Compare a parameter across two presets of the same plugin

```swift
let a = try Pst(data: Data(contentsOf: presetA_URL))
let b = try Pst(data: Data(contentsOf: presetB_URL))

// Compare the first 64 float parameters (256 bytes)
for offset in stride(from: 0, to: 256, by: 4) {
    let valA: Float = a[byteOffset: offset]
    let valB: Float = b[byteOffset: offset]
    if valA != valB {
        print("Offset \(offset): \(valA) → \(valB)")
    }
}
```

### List all layers in a summing-stack patch

```swift
let patch = try Patch(contentsOf: patchURL)

for (name, cst) in patch.additionalChannelStrips.sorted(by: { $0.key < $1.key }) {
    let inst = cst.instrument.map { "\($0)" } ?? "(none)"
    let range: String
    if let layer = cst.environmentLayer {
        range = "notes \(layer.lowNote)–\(layer.highNote), vel \(layer.lowVelocity)–\(layer.highVelocity)"
    } else {
        range = "full range"
    }
    print("\(name): \(inst), \(range)")
}
```

### Build a preset catalog as JSON

All types conform to `Codable`, so you can serialize to JSON for external tools:

```swift
import Foundation

struct CatalogEntry: Codable {
    let filename: String
    let pluginIdentifier: PluginIdentifier?
    let fxCount: Int
}

var catalog: [CatalogEntry] = []
for url in cstFiles {
    let cst = try Cst(data: Data(contentsOf: url))
    catalog.append(CatalogEntry(
        filename: url.lastPathComponent,
        pluginIdentifier: cst.instrument?.pluginIdentifier,
        fxCount: cst.audioFxPlugins.count
    ))
}

let json = try JSONEncoder().encode(catalog)
try json.write(to: URL(fileURLWithPath: "catalog.json"))
```

### Extract the AU preset from inside a channel strip

```swift
let cst = try Cst(data: Data(contentsOf: cstURL))
if case .aupreset(let au) = cst.instrument {
    try (try au.data()).write(to: outputURL)
    // outputURL is now a standalone .aupreset file
}
```

## CLI tool

The package includes a `logicfiles` command-line tool for inspecting and 
transforming Logic Pro files. This was primarly used during development of the 
library, but it might be useful as a further example of how to use the library.

```
logicfiles info <file>
    Print metadata for .cst, .pst, .aupreset, and .patch files.

logicfiles replace <base.cst> <donor.cst> <output.cst>
    Replace the instrument plugin in base with the one from donor,
    keeping base's effects chain.

logicfiles from-scratch <source.cst> <output.cst>
    Parse source, extract its plugins, and rebuild from scratch
    using generated OCuA container bytes.

logicfiles clone <template.cst> <donor.cst> <output.cst>
    Clone template's structure (UUIDs, metadata) and replace
    only the instrument with donor's.
```

Output CSTs can be copied to `~/Music/Audio Music Apps/Channel Strip Settings/Instrument/` for use in Logic Pro.

## Non-goals

This library should not have baked-in knowledge about any specific plugin. 
A "registry" of plugin data float offsets to parameter names is also out of scope.
That might be a useful thing for someone to implement, but it is out of scope 
for this project.

## Future enhancements

- **Support `.logicx` files** - Non-support for `.logicx` files feels like an 
  obvious omission, although I don't personally need it
- **Performance** — lazy parsing for large files

## AI use

This project was developed with AI assistance (Claude). All code and 
documentation was closely reviewed by a human.
