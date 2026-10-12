-- Delta iOS dumper: rezhim ozhidaniya (hook mode)
-- Shag 1: zapusti ETOt script v Delta — on povisit loadstring-huk i budet zhdat
-- Shag 2: zapusti vtoroy script (loadstring tot samiy luraph) — dumper ego perehvatit i soldampit
-- Dump lyazhet v workspace/lurp-dump/

local function log(...) print("[dumper]", ...) end
log("huk stavlyu, zhdu loadstring...")

local dumpedStrings = {}
local seen = {}
local function noteString(s)
    if type(s) ~= "string" then return end
    if #s < 2 or #s > 20000 then return end
    if seen[s] then return end
    seen[s] = true
    dumpedStrings[#dumpedStrings + 1] = s
end

-- huki rasshifrovki (rabotayut poka zhdyom)
local orig_tostring = buffer.tostring
local orig_gsub = string.gsub
local orig_sub = string.sub
local orig_char = string.char
local orig_format = string.format

buffer.tostring = function(...)
    local r = orig_tostring(...)
    pcall(noteString, r)
    return r
end
string.gsub = function(s, pat, rep, ...)
    local r = orig_gsub(s, pat, rep, ...)
    if type(r) == "string" and r ~= s then pcall(noteString, r) end
    return r
end
string.sub = function(s, i, j, ...)
    local r = orig_sub(s, i, j, ...)
    if type(r) == "string" and #r >= 2 then pcall(noteString, r) end
    return r
end
string.char = function(...)
    local r = orig_char(...)
    pcall(noteString, r)
    return r
end
string.format = function(fmt, ...)
    local r = orig_format(fmt, ...)
    if type(r) == "string" and #r >= 2 then pcall(noteString, r) end
    return r
end

-- glavniy huk: perehvat loadstring
local orig_loadstring = loadstring or load
local orig_load = load
local dumped = false

local function saveDump(src, tag)
    if dumped then return end
    dumped = true
    log("PEREHVACHENO (" .. tag .. "), bayt: " .. #src)

    -- progonyaem VM chtob huki sobrali rasshifrovannie stroki
    local chunk, loadErr = orig_loadstring(src, "luraph_vm")
    if chunk then
        local runOk, runErr = pcall(chunk)
        log("VM otrabotal. runOk=" .. tostring(runOk) .. " err=" .. tostring(runErr))
    else
        log("VM ne vzyalsya: " .. tostring(loadErr) .. " — dampim siroy sors")
        pcall(noteString, src)
    end

    -- vozvrat originalov
    buffer.tostring = orig_tostring
    string.gsub = orig_gsub
    string.sub = orig_sub
    string.char = orig_char
    string.format = orig_format
    if loadstring then loadstring = orig_loadstring end
    if load then load = orig_load end

    -- sborka
    table.sort(dumpedStrings, function(a, b) return #a > #b end)
    local out = {}
    out[#out + 1] = "-- DUMP (" .. tag .. ") | strings: " .. #dumpedStrings
    out[#out + 1] = string.rep("=", 60)
    out[#out + 1] = "\n-- ===== RAW SRC (" .. #src .. " bayt) ====="
    out[#out + 1] = src
    out[#out + 1] = "\n" .. string.rep("=", 60)
    out[#out + 1] = "-- ===== STRINGS (" .. #dumpedStrings .. ") ====="
    for i, s in ipairs(dumpedStrings) do
        if s:find("[%a_]{2,}") then
            out[#out + 1] = "\n-- [" .. i .. "] len=" .. #s
            out[#out + 1] = s
        end
    end
    local final = table.concat(out, "\n")

    pcall(function()
        if makefolder then pcall(makefolder, "workspace/lurp-dump") end
        if makefolder then pcall(makefolder, "lurp-dump") end
        if writefile then
            writefile("workspace/lurp-dump/deobfuscated_dump.txt", final)
            log("GOTOVO. dump v workspace/lurp-dump/deobfuscated_dump.txt (" .. #final .. " bayt)")
        else
            log("writefile net — kopiruy iz konsoli")
        end
    end)

    print("\n===== TOP-20 =====")
    for i = 1, math.min(20, #dumpedStrings) do
        print("[" .. i .. "] len=" .. #dumpedStrings[i])
        print(dumpedStrings[i]:sub(1, 1000))
        print("---")
    end
    if #final < 20000 then
        print("\n===== FULL DUMP =====")
        print(final)
    end
end

local function hooked(chunk, name, ...)
    if type(chunk) == "string" and #chunk > 1000 and not dumped then
        -- eto pohozhe na nash luraph (bolshoy blob) — dampim
        local c = chunk
        saveDump(c, tostring(name or "loadstring"))
        return orig_loadstring(c, name, ...)
    end
    return orig_loadstring(chunk, name, ...)
end

if loadstring then loadstring = hooked end
if load then load = hooked end

log("GOTOV. teper zapuskay vtoroy script (loadstring luraph) — ya ego perehvachu.")
