# Runtime menu data under memory pressure

The open-files menu checks its complete text-buffer size before allocating it.
The Pascal source tree checks each temporary node and releases the partial
chain if a later node cannot fit. Formatting the completed source tree into a
menu also checks the required buffer size and releases the owned chain on
failure. All refusals use the nonallocating screen notice and leave the current
document available.

Both menu-buffer size calculations use a wider accumulator and reject results
outside the signed indexing range used by the menu implementation before
converting to allocation or buffer offsets. This prevents allocation based on
a wrapped size. An oversized source tree is refused explicitly; source text
remains editable.

MEMTEST /LIST exhausts the heap while a dirty document remains open. It checks
window-list allocation refusal, failure to format an already-built source
list, cleanup of a partially built list, and rebuilding after memory is freed.
A synthetic source list also exceeds the original size counter's range. Exact
heap checks and document checks follow cleanup. Parent QEMU scenarios dismiss
the notices, then edit and save normally. Separate UI cases cancel the windows
list and use the source tree to navigate to and edit another procedure.

Build fingerprints and runtime results are in
[list-memory-milestone.json](list-memory-milestone.json). These checks extend
[screen snapshot qualification](SCREEN-MEMORY.md); startup clipboard,
highlighting and handler allocations, other backing stores, and minimum-machine
memory remain separate qualification work.
