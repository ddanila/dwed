# Backing database initialization

`dbb_Reset` and `dbm_Reset` open existing databases. They do not create a missing
file or rewrite a file whose header cannot be read or validated. Creation is
an explicit `ReWrite` or `ReWriteTemp` operation.

The buffered open path preserves DOS open, seek, and read errors. Positive short
reads continue until the initial page is complete; premature EOF is an error.
The database layer checks this status before reading a candidate header. It
validates the signature, expected block geometry, nonnegative record count,
root and free-list bounds, and the physical space for the declared blocks.
Bounds use division instead of potentially overflowing record-offset products.
These are header checks, not a full traversal or validation of every record.

A database becomes ready only after successful initialization. A rejected
candidate header is never published. Cleanup closes its raw file without
writing database metadata; a refused handle close remains owned for retry.
Record operations reject a database that is not ready, even if a raw handle is
still open for cleanup. The existing close and temporary-delete ownership
contracts continue to apply.

DBM block-size normalization rejects arithmetic overflow before opening or
truncating a destination. The header-padding loop uses an unsigned counter so
the largest representable valid block remains supported. New-file initialization
also stops on the first header-seek or write failure rather than allowing a
later write to clear its error.

The probe corrupts existing headers and truncates declared storage, checks the
file byte for byte after refusal and cleanup, injects open/seek/read failures,
consumes short reads, exhausts allocation, and combines read or validation
failure with persistent close refusal. It verifies missing-file behavior and
round trips a maximum-size block whose payload crosses a buffer boundary.
See [database-open-milestone.json](database-open-milestone.json) for build and
runtime evidence.

Free-list traversal, record payload validation, transactional mutation, and
editor-level propagation of backing-store failures remain open. Readiness
means that initialization succeeded; it is not a claim that all record chains
have been validated. See [ALTERNATIVE-STORES.md](ALTERNATIVE-STORES.md).
