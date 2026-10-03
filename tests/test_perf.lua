local fixture = dofile('tests/support/perf_fixture.lua')
local function gameplay_logs(s)
    local lines = {}
    for _, line in ipairs(s.logs) do
        if not line:find(' PERF ', 1, true) and not line:find(' START ', 1, true) then
            lines[#lines + 1] = line
        end
    end
    return table.concat(lines, '\n')
end
local function total(s, field)
    local value = 0
    for _, bucket in pairs(s.state.perf.categories) do value = value + bucket[field] end
    return value
end
for _, kind in ipairs({'magazine', 'rounds', 'heat'}) do
    for _, fps in ipairs({60, 120, 144, 240, 360}) do
        local off, on = fixture.new(kind, false), fixture.new(kind, true)
        for frame = 0, fps * 10 do
            local time = frame / fps
            fixture.trajectory(off, time); fixture.trajectory(on, time)
            off.update(time); on.update(time)
        end
        assert(not off.state.perf and off.clock_calls == 0, 'disabled statistics performed timing')
        assert(total(on, 'read_attempts') == on.reads and total(on, 'requested_bytes') == on.bytes)
        assert(total(on, 'read_failures') > 0 and total(on, 'guard_rereads') > 0 and total(on, 'map_checks') > 0)
        assert(total(on, 'read_successes') + total(on, 'read_failures') == on.reads)
        assert(on.state.perf.categories.initialization.reader_attempts == 1)
        assert(on.state.perf.categories.periodic.reader_attempts > 0)
        local refresh = kind == 'rounds' and 'continuous_refresh' or 'reload_refresh'
        assert(on.state.perf.categories[refresh].reader_attempts > 0, 'missing refresh category ' .. kind)
        assert(gameplay_logs(off) == gameplay_logs(on), 'statistics changed gameplay logs')
        assert(table.concat(off.events, ',') == table.concat(on.events, ','), 'statistics changed input timing')
        local reports = 0
        for _, line in ipairs(on.logs) do if line:find(' PERF ', 1, true) then reports = reports + 1 end end
        assert(reports == 5, 'unexpected summary frequency')
        print('PASS perf parity ' .. kind .. ' ' .. fps .. ' FPS')
    end
end
local s = fixture.new('heat', true)
for _, fault in ipairs({'nil', 'short', 'throw'}) do
    s.fault = fault
    local bucket = s.state.perf.categories.reload_refresh
    local before = bucket.reader_failures
    local ok = s.state.test_context('reload_refresh')
    assert(not ok and bucket.reader_failures == before + 1 and s.state.perf.active == 'other')
end
s.fault = nil
local seen = 0
s.on_read = function(address, size)
    if address == 0x320000 and size == 48 then
        seen = seen + 1
        if seen == 2 then s.put(0x32001c, s.word(2)) end
    end
end
local ok, row, reason = s.state.test_context('periodic')
assert(ok and not row and reason == 'context_changed_during_read')
assert(s.state.perf.categories.periodic.reader_failures == 1)
s.on_read = nil
s.corrupt_map()
ok, row = s.state.test_context('periodic')
assert(ok and row and not row.heat_verified)
assert(s.state.perf.categories.periodic.map_checks >= 2)
print('PASS failed/short/thrown reads, guard rejection and map mismatch counters')
local waiting = fixture.new('rounds', true)
waiting.put(0x200084, waiting.word(0) .. waiting.word(0))
ok, row = waiting.state.test_context('periodic')
assert(ok and row.context_status == 'waiting_for_local_player')
assert(waiting.state.perf.categories.periodic.reader_successes == 1)
assert(waiting.state.perf.categories.periodic.observed_contexts == 0)
local reporting = fixture.new('heat', true)
reporting.update(0); reporting.update(35); reporting.update(35.1); reporting.update(45)
local reports = 0
for _, line in ipairs(reporting.logs) do if line:find(' PERF ', 1, true) then reports = reports + 1 end end
assert(reports == 10, 'long update gaps should not catch up old summaries')
print('PASS waiting context classification and no summary catch-up after long frames')
