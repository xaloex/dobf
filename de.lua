-- Delta iOS dumper dlya Luraph v15.1
-- Na iOS net readfile/writefile ryadom, poetomu zagruzka idet po ssilke.
-- Shag 1: zaley my_script.txt na gist/paste (raw link) i vstav ego nizhe v URL
-- Shag 2: zapusti etot script v Delta iOS, dump uvidish v konsole + on sohranitsya esli est writefile

local URL = "VSTAV_SYUDA_RAW_LINK_NA_MY_SCRIPT_TXT"

local function log(...) print("[dumper]", ...) end

-- 1. kachaem sors
log("kachayu sors...")
local src = game:HttpGet(URL)
if not src or #src == 0 then
    error("pustoy otvet po URL, provery raw link")
end
log("sors zagruzhen, bayt: " .. #src)

-- 2. hranilische
local dumpedStrings = {}
local seen = {}
local function noteString(s)
    if type(s) ~= "string" then return end
    if #s < 2 or #s > 20000 then return end
    if seen[s] then return end
    seen[s] = true
    dumpedStrings[#dumpedStrings + 1] = s
end

-- 3. huki na rasshifrovku
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

-- 4. huk na loadstring: lovim sobrannie chanki
local orig_loadstring = loadstring or load
local captured = {}
if orig_loadstring then
    local function hooked(chunk, name, ...)
        if type(chunk) == "string" and #chunk > 10 then
            captured[#captured + 1] = chunk
            pcall(noteString, chunk)
            log("perehvachen chunk, bayt: " .. #chunk)
        end
        return orig_loadstring(chunk, name, ...)
    end
    if loadstring then loadstring = hooked end
    if load then load = hooked end
end

-- 5. zapusk VM pod hukami
log("zapuskayu VM pod hukami...")
local chunk, loadErr = (loadstring or load)(src, "luraph_vm")
if not chunk then
    error("loadstring ne vzyal fayl: " .. tostring(loadErr))
end
local runOk, runErr = pcall(chunk)
log("VM otrabotal. runOk=" .. tostring(runOk) .. " err=" .. tostring(runErr))

-- 6. vozvrat originalov
buffer.tostring = orig_tostring
string.gsub = orig_gsub
string.sub = orig_sub
string.char = orig_char
string.format = orig_format
if loadstring then loadstring = orig_loadstring end
if load then load = orig_loadstring end

-- 7. sort: snachala dlinnie
table.sort(dumpedStrings, function(a, b) return #a > #b end)

-- 8. sborka dumpa
local out = {}
out[#out + 1] = "-- DUMP | strings: " .. #dumpedStrings .. " | chunks: " .. #captured
out[#out + 1] = string.rep("=", 60)
for i, ch in ipairs(captured) do
    out[#out + 1] = "\n-- ===== CHUNK " .. i .. " (" .. #ch .. " bayt) ====="
    out[#out + 1] = ch
end
out[#out + 1] = "\n" .. string.rep("=", 60)
out[#out + 1] = "-- ===== STRINGS (" .. #dumpedStrings .. ") ====="
for i, s in ipairs(dumpedStrings) do
    if s:find("[%a_]{2,}") then
        out[#out + 1] = "\n-- [" .. i .. "] len=" .. #s
        out[#out + 1] = s
    end
end
local final = table.concat(out, "\n")

-- 9. probuem sohranit (na iOS chasto net writefile — togda ruchnoe kopirovanie)
pcall(function()
    if writefile then
        writefile("deobfuscated_dump.txt", final)
        log("GOTOVO. dump zapisan (" .. #final .. " bayt)")
    else
        log("writefile net na iOS — kopiruy iz konsoli nizhe")
    end
end)

-- 10. top-20 v konsol srazu
print("\n===== TOP-20 samih dlinnih strok =====")
for i = 1, math.min(20, #dumpedStrings) do
    print("[" .. i .. "] len=" .. #dumpedStrings[i])
    print(dumpedStrings[i]:sub(1, 1000))
    print("---")
end

-- 11. esli dump malenkiy (<20kb) — pechataem celikom dlya kopirovaniya
if #final < 20000 then
    print("\n===== FULL DUMP (kopiruy) =====")
    print(final)
else
    print("\n[info] dump bolshoy (" .. #final .. " bayt), smotri TOP-20 vyshe. samiy dlinniy kusok:")
    print(dumpedStrings[1]:sub(1, 3000))
end
