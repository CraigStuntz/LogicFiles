# Logic Pro `.cst` (Channel Strip) File Format

## Overview

Channel Strip (.cst) files store complete channel strip configurations in Logic Pro. They contain an **ordered collection** of plugin settings—one for each instrument or effect in the channel strip.

A CST file represents all the front-panel settings from all plugins in a channel strip (both instruments and effects), but does NOT include mix controls like pan, fader, or sends (those are in Patch files).

## Structure

A CST file can contain:
- **Zero or one** instrument plugin — Instrument channel strips have an instrument slot (slot 2) that holds the selected instrument, or is empty if none is selected. Track channel strips (audio tracks) never have an instrument plugin; the instrument slot is always absent.

> **Audio input and the CST file.** The OCuA header contains an audio input selector byte (see "Audio Input Encoding" below). However, in all standalone `.cst` files examined, this byte holds the default/unset value regardless of what input was selected when the file was saved. Non-default values have only been observed in CST files embedded inside a `.patch` bundle. The authoritative source for input selection is the patch bundle's `data.plist` (`Channel_inputIndex_1`, `Channel_inputIsBus`, `Channel_inputIsStereo`). Logic Pro does not restore the audio input when loading a standalone CST or even a full `.patch` bundle — this may be a Logic Pro bug. See `PatchChannelSettings.inputIndex`, `.inputIsBus`, `.inputIsStereo`, and `Cst.audioInput`.
- **Zero or more** MIDI plugins (if on an instrument track)
- **Zero or more** audio FX plugins — on Track channel strips, audio FX occupy slots starting at slot 2 (not slot 3 as on Instrument channel strips); role byte `0x10` indicates audio FX on a Track channel strip
- **Ordered**: The sequence matters, as it represents signal flow

### Example

```
Channel Strip A (Instrument channel strip — MIDI track):
  1. Retro Synth instrument (PST file)
  2. Arpeggiator MIDI effect (PST file)
  3. Channel EQ effect (PST file)
  4. Reverb effect (PST file)
  5. Third-party AU effect (AU Preset)

Channel Strip B (Track channel strip — audio track):
  1. Instrument slot (empty — no instrument selected)
  2. Channel EQ effect (PST file)
  3. Reverb effect (PST file)
```

The examples above represent what is _seen_ on the channel strip in Logic Pro. However, there are 
additional plugins, not seen on the channel strip, which are used to represent e.g. Smart Controls
and keyboard zone and MIDI routing settings (note range, velocity range, transpose, key scaling/velocity curves), which do appear in the `.cst` file.

## Container Format

CST files are stored in a Logic Pro-specific container format (OCuA header). This container format:
- Starts with "OCuA" magic bytes (Logic Pro binary format identifier)
- Contains metadata and structural information
- Embeds individual plugin setting files (PST/AU Preset) with their boundaries

### File Layout

```
Offset    Content
------    -------
0x00      OCuA header and metadata (variable size)
...       Embedded PST and AU Preset files (precise layout TBD)
EOF       End of file
```

## Plugin Settings Types

### Instrument Plugin
- Maximum of one per `cst` file
- Logic-native instruments use `pst` format; third-party AU instruments use `aupreset` format
- Represents the main sound source (e.g., Retro Synth, Sculpture)

### MIDI Effects
- Zero or more per `cst` file
- Only present in Instrument tracks (not Audio tracks)
- Can be present even when there is no instrument plugin selected
- Applied to MIDI data before reaching the instrument
- Examples: Arpeggiator, Chord Trigger

### Audio FX Plugins
- Zero or more per CST file
- Present in both audio and instrument channel strips
- Applied to audio signal in series
- Logic-native effects use PST format; third-party AU effects use AU Preset format

### System / Metadata Blocks
- Not user-visible on the channel strip UI
- Appear in high-numbered slots (9–11, and ≥ 12) beyond the user-facing audio FX range
- Format: **NSKeyedArchiver binary plist** (`bplist00` header, `$archiver` key present)
- Contain Logic-internal Objective-C objects (MA\* classes); known classes include:
  - `MAKeyboardLayer` — keyboard zone and MIDI routing settings (note range, velocity range, transpose, key scaling and velocity response curves)
  - Other MA\* classes are decoded to plain `[String: Any]` with a `__class__` key
- Raw bytes are preserved verbatim for round-trip fidelity; the UID reference graph is resolved lazily via `KeyedArchive.decoded`
- The parser exposes keyboard layer settings via `KeyedArchive.environmentLayer: MAKeyboardLayer?`

