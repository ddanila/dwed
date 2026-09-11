# Resolving an already-installed recovery payload

On the Interrupted save screen, C checks whether a recovery record describes
contents already present at its destination. The destination must match the
recorded payload size and CRC. If the temporary still exists, it must match too.
Missing temporaries are allowed because an interrupted publish or earlier cleanup
may already have removed them. CRC detects accidental changes; it is not
cryptographic authentication.

A successful check opens a confirmation showing the record and temporary paths.
D removes the duplicate temporary and a fingerprinted previous-backup temporary,
when present, and then the record. Enter or
Escape keeps them. The destination and normal backup are never removed by this
operation. The record and payloads are reread and revalidated after confirmation.
A read, close or deletion failure stops cleanup; a failed close retains ownership
in the editor context. Removing the record last keeps a failed cleanup
discoverable. A retry can validate the destination when the temporary has already
been removed.

Current journals fingerprint the previous backup before it is parked. Cleanup
checks that fingerprint and includes its path in the confirmation. Changed or
unreadable generations are retained. Older journals have no such fingerprint:
a retained previous-backup temporary blocks cleanup for those records, with its
path shown for inspection. A changed destination never qualifies solely by its filename.

The parent QEMU scenarios cover confirmation and cancellation, matching and
changed payloads, a missing temporary, an unverified previous backup, and a
read-only record whose failed deletion must remain retryable. An injected read
failure after confirmation proves that the operation validates again before
deleting. Existing discovery and close-ownership regressions remain in the
qualification set. Build fingerprints and results are in
[recovery-cleanup-milestone.json](recovery-cleanup-milestone.json).

After recovering a document, EDIT keeps an in-memory copy of the originating
record and its path with that document. Following a successful save, it verifies
the newly published file against the checked writer's size and CRC before
offering cleanup. Further edits and Save As therefore do not have to reproduce
the older journal payload. The old temporary still requires the old payload
fingerprint, and the retained older backup still requires its own fingerprint.
The new saved path must not be any of the cleanup deletion targets. The original
record snapshot is compared byte for byte against a fresh read, and the entire
check repeats after D confirms deletion. Ordinary documents never acquire an
association merely by sharing a destination name.

Enter or Escape keeps the association and files; another successful save in the
same editing session offers the check again. Failed saves do not offer cleanup
or clear the unsaved state. Cleanup failure does not undo a successful save.
The association is allocated only for a recovered document, with checked memory
availability, and released when that document is closed. It is not serialized
across editor restarts or external-command relaunches. Retained files then remain
available through startup discovery or manual inspection; no later saved file is
inferred from a filename alone. Legacy unverified older backups continue to
require manual inspection.

The tests use private local FAT images; concurrent writers and network-volume
deletion races are outside this qualification. Later-save results, allocation
probes and build fingerprints are in
[saved-recovery-milestone.json](saved-recovery-milestone.json).

Current-format and legacy-format coverage is in
[backup-fingerprint-milestone.json](backup-fingerprint-milestone.json).
