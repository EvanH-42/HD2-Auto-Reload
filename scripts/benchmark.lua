-- Run from repository root after building --enable-tactical-reload --perf.
-- QPC batch timing of synthetic memory/update work; no game input or process access.
local fixture = dofile('tests/support/perf_fixture.lua')
local seconds = tonumber(arg[1] or '10')
local repeats = tonumber(arg[2] or '3')
local stage = arg[3] or 'p0'
assert(stage == 'p0' or stage == 'p1' or stage == 'p2', 'stage must be p0, p1 or p2')
local source_path = stage == 'p0' and 'build/auto_reload_entry_tactical_perf.lua' or
    'build/auto_reload_entry_tactical_' .. stage .. '_perf.lua'
assert(seconds and seconds >= 2 and seconds <= 120 and repeats and repeats >= 1 and repeats <= 20 and repeats % 1 == 0,
    'usage: luajit scripts/benchmark.lua [seconds=10, 2..120] [repeats=3, 1..20]')
print('environment=offline_synthetic clock=QPC timing=batch_wall_seconds input=simulated stage=' .. stage)
print('kind,fps,perf,seconds,updates,periodic_samples,samples_per_second,reads,requested_bytes,read_failures,guard_rereads,map_bytes,reload_refresh,continuous_refresh,full_readers,fast_readers,cache_hits,cache_invalidations,median_batch_seconds')
for _, kind in ipairs({'magazine', 'rounds', 'heat'}) do
    for _, fps in ipairs({60, 120, 144, 240, 360}) do
        for _, perf in ipairs({false, true}) do
            local times, result = {}, nil
            for iteration = 1, repeats do
                local s = fixture.new(kind, perf, source_path)
                -- Warm up this instance; reset by creating a fresh fixture outside timing.
                for frame = 0, fps do fixture.trajectory(s, frame / fps); s.update(frame / fps) end
                s = fixture.new(kind, perf, source_path)
                collectgarbage('collect')
                local started = fixture.clock()
                for frame = 0, math.floor(fps * seconds) - 1 do
                    local time = frame / fps
                    fixture.trajectory(s, time); s.update(time)
                end
                times[#times + 1] = fixture.clock() - started
                result = s
            end
            table.sort(times)
            local p = result.state.perf
            local function sum(field)
                if not p then return '' end
                local n = 0; for _, bucket in pairs(p.categories) do n = n + bucket[field] end
                return tostring(n)
            end
            local samples = result.state.snapshots - 1 -- A failed cache plus full fallback is one sampling call.
            print(table.concat({kind, fps, tostring(perf), seconds, result.state.ticks, samples,
                string.format('%.2f', samples / seconds), result.reads, result.bytes, sum('read_failures'),
                sum('guard_rereads'), sum('map_bytes'), p and p.categories.reload_refresh.reader_attempts or '',
                p and p.categories.continuous_refresh.reader_attempts or '',
                sum('full_readers'), sum('fast_readers'), sum('cache_hits'), sum('cache_invalidations'),
                string.format('%.6f', times[math.floor(#times / 2) + 1])}, ','))
        end
    end
end
