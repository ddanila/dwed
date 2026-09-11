# EDIT replacement implementation

The target is a reliable MIT-licensed DOS editor built on the existing DWED
Pascal implementation. Development belongs to ddanila/dwed:custom; main stays
available for upstream synchronization. Preserve original source bytes.

Completion gates:

1. Reproducible host-native build with open tools, pinned dependencies and
   regenerated help resources; no bundled EXE/OBJ is a build input.
2. Safe saves: detect short writes and flush/close/rename failures; retain the
   old destination and unsaved editor state on failure. Test disk full,
   read-only files/media and interrupted replacement recovery.
3. Predictable file semantics: preserve tabs, physical lines, codepage bytes
   and existing line endings/final-newline state; explicitly reject unsupported
   input instead of silently changing it. Implement undo/redo.
4. Classic File/Edit/Search/Options/Help menu interface sharing command actions
   with shortcuts; mouse and keyboard navigation, selection preservation,
   accessible monochrome colours, consistent save/discard/cancel dialogs.
5. Runtime qualification on DOS LOW/HIGH, low memory, legacy CPUs and supported
   codepages/displays. Measure memory use and enforce tested limits.
6. Parent msdos distribution ships the qualified result as EDIT, with help,
   licensing notices and regression coverage. QBASIC runtime/debugging is a
   separate project.

The build uses Free Pascal's i8086 MS-DOS cross compiler and retains the Pascal
editor. Its runtime license and linking exception must be shipped as required;
MIT applies to our and inherited MIT editor sources. NASM builds the launcher,
and Python regenerates help data without historical BIN2OBJ/HLPC executables.
The current text representation and remaining editing limits are described in
`TEXT-FORMAT.md`.

The previous bundled-binary assessment found successful ordinary edits in LOW
and HIGH/UMB, but silent empty output on a nearly full disk (also reproduced on
Microsoft 6.22), tab expansion, physical-line splitting and newline conversion.
The existing vmenu and event-handler code can support the menu work. The undo
unit currently contains scaffolding only. These findings are adoption gates,
not behaviours to preserve merely to make an initial port pass.

Record concrete progress and qualification in commits and machine-readable
reports. Do not advertise a release until all gates above have evidence.
