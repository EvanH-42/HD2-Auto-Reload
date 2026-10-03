local fixture = dofile('tests/support/perf_fixture.lua')
local paths = {'build/auto_reload_entry_tactical_perf.lua',
    'build/auto_reload_entry_tactical_p1_perf.lua', 'build/auto_reload_entry_tactical_p2_perf.lua'}
local function new(kind, stage) return fixture.new(kind, true, paths[stage + 1]) end
local function same_row(a, b)
    assert(a and b)
    for key, value in pairs(a) do
        if key ~= 'memory_reads' and key ~= 'memory_bytes' then assert(value == b[key], 'row differs: ' .. key) end
    end
    for key in pairs(b) do assert(a[key] ~= nil, 'new row field: ' .. key) end
end
local function actions(s)
    local result = {}
    for _, line in ipairs(s.logs) do
        if line:find(' RELOAD_REQUEST ', 1, true) then result[#result + 1] = line end
    end
    return table.concat(result, '\n')
end
for _, kind in ipairs({'magazine', 'rounds', 'heat'}) do
    local s = new(kind, 1)
    assert(s.state.fast_context, 'initial cache missing')
    local initial_reads = s.state.latest_row.memory_reads
    for _, count in ipairs({20, 8, 3, 2, 1, 0, 20}) do
        s.ammo(count, count == 1 and 9 or 0)
        local ok_fast, fast = s.state.test_context('periodic')
        local ok_full, full = s.state.test_context('reload_refresh')
        assert(ok_fast and ok_full); same_row(fast, full)
        assert(fast.memory_reads < initial_reads, 'fast reader did not reduce reads')
    end
    local bucket = s.state.perf.categories.periodic
    assert(bucket.fast_readers == 7 and bucket.full_readers == 0 and bucket.cache_hits == 7)
    local full_bucket = s.state.perf.categories.reload_refresh
    assert(full_bucket.full_readers == 7 and full_bucket.fast_readers == 0)
    for _, fps in ipairs({60, 120, 144, 240, 360}) do
        local p0, p1 = new(kind, 0), new(kind, 1)
        for frame = 0, fps * 10 - 1 do
            local time = frame / fps
            fixture.trajectory(p0, time); fixture.trajectory(p1, time)
            p0.update(time); p1.update(time)
        end
        assert(actions(p0) == actions(p1), 'P1 changed reload actions')
        assert(table.concat(p0.events, ',') == table.concat(p1.events, ','), 'P1 changed input timing')
        assert(p1.reads < p0.reads, 'P1 did not reduce total reads')
        print('PASS P1 ' .. kind .. ' row/action parity ' .. fps .. ' FPS')
    end
    -- Uncached full refresh remains authoritative for both action paths.
    s.state.test_context('continuous_refresh')
    assert(s.state.perf.categories.continuous_refresh.full_readers == 1)
    assert(s.state.perf.categories.continuous_refresh.fast_readers == 0)
end

local mutations = {
    {'slot', function(s) s.put(0x32001c, s.word(2)) end},
    {'selected id', function(s) s.put(0x320000, s.word(0)) end},
    {'ownership', function(s) s.put(s.weapon_address + 20, '\0') end},
    {'avatar', function(s) s.put(s.avatar_address + 16, s.word(999)) end},
    {'global', function(s) s.put(0x100000 + 0x3326738, s.ptr(0x340000)) end},
    {'registry', function(s) s.put(0x510010, s.ptr(s.avatar_address)) end},
    {'map content', function(s) s.corrupt_map() end},
    {'config content', function(s) s.put(s.config_address + 0x90, '\0') end},
    {'config override', function(s) s.map(0x500068, 42, 0); s.put(0x5000a8, s.ptr(s.config_address)) end},
    {'driver path', function(s) s.put(0x420000, s.word(0x100)) end},
    {'nil', function(s) s.fault = 'nil' end},
    {'short', function(s) s.fault = 'short' end},
    {'throw', function(s) s.fault = 'throw' end},
}
for _, mutation in ipairs(mutations) do
    local s = new('heat', 1)
    mutation[2](s)
    local ok, row = s.state.test_context('periodic')
    local bucket = s.state.perf.categories.periodic
    assert(bucket.cache_invalidations == 1 and bucket.full_readers == 1, mutation[1])
    local full_ok, full = s.state.test_context('reload_refresh')
    assert(ok == full_ok, 'fallback status differs: ' .. mutation[1])
    if ok and row then same_row(row, full) else assert(not s.state.fast_context) end
    print('PASS cache invalidation ' .. mutation[1])
end
local changed = new('heat', 1)
local inventory_reads = 0
changed.on_read = function(address, size)
    if address <= 0x320000 and address + size >= 0x320030 then
        inventory_reads = inventory_reads + 1
        if inventory_reads == 2 then changed.put(0x32001c, changed.word(2)) end
    end
end
local ok, row = changed.state.test_context('periodic')
assert(ok and row.selected_slot == 2)
assert(changed.state.perf.categories.periodic.cache_invalidations == 1)
assert(changed.state.perf.categories.periodic.full_readers == 1)
print('PASS mid-read change discards fast result and rebuilds once')

for _, fps in ipairs({60, 120, 144, 240, 360}) do
    local s = new('magazine', 2)
    local initial_clock_calls = s.clock_calls
    for frame = 0, fps * 10 - 1 do s.update(frame / fps) end
    local samples = s.state.perf.categories.periodic.reader_attempts
    assert(math.abs(samples - math.min(fps, 120) * 10) <= 1, 'bad 120 Hz schedule ' .. fps .. ': ' .. samples)
    assert(s.state.ticks == fps * 10)
    assert(s.original_calls == s.state.ticks and s.release_calls == s.state.ticks)
    assert(s.key_reads == s.state.ticks * 4)
    local latest = s.state.latest_at
    if fps > 120 then
        s.update(10 - 0.001)
        assert(s.state.latest_at == latest, 'skipped sample marked stale row fresh')
    end
    assert(s.clock_calls >= initial_clock_calls)
    local before = s.state.snapshots
    s.update(15); assert(s.state.snapshots == before + 1, 'long frame caused burst polling')
    s.focused = false; s.update(15.001)
    local background = s.state.snapshots
    for frame = 1, 1000 do s.update(15.001 + frame / 1000) end
    assert(math.abs(s.state.snapshots - background - 20) <= 1, 'bad background rate')
    s.focused = true; before = s.state.snapshots; s.update(16.002)
    assert(s.state.snapshots == before + 1 and s.state.latest_at == s.state.elapsed)
    print('PASS P2 rates, freshness, long frame and focus ' .. fps .. ' FPS')
end
-- P2 at 60/120 FPS retains per-update actions on the common trajectory.
for _, kind in ipairs({'magazine', 'rounds', 'heat'}) do
    for _, fps in ipairs({60, 120}) do
        local p1, p2 = new(kind, 1), new(kind, 2)
        for frame = 0, fps * 10 - 1 do
            local time = frame / fps
            fixture.trajectory(p1, time); fixture.trajectory(p2, time)
            p1.update(time); p2.update(time)
        end
        -- Background polling is deadline based in P2, so compare request/input events only.
        assert(actions(p1) == actions(p2), 'P2 low FPS changed reload actions')
        assert(table.concat(p1.events, ',') == table.concat(p2.events, ','), 'P2 low FPS changed key timing')
    end
end
print('PASS P2 60/120 FPS action parity')
local function accepted(s)
    local result = {}
    for _, line in ipairs(s.logs) do
        if line:find(' RELOAD_REQUEST ', 1, true) and line:find(' sent=true ', 1, true) then
            result[#result + 1] = {time=tonumber(line:match('elapsed=([%d.]+)')), reason=line:match('reason=(%S+)')}
        end
    end
    return result
end
for _, kind in ipairs({'magazine', 'rounds', 'heat'}) do
    for _, fps in ipairs({144, 240, 360}) do
        local p1, p2 = new(kind, 1), new(kind, 2)
        for frame = 0, fps * 4 do
            local time = frame / fps
            fixture.trajectory(p1, time); fixture.trajectory(p2, time)
            p1.update(time); p2.update(time)
        end
        local before, after = accepted(p1), accepted(p2)
        assert(#before == #after, 'P2 changed accepted request count')
        for index, action in ipairs(before) do
            assert(action.reason == after[index].reason, 'P2 changed request priority')
            -- Timers retain their original millisecond clock; roundoff and one update
            -- quantize the extra <=1/120 second sampling delay.
            assert(math.abs(action.time - after[index].time) <= 1/120 + 1/fps + 0.001,
                'P2 extra request delay exceeds polling plus frame quantization')
        end
        assert(p2.reads < p1.reads, 'P2 did not lower total reads')
        print('PASS P2 accepted actions and bounded detection delay ' .. kind .. ' ' .. fps .. ' FPS')
    end
end
-- A full refresh crossing to the last round must choose the original last-round
-- branch, rather than send continuous_load now and another final request later.
local crossing = new('rounds', 2)
crossing.ammo(2); crossing.update(0)
crossing.update(0.101)
crossing.update(0.200) -- Release the key just before the 0.1-second retry boundary.
crossing.ammo(1); crossing.update(0.202)
assert(crossing.state.latest_row.rounds_magazine_count == 1)
local crossing_actions = accepted(crossing)
assert(crossing_actions[#crossing_actions].reason == 'tactical_last_round')
assert(select(1, crossing.update(0.203)) == 'original_update')
print('PASS P2 fresh-count priority and original callback return values')
