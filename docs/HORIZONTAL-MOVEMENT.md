# Checked horizontal movement

Left, Right, Shift-Left, and Shift-Right use checked horizontal movement.
Crossing a line boundary stages the destination through the checked vertical
movement primitive, including reciprocal links and any new selection anchor.
Only after committing succeeds does the action select the destination and place
the cursor at its end or beginning. Failed reads or commits preserve the edited
line and the file context. A document boundary without a neighboring line does
not reload old stored text into the edited buffer.

Moving within the buffered line changes its cursor and optional selection
anchor without replacing the backing payload. A new selection anchor uses a
checked line-number read. DOS-store actions retain the existing undo transaction
and final commit behavior; the alternative stores keep their dirty edit buffer.

Nonvertical events normally clear the desired visual column before dispatch.
When an action returns `SCRU_FAILED`, the event handler restores the previous
value if the original document is still selected, and skips selection reset and
viewport normalization. Successful horizontal movement still clears that value
so a later vertical move starts from its new column.

The [qualification report](horizontal-movement-milestone.json) records faults
through actual arrow-key events, both new and existing selections, conventional
memory refusal, preserved contexts, exact destination text on retry, and inline
movement without payload writes. Tab layout and undo checks cover integration
with the default DOS store. The expanded probe also reruns vertical movement
and the existing line-commit and document-command cases.

Page, word, mouse, search, and editing callers still need checked movement.
Legacy helpers remain for those callers. Subsequent viewport normalization and
rendering also need checked reads; the staged move is not qualification of those
later operations or of complete alternative-store editing.