### `pst` (Plug-In Settings)
- Binary format with GAMETSPP magic-string header
- Used for Logic Pro's native instruments and effects
- Contains binary parameter data
- Starts with structured header: fileSize (4B) + formatVersion (4B) + dataSize (4B) + magic (8B) + flags (4B)

### `aupreset`
- XML or binary plist format
- Used for third-party Audio Unit plugins; Logic-native plugins use `.pst` 
- Contains structured property list data
- Typically includes `data` key with embedded binary payload

Not all embedded files have associated filenames; some are raw data

## Current Implementation

The `Cst` struct provides:
- `instrument: PluginSetting?` — Optional instrument plugin
- `midiPlugins: [PluginSetting]` — MIDI plugins
- `audioFxPlugins: [PluginSetting]` — Audio FX plugins
- `audioInput: AudioInput?` — Selected hardware audio input; `nil` for instrument/bus strips and standalone CSTs (see "Audio Input Encoding" above)

`PluginSetting` cases:
- `.pst(Pst)` — Logic-native binary preset (GAMETSPP header)
- `.aupreset(Aupreset)` — Audio Unit plist preset (XML or binary plist)
- `.keyedArchive(KeyedArchive)` — NSKeyedArchiver binary plist; system/metadata block (`isSystemBlock == true`); UID graph resolved via `decoded`; Environment Layer settings accessible via `environmentLayer`
- `.unknown(Data)` — Raw bytes for formats not yet modelled; also `isSystemBlock == true`

System blocks (`.keyedArchive` and `.unknown`) are excluded from the user-visible plugin lists.

### Plugin Role Classification

Each UCuA block carries a role byte at offset 187 of the block prefix. Use bit tests, not equality:

| Bit | Meaning |
|-----|---------|
| `0x08` | Instrument (may combine with other bits, e.g. `0x18` on RS Antimatter) |
| `0x02` | MIDI FX (never combined with `0x08` in observed files) |
| neither | Audio FX (`0x00` on Instrument channel strips, `0x10` on Track channel strips) |

Classification rules:
- instrument: `role & 0x08 != 0`
- MIDI FX: `role & 0x02 != 0 && role & 0x08 == 0`
- audio FX: `role & 0x08 == 0 && role & 0x02 == 0`

For from-scratch CSTs where the prefix is shorter than 188 bytes, the parser falls back to treating the first PST as the instrument and the rest as audio FX (MIDI FX cannot be distinguished in that case).

### Slot Numbering

- Slot 2: instrument (Instrument channel strips); first audio FX (Track channel strips)
- Slots 3–6: audio FX in signal-flow order (Instrument channel strips only; Track uses 2–5)
- Slots 7–10: MIDI FX in signal-flow order
- Slots 9–11: may also hold NSKeyedArchiver system blocks
- Slot 12+: opaque/system blocks (`.opaque` or `.keyedArchive` in parser)

## Future Work

- [ ] Expand NSKeyedArchiver typed coverage: add fixture CSTs for all MIDI FX plugin types (Note Repeater, Velocity Processor, Scripter, etc.) to discover any additional MA\* class names beyond the currently observed set

## Technical Notes

### OCuA Container Structure

- **Header size**: `237 + (byte_62 * 4)` bytes. Byte 62 = slot capacity.
- **Header byte 40**: Channel strip type — `0x40`=Track, `0x42`=Bus, `0x43`=Instrument.
- **Header bytes 97–103**: Channel name string (null-terminated, e.g. `" Inst 1"`).
- **Header bytes 224+**: UUID-like field, unique per file.
- **Header bytes 237+**: Variable-length slot array, 4 bytes per slot.
- **Footer**: Constant 50 bytes, identical across all files.
- Each embedded plugin lives in a UCuA sub-container block (36-byte header + prefix + payload).
- UCuA block size field at offset 28 (LE uint32) = total block size − 36; updated on serialization.
- UCuA slot number at offset 18 (LE uint16).
- UCuA sub-header size at offset 36: `424` for named plugins (PST/XML-AU), `64` for direct BIN-AU, `196` for opaque.

### UCuA Block Prefix Sizes

| Type | Prefix size | Key fields |
|------|-------------|------------|
| PST (named) | 220 bytes | Filename at +50; plugin display name at +156; `"GAME"` at +168; manufacturer codes at +176 |
| XML AU (named) | 208 bytes | Filename at +50; AU component codes at +168 (manufacturer, type, subtype) |
| Binary AU (direct) | 56 bytes | Data length at +52; bplist starts at +56 |
| Opaque (patch ref) | 228 bytes | Patch filename; no parseable plugin |

### What Logic Reads From Where

