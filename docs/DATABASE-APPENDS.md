# Checked backing-database appends

`dbb_TryAppend` and `dbm_TryAppend` write new records beyond the published
record-count boundary. They do not consume the free list, change the database
root, or alter an existing record chain. They stage caller input before changing
file buffers and return a new record ID only after complete buffered writeback.
A failed call returns false, preserves the caller's record-ID variable and
published header fields, and reports status in `f.f.ioresult`.

These operations check initialization, header bounds, representable file
positions, and contiguous heap availability. Chained appends allocate input
staging and a complete padded-block buffer before writing. Failure of the second
allocation releases the first. An empty chained append succeeds with a null
record ID and leaves header state unchanged.

A failed write can leave an unpublished tail in memory or on disk. That tail is
not linked from a live record, and the record-count boundary stays unchanged.
Retry starts at that boundary and overwrites the unpublished tail. Closing and
reopening after failure retains access to the previously published records.
This is a runtime failure contract, not a power-loss durability guarantee:
header persistence still occurs through the existing checked close path, and
DOS buffered writeback is not a hardware persistence barrier.

The DOS `DBAPPEND` probe exercises fixed and chained payloads crossing buffered
pages, including full and short write failures, refused seeks, read failures,
persistent failure, and a failure after an earlier page was written. It checks
old payloads, roots, free-list heads, allocation cleanup, retry, and reopening.
Boundary tests use maximum WORD-sized payloads and the largest representable
fixed records and chained blocks. Copy and fill helpers advance normalized far
pointers between bounded chunks; buffered reads and writes do the same. This
avoids offset wrap when a heap buffer spans a segment boundary. The byte oracle
uses explicit segment addressing, independently of these helpers. Optional XMS
cache allocation is refused for the disk-fault cases so injected DOS calls are
observable. When real XMS is present, a separate case enables the cache and
partially fails dirty-page retrieval before checking that the append stays
unpublished and retry preserves both old and new payloads.

See [record-append-milestone.json](record-append-milestone.json) for observed
results, build identities, and the legacy append control. These are new APIs for
staging future replacements. Legacy `Add`, `Put`, free-list mutations, and editor
line replacement have not been switched to them. Publishing a replacement index
entry, retiring its old payload, and coordinating multi-record edits still need
transactional failure handling before the alternative stores can be qualified.
