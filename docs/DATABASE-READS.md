# Checked backing-database reads

`dbb_TryGet` and `dbm_TryGet` return success only after staging and validating
all requested bytes. Staging copies and buffered transfers handle far buffers
that cross a segment boundary; maximum-size cases are covered by
[the append probe](DATABASE-APPENDS.md). On failure, the caller's destination remains unchanged;
`f.f.ioresult` identifies the failure. Staging allocation refusal reports the
DOS out-of-memory status. Legacy `dbb_Get` and `dbm_Get` delegate to these
functions, retaining status in the database object.

Fixed-record reads validate the record number and its complete physical extent
before allocating or seeking. Chained reads validate each block's extent,
payload length, and next link, with constant-memory cycle detection and a
record-count bound. A prefix read still validates the complete chain. A valid
chain shorter than the requested output is an error. `dbm_Size` uses the same
traversal and reports failure through a zero result and nonzero status; callers
must inspect status to distinguish failure from an empty chain.

Buffered page switching consumes positive short DOS reads until the logical
page is complete. Seek failure, read failure, or premature EOF leaves the
previous working page owned and reports failure. Seeking to an empty page
beyond EOF does not increase the logical file size. A successful retry can move
the file cursor; these APIs promise atomic destination publication, not cursor
rollback or isolation from concurrent external file modification.

The DOS `DBREAD` probe exercises fixed and chained records crossing buffered
pages, repeated reads after failure, heap exhaustion, malformed links and
lengths, cycles, prefix validation, and size traversal. Its interrupt hook is
installed only during the read under test, after native fixture creation and
opening. The old implementation control uses legacy reads with the same
unchanged-destination assertion. Build identity and observed results are in
[record-read-milestone.json](record-read-milestone.json).

This is a backing-database API contract. [Checked string-store saves](STORE-SAVES.md) propagate read failures into the
shared writer. Loading, navigation, and editing still need checked propagation.
Record allocation, free-list mutation, replacement, transactions, and undo
remain separate release work; see [ALTERNATIVE-STORES.md](ALTERNATIVE-STORES.md).
