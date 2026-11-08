# Logic Pro `.patch` (Channel Strip++) File Format

## Overview

Patch (.patch) files are directory bundles that contain complete Logic Pro channel strip configurations. They represent "complete" presets that can include multiple channel strips for summing stacks and complex routing configurations.

> Patches include everything Channel Strip Settings do—all front-panel settings for all the individual plug-ins in the strip—but they also include the values of the other channel strip controls that are not part of a Channel Strip Setting—Send settings, and Pan and Channel Fader values. Patches can even include multiple channel strips, if they’re part of a Track Stack, including destination Aux channels within the Stack. 
(From "[Demystifying Logic Pro's Plug-In Settings, Channel Strip Settings & Patches](https://www.macprovideo.com/article/logic-pro/demystifying-logic-pro-x-s-plug-in-settings-channel-strip-settings-patches)")

Additionally, a `.patch` contains the selected audio input of an audio track. 

## Directory Structure

Patch files are actually [bundles](https://en.wikipedia.org/wiki/Bundle_(macOS)) with a `.patch` extension containing:

```
My Patch.patch/
├── #Root.cst                 # Main channel strip configuration (required)
├── data.plist               # Channel strip surface settings (required)
├── [Additional CST files]   # Additional channel strips for summing stacks
```

## Key Components

### 1. Root Channel Strip (#Root.cst)
- **Primary File**: Main channel strip configuration
- **Format**: CST format (contains embedded PST/AU presets)
- **Required**: Every patch must have a root channel strip

### 2. Additional Channel Strips
- **Format**: CST files (named like `Inst2.cst`, `TestPatch.cst`, etc.)
- **Purpose**: Additional channel strips in summing stacks
- **Optional**: Only present in summing stack patches

### 3. Metadata (data.plist)
Required plist file containing:
- `versionPatches` — patch format version
- `channels` — array of per-channel-strip settings (filename, UUID, name, mute/solo state, routing, MIDI receive channel, etc.)

The plist may also contain additional keys not yet modeled by the parser; these are preserved verbatim for round-trip fidelity.

## Characteristics

- **Bundle Format**: Directory presented as single file in Finder
- **Hierarchical**: Can contain multiple channel strips for summing stacks
- **Portable**: Self-contained with all dependencies
- **Version Safe**: Compatible across Logic Pro versions
- **Editable**: Contents can be modified and saved

## File Structure Examples

### Simple Patch
```
Retro Synth Patch.patch/
├── #Root.cst                    # Main Retro Synth preset
└── data.plist                   # Patch metadata
```

### Summing Stack Patch
```
Summing Stack.patch/
├── #Root.cst                    # Main channel strip
├── Inst2.cst                    # Additional instrument channel strip
├── TestPatch.cst                # Another channel strip
└── data.plist                   # Patch metadata
```

## Common Contents

- **Instrument Patches**: Complete instrument setups with effects
- **Effect Chains**: Multiple effects configured together
- **Channel Strips**: Full channel configurations
- **Summing Stacks**: Multiple channel strips combined
- **Complex Routings**: Sends, groups, and aux configurations

## Sends and Bus Routing

Measured on Logic Pro 13.0 (VersionPatches 40014) from calibration patches saved by Logic and compared with their
`data.plist`, and checked against Logic 13.0's factory patches. Offsets are file offsets within a channel's `.cst`
inside the bundle (the OCuA header starts at 0, so the header's channel type is at byte 40).

### data.plist

Each entry of `channels[]` carries the routing in patch-local bus numbers (0-based: index 0 is "Bus 1" as saved):

| Key | Meaning |
|-----|---------|
| `Channel_outputIsBus`, `Channel_outputIndex` | the output: a bus index, or not a bus (`false`, index 0: the Stereo Out) |
| `Channel_inputIsBus`, `Channel_inputIndex_1` | the input: on an aux or a summing stack's root, a bus index |
| `Channel_sends` | an array of two dictionaries, one per send slot; `{}` when the slot is empty |

A populated send dictionary:

| Key | Type | Meaning |
|-----|------|---------|
| `sendOutputIndex` | int | the destination bus (patch-local, 0-based) |
| `sendVolume` | real | the level as a fraction of 127: 0.7087 (= 90/127) is the commonest non-zero value in the factory patches; 0.4007 measured at "about -10 dB" |
| `sendMode` | int | 0, 1 or 2 (2 in the calibration's sends, made with Logic's defaults; which mode each value is wasn't checked) |
| `sendIsMuted` | bool | |
| `auxTag` | string | instead of `sendOutputIndex` in some factory patches: names a shared aux patch in `Patches/Aux/Shared Aux/` |

When Logic loads a patch it renumbers its buses onto free buses of the project (a patch whose sends go to patch-local
buses 1 and 2 loaded them on Bus 7 and Bus 8 of an empty project). Observed once: an aux whose input bus nothing in the patch feeds loads with no
input at all.

### The channel's OCuA header

| File offset | Size | Meaning |
|-------------|------|---------|
| 0x80 (128) | u16 LE | the output: 0 = the Stereo Out, else `Channel_outputIndex` + 1 (8 of 8 tracks in the calibration) |
| 0x82 (130) | u16 LE | the input bus on an aux or a stack's root: `Channel_inputIndex_1` + 0 (2 of 2 in the calibration); 0xFFFF on a track whose input isn't a bus |

Also in the header, for completeness: the fader's whole part at 0x79 (a byte, 90 on a new track), the fader as a u32
8.24 fixed-point value at 0x98 (0x5A000000 = 90.0; its top byte equals 0x79 in all 410 factory channels read), and the
pan at 0x7D (-64..+63 stored + 64). The fader's value in dB is not known.

### The send record (UCuA slots 0 and 1)

A send is a 76-byte record in slot 0 or 1 (slots 0 and 1 are reserved for sends; inserts start at slot 2). Offsets
from the start of the record's payload, after its 36-byte block header:

| Offset | Size | Meaning |
|--------|------|---------|
| 0x00 | u32 | 0x44 in Logic 13.0's records, 0x48 in 12.4's and the factory records |
| 0x06 | u16 | the slot (0 or 1) |
| 0x0A | 2 | `35 12` |
| 0x10 | u8 | a mode flag: 1 exactly where `sendMode` is 2 (4 of 4 records), 0 in all 8,771 factory records with `sendMode` 0 or 1. It is **not** the bus |
| 0x11 | u8 | the level's whole part (`sendVolume` x 127, truncated) |
| 0x14 | u8 | **the bus: `sendOutputIndex` + 2** (3 of 3 records saved by Logic: two from 13.0, one from 12.4) |
| 0x18 | u32 LE | the level, 8.24 fixed point = `sendVolume` x 127 (all 8,772 factory records with a `sendVolume`, and the 3 calibration records) |
| 0x2C, 0x3C | 16 each | UUIDs |

In Logic's factory patches the 0x14 bus byte and the aux's 0x82 often disagree with their own `data.plist`
(0x14 - `sendOutputIndex` is +14, +2, +20 or +4), which suggests the factory buses were renumbered in `data.plist`
after saving, and that Logic routes by `data.plist` when it loads a patch (an inference, not tested on its own: the
patches I generated write both consistently).

### Patch channel layout in Logic 13.0

A channel's slot count n is the u16 at file offset 0x3E (OCuA payload 0x1A). The trailing records sit at fixed steps
below n, not at fixed slots: the name record at n-5 (Logic 13.0 writes it on the stack's root only; 12.4 wrote it on
every channel), Smart Control mappings at n-3, the Smart Control layout at n-2, track settings at n-1. Logic 12.4's
patch channels have n = 19; Logic 13.0's have n = 21.

## Relationship to Other Formats

- **Contains CST files**: Patch bundles contain channel strip configurations
- **CST contains PST/AUPRESET**: Individual channel strips embed preset data
- **Project Integration**: Can be dragged into Logic Pro projects
- **Library Storage**: Stored in User Patch Library
- **Sharing**: Portable format for sharing complete setups

## File Locations

- **User Library**: `~/Music/Audio\ Music\ Apps/Patches/`
- **Project Bundles**: Within `.logicx` project packages

## Usage in Logic Pro

- **Channel Strip Menu**: "User Patches" submenu in channel strip menu
- **Library Browser**: Browse and organize in Library panel
- **Drag & Drop**: Can be dragged directly into tracks
- **Save Function**: "Save..." button in Library

## Technical Notes

- **Directory Bundle**: macOS package format
- **Extension Hiding**: `.patch` directories appear as files
- **Resource Fork**: May contain additional macOS metadata
- **Cross-Version**: Generally compatible between Logic versions
- **Validation**: Parser requires `#Root.cst` file to be present

## Implementation

See [Patch.swift](Patch.swift) for the Swift implementation that parses and serializes Patch files.