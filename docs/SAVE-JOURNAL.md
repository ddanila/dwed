# Persistent save record

The checked writer creates a recovery record in the destination directory after
the payload has been completely written, committed and closed. The record must
also be completely written, committed and closed before any replacement rename.
A record failure leaves the destination and previous backup untouched.

`SAVEINFO.PAS` defines the packed, versioned record. It identifies the
destination, payload temporary, ordinary backup and planned location for a
previous backup. Current records contain size and IEEE CRC-32 fingerprints for
the payload and any previous backup that will be parked, plus a CRC-32 covering
the record. Records are immutable during replacement: recovery must
inspect which files survived instead of assuming that a recorded plan finished.
CRC detects accidental corruption; it is not authentication of a record's author.

New builds read both journal layouts. Earlier builds cannot validate the new
layout and must leave it for a current editor to recover.

Record creation uses an unused `$ER*.REC` name and DOS create-new semantics.
Payload and record candidates exclude the destination, including when the user
edits a file with a name resembling the editor's own temporary names. The
planned backup location is selected before the record is written. If another
file claims that location, rename fails without overwriting it.

The transaction retains the record's handle if close fails. The session recovery
screen shows the record path and prevents leaving while an owned payload,
record or backup-verification handle remains open. Successful replacement or rollback removes the record only after
the other owned cleanup is complete. Failed rollback, failed cleanup and an
explicit choice to keep recovery files leave the record available.

## Validation

A reader must read exactly the packed record and reject short or trailing data.
`valid_record` checks the signature, version, declared size and checksum, then
checks the path relationships and owned filename patterns. Payload identity
requires checking the candidate file's actual size and CRC against the record.
The reader also accepts the original record layout, whose previous-backup
identity remains unknown. The old destination is not fingerprinted and is never
a cleanup deletion target. A previous-backup fingerprint must be checked against
the actual retained file before confirmed cleanup can remove it.

The SAVETEST probe injects record create, write, short-write, commit, close and
cleanup failures into the actual writer. It verifies that failing to complete
the record precedes every rename, checks retained handle ownership and retry,
and protects another recovery record from deletion. It also saves destinations
whose names resemble the payload, record and parked-backup names.

The parent's `dwed_save_cut_scenarios.py` terminates QEMU immediately after
selected successful DOS operations, inspects the retained files independently
on the host, then boots DOS again from the same private disk images. RECVTEST
reads and validates the record and checks every surviving file generation after
the reboot. Its format checks reject damaged records, unsupported versions and
sizes and unrelated paths. Startup discovery also accepts normalized directory
aliases while rejecting paths containing control characters. The host uses an independent CRC
implementation. Generated results and artifact hashes are in
`save-journal-milestone.json`.

## Remaining integration

The interruption tests cover boundaries after completed DOS calls. They do not
simulate a torn filesystem-sector write, host power loss or faulty hardware
write caches. [Startup discovery](STARTUP-RECOVERY.md) offers verified payloads
as unsaved documents, with a subsequent editor boot in the interruption tests.
Safe resolution of retained generations and broader platform qualification
remain release gates.

Current backup-fingerprint qualification is recorded in
[backup-fingerprint-milestone.json](backup-fingerprint-milestone.json). Reading
and closing the previous backup must succeed before creating the journal or
renaming any generation. The transaction owns a failed-close read handle until
cleanup succeeds; failed verification preserves the original and backup.
