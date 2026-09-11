# Temporary backing-file ownership

`SYSTEM2.ReWriteTemp` uses DOS create-new, so an occupied name is never opened
for truncation. Name collisions retry with another DOS basename within a bounded
attempt count; other errors stop immediately. Directory length is checked before
adding the basename and terminating NUL. Buffer allocation precedes creation,
and failed creation releases that buffer without acquiring a deletion owner.

File and database owners must be zero-initialized before their first use.
Creation cannot replace an open temporary owner or one with deletion pending.
DBB/DBM reset, rewrite, and temporary rewrite also refuse an owned object. Do not
use `Assign` or `FillChar` to reset a live owner: finish its cleanup first.

Closing a temporary file discards its buffered contents as before. If the DOS
handle closes but deletion fails, `delete_pending` and the filename remain with
the owner and `ioresult` contains the DOS error. The now-unused buffer and caches
are released. A subsequent `Close` retries deletion without closing the old
handle number, which DOS may already have reused for another file. An already
absent file completes cleanup. The database wrappers retain their metadata and
invoke this retry even though the underlying handle is no longer open.

If the handle itself cannot close, the open file, buffer, and caches remain
owned, following the existing [database close contract](ALTERNATIVE-STORES.md).
Explicit `Erase` now reports success and DOS errors correctly. A retained
filename after temporary close is a cleanup obligation, not a recovery copy
of unsaved editor text.

The probe forces a deterministic name collision and checks the pre-existing
file byte for byte. It also checks bounded collision exhaustion, creation and
allocation refusal, repeated deletion errors, actual DOS handle-number reuse,
already-removed files, database reinitialization refusal, and buffer/cache heap
release. Separate old-implementation controls demonstrate truncation on a name
collision and loss of deletion ownership. See [temporary-file-milestone.json](temporary-file-milestone.json)
for build identity and runtime evidence.

This does not complete alternative-store initialization error propagation,
transactional record mutation, undo/redo, or editor-level cleanup interaction.
Those remain part of the [alternative-store work](ALTERNATIVE-STORES.md).
