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

Tabs currently appear as a one-cell arrow while remaining literal TAB bytes in
storage. This keeps byte positions and selection consistent during this stage
of the port. Normal tab-stop display, tab-aware cursor/mouse positioning and
clipboard/insertion behavior still need implementation and qualification.
Automatic indentation and commands that intentionally change whitespace also
need their own behavioral coverage.

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
Shift navigation and mouse selection still need qualification during menu work.
