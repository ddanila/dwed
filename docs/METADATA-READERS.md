# Configuration and resume metadata

`DOSLINES` reads metadata through the checked DOS reader into bounded, owned
line records. It consumes short reads, checks the total against the opened file
size, and rejects early EOF, growth, control bytes, and overlong physical lines.
CRLF, LF, and CR separators are accepted, including a separator split across
read buffers and a final line without a newline.

Every staging allocation checks available memory. An error frees the staged
records; a failed handle close remains owned by `TEditorContext.file_reader`
for the existing read-cleanup flow. No callback receives lines before the
complete input has been read and its handle closed successfully.

Configuration loading applies a complete file to a candidate configuration
before publishing it. A missing optional configuration is allowed. Other read
or close errors abort startup before document loading, with a diagnostic;
settings from a partial file are not applied. Existing parameter interpretation
and command-line overrides remain shared through `DWEDINIT`.

Resume loading validates all records and numeric ranges before opening any
listed document. Empty or malformed checkpoints are rejected. A missing target
is an error, not a request to create an empty document. Cursor positions are
normalized against the loaded document, including a row beyond its current end.
Only complete restoration followed by successful deletion consumes a checkpoint.
Read, validation, allocation, document-open, close, and deletion errors retain
it. Documents restored before a later document fails remain available in the
editor; restoration is not an atomic replacement of the document list.

The probe exercises DOS failures through the real routines, verifies exact
checkpoint bytes, checks cleanup and configuration state, and tests allocation
failure and record boundaries. Packaged launcher tests cover successful startup
and external-command resume. See [metadata-reader-milestone.json](metadata-reader-milestone.json)
for executable identity and results. Optional document stores and final memory
and runtime qualification remain separate release gates.
