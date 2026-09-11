# Memory exhaustion during document loading

The DOS backing store checks both the largest available heap block and the
remaining free heap before allocating a line for an unpublished load. It uses
the same working reserve as undo. Refusal returns DOS memory error semantics;
it does not install a partial document. The shared loader releases the partial
line chain and closes its owned reader, retaining ownership if close fails.

Document creation and ordinary file loading check the document-header allocation
before use. New returns an error without changing the document list when the
header or initial line cannot be allocated. The command handler reports that
error. Startup checks whether a document exists before entering the editor, and
error colors come from the editor configuration without requiring a document.
Recovery frees the fully parsed candidate if creating its destination document
fails. Existing documents stay available throughout.

`MEMTEST.PAS` exercises oversized ordinary loads and recovery attempts repeatedly
while a dirty original document is open. It compares the heap before and after
each failure, checks the working text and document pointers, fills memory with
real documents until New refuses, and retries New and Open after releasing
documents. Parent QEMU scenarios also open an oversized file at startup, dismiss
the memory error, and edit and save a new document while preserving the rejected
source. Generated evidence and the previous-build negative control are in
`load-memory-milestone.json`.

## Remaining qualification

This is exhaustion caused by document data in the DOS backing store. It does
not establish safe behavior for every allocation in the program. Initial
screen/clipboard setup, heavily fragmented heaps, menu and help allocations,
alternate backing stores, and minimum-machine-memory startup still require
qualification. Reserving total free heap alone does not guarantee a large
contiguous block for every later UI operation. There is no fixed maximum file
size: line overhead, open documents, undo history and available DOS memory all
affect capacity.
