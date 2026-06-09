#!/usr/bin/env tarantool
--
-- sort_order benchmark (memtx)
-- Requires Tarantool with sort_order support in index parts.
-- Will exit with error on unpatched builds — that is expected.
--
-- Creates three spaces with differently-ordered secondary indexes on the
-- same (a, b, c) key and compares INSERT / SELECT_RANGE / UPDATE / REPLACE / DELETE TPS.
--
--   plain    : parts = {a asc, b asc, c asc}  (equivalent to no sort_order)
--   all_desc : parts = {a desc, b desc, c desc}
--   mixed    : parts = {a desc, b asc, c desc}
--
-- Usage:
--   tarantool bench_sort_order.lua [scale]
--     scale 1  →  60 K rows, 30 K bench ops
--     scale 10 → 600 K rows, 300 K bench ops
--

local SCALE      = tonumber(arg and arg[1]) or 1
local NUM_ROWS   = 60000 * SCALE
local BENCH_OPS  = 30000 * SCALE
local LOAD_BATCH = 1000

local clock      = require('clock')

-- 3 spaces coexist in memory simultaneously.
-- ~300 bytes per row × 3 spaces, capped at 10 GB.
local MEMTX_MEM = math.min(
    10 * 1024 * 1024 * 1024,
    math.max(512 * 1024 * 1024, 3 * NUM_ROWS * 300)
)

box.cfg {
    log          = 'bench_sort_order.log',
    log_level    = 'warn',
    memtx_memory = MEMTX_MEM,
}

-------------------------------------------------------------------------------
-- Helpers
-------------------------------------------------------------------------------

local PAD = string.rep('x', 60)
local function make_val(i)
    local prefix = tostring(i)
    return prefix .. PAD:sub(1, 60 - #prefix)
end

local function report(label, n, elapsed)
    local tps = n / math.max(elapsed, 1e-9)
    print(string.format('[BENCH] %-26s  ops=%-8d  elapsed=%7.3fs  TPS=%d',
        label, n, elapsed, math.floor(tps)))
    io.flush()
end

-------------------------------------------------------------------------------
-- Space factory
--
-- sec_parts: list of {field_no, type, sort_order = ...} tables forwarded
-- directly to create_index, so the caller controls sort_order per part.
-------------------------------------------------------------------------------

local function create_space(name, sec_parts)
    if box.space[name] then box.space[name]:drop() end
    local sp = box.schema.space.create(name, {
        engine = 'memtx',
        format = {
            { name = 'id',  type = 'unsigned' },
            { name = 'a',   type = 'unsigned' },
            { name = 'b',   type = 'unsigned' },
            { name = 'c',   type = 'unsigned' },
            { name = 'val', type = 'string' },
        },
    })
    sp:create_index('pk', { parts = { 'id' } })
    sp:create_index('sec', { parts = sec_parts, unique = false })
    return sp
end

-------------------------------------------------------------------------------
-- Build index definitions
--
-- 'plain' uses no sort_order key so it also works on unpatched builds —
-- useful as a baseline when you deliberately run only that variant.
-------------------------------------------------------------------------------

local variants = {
    {
        name  = 'plain',
        parts = {
            { 'a', 'unsigned' },
            { 'b', 'unsigned' },
            { 'c', 'unsigned' },
        },
    },
    {
        name  = 'all_desc',
        parts = {
            { 'a', 'unsigned', sort_order = 'desc' },
            { 'b', 'unsigned', sort_order = 'desc' },
            { 'c', 'unsigned', sort_order = 'desc' },
        },
    },
    {
        name  = 'mixed',
        parts = {
            { 'a', 'unsigned', sort_order = 'desc' },
            { 'b', 'unsigned', sort_order = 'asc' },
            { 'c', 'unsigned', sort_order = 'desc' },
        },
    },
}

-- Create spaces and detect patching support early.
local spaces = {}
for _, v in ipairs(variants) do
    local ok, result = pcall(create_space, 'so_' .. v.name, v.parts)
    if not ok then
        io.write(string.format(
            'ERROR: failed to create index for variant "%s": %s\n',
            v.name, tostring(result)))
        io.write('This benchmark requires Tarantool with sort_order support.\n')
        io.flush()
        os.exit(1)
    end
    spaces[v.name] = result
end

-------------------------------------------------------------------------------
-- Per-variant benchmark runner
-------------------------------------------------------------------------------

local function run_variant(name, sp)
    local tag = string.format('%-10s', name)

    -- Load
    local batch = 0
    box.begin()
    for i = 1, NUM_ROWS do
        sp:replace({ i, i % 500, i % 200, i % 100, make_val(i) })
        batch = batch + 1
        if batch >= LOAD_BATCH then
            box.commit()
            box.begin()
            batch = 0
        end
    end
    if batch > 0 then box.commit() else box.rollback() end

    -- INSERT (rows beyond NUM_ROWS)
    do
        local base = NUM_ROWS
        local elapsed = clock.bench(function()
            for i = 1, BENCH_OPS do
                local id = base + i
                sp:insert({ id, id % 500, id % 200, id % 100, make_val(id) })
            end
        end)[1]
        report(tag .. ' INSERT', BENCH_OPS, elapsed)
    end

    -- SELECT range on secondary (prefix on first key part)
    do
        local elapsed = clock.bench(function()
            for i = 1, BENCH_OPS do
                sp.index.sec:select({ i % 500 }, { limit = 10 })
            end
        end)[1]
        report(tag .. ' SELECT_RANGE', BENCH_OPS, elapsed)
    end

    -- SELECT range reverse (tests the opposite traversal direction)
    do
        local elapsed = clock.bench(function()
            for i = 1, BENCH_OPS do
                sp.index.sec:select({ i % 500 }, { limit = 10, iterator = 'LE' })
            end
        end)[1]
        report(tag .. ' SELECT_RANGE_REV', BENCH_OPS, elapsed)
    end

    -- UPDATE (increments field 'a' on rows cycling through the loaded dataset)
    do
        local elapsed = clock.bench(function()
            for i = 1, BENCH_OPS do
                sp:update(1 + (i % NUM_ROWS), { { '+', 'a', 1 } })
            end
        end)[1]
        report(tag .. ' UPDATE', BENCH_OPS, elapsed)
    end

    -- REPLACE (overwrites existing rows cycling through the loaded dataset)
    do
        local elapsed = clock.bench(function()
            for i = 1, BENCH_OPS do
                local id = 1 + (i % NUM_ROWS)
                sp:replace({ id, id % 500, id % 200, id % 100, make_val(id + 1) })
            end
        end)[1]
        report(tag .. ' REPLACE', BENCH_OPS, elapsed)
    end

    -- DELETE
    do
        local n = math.min(BENCH_OPS, NUM_ROWS)
        local elapsed = clock.bench(function()
            for i = 1, n do
                sp:delete(i)
            end
        end)[1]
        report(tag .. ' DELETE', n, elapsed)
    end
end

-------------------------------------------------------------------------------
-- Main
-------------------------------------------------------------------------------

print(string.format('sort_order benchmark — scale=%d  rows=%d  bench_ops=%d\n',
    SCALE, NUM_ROWS, BENCH_OPS))

for _, v in ipairs(variants) do
    io.write(string.format('--- variant: %s ---\n', v.name))
    io.flush()
    run_variant(v.name, spaces[v.name])
    print('')
end

print('[BENCH] DONE')
os.exit(0)
