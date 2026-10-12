-- Delta iOS Luraph-killer v5: chokpoint-trap (pcall(loadstring, DECOMPRESSED))2222222222
--
-- UYAZVIMOST (naydena statikoy v samom VM, etot samiy fayl 1.9MB):
--   C() loader sostoyanie y==0 delaet:
--     S = tostring(rasshifrovanniy_buffer)      -- decompress -> stroka
--     M,G = pcall(loadstring, S, "Luraph", nil) -- S = CHISTIY DEKOMPILIROVANNIY KOD
--   To est ves 1.8MB shifrobloba prevraschaetsya v ODIN vizov loadstring s otkritim tekstom.
--   Luraph ne mozhet bez etogo: emu nuzhen loadstring chtob prevratit baytkod v funkciyu.
--   Etot vizov NELZYA spryatat — on obyazan proyti cherez globalniy loadstring.
--   Poetomu: propuskaem vneshniy (1.9MB shifr), lovim VNUTRENNIY (chistiy kod), podmenyaem zaglushkoy.
--
-- Shag 1: zapusti ETOt script — visit lovushka
-- Shag 2: zapusti vtoroy script (loadstring luraph) — on OTRABOTAET (ne blokiruetsya),
--         vnutrenniy loadstring perehvatitsya, chistiy kod upadyot v workspace/lurp-dump/inner_src.lua
--         realnoe ispolnenie podmenyaetsya zaglushkoy (igra ne visit, payload ne startuet)

local function log(...) print("[killer]", ...) end
log("stavlyu chokpoint-lovushku...")

if not hookfunction then error("net hookfunction — nuzhna Delta s hookfunction") end
local wrap = newcclosure or function(f) return f end

local DUMP_DIR = "workspace/lurp-dump"
pcall(function()
    if makefolder then pcall(makefolder, "workspace/lurp-dump") end
    if makefolder then pcall(makefolder, "lurp-dump") end
end)
local function save(name, data)
    local ok, err = pcall(function()
        if writefile then writefile(DUMP_DIR .. "/" .. name, data) end
    end)
    if ok then log("saved " .. name .. " (" .. #data .. " bayt)")
    else log("save FAIL " .. name .. ": " .. tostring(err)) end
end

-- otsenka "chitabelnosti" BISTRO: tolko pervie 500 simvolov, odin prohod
local function readability(s)
    if type(s) ~= "string" or #s < 50 then return 0 end
    local sample = s:sub(1, 500)
    local kw = 0
    for _ in sample:gmatch("%f[%a](local|function|end|if|then|else|return|for|while|do|nil|true|false)%f[^%a]") do
        kw = kw + 1
        if kw >= 6 then break end -- raniy vihod: i tak ponyatno
    end
    return kw * 10
end

local orig_loadstring = loadstring or load
local stage = "WAIT_OUTER"  -- WAIT_OUTER -> WAIT_INNER (navsegda, lovim skolko ugodno)
local outerSize = 0
local catchCount = 0

-- backup-kanal: buffer.tostring vidit S pered loadstring (dvizhok buffer.* ne yuzaet — bezopasno)
local backupSrc = nil
if buffer and buffer.tostring then
    local o_ts = buffer.tostring
    local n = 0
    pcall(hookfunction, buffer.tostring, wrap(function(...)
        local r = o_ts(...)
        if stage == "WAIT_INNER" and type(r) == "string" and #r > 5000 then
            n = n + 1
            if n <= 3 and readability(r) > 8 then
                backupSrc = r
                log("backup-kanal: buffer.tostring poymal chitabelniy kusok (" .. #r .. " bayt)")
            end
        end
        return r
    end))
end

local function hooked(chunk, name, ...)
    if type(chunk) ~= "string" then
        return orig_loadstring(chunk, name, ...)
    end

    if stage == "WAIT_OUTER" and #chunk > 500000 then
        -- eto sam VM (1.9MB shifr): PROPUSKAEM, chtob doshel do chokpointa
        stage = "WAIT_INNER"
        outerSize = #chunk
        log("vneshniy VM propuschen (" .. #chunk .. " bayt). zhdu vnutrennie loadstring (lovlyu VSE, bez limita)...")
        -- sohranenie syrtca V FONE, chtob ne derzhat goryachiy put (1.9MB pishetsya dolgo)
        if task and task.spawn then task.spawn(save, "raw_src.txt", chunk) else save("raw_src.txt", chunk) end
        return orig_loadstring(chunk, name, ...)
    end

    -- noviy bolshoy vneshniy (drugoy luraph) posle pervogo: tozhe propustit, obnovit etalon
    if stage == "WAIT_INNER" and #chunk > 500000 then
        outerSize = #chunk
        log("noviy vneshniy VM (" .. #chunk .. " bayt), propuskayu, prodolzhayu lovit...")
        return orig_loadstring(chunk, name, ...)
    end

    if stage == "WAIT_INNER" and #chunk > 1000 then
        local score = 0
        pcall(function() score = readability(chunk) end)
        log("kandidat: bayt=" .. #chunk .. " score=" .. string.format("%.1f", score) .. " name=" .. tostring(name))
        if score > 8 or chunk:find("Luraph") or (#chunk < outerSize / 2 and #chunk > 5000) then
            catchCount = catchCount + 1
            local fname = "inner_src_" .. catchCount .. ".lua"
            log("POYMAL #" .. catchCount .. " (" .. #chunk .. " bayt). sokhranyayu v " .. fname .. " + podmena zaglushkoy.")
            -- sohranenie + print golovi V FONE: huk otdaet zaglushku SRAZU, bez ozhidaniya diska
            local c = chunk
            if task and task.spawn then
                task.spawn(function()
                    save(fname, c)
                    print("----- INNER #" .. catchCount .. " HEAD (500) -----")
                    print(c:sub(1, 500))
                    print("----- END HEAD -----")
                end)
            else
                save(fname, c)
                print("----- INNER HEAD (500) -----")
                print(c:sub(1, 500))
                print("----- END HEAD -----")
            end
            -- VAZHNO: vozvraschaem zaglushku vmesto realnoy funkcii:
            -- VM poluchit function (proverka r(g)==\"function\" proydet), no payload NE vipolnitsya
            local stub = function(...) log("stub: realniy payload zablokirovan, tolko dump") return nil end
            return stub
        end
        -- ne pohozh na vnutrenniy (sluzhebniy chank dvizhka) — propustit
        return orig_loadstring(chunk, name, ...)
    end

    return orig_loadstring(chunk, name, ...)
end

hookfunction(loadstring or load, wrap(hooked))
if load and load ~= (loadstring or nil) then
    pcall(hookfunction, load, wrap(hooked))
end

log("GOTOV. poryadok: 1) etot script uzhe visit 2) gonay vtorie (luraph) skolko ugodno 3) zaberi " .. DUMP_DIR .. "/inner_src_N.lua")
log("esli vnutrenniy ne prishel za 30s — smotri konsol, tam budet vidno vse vizovi loadstring.")
