# Literal search and checked replacement

Find and Replace are separate Search menu commands. Ctrl-F finds text; Ctrl-R
or F7 opens replacement. Adding Shift to Ctrl-F or Ctrl-R requests case-sensitive
matching. Ctrl-K always finds the next match, even after a replacement command.
Matching proceeds forward from the cursor without wrapping. The insensitive
mode folds ASCII letters; other codepage bytes remain literal.

Find selects the matched bytes. Cancelling its input keeps an existing selection
and the previous search term. Spaces in either input are significant, and an
empty replacement deletes matches. Empty search input cancels the request;
Find Next with no prior term does nothing. Inputs must be single-line text.
An oversized selection prefill is clipped to the bounded search field before
editing, so the edited field is the term that will actually be searched.

Replacement highlights each candidate. Y replaces it, N skips to the next
candidate, A replaces the remaining matches, and Escape stops. Stopping retains
already accepted changes. Inserted replacement text is not searched again within
that command. The confirmation currently uses keyboard controls.

Before a replacement, EDIT checks the resulting physical-line length. All checks
the remaining matches before modifying them. Overlong replacements report an
error instead of letting a Pascal short-string insertion truncate the line.
In the conventional-memory backend, the complete replacement command is one
undo transaction: Undo restores its preimage, Redo restores the result, and
length or undo-capacity failure rolls back the entire command, including any
matches accepted earlier in that invocation. A replacement that changes no bytes
does not make a saved document dirty.

The parent scenarios drive menu and keyboard commands, copy found selections,
check case and literal spaces, and verify exact destination and backup bytes.
They exercise deletion, growing and self-containing replacement text, skipping,
stopping, no-op replacement, the physical-line boundary, and rollback after a
previously accepted match or exhausted undo capacity. The historical-build
negative control lacks overflow refusal. Build fingerprints, reproducibility
and runtime results are in [search-replace-milestone.json](search-replace-milestone.json).
Alternate backing stores and broader command/platform qualification remain
separate release gates.
