local ffi = require('ffi')
if ffi.os ~= 'Windows' then
    print('SKIP Windows input API initialization')
    return
end
if arg[1] == 'existing-declaration' then
    ffi.cdef('uint32_t __stdcall SendInput(uint32_t, const uint8_t *, int);')
end
local source_file = assert(io.open('src/auto_reload.lua', 'rb'))
local source = source_file:read('*a')
source_file:close()
local code = assert(source:match('(local function read_api%(%).-)%\nlocal function context_reader'))
local factory = assert(loadstring(code .. '\nreturn read_api()'))
setfenv(factory, setmetatable({debug_emit=function() end, state={ticks=0,elapsed=0},
    bit=require('bit'), PERF=arg[1]=='perf', OPTIMIZATION_STAGE=arg[1]=='p3' and 3 or arg[1]=='p2' and 2 or 0}, {__index=_G}))
local api = factory()
assert(api.module('user32.dll'))
assert(not api.own_reload_active())
if arg[1] == 'perf' then
    local started = api.perf_now()
    assert(api.perf_now() >= started)
else
    assert(api.perf_now == nil)
end
if arg[1] == 'p2' or arg[1] == 'p3' then assert(api.poll_now() <= api.poll_now()) else assert(api.poll_now == nil) end
print('PASS Windows API initialization without input: ' .. (arg[1] or 'fresh-declarations'))
