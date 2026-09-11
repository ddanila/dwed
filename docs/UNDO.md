# Undo journal and remaining integration

`SRC/UNREDO.PAS` implements a bounded, per-document journal of line insertions,
deletions and replacements. Each group represents one editor command. It
stores the changed byte strings and cursor/selection/viewport positions, not
copies of the complete document or pointers into mutable editor storage.
The limits and working-memory reserve are defined in the unit; strings occupy
only their actual payload length plus record overhead.

Conventional-memory storage can apply recorded groups atomically. Live
editing is not yet recorded into this journal, so undo/redo are not available
editor commands yet. The old startup/shutdown scaffold that created unused
temporary databases has been removed. Command integration must cover all
mutation paths before menu items and shortcuts are enabled.

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

## Conventional-memory replay

`STRSDOS.replay_group` prepares the complete group before changing a link. It
allocates replacement lines and replay records while preserving the requested
working-memory reserve. Preparation memory is proportional to changed lines,
without cloning the full document. It then resolves each line ordinal in the
intermediate document and checks replacement/deletion preimages byte for byte.

Removed nodes remain allocated until the entire group succeeds. A mismatched
preimage or invalid ordinal reverses all applied splices in reverse order,
using the retained nodes without allocating. Failure preserves original node
identities, links, contents and cached line numbers, and frees preparation
memory. Success publishes the new root, renumbers the chain, frees removed
nodes and releases temporary replay records. Unchanged lines retain their
nodes. The journal and its current/saved state are not modified by replay.

The return value and `errCode` distinguish success, insufficient working
memory (`REPLAY_NO_MEMORY`) and a bad ordinal or preimage (`REPLAY_INVALID`).
The controller must acknowledge the journal only on success and rebuild its
cursor/viewport pointers from the group's saved positions. The storage API
supports empty chains; the editor controller must preserve its own invariant
that an empty document contains an empty line.

The existing live `put`/`create`/`delete` editing paths do not yet record groups
or use this transaction mechanism. Swap and XMS replay remain unimplemented
and unqualified. Atomic replay does not by itself make live edits atomic.

## Evidence and remaining work

`tests/UNDOTEST.PAS` replays journal records against a separate array-based
text model and checks exact state fingerprints, preimages, history links,
accounting and heap recovery. It covers mixed multi-line groups, branching,
eviction, saved states, independent documents, opaque maximum-length payloads,
cursor state, no-ops and forced capacity/reserve failures. `tools/build.py
--tests` builds the probe from source. The parent QEMU gate runs it in LOW and
HIGH/UMB; the generated `undo-journal-milestone.json` records results.

`tests/STORTEST.PAS` exercises the real conventional-memory backend against
a separate array-based text model. It checks every stored byte, both link
directions, cached line numbers, empty chains, maximum payloads, branching,
eviction and heap recovery. Failure cases include preparation exhaustion and
invalid ordinals/preimages after partial forward and reverse replay; they
also assert original pointer identities. Parent LOW/HIGH QEMU results and a
negative control with rollback disabled are recorded in
`undo-storage-milestone.json`.

Remaining integration includes atomic live mutation capture, per-file
history ownership, edit boundaries including cached typing and bulk edits,
save checkpoints, user-visible undo/redo commands and enabled states, and
real editor tests for every mutation path and low-memory failure. The model
probe alone does not establish those editor behaviors.
