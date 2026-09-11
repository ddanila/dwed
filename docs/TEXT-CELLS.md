# Tab stops and document positions

`TEXTCELL.PAS` maps document byte boundaries to display cells and back. Document
cursor and selection positions remain byte offsets, so rendering never expands
stored tabs into spaces. Horizontal scrolling uses display cells. Rendering
builds only the visible slice, including a viewport beginning inside a tab;
an expanded line need not fit a Pascal short string.

Tab stops follow `tab_size` from the configuration. The loader and geometry
unit normalize unsupported values to the default defined in their source.
Other DOS characters retain their byte values and occupy a display cell.
The status column and BIOS cursor position use the same visual mapping.

Left and Right move across whole bytes, including a whole tab. Up and Down,
with or without selection, retain the intended visual column across shorter
lines. If that column falls inside a tab, the cursor stops before the tab;
the intended column remains available for subsequent vertical movement. Other
commands reset that remembered column. Page navigation retains the inherited
start-of-line behavior.

Selection highlighting uses the byte boundaries of each affected line and
colors the entire visible span of a selected tab. Multi-line selections also
highlight the selected newline through the remainder of the display row.
Mouse positions use the same conversion after horizontal scrolling. A click
inside a tab places the cursor before it, and the first drag movement both
starts and extends the selection.

## Editing

With no selection, Tab inserts a literal tab byte. In overwrite mode it
replaces the byte under the cursor, or inserts at the end of the line.
The checked clipboard replacement path enforces the physical-line limit;
rejection leaves the document and dirty state unchanged. In conventional
memory, Tab and its associated selection replacement are one undo command.
Backspace and Delete remove whole tab bytes without expanding adjacent tabs.

With a selection, Tab adds a tab-width space prefix to each selected line.
The complete range is checked against the physical-line limit before any line
changes. A selection ending at the start of a later line excludes that line.
Shift-Tab removes leading spaces and tabs through the first tab stop, either
from the selected lines or from the current line without a selection. Cursor
and selection byte boundaries move with the surviving text. Each whole
indent/unindent command is undoable in conventional memory.

Table commands retain their inherited whitespace policies and need separate
qualification. Automatic indentation is also separate from display geometry.

The mouse clipboard popup now dispatches through the same transaction boundary
as keyboard and menu commands. Real DOS driver interaction, popup cancellation and clipboard undo/redo are
covered by the scoped `DISPLAY-MOUSE.md` matrix.

## Evidence and remaining scope

`tests/TABTEST.PAS` compares geometry and clipped rendering against an expanded
array model across supported tab widths, including lines wider than a Pascal
string. It also exercises real editor movement, selected-tab attributes,
copying, Tab insertion, undo/redo, and direct mouse events with horizontal
scrolling. Direct event injection tests the editor's event handling; it does
not qualify a mouse driver.

The parent `tests/dwed_tab_scenarios.py` inspects VGA character and attribute
bytes and BIOS cursor positions during keyboard interaction. It compares
saved file and backup bytes after insertion, deletion, overwrite, undo/redo
and rejected insertion or block indentation at the line limit. Layout cases
cover nondefault and
invalid configuration values, multi-line selection and long visual lines.
`text-cells-milestone.json` records build and runtime evidence.

Monochrome and real-driver results are recorded in `DISPLAY-MOUSE.md`.
Alternate text geometries, additional drivers, legacy CPUs and constrained-memory
runs remain part of the broader `EDIT-PLAN.md` gates.
