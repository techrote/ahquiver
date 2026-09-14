# F10 — Experimental rendered-selection to source edit bridge

Status: implemented as an experimental cooperating-renderer bridge; disabled by default.

F10 does **not** attempt to reverse arbitrary terminal glyphs into source positions. It becomes usable only when a renderer/editor that owns the source writes two current local snapshots: a rendered-selection snapshot and a versioned source map.

## Selection snapshot

INI format:

```ini
[selection]
render_session_id=session-123
render_start=6
render_end=9
```

Rendered offsets are zero-based, half-open visible-cell coordinates in the cooperating renderer's coordinate system. ANSI escape bytes are not visible cells.

## Source-map contract v1

```ini
[map]
contract_version=1
render_session_id=session-123
source_document_id=document-abc
source_path=C:\project\scene.txt
source_hash=<F10 fingerprint of the exact mapped source>
range_count=2

[range.1]
render_start=0
render_end=6
source_start=0
source_end=6
generated=0

[range.2]
render_start=6
render_end=9
source_start=6
source_end=9
generated=0
```

Offsets are zero-based half-open character ranges in the source text as read by AHQuiver. The producer is responsible for wrapping, tabs, ANSI styling, combining/zero-width characters and any other rendering transformation. F10 does not infer those transformations.

A range may be marked `generated=1`. Such cells explicitly have no editable source range, and any selection touching them is rejected. If a transformed segment is not 1:1, the producer must emit finer ranges that are 1:1 for selectable portions; F10 refuses partial selection of a coarse non-1:1 segment.

## Validation and destructive edit sequence

Every preview/action re-reads both snapshots. F10 checks:

1. selection and map use the same `render_session_id`;
2. the mapped source file exists;
3. its current fingerprint exactly equals `source_hash` from the map;
4. the full rendered selection is covered by non-generated map ranges without gaps;
5. resolved source ranges are valid/non-overlapping.

`terminal.source_edit.preview` returns the current resolved source ranges and a preview token.

`terminal.source_edit.delete` is safety class S2. With the default `require_confirmation=1`, it also requires `confirm=DELETE`. Supplying the preview token is optional but, when supplied, it must still match the freshly revalidated selection/map/source state.

Immediately before writing, the source store reads and validates the source hash again. It creates `<source>.ahquiver.bak`, writes a temporary file, and atomically replaces the original where Windows permits. On a write/replace failure it attempts rollback from the backup and reports failure rather than claiming the edit succeeded.

## Capability truth

With F10 enabled but no `selection_file`, `terminal.source_map_edit` is `unsupported`; the host still starts normally. A generic terminal without a cooperating source-map provider therefore cannot enable destructive source editing.

When cooperating snapshot paths are configured, capability begins `degraded` until an actual preview proves the session, map and source version are current. A successful preview upgrades the capability to `supported`; stale or malformed state degrades/rejects it again.

## Registered actions

- `terminal.source_edit.preview` — S0
- `terminal.source_edit.delete` — S2; `confirm=DELETE`, optional `preview_token`
- `terminal.source_edit.status` — S0

## Verification

`tests/F10TestRunner.ahk` covers mapping/deletion, stale session, stale source fingerprint, generated/gapped regions, unsupported selection, rollback behavior, stale preview tokens and a deterministic ANSI-renderer fixture using the real INI adapters plus transactional file source store.

`tests/F10EnabledStartup.ini` verifies that enabling F10 without any cooperating renderer remains an isolated `unsupported` capability rather than breaking AHQuiver startup.
