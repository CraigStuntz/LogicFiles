---
name: release
description: Create a new versioned release of the LogicFiles Swift library. Run this when the user invokes /release. Covers version determination, code/security/docs review, fuzzing, benchmarking, CHANGELOG update, formatting, tests, tagging, and GitHub release creation.
disable-model-invocation: true
---

# Release

This skill produces a signed, tagged, pushed release of the LogicFiles library. It is intentionally sequential — each phase gates the next. Do not skip phases or proceed past a blocking finding without explicit user confirmation.

---

## Phase 1 — Determine version

1. Find the most recent release tag: `git describe --tags --abbrev=0`
2. List all commits since that tag: `git log <tag>..HEAD --oneline`
3. Apply semver rules to determine the bump:
   - **patch** — bug fixes, docs, performance, test-only changes
   - **minor** — new public API, new file format support, new features
   - **major** — breaking changes to existing public API or serialization format
4. Propose the new version (e.g., `v0.4.0`) and show your reasoning. **Wait for user confirmation** before continuing.
5. Update `README.md` code examples with the new version number, but do not commit these changes yet.

---

## Phase 2 — Initial format, build, and test

Run these in order and stop on any failure:

```bash
swift package plugin format-source-code
swift build
swift test
zizmor -p --gh-token $(gh auth token) . # Security audit for GitHub Actions
```

If anything fails, report the error and ask the user how to proceed. Do not continue to Phase 3 until all commands pass clean.

---

## Phase 3 — Review pass

Get the full diff since the last release tag:

```bash
git diff <last-tag>..HEAD -- Sources/
```

Do all four reviews in a single pass over that diff:

### Code review
Look for: logic errors, incorrect assumptions about Logic Pro file formats, unnecessary complexity, missing edge-case handling in `init(data:)` / `data()` round-trips, violation of the primary invariant (byte-for-byte round-trip).

### Security review
Look for: path traversal in `Patch` bundle handling, unbounded allocations on malformed input, integer overflow in binary parsing, any place where attacker-controlled input reaches a dangerous API.

### Docstring and documentation review
Look for: missing or stale docstrings on public API, inconsistencies between `.md` format documentation in `Sources/Models/` and the actual code behavior, terminology violations (Track vs Instrument channel strip, etc. — see CLAUDE.md § Terminology).

### Readability and organization review
Look for: confusing naming, public API that is hard to discover, documentation that describes *what* the code does rather than *why* or *when to use it*.

Produce a consolidated findings list grouped by severity:
- **Blocking** — must fix before release
- **Recommended** — worth fixing now
- **Future** — log but skip for this release

**Wait for user to confirm** how to handle blocking and recommended findings before continuing. If any fixes are made, return to Phase 2.

---

## Phase 4 — Fuzz and benchmark

### Short fuzz run
Run all fuzz targets for 120 seconds:

```bash
./Tools/run-fuzzers.sh 120
```

Report any crashes or hangs. If any are found, they are **blocking** — stop and work with the user to fix them, then return to Phase 2.

### Performance check
libFuzzer reports `exec/s` for each target. Record those numbers from the run above and note any target that looks unusually slow compared to prior releases. A dramatic drop in exec/s (>50%) is worth flagging to the user before continuing, but is not automatically blocking — the user decides.

---

## Phase 5 — CHANGELOG

1. Verify every commit since the last tag is accounted for in `CHANGELOG.md`. Cross-reference `git log <last-tag>..HEAD --oneline` against the Unreleased section.
2. Report any missing entries. If any are missing, work with the user to add them.
3. Organize the Unreleased section:
   - Merge any duplicate subheadings (e.g., two `### Added` blocks become one).
   - Reorder subheadings into the standard sequence: **Added → Changed → Deprecated → Removed → Fixed → Security → Performance**.
   - Omit subheadings that have no entries.
4. Update the `## Unreleased` header to `## <version> — <YYYY-MM-DD>` (today's date).
5. Add a new empty `## Unreleased` section above it.

If steps 2 or 3 produced any edits, return to Phase 2 for formatting.

---

## Phase 6 — Final format, build, test, and clean-tree check

Run the full suite again — any fix from Phases 3–5 may have introduced issues:

```bash
swift package plugin format-source-code
swift build
swift test
```

Then verify the working tree is clean:

```bash
git status
```

If there are uncommitted changes, commit them now with an appropriate message (e.g., `Release v0.4.0`). Do not tag a dirty tree.

---

## Phase 7 — Tag and publish

**Confirm with the user before each of these steps.**

1. Create the annotated tag:
   ```bash
   git tag -a <version> -m "<version>"
   ```

2. Push the tag:
   ```bash
   git push origin <version>
   ```

3. Create the GitHub release using the CHANGELOG section for this version as the body:
   ```bash
   gh release create <version> --title "<version>" --notes "<changelog body>"
   ```

Report the release URL when done.
