-- Delta iOS MEGA-dumper v4 dlya Luraph v15.1 (crash-safe, staged)
-- Ideya: ne viset na goryachih string-hukah, a idti po stupenyam s limitami.
-- Stadii: 1) raw perehvat 2) konstanty/upvalues bez zapuska 3) getgc sweep
--         4) time-boxed buffer-huki + kontroliruemiy progon VM 5) bytecode
-- Vse stadii pishut otdelnie fayli v workspace/lurp-dump/
-- Esli kakaya stadiya visit — sleduyuschie vsyo ravno otrabotayut (kazhdaya v pcall).

local function log(...) print("[mega]", ...) end
log("start. staged dump...")

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

-- limitirovanniy huk s byudzhetom (anti-crash: posle N vizovov snimaetsya sam)
local managedHooks = {}
local function budgetHook(fnPath, tableRef, key, wrapperFactory, budget)
    budget = budget or 50000
    local orig = tableRef[key]
    local count = 0
    local active = true
    local h
    h = hookfunction(orig, wrap(function(...)
        if not active then return orig(...) end
        count = count + 1
        if count > budget then
            active = false
            log("budget ischerpan dlya " .. fnPath .. " (" .. budget .. "), snimayu")
            -- vosstanovit nelzya napryamuyu (readonly) — prosto probrasivaem dalshe bez logiki
            return orig(...)
        end
        return wrapperFactory(orig, ...);
    end))
    managedHooks[#managedHooks + 1] = { path = fnPath, orig = orig }
    return h
end

-- hranilische stadiy
local strings = {}
local seen = {}
local function note(s)
    if type(s) ~= "string" then return end
    if #s < 2 or #s > 20000 then return end
    if seen[s] then return end
    seen[s] = true
    strings[#strings + 1] = s
end

-- STAGE 0: perehvat loadstring (vtoroy script sam pridet)
local orig_loadstring = loadstring or load
local rawSrc = nil
local rawName = "?"
local gotRaw = false

local function onRaw(chunk, name)
    if gotRaw then return end
    if type(chunk) ~= "string" or #chunk < 1000 then return end
    gotRaw = true
    rawSrc = chunk
    rawName = tostring(name or "loadstring")
    log("STAGE0 perehvat (" .. rawName .. "), bayt: " .. #chunk)
    save("raw_src.txt", chunk)
end

local function loadHook(chunk, name, ...)
    if type(chunk) == "string" and #chunk > 1000 and not gotRaw then
        local c = chunk
        onRaw(c, name)
        -- blokiruem realniy zapusk: vozvraschaem zaglushku (igra ne visit)
        return function() log("vtoroy script zablokirovan (tolko dump)") end
    end
    return orig_loadstring(chunk, name, ...)
end

hookfunction(loadstring or load, wrap(loadHook))
if load and load ~= (loadstring or nil) then
    pcall(hookfunction, load, wrap(loadHook))
end
log("STAGE0 gotov. zapusti vtoroy script (loadstring luraph). zhdu 60 sek...")

-- zhdiom raw do 60 sek (ne blokiruem potok executor zhestko: korotkie sni)
local waited = 0
while not gotRaw and waited < 60 do
    if task and task.wait then task.wait(1) else wait(1) end
    waited = waited + 1
end
if not gotRaw then
    log("STAGE0 timeout: vtoroy script ne prishel. ostanovka (huki loadstring ostayutsya).")
    return
end

-- STAGE 1: zagruzit chunk BEZ zapuska, razobrat konstanty/upvalues
log("STAGE1: konstanty/upvalues bez zapuska...")
pcall(function()
    local chunk = orig_loadstring(rawSrc, "luraph_static")
    if not chunk then log("STAGE1: load ne vzyal"); return end

    -- 1a. upvalues verhnevo closure
    local uvOut = {}
    local i = 1
    while true do
        local ok, name, val = pcall(debug.getupvalue, chunk, i)
        if not ok or not name then break end
        local t = type(val)
        uvOut[#uvOut + 1] = "up[" .. i .. "] " .. tostring(name) .. " : " .. t ..
            (t == "string" and (" len=" .. #val) or "") ..
            (t == "number" and (" v=" .. tostring(val)) or "")
        if t == "string" then pcall(note, val) end
        if t == "table" then
            -- melkaya tablitsa: proyti po klyucham pervogo urovnya
            pcall(function()
                local n = 0
                for k, v in pairs(val) do
                    n = n + 1
                    if n > 200 then break end
                    if type(v) == "string" then pcall(note, v) end
                    if type(k) == "string" then pcall(note, k) end
                end
            end)
        end
        i = i + 1
    end
    save("stage1_upvalues.txt", table.concat(uvOut, "\n"))

    -- 1b. konstanty (Delta: debug.getconstants / debug.getconstant)
    local constOut = {}
    pcall(function()
        local getconstants = debug.getconstants or debug.getconsts
        if getconstants then
            local consts = getconstants(chunk)
            if type(consts) == "table" then
                for idx, c in pairs(consts) do
                    if type(c) == "string" then
                        pcall(note, c)
                        constOut[#constOut + 1] = "[" .. tostring(idx) .. "] str len=" .. #c .. " :: " .. c:sub(1, 300)
                    else
                        constOut[#constOut + 1] = "[" .. tostring(idx) .. "] " .. type(c) .. " = " .. tostring(c):sub(1, 200)
                    end
                end
            end
        elseif debug.getconstant then
            local idx = 1
            while true do
                local ok, c = pcall(debug.getconstant, chunk, idx)
                if not ok or c == nil then break end
                if type(c) == "string" then
                    pcall(note, c)
                    constOut[#constOut + 1] = "[" .. idx .. "] str len=" .. #c .. " :: " .. c:sub(1, 300)
                else
                    constOut[#constOut + 1] = "[" .. idx .. "] " .. type(c) .. " = " .. tostring(c):sub(1, 200)
                end
                idx = idx + 1
                if idx > 5000 then break end
            end
        else
            constOut[#constOut + 1] = "net debug.getconstants/getconstant v etoy Delta"
        end
    end)
    save("stage1_constants.txt", table.concat(constOut, "\n"))
    log("STAGE1 gotovo. upvalues/const sobrani.")
end)

-- STAGE 2: getgc sweep — ischem krupnie stroki/tablitsi VM (budit posle load, do zapuska)
log("STAGE2: getgc sweep...")
pcall(function()
    if not getgc then log("STAGE2: net getgc, propusk"); return end
    local out = {}
    local nStr, nTab, nFunc = 0, 0, 0
    for _, obj in pairs(getgc()) do
        local t = type(obj)
        if t == "string" then
            if #obj >= 4 and #obj <= 20000 then
                -- filtr musora: hotya bi 2 bukvi podrjad
                if obj:find("[%a_][%a_0-9]") then
                    pcall(note, obj)
                    nStr = nStr + 1
                end
            end
        elseif t == "table" then
            nTab = nTab + 1
        elseif t == "function" then
            nFunc = nFunc + 1
        end
    end
    out[#out + 1] = "strings_noted=" .. nStr .. " tables_seen=" .. nTab .. " funcs_seen=" .. nFunc
    save("stage2_getgc.txt", table.concat(out, "\n"))
    log("STAGE2 gotovo. strok zamecheno: " .. nStr)
end)

-- STAGE 3: time-boxed buffer-huki + kontroliruemiy progon VM
-- Luraph v15 t-managed: huki tolko na buffer.read*/buffer.tostring s byudzhetom,
-- progon v otdelnoy coroutine, posle — srazu vosstanovlenie cherez pcall.
-- Eto uyazvimost VM: ves baytkod i stroki prohodyat cherez eti 2-3 tochki.
log("STAGE3: buffer-huki s byudzhetom + progon VM...")
pcall(function()
    local READ_BUDGET = 200000   -- hvataet na polniy progon 1.9MB VM
    local STR_BUDGET = 50000

    local o_readu8 = buffer.readu8
    local o_readu32 = buffer.readu32
    local o_readstring = buffer.readstring
    local o_tostring = buffer.tostring

    if o_readstring then
        budgetHook("buffer.readstring", buffer, "readstring", function(orig, buf, off, len, ...)
            local r = orig(buf, off, len, ...)
            if type(r) == "string" then pcall(note, r) end
            return r
        end, STR_BUDGET)
    end
    if o_tostring then
        budgetHook("buffer.tostring", buffer, "tostring", function(orig, buf, ...)
            local r = orig(buf, ...)
            if type(r) == "string" then pcall(note, r) end
            return r
        end, STR_BUDGET)
    end
    -- readu8/readu32 ne logiruem znacheniya (slishkom chasto), tolko schitaem:
    -- znachit VM zhiva i gde-to vnutri dispatch. Esli schetchik rastet — VM rabotaet.
    local readCount = 0
    if o_readu8 then
        budgetHook("buffer.readu8", buffer, "readu8", function(orig, ...)
            readCount = readCount + 1
            return orig(...)
        end, READ_BUDGET)
    end
    if o_readu32 then
        budgetHook("buffer.readu32", buffer, "readu32", function(orig, ...)
            readCount = readCount + 1
            return orig(...)
        end, READ_BUDGET)
    end

    -- progon v coroutine s zashitoy po vremeni: esli VM visit >25 sek — brosaem
    local chunk = orig_loadstring(rawSrc, "luraph_run")
    if not chunk then log("STAGE3: load fail"); return end
    local co = coroutine.create(chunk)
    local startT = os.clock()
    local TIMEOUT = 25
    local ok, err = true, nil
    while coroutine.status(co) ~= "dead" do
        if os.clock() - startT > TIMEOUT then
            log("STAGE3: timeout 25s — VM controliruemo ostanovlena (eto norm, chast strok uzhe sobrana)")
            break
        end
        local a, b = coroutine.resume(co)
        ok, err = a, b
        if not a then break end
        if task and task.wait then task.wait() end
    end
    log("STAGE3 progon zavershen. ok=" .. tostring(ok) .. " err=" .. tostring(err):sub(1, 300) .. " bufferReads~" .. readCount)
end)

-- STAGE 4: bytecode (esli Delta umeet getscriptbytecode — redkiy no schitat)
log("STAGE4: bytecode...")
pcall(function()
    if getscriptbytecode then
        local chunk = orig_loadstring(rawSrc, "luraph_bc")
        if chunk then
            local ok, bc = pcall(getscriptbytecode, chunk)
            if ok and type(bc) == "string" and #bc > 0 then
                save("stage4_bytecode.bin", bc)
            else
                log("STAGE4: bytecode pust")
            end
        end
    else
        log("STAGE4: net getscriptbytecode, propusk")
    end
end)

-- STAGE 5: final — sort po dline, sborka itogovogo dumpa
log("STAGE5: sborka finala...")
table.sort(strings, function(a, b) return #a > #b end)
local out = {}
out[#out + 1] = "-- MEGA DUMP (" .. rawName .. ") | strings: " .. #strings
out[#out + 1] = string.rep("=", 60)
out[#out + 1] = "-- smotri takzhe: raw_src.txt, stage1_upvalues.txt, stage1_constants.txt, stage2_getgc.txt"
out[#out + 1] = string.rep("=", 60)
out[#out + 1] = "-- ===== STRINGS (" .. #strings .. ") ====="
for i, s in ipairs(strings) do
    if s:find("[%a_]{2,}") then
        out[#out + 1] = "\n-- [" .. i .. "] len=" .. #s
        out[#out + 1] = s
    end
end
local final = table.concat(out, "\n")
save("deobfuscated_dump.txt", final)

print("\n===== TOP-30 =====")
for i = 1, math.min(30, #strings) do
    print("[" .. i .. "] len=" .. #strings[i])
    print(strings[i]:sub(1, 1000))
    print("---")
end
log("VSE STADII GOTOVI. fayli v " .. DUMP_DIR .. "/")
