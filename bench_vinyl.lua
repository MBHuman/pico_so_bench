#!/usr/bin/env tarantool
--
-- Vinyl engine benchmark: INSERT, SELECT (point + range), UPDATE, REPLACE, DELETE
-- No sort_order used — runs on both master and patched builds.
-- Use to detect regressions introduced by the sort_order change.
--
-- box.snapshot() is called after the load phase so read benchmarks
-- always hit disk, not the in-memory write buffer.
--
-- Usage:
--   tarantool bench_vinyl.lua [scale]
--     scale 1  →  50 K rows, 20 K bench ops
--     scale 10 → 500 K rows, 200 K bench ops
--

local SCALE      = tonumber(arg and arg[1]) or 1
local NUM_ROWS   = 50000  * SCALE
local BENCH_OPS  = 20000  * SCALE
local LOAD_BATCH = 1000

-- vinyl_memory is the in-memory write buffer (L0).
-- It should be fixed regardless of scale: vinyl flushes to disk automatically.
-- Together with vinyl_cache this stays well within a 10 GB RAM budget.
-- Disk usage grows with NUM_ROWS; 50 GB disk supports roughly scale ~5000
-- with the current 80-byte value size (~100 bytes/row on disk after compaction).
local VINYL_MEM   = 2 * 1024 * 1024 * 1024  -- 2 GB write buffer
local VINYL_CACHE = 4 * 1024 * 1024 * 1024  -- 4 GB read cache

local clock = require('clock')

box.cfg {
    log              = 'bench_vinyl.log',
    log_level        = 'warn',
    vinyl_memory     = VINYL_MEM,
    vinyl_cache      = VINYL_CACHE,
    checkpoint_count = 1,
}

if box.space.bench_vinyl then box.space.bench_vinyl:drop() end
local s = box.schema.space.create('bench_vinyl', {
    engine = 'vinyl',
    format = {
        { name = 'id',  type = 'unsigned' },
        { name = 'a',   type = 'unsigned' },
        { name = 'b',   type = 'unsigned' },
        { name = 'val', type = 'string'   },
    },
})
s:create_index('pk',  { parts = { 'id' } })
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

local function vinyl_stats()
    local vs = box.stat.vinyl()
    local is = s.index.pk:stat()
    print(string.format('[VINYL] pk: ranges=%d runs=%d disk_bytes=%d',
        is.range_count, is.run_count, is.disk.bytes or 0))
    print(string.format('[VINYL] bloom: hit=%d miss=%d',
        is.disk.iterator.bloom.hit, is.disk.iterator.bloom.miss))
    print(string.format('[VINYL] scheduler: dump_count=%d tasks_completed=%d',
        vs.scheduler.dump_count, vs.scheduler.tasks_completed))
    io.flush()
end

-------------------------------------------------------------------------------
-- Load (not timed)
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
io.write(string.format('Load done: %d rows in %.1fs\n', NUM_ROWS, clock.monotonic() - t0))

-- Flush memtable to disk so reads go through the LSM layers.
io.write('Taking snapshot ...\n')
io.flush()
box.snapshot()
io.write('Snapshot done\n\n')
io.flush()

-------------------------------------------------------------------------------
-- INSERT  (rows beyond NUM_ROWS — no conflicts)
-------------------------------------------------------------------------------

do
    local base = NUM_ROWS
    local elapsed = clock.bench(function()
        for i = 1, BENCH_OPS do
            local id = base + i
            s:insert({ id, id % 1000, id % 500, make_val(id) })
        end
    end)[1]
    report('INSERT', BENCH_OPS, elapsed)
end

-------------------------------------------------------------------------------
-- SELECT point  (pk lookup)
-------------------------------------------------------------------------------

do
    local elapsed = clock.bench(function()
        for i = 1, BENCH_OPS do
            s:get(1 + (i % NUM_ROWS))
        end
    end)[1]
    report('SELECT_POINT', BENCH_OPS, elapsed)
end

-------------------------------------------------------------------------------
-- SELECT range  (secondary index prefix scan, limit 10)
-------------------------------------------------------------------------------

do
    local elapsed = clock.bench(function()
        for i = 1, BENCH_OPS do
            s.index.sec:select({ i % 1000 }, { limit = 10 })
        end
    end)[1]
    report('SELECT_RANGE', BENCH_OPS, elapsed)
end

-------------------------------------------------------------------------------
-- UPDATE  (increments field 'a' on rows cycling through the loaded dataset)
-------------------------------------------------------------------------------

do
    local elapsed = clock.bench(function()
        for i = 1, BENCH_OPS do
            s:update(1 + (i % NUM_ROWS), { { '+', 'a', 1 } })
        end
    end)[1]
    report('UPDATE', BENCH_OPS, elapsed)
end

-------------------------------------------------------------------------------
-- REPLACE  (overwrites existing rows cycling through the loaded dataset)
-------------------------------------------------------------------------------

do
    local elapsed = clock.bench(function()
        for i = 1, BENCH_OPS do
            local id = 1 + (i % NUM_ROWS)
            s:replace({ id, id % 1000, id % 500, make_val(id + 1) })
        end
    end)[1]
    report('REPLACE', BENCH_OPS, elapsed)
end

-------------------------------------------------------------------------------
-- DELETE
-------------------------------------------------------------------------------

do
    local n = math.min(BENCH_OPS, NUM_ROWS)
    local elapsed = clock.bench(function()
        for i = 1, n do
            s:delete(i)
        end
    end)[1]
    report('DELETE', n, elapsed)
end

print('')
vinyl_stats()
print('[BENCH] DONE')
os.exit(0)
