# Save replacement protocol

The shared string-store save entry point writes through `SRC/SAFESAVE.PAS`.
It obtains an exclusive DOS create-new file in the destination directory,
checks each unbuffered write (including a successful short write), commits DOS
buffers and checks close before changing the destination. Existing read-only
files are rejected. All storage backends use this writer through `strs.to_file`.

After the new file is complete, the old destination moves to its `.BAK` name
and the temporary file moves to the destination. Saving a `.BAK` document uses
`.BK!` for its backup. An installation rename error triggers a rollback; if
rollback also fails, both recoverable files are retained. An existing backup
is replaced only after the complete new file has closed successfully.

DOS does not provide a single atomic replacement operation. After an interrupted
replacement, inspect the destination, its backup and the `$EDnnnn.TMP` files
in that directory before deleting anything. The backup holds the previous
destination and a surviving temporary file may hold the new contents. Exclusive
creation skips existing temporary files, including files from interrupted saves.
Automatic recovery prompts are still a release gate.

The parent `tests/test_dwed_qemu.py` checks ordinary saves, disk-full failures,
read-only documents and saving a backup document. Failure cases check the error
dialog, edited buffer and dirty-state prompt as well as on-disk bytes. A previous
build serves as a negative control for the disk-full regression. Runtime fault
injection for commit/close/rename and read-only media, interruption recovery,
alternative storage backends and Microsoft 6.22 qualification remain open.

This change preserves the existing line serialization. Tabs, long lines, line
endings and final-newline state still need the file-semantics work in
`EDIT-PLAN.md`. Clipboard export and other system2 buffered writers also need
their own error-path audit; the editor save fix does not establish their safety.
