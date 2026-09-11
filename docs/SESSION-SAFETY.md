# External-command checkpoints

Before releasing the document list for an external command, the editor writes
its resume metadata through `SAFESAVE`. A write, short-write, commit, close,
recovery-record, or publication error leaves the editor session open. The
checkpoint transaction belongs to `TEditorContext`, separately from a pending
document save, so neither operation can overwrite the other's recovery owner.

The cleanup dialog includes the checkpoint's retained files and handles. It
allows retry or return to editing. Keeping recovery files while leaving is
available only when all document, checkpoint, and read handles are closed.
A pending checkpoint must be cleaned up before another checkpoint can start.

The writer preserves the existing CSV record format and reverse document-list
order expected by the loader. It validates every record before creating output
and refuses records which exceed the string limit or contain filename bytes
that would terminate or split a record. Traversal is iterative to avoid stack
growth proportional to the number of open documents.

The DOS probe invokes the real F5 event handler under injected DOS errors and
checks document links, active document, text, cursor, selection, exit state,
and previous checkpoint bytes. It exercises persistent close ownership,
cleanup dialog retry, and a simultaneous independent document transaction.
The test-only launcher stand-in prevents a legacy negative control from writing
into COMMAND's memory; it is not linked into the editor. Successful launch and
resume are covered separately through the actual packaged launcher.

See [session-safety-milestone.json](session-safety-milestone.json) for build
identity and qualification evidence. This does not complete resume-file or
configuration-reader error handling, alternative document-store qualification,
or final memory and runtime qualification. The extra persistent transaction
changes the editor's memory footprint; older memory-boundary reports do not
establish the minimum for this build.
