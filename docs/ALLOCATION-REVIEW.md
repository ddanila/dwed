# Allocation source review

The reviewed source snapshot is [allocation-inventory.json](allocation-inventory.json).
Regenerate it with `python3 tools/allocation_inventory.py --output FILE` and
compare it after source changes with
`python3 tools/allocation_inventory.py --check docs/allocation-inventory.json`.
The inventory follows local Pascal `uses` dependencies conservatively, including
inactive branches. It records explicit heap calls, source hashes and nearby
code. It does not prove control flow, inspect the compiler RTL, or replace
runtime exhaustion tests.

## Editor heap paths

`STARTMEM.startup_alloc` checks the largest available heap block and exits with
a resource-specific memory diagnostic on refusal. Its callers initialize the
screen, clipboard, syntax languages/keywords/menu, keyboard handlers, and
embedded help topics/text/menu before documents are opened. Help and syntax
resource sizes come from the built resources, not arbitrary loaded documents.
See [STARTUP-MEMORY.md](STARTUP-MEMORY.md).

`DWEDUTIL.new_file` and `load_file`, and `DWEDRCV.recover_record`, check the
header allocation and retained working reserve before allocating. Failed
candidates are freed without publishing a partial document. `STRS.from_file`
uses `STRSDOS.create_checked` for unpublished DOS lines; the shared loader frees
the partial chain on refusal. See [LOAD-MEMORY.md](LOAD-MEMORY.md).

The raw `STRSDOS.create` heap call requires caller context. Runtime DOS edits
enter `DWEDHNDL.run_action`, bind a journal with `DWEDUNDO.start_edit`, and use
`live_change` through `create`/`put`. `replay_allocate` and `UNREDO.allocate`
check both the largest block and the working reserve. Failure cancels the
transaction; rollback retains the removed nodes and does not allocate.
New/load use the checked constructor instead. The old `STRSDOS.from_file`
loader is not called by the shared editor loader.

Every recorded DOS editing action finishes by committing its editor line.
The excluded non-edit commands and direct mouse navigation therefore encounter
an already committed line. This invariant matters: the public raw constructor
is not a general allocation-safe API outside a transaction or checked caller.
See [UNDO.md](UNDO.md) and the table failure checks in
[table-row-milestone.json](table-row-milestone.json).

`SCR.try_push` checks the contiguous snapshot size; callers can retain the
session and use a nonallocating notice. The open-document menu, source-jump
list, and source-jump menu check their allocations. Partial source lists are
freed on refusal. Menu string sizes are accumulated in a wide integer and
bounded before allocation. See [SCREEN-MEMORY.md](SCREEN-MEMORY.md) and
[LIST-MEMORY.md](LIST-MEMORY.md).

Clipboard import, Windows clipboard copy and refresh check their temporary
buffers before allocation, validate content before publication, and free the
buffers after use. `SYSTEM2.ReWrite` and `ResetMode` check their buffered-file
allocation before opening a file; failure leaves the reader/writer closed.
`EXCACHE.excache_Create` checks its conventional-memory descriptor before
requesting optional extended memory. Refused optional cache creation returns
nil. These checks are present in the vendored code as well as editor sources.

## Exclusions and remaining work

`HELP.compile` and `HELP.from_file` contain unchecked legacy allocations but
have no editor callers. The editor initializes help with `from_memory`; the
host build uses `tools/build_help.py`. Other allocating vendor units outside
the editor's local unit closure are listed in the inventory. They are not
qualified by this review.

Assembly and external memory APIs require separate review. `LAUNCH.ASM` checks
carry after resizing the resident block and after allocating the external
command's private environment. The EMS/XMS allocation wrappers return a zero
handle on allocation failure, which the optional cache creator checks.

`EXMS.xms_malloc` initializes the page-to-KiB shift before selecting ordinary
XMS or SXMS allocation. The [allocation-size probe](xms-allocation-milestone.json)
checks the driver's observed request with deliberately varied incoming CL,
including wide SXMS sizes and failure returns. Its test-only multiplex shim
intercepts XMS discovery and chains all unrelated requests to the real handler.
This qualifies request construction, not an actual SXMS driver's memory manager.
Extended-memory transfer error propagation and alternative document stores
remain runtime review work.

The heap review does not establish minimum physical RAM, supported file size,
full-command operation at the startup boundary, or final legacy CPU coverage.
The measured startup/edit boundary for the current executable is recorded in
[current-memory-milestone.json](current-memory-milestone.json). Final runtime
qualification and distribution promotion remain open.
