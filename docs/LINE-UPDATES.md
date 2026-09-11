# Checked editor line replacement

`STRS.try_put` reports replacement failure before publishing a new line pointer.
The disk-backed SWAP and current SXMS stub append the replacement payload, then
publish its index through `dbb_TryPut`. Failed index writes retain the previous
index image and payload. A later replacement must first complete the retained
rollback; it cannot append another payload while rollback is refused.

Old payloads and unpublished replacements remain allocated until the temporary
store is discarded. This deliberately avoids unsafe free-list updates. Checked
reclamation or compaction is required before qualifying long editing sessions.
The retained index image is an in-memory runtime safeguard, not crash recovery.

`DWEDUTIL.try_commit` leaves the complete file context unchanged on ordinary
failure. Success updates current/root/scroll aliases after a DOS-store relocation
and publishes dirty flags. The DOS store checks growth allocation before changing
links; edits inside an active undo transaction retain its existing rollback
mechanism. Save, Save As, Save All, Close, Exit, New, Open, Windows, and Next
Window use the checked entry and report an error before proceeding when
replacement fails. Creating or selecting another document must wait until the
current edited line is committed. Save All stops on the failing document so the
user can retry it. External-command preflight also stops on commit refusal,
selects the failing document, and returns before writing session state or
releasing documents.

`STRS.try_done` discards the index before releasing payload ownership. Refused
index close retains the payload store; refused deletion retains its cleanup
owner. `dbm_Discard` closes temporary payload storage without seeking to or
writing its header, so dirty data can be abandoned when writes fail. These are
explicit discard operations and must not be used to persist databases.

The [qualification report](line-update-milestone.json) records build identities,
fault cases, and reference-DOS results. The probe compares the entire editor file
context after refusal, verifies target text and neighboring links, retries
replacement and cleanup, and exercises the real save/close/exit command dispatch
with injected payload write failure. The subsequent
[document-command report](document-commit-milestone.json) extends these checks
to document creation and switching, partial index writes with retained rollback,
a separate unchanged document, and conventional-memory allocation refusal.
Next Window is retried successfully after the failure to verify publication
before switching. The [handoff report](handoff-commit-milestone.json) adds
F5/F8/F9 event-handler refusal tests, including an unselected failing document,
and ordinary launch/resume and recursive-launch regression checks.
A BIOS keyboard hook acknowledges only the error dialog; filesystem failures use real DOS file handles with optional cache
allocation refused during fixture setup.

[Vertical keyboard movement](VERTICAL-MOVEMENT.md) and
[horizontal keyboard movement](HORIZONTAL-MOVEMENT.md) stage destination reads
before committing and crossing line boundaries. Remaining command callers still use legacy
`commit`/`put`, whose own updates
are unchecked. Multi-line mutation, free-list updates, navigation, loading,
rendering, undo for alternative stores, and application-level cleanup ownership
still need migration and qualification. This milestone does not qualify the
alternative stores or promote the distribution as EDIT.
