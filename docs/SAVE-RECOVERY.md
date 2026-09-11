# Recovery during an editor session

The editor context owns the shared writer's transaction record. Document and
clipboard saves use that record directly, so returning from a failed save or
closing its document cannot discard an open handle or the retained paths.
The writers reject a new save while the previous transaction is pending.
Stored paths are expanded before the transaction begins so a later directory
change cannot redirect cleanup. Construction checks lengths before concatenation
and propagates directory lookup errors; overlong paths are rejected before a
file is created rather than silently naming a truncated destination.

The recovery screen appears after the primary save error, or directly after a
successful publication whose backup cleanup failed. It shows the destination,
retained temporary and backup paths, secondary DOS errors and whether the
payload or recovery-record handle remains open. Paths wrap and the screen
scrolls with Up/Down. The screen repaints the live editor on return, including its cursor; it does not
allocate a saved-screen copy.

- **R Retry cleanup** retries the owned close and remaining rollback or cleanup.
  For an unpublished save it restores the old files and removes the temporary
  after successful rollback. It does not mark the unsaved document as saved.
  For a published save it removes the parked previous backup and completed
  recovery record.
- **Enter/Esc Return** keeps the transaction pending and returns to editing.
  Save and Save Clipboard remain guarded until cleanup succeeds.
- **K Keep files and leave** is available when leaving the editor and both
  owned handles are closed. This explicitly leaves the displayed recovery
  files on disk. An open handle prevents that choice.

Exit, closing the last document and handing control to an external command
check the same transaction. Closing another document leaves the editor-owned
record intact. A successfully published document is marked saved even when
cleanup remains pending; a failed publication keeps its dirty state.

## Evidence and limits

The SAVETEST probe exercises both document and clipboard writers with a close
that keeps failing after the writer returns. It checks that subsequent writers
cannot overwrite the pending record, then settles and retries the operations.
It also retries failed rollback and cleanup using actual DOS file contents,
checks path overflow rejection and changes directory during a save to verify
that ownership remains attached to the original destination.

The parent's `dwed_save_lifecycle_scenarios.py` exercises persistent close,
rollback and post-publication cleanup failures in the actual editor. The
resident injector records save creation and failure counts; Caps Lock releases
its persistent fault for retry testing. Scenarios cover other documents,
Save, Exit, closing the last document, cancelling an external command, explicit
retention of recoverable generations, and monochrome recovery display. The
preceding editor fails the recovery-screen negative control. Results and
reproducibility evidence are in `save-lifecycle-milestone.json`.

The writer now leaves a [persistent recovery record](SAVE-JOURNAL.md), with
DOS-call boundary interruption tests. Editor recovery is still in-process:
keeping files and leaving currently requires manual inspection of the displayed
paths. Startup discovery, verified recovery into an editor document, read-only
media, low memory and broader platform qualification remain release gates.
The recovery screen currently uses keyboard controls; mouse interaction remains unqualified.
