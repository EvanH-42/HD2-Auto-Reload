-- Embedded fast reader. Retains every resolved dependency and both guard passes.
local function cache_context(row, dependencies)
    if not row or row.context_status ~= 'context_observed' or not dependencies or NATIVE_RELOAD then return nil end
    if not ((row.ammo_path == 'weapon_magazine' and row.magazine_verified) or
        (row.ammo_path == 'weapon_rounds' and type(row.rounds_chambered) == 'boolean') or
        (row.ammo_path == 'weapon_heat' and row.heat_verified)) then return nil end
    local template, sorted, guards = {}, {}, {}
    for key, value in pairs(row) do template[key] = value end
    for _, dependency in ipairs(dependencies) do
        sorted[#sorted + 1] = dependency
        if dependency.guard then guards[#guards + 1] = dependency end
    end
    table.sort(sorted, function(a, b) return a.address < b.address end)
    local function batches(entries)
        local result = {}
        for _, dependency in ipairs(entries) do
            local last = result[#result]
            local finish = dependency.address + #dependency.expected
            -- Small gaps only, same memory page. A failed merged read falls back safely.
            if not last or dependency.address > last.finish + 32 or finish - last.address > 4096 or
                math.floor(last.address / 4096) ~= math.floor((finish - 1) / 4096) then
                last = {address=dependency.address, finish=finish, entries={}}
                result[#result + 1] = last
            end
            last.finish = math.max(last.finish, finish)
            last.entries[#last.entries + 1] = dependency
        end
        return result
    end
    table.sort(guards, function(a, b) return a.address < b.address end)
    local first, second = batches(sorted), batches(guards)
    local total = 0
    for _, pass in ipairs({first, second}) do
        for _, batch in ipairs(pass) do total = total + batch.finish - batch.address end
    end
    if total > 32768 or #first + #second > 768 then return nil end
    return {row=template, first=first, second=second}
end

local function fast_context_reader(api, cache, metrics)
    local reads, bytes, values, guarded = 0, 0, {}, {}
    local row = {}
    for key, value in pairs(cache.row) do row[key] = value end
    local function read_batch(batch)
        local size = batch.finish - batch.address
        reads, bytes = reads + 1, bytes + size
        assert(reads <= 768 and bytes <= 32768, 'snapshot_budget')
        local result = assert(api.read(batch.address, size), 'read_unavailable')
        assert(#result == size, 'short_read')
        return result
    end
    local map_started = false
    for _, batch in ipairs(cache.first) do
        local result = read_batch(batch)
        for _, dependency in ipairs(batch.entries) do
            local offset = dependency.address - batch.address
            local value = result:sub(offset + 1, offset + #dependency.expected)
            if dependency.kind and dependency.kind ~= 'static_map' then
                values[dependency.kind] = value
            elseif value ~= dependency.expected then
                return nil, 'cached_dependency_changed'
            end
            if dependency.kind == 'static_map' and metrics then
                if not map_started then metrics.map_checks = metrics.map_checks + 1; map_started = true end
                metrics.map_reads = metrics.map_reads + 1
                metrics.map_bytes = metrics.map_bytes + #dependency.expected
            end
            if dependency.guard then guarded[dependency] = value end
        end
    end
    local inventory, driver = assert(values.inventory), assert(values.driver)
    local slot = u32(inventory, 0x1c)
    local offsets = {[1]=0, [2]=4, [3]=8, [4]=16, [5]=16, [6]=12}
    if slot ~= row.selected_slot or not offsets[slot] or
        u32(inventory, offsets[slot]) ~= row.selected_entity_id then return nil, 'cached_selection_changed' end
    local flags = u32(driver, 0)
    row.weapon_driver_flags = string.format('%08x', flags)
    local path = bit.band(flags, 0x80) ~= 0 and 'weapon_magazine' or
        bit.band(flags, 0x100) ~= 0 and 'weapon_rounds' or
        bit.band(flags, 0x400) ~= 0 and 'weapon_resource' or
        bit.band(flags, 0x200) ~= 0 and 'weapon_heat' or 'no_native_ammo_component'
    if path ~= row.ammo_path then return nil, 'cached_ammo_path_changed' end
    if path == 'weapon_magazine' then decode_magazine(row, assert(values.ammo), assert(values.runtime))
    elseif path == 'weapon_rounds' then decode_rounds(row, assert(values.ammo), assert(values.runtime))
    elseif path == 'weapon_heat' then decode_heat(row, assert(values.runtime))
    else return nil, 'cached_ammo_path_unsupported' end
    for _, batch in ipairs(cache.second) do
        local result = read_batch(batch)
        for _, dependency in ipairs(batch.entries) do
            if metrics then metrics.guard_rereads = metrics.guard_rereads + 1 end
            local offset = dependency.address - batch.address
            if result:sub(offset + 1, offset + #dependency.expected) ~= guarded[dependency] then
                return nil, 'context_changed_during_read'
            end
        end
    end
    row.memory_reads, row.memory_bytes = reads, bytes
    return row
end
