# Recovery after restarting

Startup scans the current directory and the directories of command-line files
for recovery records. Absolute directory normalization avoids duplicate scans
through dot components or case differences. This is a scoped search, not a
whole-disk search; opening a document in another directory later does not scan
that directory automatically.

The Interrupted save screen displays the record, destination and candidate
copy. R opens the verified contents as a separate unsaved document. S or Enter
skips the record; Esc skips the remaining records. Long paths wrap, with Up/Down
scrolling. Invalid records and read failures show an error and allow retry or
skip. The screen uses keyboard controls; mouse interaction remains unqualified.

The reader requires an exact, valid record with consistent path relationships.
It selects the payload temporary, or the destination only when the temporary
is absent. It checks the candidate's size and CRC while parsing the actual
input bytes. Unsupported text or any read/close failure prevents adoption;
existing documents and files remain intact. CRC is an accidental-corruption
check, not authentication.

A recovered document retains the destination name and displays a Recovered
label. Its initial undo checkpoint is unsaved, so editing and undoing does not
make it appear saved. F2 explicitly saves through the ordinary checked writer.
Discarding the buffer leaves the recovery files intact. An already opened
original document remains a separate window.

A reader whose close fails remains owned by the editor context. Retry can close
it before discovery resumes. Returning to editing stops further discovery when
the handle is still open; Save, Exit and the other shared cleanup guards retain
that ownership. There is no leave-with-open-handle option.

## Qualification and remaining work

The parent interruption scenarios reboot first into the record-validation probe
and then into the editor, recover the saved contents, and exercise undo and an
explicit save. Synthetic fixtures exercise damaged and mis-sized records,
invalid paths, directory aliases, corrupt payloads, read-only file attributes,
preserved text bytes, interrupted reads, early EOF and persistent close errors.
Generated results and reproducibility evidence are in
`save-discovery-milestone.json`.

Read-only file attributes do not establish read-only media support. Tests use
the DOS memory backend on emulated hardware; low-memory, alternate stores and
broader platform qualification remain open. Interruption occurs at completed
DOS-call boundaries, not during physical sector writes.

Recovery currently preserves the old record and retained file generations even
after an explicit save. A guided resolution and cleanup workflow remains a
release gate. The record does not fingerprint the old destination or previous
backup, so metadata alone cannot authorize deleting or replacing them.
