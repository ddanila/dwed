# Undo journal and remaining integration

`SRC/UNREDO.PAS` implements a bounded, per-document journal of line insertions,
deletions and replacements. Each group represents one editor command. It
stores the changed byte strings and cursor/selection/viewport positions, not
copies of the complete document or pointers into mutable editor storage.
The limits and working-memory reserve are defined in the unit; strings occupy
only their actual payload length plus record overhead.

The journal is a foundation, not an available editor command yet. The old
startup/shutdown scaffold that created unused temporary databases has been
removed. Menu items and shortcuts must wait for atomic storage replay and
integration across all mutation paths.

## Transaction contract

An adapter begins a group before changing the document and records each line
mutation before applying it. Line indexes describe the document at that point
in the command. For undo, visit changes from last to first and apply their
inverse; for redo, visit first to last. Empty lines are represented by insert
or delete records with empty payloads, distinct from no-op replacements.
Byte strings are opaque, including tabs and codepage bytes.

If recording fails, the adapter must reverse already applied changes before
cancelling the pending group. The journal retains those records on failure;
failed finish does not free them. Replay must likewise be atomic, with all
needed storage allocated before committing changes or with a rollback path
that does not require allocation. Merely calling `undo_accept` does not edit
text: acknowledge only after the entire group has been successfully applied.

Only a successful nonempty finish discards the redo branch and evicts old
history. Cancellation and no-op commands preserve it. Eviction removes whole
oldest groups. A group larger than the configured limit is rejected, never
partially retained. Pending records can temporarily coexist with a full
committed history, bounded by the sum of the two limits. Allocation also
preserves a working-memory reserve. The editor adapter must present an
allocation failure and leave the document unchanged.

Each history has monotonically assigned state identifiers and an explicit
saved checkpoint. Undo back to the saved state becomes clean; undo away from
it becomes dirty. Branches never reuse state identifiers. A checkpoint is
established only after a successful file save, outside a pending edit. Saving
during a pending group cannot falsely mark it clean. Histories have explicit
initialization/disposal and do not share global document state.

## Evidence and remaining work

`tests/UNDOTEST.PAS` replays journal records against a separate array-based
text model and checks exact state fingerprints, preimages, history links,
accounting and heap recovery. It covers mixed multi-line groups, branching,
eviction, saved states, independent documents, opaque maximum-length payloads,
cursor state, no-ops and forced capacity/reserve failures. `tools/build.py
--tests` builds the probe from source. The parent QEMU gate runs it in LOW and
HIGH/UMB; the generated `undo-journal-milestone.json` records results.

Remaining integration includes atomic mutation/replay primitives, per-file
history ownership, edit boundaries including cached typing and bulk edits,
save checkpoints, user-visible undo/redo commands and enabled states, and
real editor tests for every mutation path and low-memory failure. The model
probe alone does not establish those editor behaviors.
