# Checked save replacement

`SAFESAVE.PAS` writes a newly created temporary file in the destination's
directory. Create-new semantics protect temporary files belonging to another
save. Writes must report the complete requested count, and DOS commit and
close must succeed before the destination is renamed.

When a backup already exists, it is parked under an unused `$EB*.TMP` name.
DOS rename must refuse an existing target, so a competing file is never
erased to obtain that name. The destination then becomes the backup, and the
new temporary becomes the destination. Editing a backup file uses the
alternate backup suffix already defined by the saver.

A failed rename attempts to restore the original destination and then the
previous backup. Successful rollback removes the new temporary. If rollback
fails, all remaining recoverable generations stay in place; cleanup does not
erase them. The `TSaveFile` record retains their paths and the recovery error.
A failed close is retried during cancellation. An invalid-handle response
on retry means the handle was already released. If close still fails, the record
continues to own the open handle and temporary path.

After the new destination is published, failure to delete the parked previous
backup does not turn the completed save into a failure. Its path and cleanup
error remain in `TSaveFile`. This distinguishes a successful publication with
an extra retained file from failure to save the document. A failed temporary
removal likewise leaves its path and cleanup error available to the caller.

## Fault evidence

`tests/SAVETEST.PAS` intercepts real DOS calls while invoking the actual saver.
It forwards ordinary calls to DOS and injects selected write, commit, close,
rename and cleanup failures. A short-write case actually writes a prefix and
returns the shorter count. Assertions compare destination, backup and retained
file bytes; check temporary-handle ownership; and protect a colliding backup
staging file. Rollback failures check each surviving generation separately.

The parent `tests/dwed_save_fault_scenarios.py` drives actual editor Save,
Cancel, Retry and Discard commands while a small DOS resident injector fails
an owned close or a replacement rename. It verifies that injection occurred,
the dirty buffer remains visible, and both saved files and backups contain
the expected bytes. The preceding editor build fails the rename scenario by
losing the previous backup. `save-fault-milestone.json` records the builds,
negative control and LOW/HIGH results together with the regression suite.

## Remaining recovery work

These are synchronous DOS-call failures, not simulated power cuts inside a
filesystem write. The editor still needs persistent recovery metadata,
startup discovery and recovery decisions after an interrupted replacement.
A recoverable temporary filename alone does not identify its destination or
prove that it is safe to restore.

The editor now retains the transaction in its context and reports secondary
errors and retained paths through the [session recovery screen](SAVE-RECOVERY.md).
Persistent metadata, restart recovery, read-only media and interruption tests
remain release gates. The synchronous fault milestone does not establish
crash-safe save or complete recovery support.
