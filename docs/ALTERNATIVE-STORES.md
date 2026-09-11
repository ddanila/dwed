# Alternative document stores

The default DOS store has the editor's transaction and undo integration.
`STRSSWAP` uses a fixed-record `DBB` index and a chained-block `DBM` payload
store, both backed by `SYSTEM2` temporary files. `STRSSXMS` currently duplicates
that disk-backed implementation; its unit explicitly says the SXMS store is
not implemented. Selecting that name does not establish XMS-backed document
storage. The optional XMS cache in `SYSTEM2` is a separate layer.

## Database close ownership

`dbb_Close` and `dbm_Close` stop when seeking to or writing the header fails.
They preserve the database object when buffered-file flush or handle close
fails. Callers can inspect `f.f.ioresult`, retain the object, and retry close.
The object is cleared only after the underlying file is closed, preserving the
header, record geometry, handle, working buffer, and cache owners on handle-close
refusal. A closed temporary file with deletion pending retains its filename and
database metadata while releasing unused buffers and caches; see
[TEMPORARY-FILES.md](TEMPORARY-FILES.md).

The DOS probe covers repeated write, short-write, seek, and close failures,
then reads and appends records and verifies them after retry and reopening.
It also exhausts the scratch allocation needed to seek back to the header,
and checks temporary-file ownership through a refused close and later discard.
Its interrupt hook is installed only during close: forwarding an unrelated
long-filename probe through the Pascal interrupt helper would change its
incoming-carry fallback behavior and invalidate file setup.

See [database-close-milestone.json](database-close-milestone.json) for build
identity, fault evidence, reference-DOS coverage, and the old implementation
control. This contract covers database close ownership, not transactional
record mutation or complete editor behavior with these stores.

## Remaining qualification

[Database initialization](DATABASE-INITIALIZATION.md) validates headers without
rewriting failed input and retains cleanup ownership. [Checked append APIs](DATABASE-APPENDS.md)
write unpublished records for replacement transactions. [Checked index updates](DATABASE-UPDATES.md)
retain a before-image through partial-write failure and rollback.
[Checked line replacement](LINE-UPDATES.md) connects these APIs to editor
commits used by saving and closing. Remaining callers still need migration. Legacy allocation,
free-list traversal and updates, and replacement still need checked status
propagation and failure-safe publication. [Checked record reads](DATABASE-READS.md)
stage output and validate chains. [Checked string-store saves](STORE-SAVES.md)
propagate metadata and payload failures into safe-save cleanup. Loading,
page/word/mouse navigation, rendering, and editing still need checked error
propagation. [Vertical keyboard movement](VERTICAL-MOVEMENT.md) now checks its
source links and destination text before committing or moving.
Legacy string-store replacement frees the old payload before installing its
replacement. The checked path retains old and orphaned payloads until discard;
checked reclamation and migration of remaining editing callers are required
before the stores can be qualified for editing.

The alternative stores also need edit transaction and undo/redo integration,
exact-text and clipboard tests, and end-to-end disk-full, allocation, transfer,
and cleanup failures. Temporary-file creation and deletion ownership is covered by
[TEMPORARY-FILES.md](TEMPORARY-FILES.md); editor-level error propagation and
cleanup interaction still need qualification. The intended SXMS implementation must be distinguished
from the present disk-backed stub during that work. Keep these release gates
open; successful low-level cache or close tests do not satisfy them.
