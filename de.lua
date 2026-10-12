-- Delta iOS dumper v3: crash-safe (tolko loadstring-huk, bez string-hukov)
-- Prichina vyleta: huki na string.sub/gsub/char/format/tostring tormozyat ves dvizhok.
-- Eta versiya NE trogaet string.* — tolko perehvat loadstring i sohranenie syrtca.
-- Shag 1: zapusti ETOt script — visit i zhdiot
-- Shag 2: zapusti vtoroy script (loadstring luraph) — perehvat + sokhranenie v workspace/lurp-dump/

local function log(...) print("[dumper]", ...) end
log("stavlyu tolko loadstring-huk (bezopasno)...")

if not hookfunction then
    error("net hookfunction — nuzhna Delta s hookfunction")
end
local wrap = newcclosure or function(f) return f end

local orig_loadstring = loadstring or load
local orig_load = load
local dumped = false

local function saveRaw(src, tag)
    if dumped then return end
    dumped = true
    log("PEREHVACHENO (" .. tag .. "), bayt: " .. #src)
    pcall(function()
        if makefolder then pcall(makefolder, "workspace/lurp-dump") end
        if makefolder then pcall(makefolder, "lurp-dump") end
        if writefile then
            writefile("workspace/lurp-dump/raw_src.txt", src)
            log("GOTOVO. syrets v workspace/lurp-dump/raw_src.txt")
        else
            log("writefile net — vivizhu nachalo v konsol")
            print(src:sub(1, 2000))
        end
    end)
    -- NE zapuskaem VM avtomaticheski (chtob ne visnut).
    -- Esli hochesh prognat VM pod kontrolem — skazhi, dam otdelniy script.
end

local function hooked(chunk, name, ...)
    if type(chunk) == "string" and #chunk > 1000 and not dumped then
        local c = chunk
        saveRaw(c, tostring(name or "loadstring"))
        -- vozvraschaem originalniy chunk BEZ zapuska (stolknulis — vernuli upravlenie)
        -- chtob vtoroy script ne povis: vozvraschaem pustuyu funkciyu vmesto realnoy
        -- ZAMETKA: eto OTMENYAET zapusk vtorogo scripta (on ne vipolnitsya, tolko dampitsya).
        return function() log("vtoroy script zablokirovan (tolko dump), chtob ne vislo") end
    end
    return orig_loadstring(chunk, name, ...)
end

hookfunction(loadstring or load, wrap(hooked))
if load and orig_load ~= orig_loadstring then
    pcall(hookfunction, load, wrap(hooked))
end

log("GOTOV. zapuskay vtoroy script — perehvachu i sokhranyu syrets, igra NE zavisnet.")
