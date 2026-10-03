-- Offline-only memory and input backend. Never loads the game's DLL or sends input.
local ffi = require('ffi')
local M = {}
local function file(path)
    local handle = assert(io.open(path, 'rb'))
    local value = handle:read('*a'); handle:close(); return value
end
local function word(n) return ffi.string(ffi.new('uint32_t[1]', n), 4) end
local function ptr(n) return ffi.string(ffi.new('uint64_t[1]', n), 8) end
local function unhex(s) return (s:gsub('%s', ''):gsub('..', function(p) return string.char(tonumber(p, 16)) end)) end
local function u32(s, offset)
    local n = ffi.new('uint32_t[1]'); ffi.copy(n, s:sub(offset + 1, offset + 4), 4)
    return tonumber(n[0])
end
ffi.cdef('int QueryPerformanceCounter(int64_t *); int QueryPerformanceFrequency(int64_t *);')
local kernel = ffi.load('kernel32')
local frequency, counter = ffi.new('int64_t[1]'), ffi.new('int64_t[1]')
assert(kernel.QueryPerformanceFrequency(frequency) ~= 0)
local divisor = tonumber(frequency[0])
function M.clock()
    assert(kernel.QueryPerformanceCounter(counter) ~= 0)
    return tonumber(counter[0]) / divisor
end