- **Plugin type to instantiate**: UCuA block prefix offsets 156–175 (plugin name + component codes)
- **Preset name displayed in UI**: UCuA block prefix offset 50 (filename string)
- **Actual parameter values**: PST/AU payload data — independent of the prefix
- Logic does **not** cross-check prefix metadata against payload data
- Logic silently ignores blocks with unrecognized or missing prefix metadata (shows "No Plug-in")

### Audio Input Encoding (OCuA header)

Within the OCuA header's slot array region (bytes 237+), the 4-byte marker `00 80 00 80`
is followed by a 1-byte audio input selector:

| Value | Meaning |
|-------|---------|
| `0x00` | Default / no input |
| `0x0c` | Default / no input (present on instrument, bus/aux, and audio tracks with no input selected) |
| `0x01` | Mono Input 1 *(confirmed)* |
| `0x09` | Stereo In 1-2 *(confirmed)* |
| `1..8` | Mono inputs *(inferred)*: `inputIndex = value − 1` (0-indexed) |
| `9+`   | Stereo pairs *(inferred)*: `inputIndex = value − 9` (0-indexed) |

The marker position is not at a fixed absolute offset — it varies by channel type and slot
capacity. Search for `[0x00, 0x80, 0x00, 0x80]` within the header and read the following byte.

Only two non-default values (`0x01`, `0x09`) have been confirmed from real files. The conversion
formula for other values is inferred and may be incomplete. Non-default values have only been
observed in CST files embedded inside a `.patch` bundle; standalone CSTs always show `0x0c`.

Bus/Aux channel strips (`0x42`) always produce `0x0c` — bus routing is not encoded in the
CST binary. Exposed as `Cst.audioInput: AudioInput?` (nil for `0x00`/`0x0c`).

### Audio Track Environment Properties (OCuA header, exploratory)

Audio track CSTs store Environment Instrument properties (Flex Mode, Show Sends, etc.) inline
in the OCuA header — not as NSKeyedArchiver blocks. These offsets were identified by comparing
an unmodified audio track CST (`Audio track minimal.cst`) against one with Flex Mode set to
Monophonic and Show Sends turned off (`Audio track layer edited.cst`):

| Offset | Known values | Candidate meaning |
|--------|-------------|-------------------|
| `0x78` (120) | `0x00` = Off, `0x04` = Monophonic | Flex Mode |
| `0x82–0x83` (130–131) | `0x00 0x00` = on, `0xff 0xff` = off | Show Sends (inverted: `0x0000` = default/on) |

Other bytes that changed between the two files (`0x3E`, `0x42`, `0x44`, `0x4E`) also shifted
but their semantics are not yet understood. MIDI/Instrument track CSTs do not appear to use
these offsets for the same purpose — their Environment Layer settings are in an `MAKeyboardLayer`
NSKeyedArchiver block instead.

## Related Formats

- **PST files**: Individual plugin settings (can also be saved as `.pst` files)
- **AU Preset files**: Individual au preset settings (can also be saved as `.aupreset` files)
- **Patch files** (`.patch`): Like CST but includes mix controls; can contain Track Stacks
- **Instrument files** (`.exs`): Sampler instrument settings (separate format)

## File Structure Examples

### PST-based Channel Strip
```
File: Channel Strip.cst
Format: PST (magic-string)
Size: Variable
Contents: Binary PST data with instrument/effect parameters
```

### AU Preset-based Channel Strip
```
File: AU Channel Strip.cst
Format: AU Preset (plist)
Size: Variable
Contents: XML/binary plist with AU plugin data
```

## Common Use Cases

- **Instrument Tracks**: Retro Synth, Sculpture presets
- **Audio Effects**: Channel Strip effects, EQ, dynamics
- **MIDI Effects**: Arpeggiator, chord trigger settings
- **Third-party AU**: External plugin configurations

## Relationship to Other Formats

- **Contains PST/AU**: Channel strips embed preset data
- **Referenced by Patches**: Patch bundles contain channel strip files
- **Project Integration**: Used throughout Logic Pro projects

## File Locations

- **User Presets**: `~/Music/Audio Music Apps/Channel Strip Settings/` — subfolders: `Instrument/`, `Track/`, `Bus/`, `Output/`
- **Project Specific**: Within `.logicx` project bundles
- **Patch Bundles**: Inside `.patch` directory bundles

> **Note:** Logic Pro does **not** read channel strips from `~/Library/Application Support/Logic/Channel Strip Settings/` — that path is ineffective.

## Implementation

See [Cst.swift](Cst.swift) for the Swift implementation that parses and serializes CST files, and [KeyedArchive.swift](KeyedArchive.swift) for the NSKeyedArchiver decoder and `MAKeyboardLayer` model.