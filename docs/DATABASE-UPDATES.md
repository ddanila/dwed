# Checked fixed-record updates

`dbb_TryPut` stages the replacement and reads the complete old record before
writing. Once it can start changing the record, the database owns that old
record as a before-image. Success requires complete buffered writeback of the
replacement. On failure, `dbb_TryGet` and the legacy `dbb_Get` return the old
record from the before-image, and `dbb_PendingWrite` identifies the retained
rollback owner. Header root, free-list head, and record count are unchanged.

`dbb_RetryRollback` restores the old record and flushes it before releasing the
before-image. Another checked update, append, legacy mutation, or ordinary close
must first settle that rollback. Failed rollback retains the handle, file
buffers, metadata, and before-image. Initialization refuses to overwrite these
owners. Reading the pending old record needs no additional heap allocation.
Callers must retain the database object and use these database APIs; closing its
underlying `BFILE` directly or modifying rollback fields violates ownership.

This is a runtime transaction for one fixed record. A failed operation may have
partly changed the backing file or cache; the old view is authoritative through
the database API until rollback succeeds. The before-image is held in memory,
so this does not establish recovery after process termination or power loss.
Ordinary `dbb_Close` restores the old record before closing.

`dbb_Discard` explicitly abandons a temporary database without requiring rollback
writes. It refuses persistent databases. A failed handle close retains every
owner; after successful close, the before-image can be released even if deleting
the temporary file still needs a retry. The filename and deletion owner remain
until that retry succeeds.

The DOS `DBUPDATE` probe covers full, short, zero-length, and delayed write
failures; failures while reading or seeking; persistent rollback refusal;
allocation refusal at each staging step and during rollback; blocked mutations;
close retries; and temporary discard failures. It checks neighboring records as
well as the target, including an index-sized record crossing a buffered page
boundary and the maximum fixed-record size. An XMS case disables only the clean
read cache so a partial transfer failure targets dirty write-cache retrieval.
See [record-update-milestone.json](record-update-milestone.json) for build
identity, runtime evidence, and the legacy update control.

The legacy `dbb_Put` API remains unchecked for its own updates, although it cannot
bypass an already pending rollback. Editor callers still need migration to the
checked append and update APIs, with error propagation and safe retirement of
old payloads. Multi-record edits and undo/redo need transaction integration
beyond this single-record operation; keep [ALTERNATIVE-STORES.md](ALTERNATIVE-STORES.md)
release work open.
