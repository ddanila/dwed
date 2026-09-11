# Embedded help

DWED.TXT is the byte-preserved CRLF help source. The open build compiles it into
both a standalone help file and the overlay's embedded help data. F1 and Help /
Contents open the same topic browser.

Up/Down selects a topic; Enter or Space opens it. Left/Right pages through the
current topic text, and Esc or Backspace returns to editing. Long physical
lines wrap within the text pane, preserving highlight state across wrapped
segments. Rendering checks the visible rows before writing text, and clips the
title and footer to the pane width. Help navigation does not change the document.

The help describes the maintained menus, save/cancel behavior, pending cleanup,
startup recovery, text limits, indentation, undo and memory-backend boundaries.
It includes the project's MIT license text. Runtime notices retain their
separate licensing terms. The old unsupported large-file claims and outdated
launcher name are no longer presented as supported behavior.

The parent help scenarios open About and Recovery, page through the complete
license and back, return to a dirty document and save it. LOW, HIGH/UMB and
monochrome modes are covered. Generated results and reproducibility evidence are
in `help-milestone.json`. Other affected memory, save and dialog checks run
against the same build. Help allocation under a fragmented or exhausted heap,
and further display sizes, still need qualification.
