# Table editing

On a row whose first and last non-space bytes are single or double vertical
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

Row insertion remains under review: the inherited Enter handler trims trailing
whitespace and can alter tab alignment. Table selection handling and row
insertion must be qualified before distribution promotion.