function M.new(kind, perf, source_path)
    assert(kind == 'magazine' or kind == 'rounds' or kind == 'heat')
    local source = file(source_path or 'build/auto_reload_entry_tactical_perf.lua')
    local pages, logs, events = {}, {}, {}
    local fixture = {time=0, precise_time=0, focused=true, keys={}, reads=0, bytes=0, clock_calls=0,
        original_calls=0, key_reads=0, release_calls=0}
    local function put(address, value)
        local offset = 0
        while offset < #value do
            local page_id = math.floor((address + offset) / 4096)
            local within = (address + offset) % 4096
            pages[page_id] = pages[page_id] or ffi.new('uint8_t[4096]')
            local count = math.min(4096 - within, #value - offset)
            ffi.copy(pages[page_id] + within, value:sub(offset + 1, offset + count), count)
            offset = offset + count
        end
    end
    local function read(address, size)
        fixture.reads, fixture.bytes = fixture.reads + 1, fixture.bytes + size
        if fixture.on_read then fixture.on_read(address, size) end
        if fixture.fault == 'nil' then return nil end
        if fixture.fault == 'short' then return '' end
        if fixture.fault == 'throw' then error('fixture_read_error') end
        local chunks, offset = {}, 0
        while offset < size do
            local page_id = math.floor((address + offset) / 4096)
            local within = (address + offset) % 4096
            local page = pages[page_id]
            if not page then return nil end
            local count = math.min(4096 - within, size - offset)
            chunks[#chunks + 1] = ffi.string(page + within, count)
            offset = offset + count
        end
        return table.concat(chunks)
    end
    local function pointer(value)
        if not value or #value < 8 then return nil end
        local n = ffi.new('uint64_t[1]'); ffi.copy(n, value, 8)
        n = tonumber(n[0]); if n >= 65536 and n < 0x800000000000 then return n end
    end
    local next_map = 0x9000000
    local function map(address, key, index)
        local base = next_map; next_map = next_map + 0x100
        put(address, ptr(base) .. word(8) .. word(0xffffffff) .. word(1))
        put(base, string.rep(word(0xffffffff) .. word(0xffffffff), 8))
        if key then put(base + (key % 8) * 8, word(key) .. word(index)) end
    end
    local function entity(resource, id, unit)
        return resource .. word(id) .. word(0) .. word(unit) .. '\1\0\0\0'
    end
    local component = kind:sub(1, 1):upper() .. kind:sub(2)
    local static_map = unhex(file('data/Weapon' .. component .. 'Component.25327279.map.hex'))
    local resource_id = kind == 'magazine' and '968211c0033dce64' or
        kind == 'rounds' and '41eac4a03987faa0' or nil
    local key, index
    for offset = 0, #static_map - 16, 16 do
        local candidate = static_map:sub(offset + 1, offset + 8)
        local id = candidate:reverse():gsub('.', function(c) return string.format('%02x', c:byte()) end)
        if (resource_id and id == resource_id) or
            (not resource_id and candidate ~= string.rep('\0', 8) and id ~= 'd54b9505c0f72873') then
            key, index = candidate, u32(static_map, offset + 8); break
        end
    end
    assert(key, 'fixture resource missing')
    local game, pm, owner, inv, driver, ammo = 0x100000, 0x200000, 0x4000000, 0x300000, 0x400000, 0x500000
    local manager_rva = kind == 'magazine' and 0x3326648 or kind == 'rounds' and 0x3326cf0 or 0x3326d48
    for rva, value in pairs({[0x3326468]=pm, [0x346bf98]=owner, [0x3326738]=inv,
        [0x3326660]=driver, [manager_rva]=ammo}) do put(game + rva, ptr(value)) end
    put(pm + 0x84, word(1) .. word(1)); put(pm + 0xe8, ptr(0x210000))
    put(0x210000, entity(string.rep('P', 8), 5, 123)); map(pm + 0xd0, 5, 0); put(pm + 0x3a8, word(123))
    map(owner + 0xf22ec8, 123, 1); map(owner + 0xf1aeb0, 42, 2)
    local avatar, weapon = entity(string.rep('A', 8), 7, 123), entity(key, 42, 456)
    put(owner + 0xf32f18 + 24, avatar); put(owner + 0xf32f18 + 48, weapon)
    map(inv + 0x28, 7, 0); put(inv + 0x14, word(1)); put(inv + 0x40, ptr(0x310000))
    put(0x310000, ptr(owner + 0xf32f18 + 24)); put(inv + 0x50, ptr(0x320000))
    put(0x320000, string.rep('\0', 48)); put(0x320000, word(42) .. word(42) .. word(42)); put(0x32001c, word(1))
    map(driver + 0x28, 42, 0); put(driver + 0x40, ptr(0x410000)); put(0x410000, ptr(owner + 0xf32f18 + 48))
    put(driver + 0x50, ptr(0x420000))
    put(0x420000, word(kind == 'magazine' and 0x80 or kind == 'rounds' and 0x100 or 0x200) .. string.rep('\0', 36))
    local magazine = kind == 'magazine'
    map(ammo + (magazine and 0x20 or 0x28), 42, 2)
    put(ammo + (magazine and 0x38 or 0x40), ptr(0x510000)); put(0x510010, ptr(owner + 0xf32f18 + 48))
    put(ammo + (magazine and 0x48 or 0x50), ptr(0x520000))
    put(ammo + (magazine and 0x50 or 0x58), ptr(0x530000))
    if not magazine then map(ammo + 0x68, nil, nil) end
    local spec = kind == 'magazine' and {slot=0xf124a0, stride=160} or
        kind == 'rounds' and {slot=0xf12820, stride=0x88} or {slot=0xf12cc8, stride=0x250}
    put(owner + spec.slot, ptr(0x600000)); put(0x600000, static_map)
    local config = 0x600000 + #static_map + index * spec.stride
    put(config, string.rep('\0', spec.stride))
    if kind == 'heat' then put(config + 0x50, '\1'); put(config + 0x90, '\1') end
    local state_address = 0x520000 + 2 * (magazine and 16 or 24)
    local runtime_address = 0x530000 + 2 * (kind == 'rounds' and 20 or 12)
    put(state_address, string.rep('\0', magazine and 16 or 24))
    put(runtime_address, string.rep('\0', kind == 'rounds' and 20 or 12))
    function fixture.ammo(count, token)
        if kind == 'heat' then
            put(runtime_address, word(2) .. word(0) .. string.char(count == 0 and 1 or 0) .. '\0\0\0')
        elseif magazine then
            put(state_address, word(count) .. word(0) .. word(token or 0) .. word(0))
        else
            put(state_address + 4, word(count)); put(state_address + 0x10, word(token or 0))
        end
    end
    fixture.ammo(20)
    -- Only the verified input build is supported by this fixture.
    local dos = 'MZ' .. string.rep('\0', 58) .. word(0x80)
    put(game, dos)
    put(game + 0x80, 'PE\0\0' .. word(0) .. word(0x6ab3b43f) .. string.rep('\0', 68) .. word(0x4744000))
    for rva, value in source:gmatch('{(0x%x+),%s*\'(%x+)\'') do put(game + tonumber(rva), unhex(value)) end
    put(game + 0x744d02, unhex('488b2d3f19be02'))
    put(game + 0x744d6c, unhex('488b4d38488bdf48c1e30448035d48488b0cf9e8bce9daff80b89c000000007420488b4550488d0c7f807c880800750a837b08000f85b600000032c0e9b1000000833b000f9fc0e9a6000000'))
    put(game + 0x764efa, unhex('4c8b15471ebc02'))
    put(game + 0x764f79, unhex('8bc8498b4258488d1449807c9008000f94c0'))
    local release_at, released_tick, state
    local api = {read=read, pointer=pointer, module=function() return game end,
        now=function() return fixture.time end, game_focused=function() return fixture.focused end,
        poll_now=function() return fixture.precise_time end,
        key_state=function(code) fixture.key_reads=fixture.key_reads + 1; return fixture.keys[code] and -32768 or 0 end,
        perf_now=function() fixture.clock_calls=fixture.clock_calls + 1; return M.clock() end,
        own_reload_active=function() return release_at ~= nil end}
    function api.release_reload(force)
        fixture.release_calls = fixture.release_calls + 1
        if release_at and (force or fixture.time >= release_at) then
            if fixture.fail_release then return false end
            events[#events + 1] = 'up:' .. state.ticks
            release_at, released_tick = nil, state.ticks
        end
        return true
    end
    function api.send_reload()
        if not fixture.focused then return false, 'game_not_focused' end
        if release_at then return false, 'key_release_pending' end
        if released_tick == state.ticks then return false, 'keyup_frame_pending' end
        if fixture.fail_send then return false, 'fixture_send_failed' end
        if fixture.keys[0x52] then
            released_tick = state.ticks; events[#events + 1] = 'stale_up:' .. state.ticks
            return false, 'stale_key_released_retry_next_frame'
        end
        events[#events + 1] = 'down:' .. state.ticks; release_at = fixture.time + 0.08
        return true, 'keydown_accepted_release_after_80ms_not_reload_confirmation'
    end
    local replaced
    source, replaced = source:gsub('local function read_api%(%).-\nlocal magazine_static_records, component_static_record',
        'local function read_api() return test_api end\n\nlocal magazine_static_records, component_static_record', 1)
    assert(replaced == 1)
    source, replaced = source:gsub('local PERF = %a+ %-%- PERF_BUILD_FLAG',
        'local PERF = ' .. tostring(perf) .. ' -- PERF_BUILD_FLAG', 1); assert(replaced == 1)
    source, replaced = source:gsub('\nreturn state%s*$',
        '\nstate.test_context = observed_context\nreturn state', 1); assert(replaced == 1)
    local environment = setmetatable({test_api=api, print=function(line) logs[#logs + 1] = line end,
        update=function(dt, ...)
            fixture.original_calls = fixture.original_calls + 1
            return 'original_update', dt, ...
        end}, {__index=_G})
    environment._G = environment
    local chunk = assert(loadstring(source, '@offline_auto_reload'))
    setfenv(chunk, environment); state = chunk()
    assert(state.latest_row and state.latest_row.context_status == 'context_observed', table.concat(logs, '\n'))
    fixture.state, fixture.logs, fixture.events, fixture.api = state, logs, events, api
    fixture.put, fixture.word, fixture.map_address = put, word, 0x600000
    fixture.ptr, fixture.map = ptr, map
    fixture.state_address, fixture.runtime_address, fixture.config_address = state_address, runtime_address, config
    fixture.weapon_address, fixture.avatar_address = owner + 0xf32f18 + 48, owner + 0xf32f18 + 24
    function fixture.corrupt_map()
        put(0x600000 + #static_map - 1, string.char(require('bit').bxor(static_map:byte(#static_map), 1)))
    end
    function fixture.update(time)
        fixture.precise_time = time
        fixture.time = math.floor(time * 1000 + 0.5) / 1000
        return environment.update(0, 'fixture')
    end
    return fixture
end

function M.trajectory(fixture, time)
    local phase = time % 2
    fixture.ammo(phase < 0.5 and 20 or phase < 0.8 and 2 or phase < 0.9 and 1 or phase < 1 and 0 or 20)
    fixture.keys[0x01] = phase >= 0.4 and phase < 0.65 or phase >= 0.85 and phase < 0.95
    fixture.keys[0x52] = phase >= 1.4 and phase < 1.45
    fixture.focused = not (phase >= 1.6 and phase < 1.7)
    fixture.fail_send = phase >= 0.5 and phase < 0.55
    fixture.fail_release = phase >= 0.7 and phase < 0.75
    fixture.fault = phase >= 1.8 and phase < 1.82 and 'short' or nil
    fixture.put(0x32001c, fixture.word(phase >= 1.2 and phase < 1.3 and 2 or 1))
end
return M
