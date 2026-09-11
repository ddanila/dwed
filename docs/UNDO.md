# Undo and redo

`SRC/UNREDO.PAS` implements a bounded, per-document journal of line insertions,
deletions and replacements. Each group represents one editor command. It
stores the changed byte strings and cursor/selection/viewport positions, not
copies of the complete document or pointers into mutable editor storage.
The limits and working-memory reserve are defined in the unit; strings occupy
only their actual payload length plus record overhead.

In conventional-memory mode, the Edit menu and Ctrl-Z / Ctrl-Shift-Z provide
Undo and Redo. Each document owns its history. Typing records one character per
group; compound commands such as a selection cut, paste or line split record
all their component changes in one group. Navigation and no-op edits preserve
redo and allocate no journal group. Menu entries are disabled when the
corresponding history is unavailable. The legacy Ctrl-Y cut-line shortcut is
preserved.

Successful saves establish a checkpoint. Undoing back to it clears the dirty
marker, and redoing away from it makes the document dirty again. Saving after
undo establishes the checkpoint at the current state. Closing a document frees
its history. External-command launch saves/reloads documents using the existing
session mechanism and starts new histories on return.

Swap and XMS modes do not yet have undo/redo support; their menu entries remain
disabled. This milestone does not complete the EDIT release qualification.

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

## Live edit capture

`DWEDHNDL.run_action` places command callbacks inside an edit boundary.
`DWEDUNDO.PAS` snapshots the active file context and commits cached typing
before finishing the group. File lifecycle, saving, window switching and
undo/redo use their own paths. Conventional-memory `put`, `create` and deletion
capture deltas before changing links; merge, split and paste use those same
entry points. The live transaction retains removed nodes until commit.

A history-capacity or working-memory failure aborts the command, restores all
original nodes without allocation, cancels its journal group and restores the
file context, including selection, cursor, dirty state and existing history.
The error dialog reports that the document is unchanged. Large compound edits
that cannot fit in a whole history group are cancelled rather than partially
retained. The clipboard is separate from document undo history.

The abort boundary uses the pinned FPC RTL's `setjmp`/`longjmp`, including
returns across far editor callbacks. Mutation callbacks use short-string
locals. Any future heap-owning resource inside that boundary needs explicit
cleanup before an abort can bypass its normal return path. The DOS storage
probe tests an allocation failure inside a far callback after a live mutation,
then verifies byte/node/heap restoration and preserved redo history.

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

The parent `dwed_undo_scenarios.py` exercises real editor commands and disk
outputs, including typing, split/join, cut and restored selection, multi-line
cut, paste, indentation, line movement, save checkpoints, branching, independent
windows and cancellation of an oversized edit. The generated
`undo-live-milestone.json` records the build and runtime evidence.

Remaining qualification includes search/replace and optional addon/table
commands, constrained-memory editor runs beyond the tested capacity failure,
legacy CPUs and modifier-key queues under delayed input, and swap/XMS support.
The broader text-format, clipboard, mouse, display and safe-save recovery gates
in `EDIT-PLAN.md` also remain open.
