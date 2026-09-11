# Clipboard behavior and qualification

Copy serializes the whole selection with CRLF separators and retains literal
tabs and codepage bytes. It validates the complete selection against the
capacity defined by `CB_SIZE` before publishing anything. Cut also checks that
joining the surviving line fragments fits the editor's physical-line limit.
A rejected selection leaves the old internal clipboard and document intact. Clipboard
contents are independent of document undo history: a later edit-transaction
failure can leave the successfully copied selection in the clipboard while
restoring the document.

Paste validates every input byte and the resulting physical lines before
removing a selection or changing text. It recognizes CRLF, lone CR and lone LF
as logical separators, including mixed separators in clipboard input. Saving
uses the receiving document's existing newline style. This is distinct from
opening a file, where mixed newline styles are rejected to prevent an implicit
conversion. Empty clipboard paste retains the selection. Replacement builds
the first and last lines from their surviving fragments; it does not first
join those fragments into an oversized intermediate line.

In conventional-memory mode, a paste or selection replacement is one undo
command. Failure to retain the complete edit group rolls back the document
through the transaction contract in `UNDO.md`. The shared replacement path
also serves alternate stores, whose failure behavior still needs runtime
qualification.

## Clipboard files

Load Clipboard opens the source read-only and checks its size, full read,
end of file and close before publishing the result. Oversized files, embedded
NULs and unsupported control bytes fail explicitly and retain the prior
internal clipboard. Empty files are valid. Import does not require individual
lines to fit the editor; Paste checks them in their destination context.
Concurrent same-size rewrites of the source are not detected by this check.

Save Clipboard uses the document saver in `SAFESAVE.PAS`, including checked
writes, temporary files and backup replacement. Disk-full failure preserves
the existing destination and backup. The broader injected close/rename failure
and interrupted-save recovery qualification remains part of `EDIT-PLAN.md`.

## Host clipboard boundary

The vendored `system2/WINCB.PAS` adapter bounds the reported transfer size and
requires a NUL within the transferred data. An exact-capacity transfer is
valid when terminated within that capacity; no terminator is written beyond
the buffer. Export passes the actual allocated payload length, including its
terminator, rather than rounding the read length upward. Every successfully
opened clipboard is closed, including failure after Clear.

The editor stages host reads and validates them before replacing its internal
clipboard. Host writes publish internally only after the host accepts them.
The host API's Clear followed by SetData cannot preserve the previous host
clipboard if SetData fails; the internal clipboard and source document remain
available. The adapter currently transfers raw bytes as CF_TEXT and does not
convert between Windows ANSI and DOS OEM codepages. Real Windows/DOSBox host
interoperability and encoding conversion remain unqualified.

Microsoft's [clipboard format specification](https://learn.microsoft.com/en-us/openspecs/windows_protocols/ms-dclb/53128a2c-84ad-464e-8a12-75c5da932237)
describes CF_TEXT termination and line separators. The DOS interrupt adapter
and its simulated service are separate from a real host implementation.

## Evidence

`tests/CLIPTEST.PAS` checks parser boundaries, a simulated host interrupt
service, guarded import buffers, read-only and empty imports, exact export
and backup bytes, and real replacement/undo/redo. The simulation checks both
transfer directions and failure cleanup; it is not evidence of interoperability
with a particular Windows or DOSBox release.

The parent `tests/dwed_clipboard_scenarios.py` drives actual editor commands
and compares disk bytes after mixed-separator paste and undo/redo, rejected
imports, oversized paste/cut/copy, long-line selection replacement and
clipboard export on a full disk. `clipboard-milestone.json` records the builds
and QEMU results. Tab-stop rendering, mouse selection and alternate-store
qualification remain in the broader editor plan.
