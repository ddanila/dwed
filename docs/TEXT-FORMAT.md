# Text representation and current limits

The shared loader reads bytes with checked I/O and retains tab bytes and DOS
high-bit characters. Each document stores its newline style: CRLF, LF or CR.
A final newline is represented by a final empty line, so saving does not add
or remove it implicitly. An empty file remains empty; a new file starts with
DOS CRLF as its style. Enter and Backspace can add and remove a final newline.
Splitting a line no longer trims its existing whitespace.

The current short-string line editor accepts physical lines up to 255 bytes.
Longer lines, mixed newline styles and control bytes other than TAB/CR/LF are
rejected with an error before the document enters the editor. Partial input is
freed, and an existing current document stays current. Rejection is an explicit
limit, not permission to normalize or split the source. A missing filename
opens a new document with that name; other open/read errors remain errors.

Tabs display at configured tab stops while remaining literal bytes in storage.
Cursor movement, selection highlighting and horizontal scrolling share the
byte-to-cell mapping described in `TEXT-CELLS.md`. Clipboard byte preservation
and rejection behavior are described in `CLIPBOARD.md`. Automatic indentation
and commands that intentionally change whitespace still need their own
behavioral coverage.

The parent QEMU gate checks exact bytes after editing and saving each supported
newline style, absent final newlines, tabs and high-bit characters; it checks
the line-length boundary, empty/new documents, whitespace-preserving splits
and removal of the final newline. Rejected-input cases verify that subsequent
editing and saving cannot replace the rejected source file.

The shared loader and saver cover every storage backend through `strs`, but
the alternate backing stores still need runtime qualification. Raw metadata
does not establish undo correctness or clipboard fidelity. The event decoder
now recovers modifiers encoded in BIOS key words, fixing queued Ctrl-End and
Ctrl-S after key release. BIOS entries do not encode every modifier combination;
Delayed modifier queues and additional mouse drivers still need qualification;
held Shift navigation and direct mouse-event mapping are covered in
`TEXT-CELLS.md`.

Real-driver and monochrome qualification is scoped in `DISPLAY-MOUSE.md`.

The shared loader uses an editor-owned read handle and checks the byte count
against the size observed on open. Positive short reads continue; premature EOF
and read errors reject the partial document. A failed close retains its handle
for [cleanup retry](SAVE-RECOVERY.md). Recovery additionally checks the size and
CRC of the exact bytes passed through the parser before adopting the document.
These checks detect size changes and accidental recovery-copy corruption;
ordinary loads do not promise a snapshot against concurrent same-size writes.

DOS-store loading now rejects exhausted document memory without retaining a
partial document. See [allocation behavior and limits](LOAD-MEMORY.md).
