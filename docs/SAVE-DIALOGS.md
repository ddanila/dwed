# Save and close behavior

Save, Save As, Save All, Close and Exit use one save operation with explicit
success, cancellation and failure outcomes. Close and Exit share the same
keyboard Save/Discard/Cancel prompt. Enter or Y saves, N discards, and C or Esc
cancels. Clean documents close without an unnecessary confirmation.

An unnamed document asks for a filename in every save path. Cancelling that
prompt or encountering a write error leaves its name and unsaved contents
intact and prevents Close/Exit. Save All stops at the first cancellation or
failure and keeps that document active; earlier successful saves remain saved.
After a successful save during Exit, exit proceeds without a second request.

Save As asks before replacing another existing filename. Replace proceeds;
Keep or Cancel preserves the destination and its backup and leaves the edited
document unchanged. The filename and dirty state update only after the shared
safe writer succeeds.

Startup without a filename, File/New and the fallback after a rejected load
use an unnamed document displayed as Untitled. Saving never silently chooses
an existing NONAME.TXT. Empty unnamed windows can also survive the external
command/session-resume path without trying to open an empty DOS pathname.

The parent dialog scenarios exercise save-on-exit, discard/cancel, cancelled
Save As, unnamed Close/Exit/Save All, stopping a batch on cancellation,
overwrite acceptance/refusal, disk-full retention and unnamed startup/resume.
They verify actual destination and backup bytes as well as editor state and
process completion. Mouse operation of the confirmation controls and injected
commit/close/rename failures remain part of release qualification.
