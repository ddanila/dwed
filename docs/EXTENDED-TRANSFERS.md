# Extended-memory transfers

`ems_try_copy`, `xms_try_copy` and `exms_try_copy` return zero on success and a
nonzero status on failure. EMS returns the driver status byte. XMS returns the
driver error byte after a failed call, using a nonzero fallback if a driver
reports failure without an error byte. Dispatch without a memory manager also
returns a nonzero fallback. A driver may have partially modified a destination
before reporting failure; these APIs do not promise atomic transfer.

The legacy copy procedures remain source-compatible wrappers which discard the
status. EMS transfers now request a copy rather than an exchange, so copying to
extended memory does not replace the conventional source with old page contents.
Reading a page also preserves the extended source for subsequent reads.

The test shims exercise copy semantics, ordinary and SXMS descriptor fields,
wide page offsets, both directions, and driver failure returns. Separate probes
use the actual configured HIMEM and EMM386 drivers, verify patterned round trips
and source preservation, and require a transfer through a freed handle to fail.
The parent runner enables EMS explicitly for the real EMS cases. See
[transfer-status-milestone.json](transfer-status-milestone.json) for executable
identity, driver hashes, results and the old-implementation negative control.

## Cache ownership and writeback

`EXCACHE` writes replacements into a spare extended-memory page. Only a
successful transfer swaps that page into a live cache item. A failed or partial
replacement therefore preserves the previous record and its metadata. Updating
an existing record does not create a duplicate. Cache creation remains optional
and declines if its descriptor or extended-memory pages cannot be allocated.

`excache_Peek` distinguishes a miss from a transfer error and retains the item.
A failed read may modify its destination, so `SYSTEM2` reads into checked,
temporary conventional-memory storage and publishes the new file buffer only
after the operation succeeds. A failed dirty-cache read reports an error;
a failed clean-cache read can fall back to its authoritative disk copy.

The write cache is drained before it can evict dirty data. Flush peeks at each
cached item, checks the seek and full disk-write result, and removes that item
only after success. The working file buffer retains its contents and position.
Failed cache writes can fall back to checked disk writes while the original
buffer still owns the data. Failed page switches and boundary reads retain
that buffer and cursor for retry. Failed flush or DOS handle-close refusal retains the open file,
buffers, cache, and remaining dirty data instead of discarding them.

The cache probe injects partial XMS transfers against the real driver, short
DOS writes, failed seeks and closes, combined cache/disk failure, and scratch
allocation exhaustion. It verifies retry, complete saved bytes, and operation
beyond cache capacity. See [cache-safety-milestone.json](cache-safety-milestone.json)
for exact build identity, scope, and old-implementation controls.

## Remaining caller qualification

These guarantees apply to cache and buffered-file operations whose callers
check their results and retain the file object on failure. Higher-level caller
review remains necessary: `DWEDOVL.load_config` and `parse_temp` do not check
each buffered read result. Their error paths must be fixed and tested before
release. External-command checkpoints use the checked transaction described in
[SESSION-SAFETY.md](SESSION-SAFETY.md). Optional document stores also
need end-to-end qualification of their buffered-I/O failures. A successful
cache operation alone does not establish safe behavior for those callers.
