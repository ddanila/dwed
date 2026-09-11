# Checked addon insertion

Ctrl-Alt-A opens the ASCII table, Ctrl-Alt-C opens the integer calculator, and
F12 opens their chooser. The tools use the configured menu colours; the ASCII
selection and calculator radix marker remain distinct in monochrome mode.
These addon controls currently use the keyboard.

ASCII Enter inserts a text byte and Shift-Enter inserts its hexadecimal spelling.
Tab is accepted as a literal text byte. Other control bytes are refused because
they are not supported within an editable physical line. Their hexadecimal
spellings can still be inserted. The calculator inserts its value with
Shift-Enter, using the selected decimal, hexadecimal or binary radix.

Both tools use the shared checked replacement operation. Existing selection is
replaced; otherwise the value is inserted at the cursor. An overlong result is
refused before changing the document, rather than clipping the inserted value.
After validation failure the tool stays open for retry or Escape. Cancelling
keeps the document and selection. Successful insertion is a single undoable
command in the conventional-memory backend.

Calculator Backspace removes one digit in the selected radix. Arithmetic uses
fixed-width signed values, with hexadecimal and binary views of the same bits.
Division by zero reports an error while retaining the pending operation for
retry. The minimum signed value divided by negative one wraps consistently
with fixed-width arithmetic without entering a divide trap; its remainder is
zero.

Parent scenarios check raw bytes, hexadecimal spelling, literal tabs, unsupported
control refusal, line-boundary refusal and acceptance, selected replacement,
cancellation, reopening saved text, and undo/redo saved-state restoration. They
also exercise radix editing, signed values, arithmetic retry and edge cases,
and bitwise operations. Monochrome cases inspect the focus attributes as well
as document output. Build fingerprints and results are in
[addon-safety-milestone.json](addon-safety-milestone.json).

This evidence uses the conventional-memory backend and VGA text modes on private
DOS images. Other display geometries, pointer operation of addon controls and
alternate backing stores are outside this qualification. Table editing remains
a separate command gate.
