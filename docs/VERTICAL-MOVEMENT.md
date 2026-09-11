# Checked vertical movement

Up, Down, Shift-Up, and Shift-Down use a staged movement path. It reads the
current links and destination text through checked string-store APIs, verifies
the destination's reciprocal link, and obtains a checked line number when a new
selection anchor is needed. Null current lines and self-links are rejected.
The desired column and anchor remain local until committing the edited line
succeeds. A refused read or commit leaves the file context unchanged.

Successful movement publishes the destination pointer and text together, then
sets the visual column and scroll position. Movement at a document boundary
commits the edited line without replacing its buffer with stale stored text.
The existing undo transaction owns DOS-store commit allocation failures.

`SCRU_FAILED` is an internal action result, not a screen update level. The event
handler converts it to a full redraw before returning to the main loop, skipping
selection reset and viewport normalization. Failed undo transactions use the
same result after restoring their snapshot. A checked movement refusal cancels
its otherwise empty undo transaction before returning.

The [qualification report](vertical-movement-milestone.json) records injected
index/payload read failures, payload write refusal, partial index writes, and
DOS allocation refusal through actual keyboard events. Cases cover both plain
and shifted movement, new and existing selection anchors, retained desired
columns, unchanged contexts on failure, and successful retries. Existing tab
layout, undo, and reference-DOS tests cover the relevant integration paths.

This qualifies the four vertical keyboard actions at the checked read/commit
boundary. [Horizontal keyboard movement](HORIZONTAL-MOVEMENT.md) uses this staging path
when crossing lines. Page, word, mouse, search, and editing callers still use
legacy movement or commit helpers and require migration. Subsequent
viewport normalization and rendering still need checked storage access. The
local link check does not validate an entire document chain. This work does not
qualify alternative-store editing or promote the editor as a release.
