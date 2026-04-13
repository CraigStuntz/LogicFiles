# Logic Pro `.logicx` Project Format

## Overview

`.logicx` files are Logic Pro project bundles (macOS directory bundles with a `.logicx`
extension). They contain the full project — arrangement, automation, bounce files, and
embedded channel strip / preset data.

This library does **not** currently support `.logicx` files. The format documentation
here captures what is known and points to external references for future implementation.

## Known Structure

A `.logicx` bundle is a directory. Inspecting one with Finder ("Show Package Contents")
reveals a hierarchy of plists, binary data, and embedded audio files. The channel strip
and preset types documented in this library (`.cst`, `.pst`, `.aupreset`, `.patch`) appear
inside `.logicx` bundles, so this library may already be useful for reading those
sub-files once you have extracted them.

## External References

- [logicx-analyzer](https://github.com/geoffmyers/logicx-analyzer) — a reverse-engineering
  tool for the `.logicx` format; likely useful as a reference when implementing support.

## Future Work

- [ ] Parse `.logicx` bundle structure and expose embedded channel strip / preset data
      via the existing `Cst`, `Pst`, `Aupreset`, and `Patch` types
