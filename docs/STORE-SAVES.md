# Checked string-store saves

The shared `STRS.to_file` writer traverses line links without renumbering lines or
changing index records. Before creating a save transaction it counts the
lines with checked metadata reads and verifies reciprocal previous links,
starting at the root. This also rejects cycles. During serialization it checks
the links again and requires the counted number of lines.

`STRSSWAP.try_read` and `STRSSXMS.try_read` validate the stored string length,
payload reference, link bounds, complete payload size, and Pascal string length
byte before publishing a line. Both destination text and returned links remain
unchanged on failure. `STRS.try_read` exposes that contract through the shared
store interface; the conventional-memory implementation uses its in-memory
records. Empty and null lines retain their existing empty-string semantics.

A metadata or payload read failure reaches the existing safe-save cleanup path.
It cannot publish the partially serialized file as the destination. A refused
cleanup close retains the save owner and blocks another save until cleanup is
settled. Existing editor save handling keeps the document dirty when the shared
writer reports failure. This does not make an unchecked edit or line replacement
safe before saving begins.

The `STRSAVE` DOS probe builds independent swap and current SXMS-stub documents,
then exercises index and payload errors, premature EOF, short reads, invalid
lengths and links, cycle refusal, and output cleanup failure. Faults after staged
output must preserve both the original destination and the older backup; native
retry must produce exact output bytes. Single-line failures retain destination
and link sentinels, with surrounding canaries checking buffer bounds.

The probe deliberately refuses optional XMS cache allocations so backing DOS
reads are observable in both boot modes. Corruption is injected into returned
read buffers, leaving the fixture files intact. Its interrupt adapter explicitly
reports unsupported LFN calls for the two qualification kernels. Cache-transfer
qualification is separate; see [EXTENDED-TRANSFERS.md](EXTENDED-TRANSFERS.md).
Build identities, runtime results, and the old implementation control are in
[store-save-milestone.json](store-save-milestone.json).

Shared loading, navigation, rendering, editing, record replacement, and cleanup
of alternative stores still require checked status propagation and transaction
integration. The current `STRSSXMS` implementation remains a disk-backed stub.
Keep the remaining gates in [ALTERNATIVE-STORES.md](ALTERNATIVE-STORES.md) open.
