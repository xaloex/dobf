-- Delta iOS Luraph-killer v6: chokpoint-trap BEZ LIMITOV
--
-- UYAZVIMOST: C() loader, sostoyanie y==0:
--   S = tostring(rasshifrovanniy_buffer)
--   M,G = pcall(loadstring, S, "Luraph", nil)   <-- S = CHISTIY KOD, obyazan proyti cherez globalniy loadstring
-- Lovushka: vneshniy propuskaem, lovim VSE chto prihodit dalshe (kazhdiy chank >50 simvolov
-- v svoy fayl, zhirnie rezhem na parti po 400KB). Nikakih skorov i filtrov.
--
-- PORYADOK: 1) zapusti ETOt 2) gonay vtorie skolko ugodno 3) zaberi fayli iz workspace/lurp-dump/
--
-- PRO KRASH: esli vilet do pervogo POYMAL — eto iOS watchdog ubivaet igru na 1.8MB deshifre
-- (odin potok, ~30-60s frosta). Lechenie: zakrit vse prilozheniya, ne trogat ekran poka visit,
-- davat igre prozhevat. Posle POYMAL payload uzhe zablokirovan zaglushkoy — dalshe bezopasno.

local function log(...) print("[killer]", ...) end
log("stavlyu chokpoint-lovushku BEZ LIMITOV...")

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

-- zhirnie rezhem na parti po ~400KB (iOS writefile dushitsya na megabaytah)
local PART = 400000
local function saveSplit(base, data)
    if #data <= PART then save(base, data) return end
    local n = 0
    for i = 1, #data, PART do
        n = n + 1
        save(base .. ".part" .. n, data:sub(i, i + PART - 1))
    end
    log("razbito na " .. n .. " chastey: " .. base .. ".partN")
end

local orig_loadstring = loadstring or load
local stage = "WAIT_OUTER"
local catchCount = 0
local backupN = 0

-- backup-kanal: buffer.tostring vidit S pered loadstring. dvizhok buffer.* ne yuzaet.
-- lovim VSE >5KB, kazhdiy v svoy fayl.
if buffer and buffer.tostring then
    local o_ts = buffer.tostring
    pcall(hookfunction, buffer.tostring, wrap(function(...)
        local r = o_ts(...)
        if stage == "WAIT_INNER" and type(r) == "string" and #r > 5000 then
            backupN = backupN + 1
            local bn = backupN
            local rr = r
            log("backup #" .. bn .. " (" .. #rr .. " bayt)")
            if task and task.spawn then task.spawn(saveSplit, "backup_buf_" .. bn .. ".bin", rr)
            else saveSplit("backup_buf_" .. bn .. ".bin", rr) end
        end
        return r
    end))
end

local function hooked(chunk, name, ...)
    if type(chunk) ~= "string" then
        return orig_loadstring(chunk, name, ...)
    end

    -- lyuboy zhirniy (>500KB): eto vneshniy VM-shifr. PROPUSKAEM vsegda (chtob doshel do chokpointa).
    if #chunk > 500000 then
        if stage == "WAIT_OUTER" then
            stage = "WAIT_INNER"
            log("vneshniy VM propuschen (" .. #chunk .. " bayt). lovlyu VSE dalshe, bez limita...")
        else
            log("esche odin vneshniy (" .. #chunk .. " bayt), propuskayu...")
        end
        local c = chunk
        if task and task.spawn then task.spawn(saveSplit, "raw_src.txt", c)
        else saveSplit("raw_src.txt", c) end
        return orig_loadstring(chunk, name, ...)
    end

    -- VSE ostalnoe >50 simvolov: lovim, pischem, podmenyaem zaglushkoy. BEZ SKOROV I FILTROV.
    if stage == "WAIT_INNER" and #chunk > 50 then
        catchCount = catchCount + 1
        local cc = catchCount
        local c = chunk
        local cname = tostring(name or "?")
        local fname = "inner_src_" .. cc .. ".lua"
        log("POYMAL #" .. cc .. " (" .. #c .. " bayt, name=" .. cname .. ") -> " .. fname)
        if task and task.spawn then
            task.spawn(function()
                saveSplit(fname, c)
                print("----- INNER #" .. cc .. " HEAD (300) -----")
                print(c:sub(1, 300))
                print("----- END HEAD -----")
            end)
        else
            saveSplit(fname, c)
        end
        local stub = function(...) return nil end
        return stub
    end

    return orig_loadstring(chunk, name, ...)
end

hookfunction(loadstring or load, wrap(hooked))
if load and load ~= (loadstring or nil) then
    pcall(hookfunction, load, wrap(hooked))
end

log("GOTOV. gonay vtorie skolko ugodno, vse upadut v " .. DUMP_DIR .. "/inner_src_N.lua (+.partN esli zhirnie).")
log("VAZHNO: posle zapuska vtorogo NE TROGAY EKRAN — deshifr 1.8MB morozit igru na ~30-60s, iOS ubivaet esli shevelit.")
