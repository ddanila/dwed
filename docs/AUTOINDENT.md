# Enter and automatic indentation

Outside table editing, Enter splits the current line at the byte cursor. It
copies the leading spaces and tabs that lie before the cursor onto the new
line, then places the cursor after that copied indentation. The suffix keeps
its original bytes; it is never trimmed. Tabs remain literal tabs.

At the start of a line, no indentation is copied. Inside the leading whitespace,
only the portion before the cursor is copied. This avoids copying indentation
from the suffix twice. On an all-whitespace line, Enter can create an indented
blank line. The document's newline convention remains unchanged.

Copied indentation cannot exceed the removed prefix, so the resulting suffix
fits whenever the original line fits. This includes the maximum-length line
and an end-of-line cursor. The split and added indentation form a single undo
action; undo restores the bytes, cursor and prior saved state, and redo restores
the split.

The TABTEST event-level probe checks every byte boundary of known space/tab
prefixes, ordinary text, high-bit characters, empty and all-whitespace lines,
and full-length lines. Parent QEMU cases split and save a mixed-indent line
whose suffix begins with spaces, verifying exact disk bytes in LOW and HIGH.
The prior editor loses those spaces and the copied tab in this regression.
Generated evidence is in `autoindent-milestone.json`.

Table-row insertion has separate behavior and is outside this qualification.
