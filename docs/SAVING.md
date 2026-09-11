# Save replacement protocol

The shared string-store save entry point writes through `SRC/SAFESAVE.PAS`.
It obtains an exclusive DOS create-new file in the destination directory,
checks each unbuffered write (including a successful short write), commits DOS
buffers and checks close before changing the destination. Existing read-only
files are rejected. All storage backends use this writer through `strs.to_file`.

After the new file is complete, an existing backup is parked under an unused
`$EB*.TMP` name before the old destination moves to its `.BAK` name and the new
temporary moves to the destination. Saving a `.BAK` document uses `.BK!` for
its backup. A rename error triggers restoration of the original destination
and previous backup. Failed rollback retains the recoverable generations.
See [SAVE-TRANSACTION.md](SAVE-TRANSACTION.md) for the replacement protocol,
close ownership, secondary errors and fault-injection evidence.

DOS does not provide a single atomic replacement operation. After an interrupted
replacement, inspect the destination, its backup and the `$ED*.TMP` and
`$EB*.TMP` files in that directory before deleting anything. Depending on where
the save stopped, these may contain new contents, the original destination or
the previous backup. Exclusive creation skips existing payload temporaries,
including files from interrupted saves. Persistent metadata and automatic
restart recovery prompts are still release gates. Session recovery and retained
handle ownership are described in [SAVE-RECOVERY.md](SAVE-RECOVERY.md).

The parent `tests/test_dwed_qemu.py` checks ordinary saves, disk-full failures,
read-only documents and saving a backup document. Failure cases check the error
dialog, edited buffer and dirty-state prompt as well as on-disk bytes. Previous
builds serve as negative controls for disk-full and backup-loss regressions.
Injected write, commit, close, rename and cleanup failures exercise the shared
writer; actual editor scenarios also cover close and rename errors. Read-only
media, interruption recovery, alternative storage backends and Microsoft 6.22
qualification remain open.

The shared writer now uses the document's [text representation](TEXT-FORMAT.md)
to preserve newline style and final-newline state. The loader preserves tabs
and rejects unsupported input explicitly. Clipboard export also uses this writer;
its validation and remaining qualification are described in
[CLIPBOARD.md](CLIPBOARD.md). Other system2 buffered writers need their own
error-path audit; the editor save fix does not establish their safety.
