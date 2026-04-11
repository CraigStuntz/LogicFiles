# Logic Pro `.patch` (Channel Strip++) File Format

## Overview

Patch (.patch) files are directory bundles that contain complete Logic Pro channel strip configurations. They represent "complete" presets that can include multiple channel strips for summing stacks and complex routing configurations.

> Patches include everything Channel Strip Settings do—all front-panel settings for all the individual plug-ins in the strip—but they also include the values of the other channel strip controls that are not part of a Channel Strip Setting—Send settings, and Pan and Channel Fader values. Patches can even include multiple channel strips, if they’re part of a Track Stack, including destination Aux channels within the Stack. 
(From "[Demystifying Logic Pro's Plug-In Settings, Channel Strip Settings & Patches](https://www.macprovideo.com/article/logic-pro/demystifying-logic-pro-x-s-plug-in-settings-channel-strip-settings-patches)")

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