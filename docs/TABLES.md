# Table editing

On a row whose first and last non-whitespace bytes are single or double vertical
box borders, Tab moves to the next field and Shift+Tab to the previous field.
A field must contain at least one byte between its borders. Adjacent borders
are skipped. At a vertical border, Tab enters the field on its right and
Shift+Tab enters the field on its left.

Navigation wraps to the immediately adjacent table row when necessary. It
stops when that row has no editable field or is not a table. At the end of a
physical line, Shift+Tab can enter its last field without reading beyond the
line. Moving between fields does not change document bytes or dirty state.

The parent repository's table scenarios type at navigation destinations and
verify saved bytes, backup preservation, and undo/redo in LOW and HIGH modes.
See the generated `table-navigation-milestone.json` for qualification evidence.

Without a selection, Enter inserts a continuation row. Inside a field, the
text from the cursor to the right border moves to the start of the same field
in the new row. At a field's right border the new field is blank. Outside the
fields, Enter inserts a blank continuation and focuses its first editable field.
The inherited box-junction translation supplies continuation borders.

The original row keeps its length and trailing whitespace. Vacated text bytes
become spaces, while tabs remain tabs. New-row indentation, trailing whitespace,
and tabs in other fields retain their bytes. Padding after the moved text
restores the original right border's visual column. For a field containing tabs,
padding may use tabs; otherwise it uses spaces. A complete byte-length check
precedes mutation, so an unrepresentable result is refused without truncation.

Row replacement and insertion share one DOS undo transaction. Allocation or
undo-capacity refusal rolls the command back, including a row replacement
already performed. The parent tests verify saved bytes and backup preservation;
the tab probe forces both early allocation refusal and refusal after the old
row changed, then verifies rollback, retry and undo. See the generated
`table-row-milestone.json` for evidence and the qualified runtime scope.

With an active selection, Enter follows ordinary selection replacement and
line splitting. Tab and Shift+Tab use ordinary selection indentation instead
of table navigation. The default DOS backend is the qualified storage backend;
inherited alternative backends remain subject to the editor's release gates.
