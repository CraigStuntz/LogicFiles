# Logic Pro `.aupreset` File Format

## Overview

AU Preset (`.aupreset`) files are Apple's standard format for storing Audio Unit 
preset data in Logic Pro. They use Apple's Property List (plist) format to store 
preset metadata and binary parameter data.

## Format Structure

AU Preset files are XML or binary plist files containing:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>data</key>
    <data>
        [Base64-encoded binary preset data]
    </data>
    <key>manufacturer</key>
    <integer>[Manufacturer code]</integer>
    <key>name</key>
    <string>[Preset name]</string>
    <key>subtype</key>
    <integer>[AU subtype code]</integer>
    <key>type</key>
    <integer>[AU type code]</integer>
    <key>version</key>
    <integer>[Version number]</integer>
</dict>
</plist>
```

## Key Components

### 1. Plist Container
- **Format**: XML or binary plist
- **Root**: Dictionary containing preset metadata and data
- **Encoding**: UTF-8 for XML, binary for compressed storage

### 2. Core Metadata Fields
- **`data`**: Base64-encoded binary preset parameters
- **`manufacturer`**: 4-byte manufacturer code (e.g., Apple = 'appl')
- **`subtype`**: 4-byte AU subtype identifier
- **`type`**: 4-byte AU type identifier (e.g., Effect = 'aufx', Instrument = 'aumu')
- **`version`**: Preset format version

### 3. Embedded Binary Data
The `data` field contains base64-encoded binary data that may include:
- **AU Parameter Values**: Float values for plugin controls
- **Preset State**: Complete plugin state information
- **Additional Metadata**: Plugin-specific configuration data

## Characteristics

- **Cross-Platform**: Standard macOS/iOS plist format
- **Human Readable**: XML variant allows text inspection
- **Compressed**: Binary variant for smaller file sizes
- **AU Standard**: Compatible with all Audio Unit plugins
- **Round-trip Safe**: Preserves exact binary data for compatibility

## Examples

### Compressor Preset (kHs Compactor.aupreset)
```xml
<dict>
    <key>data</key>
    <data>[Base64-encoded compressor settings]</data>
    <key>manufacturer</key>
    <integer>1634758764</integer>  <!-- 'kHs ' -->
    <key>name</key>
    <string>Heavy Compression</string>
    <key>subtype</key>
    <integer>1684238189</integer>  <!-- 'Comp' -->
    <key>type</key>
    <integer>1635083896</integer>  <!-- 'aufx' (effect) -->
    <key>version</key>
    <integer>1</integer>
</dict>
```

## File Extension
- **`.aupreset`**: Standard Logic Pro preset file extension
- **Location**: `~/Music/Audio Music Apps/Channel Strip Settings/` (within CST files), or `~/Library/Audio/Presets/` (AU system-level presets)

## Relationship to Other Formats
- **Channel Strip**: CST files may reference AU presets
- **Patch Bundles**: Patches contain `.cst` files, which in turn may reference AU presets — a `.patch` never contains an `.aupreset` directly

## Implementation

See [Aupreset.swift](Aupreset.swift) for the Swift implementation that parses and serializes AU Preset files.