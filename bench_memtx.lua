#!/usr/bin/env tarantool
--
-- Memtx engine benchmark: INSERT, SELECT (point + range), DELETE
-- No sort_order used — runs on both master and patched builds.
-- Use to detect regressions introduced by the sort_order change.
--
-- Usage:
--   tarantool bench_memtx.lua [scale]
--     scale 1  →  100 K rows, 50 K bench ops  (~10 MB dataset)
--     scale 10 →    1 M rows, 500 K bench ops (~100 MB dataset)
--

local SCALE      = tonumber(arg and arg[1]) or 1
local NUM_ROWS   = 100000 * SCALE
local BENCH_OPS  = 50000 * SCALE
local LOAD_BATCH = 1000

local clock      = require('clock')

-- ~300 bytes per row (tuple body + pk node + sec node).
-- Capped at 10 GB so the process never exceeds the machine RAM budget.
local MEMTX_MEM = math.min(
    10 * 1024 * 1024 * 1024,
    math.max(512 * 1024 * 1024, NUM_ROWS * 300)
)

box.cfg {
    log          = 'bench_memtx.log',
    log_level    = 'warn',
    memtx_memory = MEMTX_MEM,
}

if box.space.bench_memtx then box.space.bench_memtx:drop() end
local s = box.schema.space.create('bench_memtx', {
    engine = 'memtx',
    format = {
        { name = 'id',  type = 'unsigned' },
        { name = 'a',   type = 'unsigned' },
        { name = 'b',   type = 'unsigned' },
        { name = 'val', type = 'string' },
    },
})
s:create_index('pk', { parts = { 'id' } })
s:create_index('sec', { parts = { 'a', 'b' }, unique = false })

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local PAD = string.rep('x', 80)
local function make_val(i)
    local prefix = tostring(i)
    return prefix .. PAD:sub(1, 80 - #prefix)
end

local function report(label, n, elapsed)
    local tps = n / math.max(elapsed, 1e-9)
    print(string.format('[BENCH] %-22s  ops=%-8d  elapsed=%7.3fs  TPS=%d',
        label, n, elapsed, math.floor(tps)))
    io.flush()
end

-------------------------------------------------------------------------------
-- Load (not timed — just fills the dataset)
-------------------------------------------------------------------------------

io.write(string.format('Loading %d rows ...\n', NUM_ROWS))
io.flush()
local t0 = clock.monotonic()
local batch = 0
box.begin()
for i = 1, NUM_ROWS do
    s:replace({ i, i % 1000, i % 500, make_val(i) })
    batch = batch + 1
    if batch >= LOAD_BATCH then
        box.commit()
        box.begin()
        batch = 0
    end
end
if batch > 0 then box.commit() else box.rollback() end
io.write(string.format('Load done: %d rows in %.1fs\n\n',
    NUM_ROWS, clock.monotonic() - t0))
io.flush()

-------------------------------------------------------------------------------
-- INSERT  (rows beyond NUM_ROWS — no conflicts)
-------------------------------------------------------------------------------

do
    local base = NUM_ROWS
    t0 = clock.monotonic()
    for i = 1, BENCH_OPS do
        local id = base + i
        s:replace({ id, id % 1000, id % 500, make_val(id) })
    end
    report('INSERT', BENCH_OPS, clock.monotonic() - t0)
end

-------------------------------------------------------------------------------
-- SELECT point  (pk lookup, sequential key sweep)
-------------------------------------------------------------------------------

do
    t0 = clock.monotonic()
    for i = 1, BENCH_OPS do
        s:get(1 + (i % NUM_ROWS))
    end
    report('SELECT_POINT', BENCH_OPS, clock.monotonic() - t0)
end

-------------------------------------------------------------------------------
-- SELECT range  (secondary index prefix scan, limit 10)
-------------------------------------------------------------------------------

do
    t0 = clock.monotonic()
    for i = 1, BENCH_OPS do
        s.index.sec:select({ i % 1000 }, { limit = 10 })
    end
    report('SELECT_RANGE', BENCH_OPS, clock.monotonic() - t0)
end

-------------------------------------------------------------------------------
-- DELETE  (removes the first BENCH_OPS rows from the loaded dataset)
-------------------------------------------------------------------------------

do
    local n = math.min(BENCH_OPS, NUM_ROWS)
    t0 = clock.monotonic()
    for i = 1, n do
        s:delete(i)
    end
    report('DELETE', n, clock.monotonic() - t0)
end

print('[BENCH] DONE')
os.exit(0)
