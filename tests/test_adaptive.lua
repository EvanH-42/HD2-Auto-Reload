local fixture = dofile('tests/support/perf_fixture.lua')
local function new(kind, stage, options, perf)
    return fixture.new(kind, perf ~= false,
        'build/auto_reload_entry_tactical_p' .. stage .. '_perf.lua', options)
end
local function accepted(s)
    local result = {}
    for _, line in ipairs(s.logs) do
        if line:find(' RELOAD_REQUEST ', 1, true) and line:find(' sent=true ', 1, true) then
            result[#result + 1] = {time=tonumber(line:match('elapsed=([%d.]+)')), reason=line:match('reason=(%S+)')}
        end
    end
    return result
end
local function compare(a, b, fps)
    local before, after = accepted(a), accepted(b)
    if #before ~= #after then
        for _,pair in ipairs({{'P2',before},{'P3',after}}) do
            for _,action in ipairs(pair[2]) do print(pair[1],action.time,action.reason) end
        end
    end
    assert(#before == #after, 'accepted request count differs ' .. #before .. '/' .. #after)
    for index, value in ipairs(before) do
        assert(value.reason == after[index].reason, 'request priority differs')
        assert(math.abs(value.time - after[index].time) <= 1/120 + 1/fps + 0.001,
            'extra request delay exceeds sampling/frame quantization')
    end
end
for _, fps in ipairs({60,120,144,240,360}) do
    for _, kind in ipairs({'magazine','rounds','heat'}) do
        local p2, p3 = new(kind, 2), new(kind, 3)
        for frame = 0, fps * 10 - 1 do
            local time = frame / fps
            fixture.trajectory(p2, time); fixture.trajectory(p3, time)
            p2.update(time); p3.update(time)
        end
        compare(p2, p3, fps)
        assert(p3.key_reads == p3.state.ticks * 4 and p3.release_calls == p3.state.ticks and
            p3.original_calls == p3.state.ticks)
        local bucket = p3.state.perf.categories.periodic
        assert(bucket.poll_20_samples + bucket.poll_30_samples + bucket.poll_60_samples +
            bucket.poll_120_samples == p3.state.snapshots - 1, 'hidden sampling work')
        assert(bucket.poll_immediate_samples > 0)
        if kind == 'heat' then assert(bucket.poll_30_samples == 0 and bucket.poll_60_samples == 0) end
        local refresh = p3.state.perf.categories.reload_refresh
        assert(refresh.fast_readers == 0)
        assert(p3.state.perf.categories.continuous_refresh.fast_readers == 0)
        print('PASS P3 common trajectory, input/callbacks and full refresh ' .. kind .. ' ' .. fps .. ' FPS')
    end
    -- Stable idle: 30 Hz far from threshold; 60 Hz with rule-derived headroom.
    for _, case in ipairs({{20,30},{4,60},{3,120}}) do
        local s = new('magazine', 3, {initial_count=case[1]})
        for frame=0, fps * 2 - 1 do s.update(frame/fps) end
        assert(s.state.poll_hz == case[2], 'wrong idle tier')
        local start = s.state.snapshots
        for frame=fps*2, fps*4-1 do s.update(frame/fps) end
        assert(math.abs(s.state.snapshots-start - math.min(fps,case[2])*2) <= 1, 'wrong actual idle rate')
    end
    local p2, p3 = new('magazine',2), new('magazine',3)
    for frame=0,fps*4-1 do p2.update(frame/fps); p3.update(frame/fps) end
    assert(p3.reads < p2.reads and p3.state.snapshots < p2.state.snapshots)
    print('PASS P3 idle rates and fewer reads ' .. fps .. ' FPS')
end

-- Immediate promotion, short count==1 observation and held fire from a 30 Hz state.
local edge = new('magazine',3)
for frame=0,719 do edge.update(frame/360) end
assert(edge.state.poll_hz == 30)
local before = edge.state.snapshots
local phase_deadline=edge.state.high_poll_deadline
edge.keys[0x01] = true; edge.ammo(1); edge.update(1.999)
assert(edge.state.snapshots == before+1 and edge.state.latest_row.magazine_count == 1)
assert(edge.state.poll_hz == 120 and accepted(edge)[1].reason == 'tactical_immediate')
assert(edge.state.high_poll_deadline==phase_deadline,'edge moved the P2 high-frequency phase')
edge.ammo(0); edge.update(2.002)
local held = edge.state.snapshots
for frame=1,360 do edge.update(2.002+frame/360) end
assert(math.abs(edge.state.snapshots-held-120) <= 1)
print('PASS P3 edge reads immediately and held fire stays high')

-- Reload/refill is an observation, not permission to assume a reload animation.
local recovered = new('magazine',3)
recovered.ammo(0); recovered.update(0)
recovered.ammo(20); recovered.update(0.009)
assert(recovered.state.poll_hz == 120)
for frame=1,30 do recovered.update(0.009+frame/120) end
assert(recovered.state.poll_hz == 120, 'refill immediately inherited low rate')
for frame=31,130 do recovered.update(0.009+frame/120) end
assert(recovered.state.poll_hz == 30)
print('PASS P3 recovery waits for fresh idle stability')

local reset = new('magazine',3)
for frame=0,719 do reset.update(frame/360) end
reset.put(0x32001c,reset.word(2)); reset.update(2)
reset.update(2.003)
assert(reset.state.latest_row.selected_slot == 2 and reset.state.poll_hz == 120)
reset.fault='short'; reset.update(2.012)
assert(reset.state.latest_row == nil and reset.state.adaptive == nil)
reset.fault=nil; reset.update(2.021)
assert(reset.state.latest_row and reset.state.poll_hz==120)
reset.focused=false; reset.update(2.022)
assert(reset.state.poll_hz==20)
local samples=reset.state.snapshots; reset.update(4)
assert(reset.state.snapshots==samples+1,'long gap caused catch-up')
reset.focused=true; reset.update(4.001)
assert(reset.state.poll_hz==120 and reset.state.latest_at==reset.state.elapsed)
print('PASS P3 selection, failure, long frame and focus reset')

-- Keep unknown rules and attack-only weapons conservative, including zero limits
-- and total-ammo rules. Real component maps/reader/controller are used throughout.
local resources = {
    {'magazine','b6aff2195568767f'}, -- R-36 zero limit
    {'rounds','dcd1c835407ef7ba'}, -- SG-97 total
    {'rounds','006e44327bb953fe'}, -- GL-15 total
    {'rounds','a8cffb316f0b5c5f'}, -- AC-8 zero
    {'magazine','11c27d3babb38956'}, -- MG-43 attack-only
}
for _,case in ipairs(resources) do
        local p2,p3 = new(case[1],2,{resource_id=case[2]}),new(case[1],3,{resource_id=case[2]})
        for frame=0,2399 do
            local time=frame/240
            fixture.trajectory(p2,time); fixture.trajectory(p3,time)
            p2.update(time); p3.update(time)
        end
        compare(p2,p3,240)
        print('PASS P3 resource trajectory '..case[2])
end

local config_file=assert(io.open('src/reload_config.lua','rb'))
local config=config_file:read('*a'); config_file:close()
local map_file=assert(io.open('data/WeaponMagazineComponent.25327279.map.hex','rb'))
local map_hex=map_file:read('*a'):gsub('%s',''); map_file:close()
local unknown
for start=1,#map_hex,32 do
    local value=map_hex:sub(start,start+15)
    local bytes={}; for i=15,1,-2 do bytes[#bytes+1]=value:sub(i,i+1) end
    local id=table.concat(bytes)
    if id~='0000000000000000' and not config:find("['"..id.."']",1,true) then unknown=id; break end
end
assert(unknown,'missing unconfigured mapped resource')
local conservative=new('magazine',3,{resource_id=unknown})
for frame=0,959 do conservative.update(frame/240) end
assert(conservative.state.poll_hz==120 and conservative.state.adaptive==nil)
print('PASS P3 unknown tactical configuration stays high '..unknown)

for _,case in ipairs({{'006e44327bb953fe',2},{'dcd1c835407ef7ba',4}}) do
    local total=new('rounds',3,{resource_id=case[1],initial_count=case[2],initial_token=1})
    for frame=0,479 do total.update(frame/240) end
    assert(#accepted(total)==0 and total.state.poll_hz==60,'total basis ignored chamber token')
    total.ammo(case[2],0); total.keys[0x01]=true; total.update(2.001)
    total.update(2.005)
    assert(total.state.poll_hz==120 and total.state.adaptive.count==case[2])
end
print('PASS P3 total-ammo tiers include the chamber and promote on consumption')

-- No idle tier can suppress an attack-only empty retry or mark unsampled data fresh.
local attack=new('magazine',3,{resource_id='11c27d3babb38956'})
attack.ammo(0); attack.update(0)
assert(#accepted(attack)==0 and attack.state.poll_hz==120)
attack.keys[0x01]=true; attack.fail_send=true; attack.update(0.001)
attack.keys[0x01]=false; attack.update(0.002)
attack.fail_send=false; attack.keys[0x01]=true; attack.update(0.003)
assert(#accepted(attack)==1 and accepted(attack)[1].reason=='empty_attack')
local idle=new('magazine',3)
for frame=0,719 do idle.update(frame/360) end
local latest=idle.state.latest_at
idle.update(1.999)
assert(idle.state.latest_at==latest,'skipped idle sampling marked row fresh')
-- A stable weapon that suddenly consumes ammo without a matching edge must
-- abandon its idle tier at the next scheduled observation.
idle.ammo(4); idle.update(2.034); idle.update(2.037)
assert(idle.state.poll_hz==120,'ammo decrease retained the old idle deadline')
for frame=1,360 do idle.update(2.037+frame/360) end
assert(idle.state.poll_hz==120 and idle.state.adaptive.unexplained,
    'unexplained consumption incorrectly authorized idle sampling')
idle.fault='short'; idle.update(3.05)
assert(idle.state.adaptive==nil and idle.state.adaptive_hazard.unexplained)
idle.fault=nil; idle.update(3.062)
for frame=1,360 do idle.update(3.062+frame/360) end
assert(idle.state.adaptive.unexplained and idle.state.poll_hz==120,
    'failed read/rebuild erased the same-weapon consumption risk')
print('PASS P3 empty retry, row freshness and sudden ammo decrease')

local burst=new('magazine',3)
for frame=0,719 do burst.update(frame/360) end
burst.keys[0x01]=true; burst.ammo(10); burst.update(2.001)
assert(burst.state.poll_hz==120 and burst.state.adaptive.max_drop==10)
burst.keys[0x01]=false; burst.update(2.002)
for frame=1,360 do burst.update(2.002+frame/360) end
assert(burst.state.poll_hz==120,'multi-round burst lost its conservative margin')
before=burst.state.snapshots; burst.keys[0x01]=true; burst.ammo(0); burst.update(10)
assert(burst.state.snapshots==before+1 and accepted(burst)[1].reason=='tactical_immediate')
print('PASS P3 multi-round burst margin and long-frame edge')

for _,pattern in ipairs({'automatic','rapid_click','jitter'}) do
    local p2,p3=new('rounds',2),new('rounds',3)
    local time=0
    for frame=0,1199 do
        if frame>0 then time=time+(pattern=='jitter' and (frame%3==0 and 0.011 or 0.002) or 1/240) end
        local shooting=time>=1 and time<3
        local count=shooting and math.max(0,20-math.floor((time-1)*24)) or time<1 and 20 or 20
        local down=shooting and (pattern~='rapid_click' or math.floor((time-1)*20)%2==0)
        for _,s in ipairs({p2,p3}) do
            s.ammo(count); s.keys[0x01]=down
            s.fail_send=time>=1.5 and time<1.55
            s.fail_release=time>=1.8 and time<1.85
            s.update(time)
        end
    end
    compare(p2,p3,pattern=='jitter' and 90 or 240)
    print('PASS P3 '..pattern..' threshold crossing and failed send/release')
end

local manual=new('magazine',3)
for frame=0,719 do manual.update(frame/360) end
assert(manual.state.poll_hz==30)
manual.keys[0x52]=true
local sampled=manual.state.snapshots; manual.update(2.001)
assert(manual.state.poll_hz==120 and manual.state.snapshots==sampled+1)
manual.keys[0x52]=false; manual.update(2.002)
for frame=1,120 do manual.update(2.002+frame/360) end
assert(manual.state.poll_hz==120,'manual release lost stability delay')
-- A backward sampling clock discards the old deadline and observes only once.
sampled=manual.state.snapshots; manual.update(0.5)
assert(manual.state.poll_hz==120 and manual.state.snapshots==sampled+1)
print('PASS P3 manual R and backward clock reset')

-- Statistics do not alter sampling, request reasons, or input times.
local enabled,disabled = new('rounds',3),new('rounds',3,nil,false)
for frame=0,2399 do
    local time=frame/240
    fixture.trajectory(enabled,time); fixture.trajectory(disabled,time)
    enabled.update(time); disabled.update(time)
end
compare(enabled,disabled,240)
assert(table.concat(enabled.events,',')==table.concat(disabled.events,','))
assert(enabled.reads==disabled.reads and enabled.state.snapshots==disabled.state.snapshots)
assert(disabled.clock_calls==0)
print('PASS P3 perf on/off sampling and key timing parity')
