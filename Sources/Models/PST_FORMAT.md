# Logic Pro `.pst` (Preset) File Format Specification

## Overview

PST files (Preset files) in Apple Logic Pro store synthesizer and instrument presets using a fixed binary format: a 24-byte GAMETSPP header followed by a payload of instrument parameter data.

The PST parser enforces **exact byte-for-byte round-tripping**: `init(data:)` followed by `data()` must produce identical bytes.

---

## Format

### Header Structure (24 bytes)

```
Offset  Size  Type        Endianness  Description
------  ----  ----------  ----------  -----------------------------------
0x00    4     UInt32      LE          Total file size (bytes)
0x04    4     UInt32      LE          Format version (typically 1)
0x08    4     UInt32      LE          Data/payload size
0x0C    8     ASCII       N/A         Magic string: "GAMETSPP"
0x14    4     UInt32      LE          Flags/additional version info
0x18    ...   Binary      N/A         Payload (parameter data)
```

### Flags Field

The flags field at offset 0x14 has been observed as `0x00000117`:

```
Binary: 0000 0001 0001 0111
Bits 0-2: 0x7  (preset flags?)
Bit  4:   0x1  (version indicator?)
Bit  8:   0x1  (additional flag?)
```

### Payload Structure

The payload immediately follows the 24-byte header. It contains:

1. **Parameter Block** — sequential IEEE 754 single-precision floats (4 bytes each, little-endian). Parameter order and meaning depend on the specific instrument.

2. **Padding Region** — sentinel value `0xcaf24971` marks uninitialized/reserved slots. As a float this is ~1e+30 (a very large sentinel). Many parameter slots are pre-allocated but unused in sparse presets. Preserving exact padding is critical for round-trip fidelity.

### Format Stability

- No detected checksums or CRC fields
- Direct serialization preserves exact bytes
- No apparent encryption or obfuscation

---

## Example: RS2.pst (Retro Synth)

```
File size:   3,648 bytes
Version:     1
Data size:   904 bytes
Header:      24 bytes
Payload:     3,624 bytes
```

### Payload Analysis

```
Offset  Hex (LE bytes)        Float Value    Likely Parameter
------  --------------------  -----------  ---------------
0x00    00 00 00 00            0.0          Shape 1 (Osc 1 waveform)
0x04    00 00 00 00            0.0          Shape 2 (Osc 2 waveform)
0x08    00 00 80 41           16.0          Pitch offset (semitones?)
0x0C    00 00 80 3f            1.0          Amplitude/Mix index
0x10    00 00 00 00            0.0          Reserved
0x14    00 00 00 00            0.0          Reserved
0x18    00 00 c0 bf           -1.5          Envelope/LFO depth
0x1C    ca f2 49 71            ???          Padding sentinel
0x20    00 00 80 bf           -1.0          Invert/negative parameter
0x24    00 00 00 40            2.0          Mix amount
0x28    00 00 40 42           48.0          Filter/envelope time
0x2C    00 00 00 00            0.0          Reserved
0x30    00 00 80 3f            1.0          Parameter
0x34    ae 47 61 3e            0.22         Modulation depth (normalized)
0x38+   ca f2 49 71 (...)      ???          Padding block (806 repetitions)
```

---

## Data Model

```swift
struct Pst: Codable {
    let envelope: PstEnvelope     // Always present; wraps header + payload

    var header: PstHeader { envelope.header }   // Convenience accessor
    var payload: Data { envelope.payload }       // Convenience accessor
}

struct PstEnvelope: Codable {
    let header: PstHeader
    let payload: Data
}

struct PstHeader: Codable {
    let fileSize: UInt32
    let formatVersion: UInt32
    let dataSize: UInt32
    let magic: String          // Always "GAMETSPP"
    let flags: UInt32
}
```

---

## Parsing

`Pst.init(data:)` delegates to `PstEnvelope.init(data:)`, which:

1. Validates `data.count >= 24`
2. Reads header fields (all little-endian)
3. Asserts `magic == "GAMETSPP"` — throws `PSTParseError.invalidMagic` if not
4. Stores all bytes after offset 24 as `payload`

`Pst.data()` returns `header.data() + payload` exactly.

---

## Error Handling

```swift
enum PstParseError: Error {
    case insufficientData(String)   // File shorter than 24 bytes
    case invalidMagic(String)       // Magic string not "GAMETSPP"
    case invalidFormat(String)      // Malformed structure
}
```

---

## Nested Payload Detection

`Pst.tryParsePreset()` inspects the payload for an embedded preset blob and returns a `PresetDetection` with a `NestedPresetFormat`:

- `.emagic` — payload itself contains a GAMETSPP header at offset 12
- `.chunked` — payload starts with a 4-byte ASCII ID + plausible length field
- `.unknown` — no recognized structure

This is a heuristic for discovery; it does not parse or validate the nested blob.

---

## Related Formats

- **AUPreset (.aupreset)**: XML or binary plist with embedded data payload
- **Chunked PST**: Generic `[ID][Length][Payload]` format for other instruments
- **AU State**: Similar parameter preservation approach

---

## Testing

### Round-Trip Invariant

All test files must satisfy:

```
original_data == Pst(data: original_data).data()
```

### Test Files

| File | Format | Size | Notes |
|---|---|---|---|
| `RS2.pst` | GAMETSPP | 3,648 bytes | Retro Synth preset |
| `Retro Synth.pst` | GAMETSPP | — | Real-world Retro Synth preset |
| `Phat FX.pst` | GAMETSPP | — | Real-world FX preset |
| `sample.pst` | Invalid | 10 bytes | Used to verify that `init(data:)` throws on non-PST data |

---

## Implementation

See [Pst.swift](Pst.swift) for the Swift implementation.

## References

- IEEE 754 single-precision float standard
- Sample PST reverse engineering (this repository)
