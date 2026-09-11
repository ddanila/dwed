# Resolving an already-installed recovery payload

On the Interrupted save screen, C checks whether a recovery record describes
contents already present at its destination. The destination must match the
recorded payload size and CRC. If the temporary still exists, it must match too.
Missing temporaries are allowed because an interrupted publish or earlier cleanup
may already have removed them. CRC detects accidental changes; it is not
cryptographic authentication.

A successful check opens a confirmation showing the record and temporary paths.
D removes the duplicate temporary, if present, and then the record. Enter or
Escape keeps them. The destination and normal backup are never removed by this
operation. The record and payloads are reread and revalidated after confirmation.
A read, close or deletion failure stops cleanup; a failed close retains ownership
in the editor context. Removing the record last keeps a failed cleanup
discoverable. A retry can validate the destination when the temporary has already
been removed.

A retained previous-backup temporary blocks this operation. The current record
has no fingerprint for that generation, so it cannot establish that the file is
safe to remove. The screen gives its path and leaves the files intact. Likewise,
a destination changed by later edits does not qualify merely because a recovered
document was saved at some point.

The parent QEMU scenarios cover confirmation and cancellation, matching and
changed payloads, a missing temporary, an unverified previous backup, and a
read-only record whose failed deletion must remain retryable. An injected read
failure after confirmation proves that the operation validates again before
deleting. Existing discovery and close-ownership regressions remain in the
qualification set. Build fingerprints and results are in
[recovery-cleanup-milestone.json](recovery-cleanup-milestone.json).

This is a startup resolution path for an already-installed payload. Guided
resolution of older generations and later-edited recovered contents remains a
release gate. The tests use private local FAT images; concurrent writers and
network-volume deletion races are outside this qualification.
