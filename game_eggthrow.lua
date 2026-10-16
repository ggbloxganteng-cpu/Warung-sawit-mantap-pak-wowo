
--==========================================================
--  PARAMEK HUB - EGG THROW & TSUNAMI (fitur game)
--  Dibuat dari analisis KickController:
--    * kekuatan lempar dihitung client: KickConfigurations.GetThrowDistance(power, bar)
--    * hasil roll diminta lewat RemoteFunction Events.RollThrow:InvokeServer(posisiMendarat, ThrowHoop)
--    * klaim item lewat Events.ClaimHatchedItem:FireServer(namaTool, rarity, scale, mutation)
--    * tertangkap tsunami & "keluar zona" dideteksi di client
--  Catatan: cheat bisa melanggar aturan game / ToS Roblox dan berisiko ban. Pakai akun alt.
--==========================================================
local GAME_NAME = "Egg Throw & Tsunami"

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local TeleportService = game:GetService("TeleportService")
local VirtualUser = game:GetService("VirtualUser")
local Mouse = LP:GetMouse()
local VIM
pcall(function() VIM = game:GetService("VirtualInputManager") end)
local T = Library.Theme

local function has(fn) return typeof(fn) == "function" end
local function Alive() return Library._gui ~= nil end
local function Flag(k) return Library.Flags[k] end
local function On(k) return Library.Flags[k] == true end
local function Note(title, content, kind)
    Library:Notify({ Title = title, Content = content, Type = kind or "info" })
end
local function Root()
    local c = LP.Character
    return c and c:FindFirstChild("HumanoidRootPart")
end
local function Hum()
    local c = LP.Character
    return c and c:FindFirstChildOfClass("Humanoid")
end

local CAP = {
    hook = has(hookmetamethod) and has(getnamecallmethod),
    hookfn = has(hookfunction),
    conns = has(getconnections),
    ups = (debug ~= nil) and (has(debug.getupvalues) or has(debug.getupvalue)) or false,
    sig = has(firesignal),
    clip = has(setclipboard),
    file = has(writefile) and has(readfile),
    fps = has(setfpscap),
}
local function yn(b) return b and "ON" or "OFF" end

--==========================================================
--  REFERENSI GAME
--==========================================================
local Modules = ReplicatedStorage:WaitForChild("Modules", 8)
local function Req(name)
    local m = Modules and Modules:FindFirstChild(name)
    if not m then return nil end
    local ok, r = pcall(require, m)
    return ok and r or nil
end
local KickCfg = Req("KickConfigurations")
local EggCfg = Req("EggConfigurations")
local TsunamiCfg = Req("TsunamiConfigurations")

local function Ev(name)
    local e = ReplicatedStorage:FindFirstChild("Events")
    return e and e:FindFirstChild(name)
end
local Templates = ReplicatedStorage:FindFirstChild("Templates")
local kickAnim = Templates and Templates:FindFirstChild("KickAnimation")
local perfAnim = Templates and Templates:FindFirstChild("PerfectThrowAnimation")

local function HUD()
    local pg = LP:FindFirstChild("PlayerGui")
    local g = pg and pg:FindFirstChild("GUI")
    return g and g:FindFirstChild("HUD")
end
local function KickButton()
    local h = HUD()
    return h and h:FindFirstChild("Kick")
end
-- nilai power bar (0..1) dibaca dari ukuran bar di HUD; nil kalau bar tidak tampil
local function PowerValue()
    local h = HUD()
    local pb = h and h:FindFirstChild("PowerBar")
    if not (pb and pb.Visible) then return nil end
    local body = pb:FindFirstChild("Body")
    local bar = body and body:FindFirstChild("Bar")
    return bar and bar.Size.Y.Scale or nil
end

local function currentPower()
    local ps = LP:FindFirstChild("PlayerStats")
    local pw = ps and ps:FindFirstChild("Power")
    local v = pw and pw.Value or 0
    local lim = tonumber(LP:GetAttribute("StrengthLimit")) or math.huge
    return math.min(v, math.max(lim, 0))
end

--==========================================================
--  TERHUBUNG KE STATE KickController (lewat handler InputBegan)
--==========================================================
local Mod = { S = nil, throwFn = nil, beginFn = nil, patched = false, origGTD = nil }

local function getUps(fn)
    if debug and has(debug.getupvalues) then
        local ok, t = pcall(debug.getupvalues, fn)
        if ok and type(t) == "table" then return t end
    end
    local t = {}
    if debug and has(debug.getupvalue) then
        for i = 1, 300 do
            local ok, a, b = pcall(debug.getupvalue, fn, i)
            if not ok or (a == nil and b == nil) then break end
            t[i] = (type(a) == "string" and b ~= nil) and b or a
        end
    end
    return t
end

local function scanHandlers()
    if not CAP.conns then return false end
    local ok, conns = pcall(getconnections, UIS.InputBegan)
    if not ok or type(conns) ~= "table" then return false end
    local list = {}
    for _, c in ipairs(conns) do
        local fn = c.Function
        if type(fn) == "function" then
            local okE, env = pcall(getfenv, fn)
            local sc
            if okE and type(env) == "table" then
                local okS, v = pcall(function() return env.script end)
                if okS then sc = v end
            end
            if typeof(sc) == "Instance" and sc.Name == "KickController" then
                local ups = getUps(fn)
                local n = 0
                for _ in pairs(ups) do n = n + 1 end
                table.insert(list, { fn = fn, n = n, ups = ups })
            end
        end
    end
    if #list == 0 then return false end
    table.sort(list, function(a, b) return a.n < b.n end)
    Mod.beginFn = list[1].fn
    Mod.throwFn = list[#list].fn
    for _, e in ipairs(list) do
        for _, v in pairs(e.ups) do
            if type(v) == "table" and type(rawget(v, "BeginPowerSelect")) == "function" then
                Mod.S = v
            end
        end
    end
    return Mod.S ~= nil
end

local function fakeInput()
    return {
        UserInputType = Enum.UserInputType.Keyboard, KeyCode = Enum.KeyCode.Space,
        Position = Vector3.new(0, 100, 0), UserInputState = Enum.UserInputState.Begin,
    }
end

local function tapSpace()
    if VIM then
        pcall(function() VIM:SendKeyEvent(true, Enum.KeyCode.Space, false, game) end)
        task.delay(0.05, function()
            pcall(function() VIM:SendKeyEvent(false, Enum.KeyCode.Space, false, game) end)
        end)
        return true
    end
    return false
end

local function doThrow()
    if Mod.throwFn then
        task.spawn(Mod.throwFn, fakeInput(), false)
        return true
    end
    return tapSpace()
end

local function beginPower()
    local S = Mod.S
    if S and type(S.BeginPowerSelect) == "function" then
        task.spawn(S.BeginPowerSelect)
        return true
    end
    local kb = KickButton()
    if kb and CAP.sig and pcall(firesignal, kb.MouseButton1Click) then return true end
    return tapSpace()
end

-- paksa jarak lempar selalu "perfect" (bar dianggap 1) tanpa menunggu bar
local function patchKick()
    if not KickCfg or Mod.patched then return Mod.patched end
    local orig = KickCfg.GetThrowDistance
    if type(orig) ~= "function" then return false end
    if has(setreadonly) then pcall(setreadonly, KickCfg, false) end
    local ok = pcall(function()
        KickCfg.GetThrowDistance = function(power, bar, ...)
            if On("ForcePerfect") then bar = 1 end
            return orig(power, bar, ...)
        end
    end)
    if ok then
        Mod.patched, Mod.origGTD = true, orig
    end
    return ok
end

local function maxThrowDist()
    local f = Mod.origGTD or (KickCfg and KickCfg.GetThrowDistance)
    if type(f) ~= "function" then return nil end
    local ok, d = pcall(f, currentPower(), 1)
    if ok and tonumber(d) then return d end
    return nil
end

--==========================================================
--  HOOK NAMECALL (throw spoofer + remote spy)
--==========================================================
local Hooks = { installed = false, spoof = false, spy = false, onRemote = nil, hoop = nil, rollRemote = nil }

-- titik di dalam zona (Detection) pada jarak d dari pad lempar, searah lemparan (+Z)
local function inZone(det, pos)
    local rel = det.CFrame:PointToObjectSpace(pos)
    local s = det.Size
    return math.abs(rel.X) <= s.X / 2 + 1.5 and math.abs(rel.Z) <= s.Z / 2 + 1.5
end
local function zonePoint(origin, x, d, only)
    local zones = workspace:FindFirstChild("Zones")
    if not zones then return nil end
    local pos = Vector3.new(x, origin.Y, origin.Z + d)
    for _, z in ipairs(zones:GetChildren()) do
        if not only or z.Name == only then
            local det = z:FindFirstChild("Detection")
            if det and det:IsA("BasePart") and inZone(det, pos) then return pos, z end
        end
    end
    return nil
end

local Spoof = {}
function Spoof.best(real)
    local root = Root()
    if not root then return nil end
    local origin = root.Position
    local md = maxThrowDist()
    if not md then return nil end
    local top = md * (Flag("SpoofMargin") or 0.97)
    local mode = Flag("SpoofMode") or "Terjauh"
    local only = (mode == "Zona pilihan") and Flag("SpoofZone") or nil
    local x = real and real.X or origin.X
    if mode == "Offset" then
        local base = real and (real.Z - origin.Z) or 0
        local d = math.clamp(base + (Flag("SpoofOffset") or 40), 0, top)
        return zonePoint(origin, x, d, nil)
    end
    local d = top
    while d > 0 do
        local p = zonePoint(origin, x, d, only)
        if p then return p end
        d = d - 3
    end
    return nil
end

local function EnsureNamecall()
    if Hooks.installed then return true end
    if not CAP.hook then
        Note("Tidak didukung", "Executor kamu tidak punya hookmetamethod.", "error")
        return false
    end
    local wrap = has(newcclosure) and newcclosure or function(f) return f end
    local ours = has(checkcaller) and checkcaller or function() return false end
    Hooks.installed = true
    Hooks.rollRemote = Ev("RollThrow")
    local old
    old = hookmetamethod(game, "__namecall", wrap(function(self, ...)
        local method = getnamecallmethod()
        if (method == "InvokeServer" or method == "FireServer") and not ours() then
            if Hooks.spy and Hooks.onRemote then
                task.defer(Hooks.onRemote, self, method, table.pack(...))
            end
            if Hooks.spoof and method == "InvokeServer" and self == Hooks.rollRemote then
                local a = table.pack(...)
                if typeof(a[1]) == "Vector3" then
                    local p = Spoof.best(a[1])
                    if p then a[1] = p end
                end
                if Hooks.hoop ~= nil then a[2] = Hooks.hoop end
                return old(self, table.unpack(a, 1, a.n))
            end
        end
        return old(self, ...)
    end))
    return true
end
Library:OnDestroy(function() Hooks.spoof, Hooks.spy = false, false end)

-- percepat semua tween (cutscene reveal) dengan membungkus TweenInfo.new
local cutHooked = false
local function EnsureCutHook()
    if cutHooked then return true end
    if not CAP.hookfn then
        Note("Tidak didukung", "Butuh hookfunction.", "error")
        return false
    end
    local wrap = has(newcclosure) and newcclosure or function(f) return f end
    local ok = pcall(function()
        local old
        old = hookfunction(TweenInfo.new, wrap(function(t, ...)
            if On("FastCut") and type(t) == "number" then
                t = t / math.max(Flag("CutMult") or 1, 1)
            end
            return old(t, ...)
        end))
    end)
    cutHooked = ok
    if not ok then Note("Gagal", "hookfunction pada TweenInfo.new tidak didukung.", "error") end
    return ok
end

--==========================================================
--  WINDOW
--==========================================================
local Window = Library:CreateWindow({
    Name = "Paramek Hub",
    Subtitle = GAME_NAME,
    ToggleKey = Enum.KeyCode.RightShift,
})

-- ===== HOME =====
local Home = Window:CreateTab("Home", "house")
Home:CreateSection("Status")
local infoPower = Home:CreateLabel("Power: -")
local infoMod = Home:CreateLabel("Module: -")
local infoRoll = Home:CreateLabel("Roll terakhir: -")
Home:CreateSection("Cepat")
Home:CreateToggle({ Name = "Auto Throw", Icon = "crosshair", Flag = "AutoThrow", Bindable = true })
Home:CreateToggle({ Name = "Anti Catch Tsunami", Icon = "shield", Flag = "AntiCatch", Bindable = true })
Home:CreateToggle({ Name = "Auto Escape", Icon = "navigation", Flag = "AutoEscape", Bindable = true })
Home:CreateSection("Support executor")
Home:CreateParagraph("Fungsi yang dipakai", string.format(
    "hookmetamethod: %s\nhookfunction: %s\ngetconnections: %s\ndebug.getupvalues: %s\nfiresignal: %s\nsetclipboard: %s\nwritefile/readfile: %s",
    yn(CAP.hook), yn(CAP.hookfn), yn(CAP.conns), yn(CAP.ups), yn(CAP.sig), yn(CAP.clip), yn(CAP.file)))
Home:CreateLabel("Auto Throw, Fast Throw, Anti Catch butuh getconnections + debug.getupvalues. Spoofer butuh hookmetamethod.")

--==========================================================
--  THROW
--==========================================================
Window:CreateGroup()
local ThrowTab = Window:CreateTab("Throw", "crosshair")

ThrowTab:CreateSection("Auto Throw")
ThrowTab:CreateToggle({ Name = "Auto Throw", Icon = "crosshair", Flag = "AutoThrow", Bindable = true })
ThrowTab:CreateToggle({
    Name = "Force Perfect Distance", Icon = "gem", Flag = "ForcePerfect", Default = true,
    Callback = function(v)
        if v and not patchKick() then
            Note("Gagal", "KickConfigurations tidak bisa dipatch (read-only / tidak ditemukan).", "error")
        end
    end,
})
ThrowTab:CreateSlider({ Name = "Target power (tanpa Force)", Min = 50, Max = 100, Default = 98, Flag = "TargetPower", Suffix = "%" })
ThrowTab:CreateSlider({ Name = "Jeda antar lemparan", Min = 0, Max = 5, Increment = 0.1, Default = 0.6, Flag = "AutoDelay", Suffix = "s" })
ThrowTab:CreateToggle({ Name = "Auto ke Kick Pad", Icon = "map-pin", Flag = "AutoPad" })

ThrowTab:CreateSection("Instant Throw")
ThrowTab:CreateToggle({ Name = "Fast Throw (animasi dipercepat)", Icon = "zap", Flag = "FastThrow", Bindable = true })
ThrowTab:CreateSlider({ Name = "Kecepatan animasi", Min = 1, Max = 20, Default = 8, Flag = "ThrowSpeed", Suffix = "x" })
ThrowTab:CreateToggle({
    Name = "Cutscene cepat (eksperimental)", Icon = "timer", Flag = "FastCut",
    Callback = function(v)
        if v and not EnsureCutHook() then Library.Elements.FastCut:Set(false, true) end
    end,
})
ThrowTab:CreateSlider({ Name = "Kecepatan cutscene", Min = 1, Max = 20, Default = 6, Flag = "CutMult", Suffix = "x" })

ThrowTab:CreateSection("Throw Spoofer")
ThrowTab:CreateToggle({
    Name = "Throw Spoofer", Icon = "ghost", Flag = "Spoof", Bindable = true,
    Callback = function(v)
        if v then
            if EnsureNamecall() then Hooks.spoof = true else Library.Elements.Spoof:Set(false, true) end
        else
            Hooks.spoof = false
        end
    end,
})
local function zoneNames()
    local out = {}
    local zs = workspace:FindFirstChild("Zones")
    if zs then
        for _, z in ipairs(zs:GetChildren()) do table.insert(out, z.Name) end
    end
    table.sort(out)
    return out
end
ThrowTab:CreateDropdown({ Name = "Mode spoof", Icon = "list", Options = { "Terjauh", "Zona pilihan", "Offset" }, Default = "Terjauh", Flag = "SpoofMode" })
local zoneDrop = ThrowTab:CreateDropdown({ Name = "Zona pilihan", Icon = "map-pin", Options = zoneNames(), Flag = "SpoofZone" })
ThrowTab:CreateButton({ Name = "Refresh daftar zona", Icon = "refresh", Text = "REFRESH", Callback = function() zoneDrop:Refresh(zoneNames()) end })
ThrowTab:CreateSlider({ Name = "Offset jarak (mode Offset)", Min = 0, Max = 500, Default = 40, Flag = "SpoofOffset", Suffix = "stud" })
ThrowTab:CreateSlider({ Name = "Batas aman jarak", Min = 0.5, Max = 1, Increment = 0.01, Default = 0.97, Flag = "SpoofMargin" })
ThrowTab:CreateInput({
    Name = "ThrowHoop (opsional)", Icon = "code", Placeholder = "kosong = asli", Flag = "HoopVal",
    Callback = function(txt)
        if txt == "" then
            Hooks.hoop = nil
        elseif tonumber(txt) then
            Hooks.hoop = tonumber(txt)
        elseif txt == "true" or txt == "false" then
            Hooks.hoop = (txt == "true")
        else
            Hooks.hoop = txt
        end
    end,
})
ThrowTab:CreateLabel("Spoofer mengganti posisi mendarat yang dikirim ke server dengan titik terjauh yang masih terjangkau Power-mu. ThrowHoop jangan diisi kalau tidak tahu nilainya.")

-- ----- mesin Throw -----
local lastBegin, lastThrow, lastPad = 0, 0, 0
local function kickPart() return workspace:FindFirstChild("KickPart") end
local function toKickPad()
    local r, kp = Root(), kickPart()
    if r and kp and kp:IsA("BasePart") then
        r.CFrame = kp.CFrame * CFrame.new(0, kp.Size.Y / 2 + 3, 0)
        r.AssemblyLinearVelocity = Vector3.zero
        return true
    end
    return false
end

Track(RunService.Heartbeat:Connect(function()
    if not On("AutoThrow") then return end
    local busy = LP:GetAttribute("ThrowBusy") == true
    local pv = PowerValue()
    if pv then
        local need = On("ForcePerfect") and 0 or ((Flag("TargetPower") or 98) / 100)
        if pv >= need and os.clock() - lastThrow > 0.12 then
            lastThrow = os.clock()
            doThrow()
        end
        return
    end
    local kb = KickButton()
    if kb and kb.Visible and not busy then
        if os.clock() - lastBegin > (Flag("AutoDelay") or 0.6) then
            lastBegin = os.clock()
            beginPower()
        end
    elseif On("AutoPad") and not busy and LP:GetAttribute("IsMorphed") ~= true and os.clock() - lastPad > 3 then
        lastPad = os.clock()
        toKickPad()
    end
end))

-- percepat animasi lempar + hilangkan jeda rearm
Track(RunService.RenderStepped:Connect(function()
    if not On("FastThrow") then return end
    local h = Hum()
    local an = h and h:FindFirstChildOfClass("Animator")
    if not an then return end
    local mult = Flag("ThrowSpeed") or 8
    for _, tr in ipairs(an:GetPlayingAnimationTracks()) do
        local a = tr.Animation
        if a and (a == kickAnim or a == perfAnim) and math.abs(tr.Speed - mult) > 0.01 then
            tr:AdjustSpeed(mult)
        end
    end
end))
task.spawn(function()
    while Alive() do
        local S = Mod.S
        if S then
            S.THROW_REARM_TIME = (On("FastThrow") or On("ForcePerfect")) and 0 or 0.18
        end
        task.wait(0.4)
    end
end)
Library:OnDestroy(function()
    local S = Mod.S
    if S then
        S.THROW_REARM_TIME = 0.18
        S.CatchPad = 1
    end
    if Mod.patched and Mod.origGTD and KickCfg then
        pcall(function() KickCfg.GetThrowDistance = Mod.origGTD end)
    end
end)

--==========================================================
--  REMOTE THROW (tanpa animasi / cutscene)
--==========================================================
Window:CreateGroup()
local RemoteTab = Window:CreateTab("Remote", "zap")
RemoteTab:CreateSection("Remote Throw")
local rtLbl = RemoteTab:CreateLabel("Belum ada lemparan remote")
local rtBusy, rtCount = false, 0

local function backpackSet()
    local t = {}
    local bp = LP:FindFirstChildOfClass("Backpack")
    if bp then
        for _, x in ipairs(bp:GetChildren()) do t[x] = true end
    end
    local c = LP.Character
    if c then
        for _, x in ipairs(c:GetChildren()) do
            if x:IsA("Tool") then t[x] = true end
        end
    end
    return t
end

local function remoteThrowOnce()
    if rtBusy then return false end
    rtBusy = true
    local okAll = false
    local function finish(msg, kind)
        rtLbl:Set(msg)
        if kind then Note("Remote Throw", msg, kind) end
        rtBusy = false
        return okAll
    end
    local rf = Ev("RollThrow")
    local root = Root()
    if not (rf and rf:IsA("RemoteFunction") and root) then
        return finish("RollThrow / karakter tidak ditemukan", "error")
    end
    if On("RTPad") then
        toKickPad()
        task.wait(0.35)
        root = Root()
        if not root then return finish("Karakter hilang", "error") end
    end
    local pos = Spoof.best(root.Position)
    if not pos then
        return finish("Tidak ada titik zona yang terjangkau dengan Power-mu", "warn")
    end
    local before = backpackSet()
    local ok, res, reason = pcall(function()
        return rf:InvokeServer(pos, LP:GetAttribute("ThrowHoop"))
    end)
    if not ok or type(res) ~= "table" or type(res.EggModel) ~= "string" then
        return finish("Ditolak server: " .. tostring(ok and (reason or "tidak ada jawaban") or res), "warn")
    end
    okAll = true
    rtCount = rtCount + 1
    local rel = tonumber(res.RelScale) or 1
    local line = string.format("#%d  %s | %s | x%.2f", rtCount, tostring(res.Rarity), tostring(res.Mutation), rel)
    rtLbl:Set(line)

    if On("RTClaim") then
        local claim = Ev("ClaimHatchedItem")
        if claim and claim:IsA("RemoteEvent") then
            local toolName = (EggCfg and EggCfg.GetEggModelName and EggCfg.GetEggModelName(res.Rarity)) or res.EggModel
            local clamped = rel
            if EggCfg and EggCfg.SIZE_MIN_SCALE and EggCfg.SIZE_MAX_SCALE then
                clamped = math.clamp(rel, EggCfg.SIZE_MIN_SCALE, EggCfg.SIZE_MAX_SCALE)
            end
            local abs = (EggCfg and EggCfg.GetAbsoluteScale and EggCfg.GetAbsoluteScale(clamped)) or clamped
            claim:FireServer(toolName, res.Rarity, abs, res.Mutation)
            task.wait(2.5)
            local got
            local bp = LP:FindFirstChildOfClass("Backpack")
            local function scan(container)
                if not container then return end
                for _, x in ipairs(container:GetChildren()) do
                    if x:IsA("Tool") and not before[x] then got = x.Name end
                end
            end
            scan(bp)
            scan(LP.Character)
            if got then
                rtLbl:Set(line .. "  ->  item masuk: " .. got)
            else
                rtLbl:Set(line .. "  ->  klaim belum masuk (server mungkin menolak)")
            end
        end
    end
    rtBusy = false
    return okAll
end

RemoteTab:CreateButton({
    Name = "Lempar sekali (remote)", Icon = "zap", Text = "THROW",
    Callback = function() task.spawn(remoteThrowOnce) end,
})
RemoteTab:CreateToggle({ Name = "Auto Remote Throw", Icon = "repeat", Flag = "RTAuto", Bindable = true })
RemoteTab:CreateSlider({ Name = "Jeda tiap lemparan", Min = 2, Max = 30, Increment = 0.5, Default = 3.5, Flag = "RTDelay", Suffix = "s" })
RemoteTab:CreateToggle({ Name = "Auto klaim hasil", Icon = "gem", Flag = "RTClaim", Default = true })
RemoteTab:CreateToggle({ Name = "Teleport ke Kick Pad dulu", Icon = "map-pin", Flag = "RTPad", Default = true })
RemoteTab:CreateLabel("Remote Throw memanggil RollThrow lalu ClaimHatchedItem langsung, tanpa animasi dan cutscene. Kalau server menolak, alasannya muncul di status di atas.")

task.spawn(function()
    while Alive() do
        if On("RTAuto") and not rtBusy then
            pcall(remoteThrowOnce)
            task.wait(math.max(Flag("RTDelay") or 3.5, 2))
        else
            task.wait(0.3)
        end
    end
end)

--==========================================================
--  TSUNAMI
--==========================================================
local TsuTab = Window:CreateTab("Tsunami", "waves")

local function collectionParts()
    local out = {}
    local zs = workspace:FindFirstChild("Zones")
    if zs then
        for _, z in ipairs(zs:GetChildren()) do
            local c = z:FindFirstChild("Collection")
            if c and c:IsA("BasePart") then table.insert(out, c) end
        end
    end
    return out
end
local function insideColl(c, pos, pad)
    local rel = c.CFrame:PointToObjectSpace(pos)
    local s = c.Size
    return math.abs(rel.X) <= s.X / 2 + pad and math.abs(rel.Z) <= s.Z / 2 + pad and math.abs(rel.Y) <= s.Y / 2 + 15
end
local function endPos()
    local ts = workspace:FindFirstChild("Tsunami")
    local e = ts and ts:FindFirstChild("End")
    if e and e:IsA("BasePart") then return e.Position end
    return TsunamiCfg and TsunamiCfg.END_POSITION or nil
end
-- titik tepat di luar semua zona Collection, ke arah tsunami berlari (arah aman)
local function escapePoint(root)
    local ep = endPos()
    if not ep then return nil end
    local colls = collectionParts()
    if #colls == 0 then return nil end
    local cur, bestD = nil, math.huge
    for _, c in ipairs(colls) do
        if insideColl(c, root.Position, 2) then
            cur = c
            break
        end
        local d = (c.Position - root.Position).Magnitude
        if d < bestD then cur, bestD = c, d end
    end
    local dir = Vector3.new(ep.X - cur.Position.X, 0, ep.Z - cur.Position.Z)
    if dir.Magnitude < 1 then return nil end
    dir = dir.Unit
    for step = 6, 800, 6 do
        local p = Vector3.new(cur.Position.X + dir.X * step, root.Position.Y, cur.Position.Z + dir.Z * step)
        local inside = false
        for _, c in ipairs(colls) do
            if insideColl(c, p, 4) then
                inside = true
                break
            end
        end
        if not inside then return p end
    end
    return nil
end
local function doEscape()
    local r = Root()
    if not r then return false end
    local p = escapePoint(r)
    if not p then
        Note("Escape", "Titik keluar zona tidak ditemukan.", "warn")
        return false
    end
    r.AssemblyLinearVelocity = Vector3.zero
    r.CFrame = CFrame.new(p) * (r.CFrame - r.CFrame.Position)
    return true
end

TsuTab:CreateSection("Perlindungan")
TsuTab:CreateToggle({
    Name = "Anti Catch (tidak tertangkap)", Icon = "shield", Flag = "AntiCatch", Bindable = true,
    Callback = function(v)
        if v and not Mod.S then
            Note("Tidak aktif", "State KickController belum terhubung (butuh getconnections + debug.getupvalues).", "warn")
        end
        if not v and Mod.S then Mod.S.CatchPad = 1 end
    end,
})
TsuTab:CreateToggle({ Name = "Auto Escape (keluar zona)", Icon = "navigation", Flag = "AutoEscape", Bindable = true })
TsuTab:CreateButton({
    Name = "Escape sekarang", Icon = "navigation", Text = "GO",
    Callback = function() doEscape() end,
})
TsuTab:CreateLabel("Auto Escape memindahkanmu ke luar zona Collection begitu kejaran dimulai, sehingga klaim item langsung terpicu.")

local lastEsc = 0
Track(RunService.Stepped:Connect(function()
    local S = Mod.S
    if S and On("AntiCatch") then
        S.CatchPad = -1e9
        S.ForceCatch = false
    end
end))
Track(RunService.Heartbeat:Connect(function()
    if On("AutoEscape") and LP:GetAttribute("ChaseActive") == true and os.clock() - lastEsc > 1.2 then
        lastEsc = os.clock()
        doEscape()
    end
end))

TsuTab:CreateSection("Teleport")
TsuTab:CreateButton({
    Name = "Ke Kick Pad", Icon = "map-pin", Text = "TP",
    Callback = function()
        if not toKickPad() then Note("Gagal", "KickPart tidak ditemukan.", "error") end
    end,
})
TsuTab:CreateButton({
    Name = "Ke plot sendiri", Icon = "house", Text = "TP",
    Callback = function()
        local pp = workspace:FindFirstChild("PlayerPlots")
        local pt = pp and pp:FindFirstChild("PlotPart_" .. LP.Name)
        local r = Root()
        if r and pt and pt:IsA("BasePart") then
            r.CFrame = CFrame.new(pt.Position + Vector3.new(0, pt.Size.Y / 2 + 4, 0))
        else
            Note("Gagal", "Plot tidak ditemukan.", "error")
        end
    end,
})
TsuTab:CreateButton({
    Name = "Return Home (remote)", Icon = "refresh", Text = "HOME",
    Callback = function()
        local rh = Ev("ReturnHome")
        if rh and rh:IsA("RemoteEvent") then rh:FireServer() else Note("Gagal", "Remote ReturnHome tidak ada.", "error") end
    end,
})

TsuTab:CreateSection("Zona")
TsuTab:CreateToggle({ Name = "Zone ESP (jarak & jangkauan)", Icon = "eye", Flag = "ZoneESP" })
local function clearZoneESP()
    local zs = workspace:FindFirstChild("Zones")
    if not zs then return end
    for _, z in ipairs(zs:GetChildren()) do
        local det = z:FindFirstChild("Detection")
        local g = det and det:FindFirstChild("PK_ZoneESP")
        if g then g:Destroy() end
    end
end
Library:OnDestroy(clearZoneESP)
task.spawn(function()
    while Alive() do
        if On("ZoneESP") then
            local zs = workspace:FindFirstChild("Zones")
            local md = maxThrowDist()
            local kp = kickPart()
            local oz = kp and kp.Position.Z or (Root() and Root().Position.Z) or 0
            if zs then
                for _, z in ipairs(zs:GetChildren()) do
                    local det = z:FindFirstChild("Detection")
                    if det and det:IsA("BasePart") then
                        local g = det:FindFirstChild("PK_ZoneESP")
                        local lbl
                        if not g then
                            g = New("BillboardGui", {
                                Name = "PK_ZoneESP", Adornee = det, Size = UDim2.new(0, 240, 0, 24),
                                StudsOffset = Vector3.new(0, 12, 0), AlwaysOnTop = true, MaxDistance = 1e5, Parent = det,
                            })
                            lbl = New("TextLabel", {
                                Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = F.GothamBold,
                                TextSize = 12, TextColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 0.3, Parent = g,
                            })
                        else
                            lbl = g:FindFirstChildOfClass("TextLabel")
                        end
                        if lbl then
                            local startD = (det.Position.Z - det.Size.Z / 2) - oz
                            local reach = md ~= nil and startD <= md * (Flag("SpoofMargin") or 0.97)
                            lbl.Text = string.format("%s | %dm | %s", z.Name, math.floor(startD), reach and "TERJANGKAU" or "terlalu jauh")
                            lbl.TextColor3 = reach and T.Green or T.Red
                        end
                    end
                end
            end
        else
            clearZoneESP()
        end
        task.wait(1)
    end
end)

--==========================================================
--  PLAYER
--==========================================================
Window:CreateGroup()
local PlayerTab = Window:CreateTab("Player", "footprints")

PlayerTab:CreateSection("Kecepatan")
PlayerTab:CreateToggle({ Name = "Speed Hack", Icon = "gauge", Flag = "SpeedOn", Bindable = true })
PlayerTab:CreateSlider({ Name = "WalkSpeed", Min = 16, Max = 300, Default = 50, Flag = "WS" })
PlayerTab:CreateToggle({ Name = "CFrame Speed (bypass)", Icon = "gauge", Flag = "CFSpeed" })
PlayerTab:CreateSlider({ Name = "Kekuatan CFrame Speed", Min = 1, Max = 10, Default = 3, Flag = "CFVal" })

PlayerTab:CreateSection("Lompat")
PlayerTab:CreateToggle({ Name = "Jump Power", Icon = "footprints", Flag = "JPOn" })
PlayerTab:CreateSlider({ Name = "JumpPower", Min = 50, Max = 400, Increment = 5, Default = 100, Flag = "JP" })
local infJump = false
PlayerTab:CreateToggle({ Name = "Infinite Jump", Icon = "footprints", Flag = "InfJump", Bindable = true, Callback = function(v) infJump = v end })

PlayerTab:CreateSection("Gerak")
PlayerTab:CreateToggle({ Name = "Fly", Icon = "plane", Flag = "Fly", Keybind = Enum.KeyCode.F })
PlayerTab:CreateSlider({ Name = "Kecepatan fly", Min = 10, Max = 300, Default = 60, Flag = "FlySpeed" })
PlayerTab:CreateToggle({ Name = "Noclip", Icon = "ghost", Flag = "Noclip", Keybind = Enum.KeyCode.N })

do
    local fly = {}
    local function flyClean()
        if fly.bv then fly.bv:Destroy() fly.bv = nil end
        if fly.bg then fly.bg:Destroy() fly.bg = nil end
        local h = Hum()
        if h then h.PlatformStand = false end
    end
    Library:OnDestroy(flyClean)

    Track(UIS.JumpRequest:Connect(function()
        if infJump then
            local h = Hum()
            if h then h:ChangeState(Enum.HumanoidStateType.Jumping) end
        end
    end))
    Track(RunService.Stepped:Connect(function()
        if On("Noclip") and LP.Character then
            for _, p in ipairs(LP.Character:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = false end
            end
        end
    end))
    Track(RunService.Heartbeat:Connect(function(dt)
        local r, h = Root(), Hum()
        if not (r and h) then return end
        if On("SpeedOn") then h.WalkSpeed = Flag("WS") or 50 end
        if On("JPOn") then
            h.UseJumpPower = true
            h.JumpPower = Flag("JP") or 100
        end
        if On("CFSpeed") and h.MoveDirection.Magnitude > 0 then
            r.CFrame = r.CFrame + h.MoveDirection * (Flag("CFVal") or 3) * 10 * dt
        end
        if On("Fly") then
            local cam = workspace.CurrentCamera
            if cam then
                local cf = cam.CFrame
                local rel = cf:VectorToObjectSpace(h.MoveDirection)
                local dir = cf.LookVector * (-rel.Z) + cf.RightVector * rel.X
                if UIS:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0, 1, 0) end
                if UIS:IsKeyDown(Enum.KeyCode.LeftShift) then dir = dir - Vector3.new(0, 1, 0) end
                if dir.Magnitude > 1 then dir = dir.Unit end
                if not fly.bv or fly.bv.Parent ~= r then
                    flyClean()
                    fly.bv = Instance.new("BodyVelocity")
                    fly.bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
                    fly.bv.Parent = r
                    fly.bg = Instance.new("BodyGyro")
                    fly.bg.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
                    fly.bg.P = 9e4
                    fly.bg.Parent = r
                end
                h.PlatformStand = true
                fly.bv.Velocity = dir * (Flag("FlySpeed") or 60)
                fly.bg.CFrame = cf
            end
        elseif fly.bv then
            flyClean()
        end
    end))
end

--==========================================================
--  MISC
--==========================================================
local MiscTab = Window:CreateTab("Misc", "wrench")
MiscTab:CreateSection("Umum")
local antiAfk = true
Track(LP.Idled:Connect(function()
    if antiAfk then
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end
end))
MiscTab:CreateToggle({ Name = "Anti AFK", Icon = "timer", Flag = "AntiAFK", Default = true, Callback = function(v) antiAfk = v end })

do
    local L0 = { Brightness = Lighting.Brightness, ClockTime = Lighting.ClockTime, GlobalShadows = Lighting.GlobalShadows, Ambient = Lighting.Ambient }
    local function restore() for k, v in pairs(L0) do pcall(function() Lighting[k] = v end) end end
    Library:OnDestroy(restore)
    MiscTab:CreateToggle({
        Name = "Fullbright", Icon = "sun", Flag = "Fullbright",
        Callback = function(v) if not v then restore() end end,
    })
    task.spawn(function()
        while Alive() do
            if On("Fullbright") then
                Lighting.Brightness = 2
                Lighting.ClockTime = 14
                Lighting.GlobalShadows = false
                Lighting.Ambient = Color3.fromRGB(200, 200, 200)
            end
            task.wait(0.3)
        end
    end)
end

MiscTab:CreateSection("Performa")
MiscTab:CreateSlider({ Name = "FPS Cap", Min = 30, Max = 360, Increment = 10, Default = 120, Flag = "FPSCap", Suffix = "fps" })
MiscTab:CreateButton({
    Name = "Terapkan FPS Unlocker", Icon = "gauge", Text = "APPLY",
    Callback = function()
        if CAP.fps then
            setfpscap(Flag("FPSCap") or 120)
            Note("FPS", "Cap diubah ke " .. (Flag("FPSCap") or 120), "success")
        else
            Note("Tidak didukung", "Executor tidak punya setfpscap.", "error")
        end
    end,
})

MiscTab:CreateSection("Server")
MiscTab:CreateButton({
    Name = "Server Hop", Icon = "server", Text = "HOP",
    Callback = function()
        local ok, body = pcall(function()
            return game:HttpGet(string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100", game.PlaceId))
        end)
        if not ok then
            Note("Gagal", "Tidak bisa ambil daftar server.", "error")
            return
        end
        local okJ, data = pcall(function() return HttpService:JSONDecode(body) end)
        if okJ and data and data.data then
            for _, s in ipairs(data.data) do
                if s.id ~= game.JobId and s.playing < s.maxPlayers then
                    TeleportService:TeleportToPlaceInstance(game.PlaceId, s.id, LP)
                    return
                end
            end
        end
        Note("Gagal", "Tidak ada server lain yang tersedia.", "error")
    end,
})
MiscTab:CreateButton({
    Name = "Rejoin Server", Icon = "refresh", Text = "REJOIN",
    Callback = function() TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LP) end,
})

--==========================================================
--  SPY (bantu cari tahu argumen remote game)
--==========================================================
Window:CreateGroup()
local SpyTab = Window:CreateTab("Spy", "webhook")
SpyTab:CreateSection("Remote Spy")
SpyTab:CreateToggle({
    Name = "Aktifkan Remote Spy", Icon = "webhook", Flag = "SpyOn",
    Callback = function(v)
        if v then
            if EnsureNamecall() then Hooks.spy = true else Library.Elements.SpyOn:Set(false, true) end
        else
            Hooks.spy = false
        end
    end,
})
SpyTab:CreateToggle({ Name = "Hanya remote folder Events", Icon = "list", Flag = "SpyEvents", Default = true })
SpyTab:CreateInput({ Name = "Abaikan nama (pisah koma)", Placeholder = "mis. SetHoldingEgg", Flag = "SpyIgnore" })
local spyLog = SpyTab:CreateLogBox({ Height = 200 })
SpyTab:CreateButton({ Name = "Bersihkan log", Icon = "trash-2", Text = "CLEAR", Callback = function() spyLog:Clear() end })
SpyTab:CreateButton({
    Name = "Salin log", Icon = "copy", Text = "COPY",
    Callback = function()
        if CAP.clip then
            setclipboard(spyLog:Text())
            Note("Disalin", "Log masuk clipboard.", "success")
        end
    end,
})
do
    local function ser(v, depth)
        local t = typeof(v)
        if t == "string" then return '"' .. v .. '"' end
        if t == "Instance" then return v:GetFullName() end
        if t == "table" then
            if depth >= 2 then return "{...}" end
            local out, n = {}, 0
            for k, x in pairs(v) do
                n = n + 1
                if n > 6 then
                    table.insert(out, "...")
                    break
                end
                table.insert(out, "[" .. tostring(k) .. "]=" .. ser(x, depth + 1))
            end
            return "{" .. table.concat(out, ", ") .. "}"
        end
        return tostring(v)
    end
    Hooks.onRemote = function(remote, method, args)
        if not On("SpyOn") then return end
        if On("SpyEvents") and not (remote.Parent and remote.Parent.Name == "Events") then return end
        local name = string.lower(remote.Name)
        for word in string.gmatch(string.lower(Flag("SpyIgnore") or ""), "[^,%s]+") do
            if name == word then return end
        end
        local parts = {}
        for i = 1, args.n do table.insert(parts, ser(args[i], 0)) end
        spyLog:Add(string.format("[%s] %s(%s)", method == "FireServer" and "FS" or "IS", remote.Name, table.concat(parts, ", ")))
    end
end

--==========================================================
--  SETTINGS
--==========================================================
local Settings = Window:CreateTab("Settings", "settings")
Settings:CreateSection("Tema")
do
    local names = {}
    for n in pairs(Library.Presets) do table.insert(names, n) end
    table.sort(names)
    Settings:CreateDropdown({
        Name = "Preset tema", Options = names, Default = "Paramek", Flag = "ThemePreset",
        Callback = function(n) if n then Library:SetTheme(n) end end,
    })
    local function debounced(key)
        local token = 0
        return function(c)
            token = token + 1
            local mine = token
            task.delay(0.15, function()
                if mine == token then Library:SetTheme({ [key] = c }) end
            end)
        end
    end
    Settings:CreateColorPicker({ Name = "Warna aksen 1", Default = Library.Theme.Accent, Callback = debounced("Accent") })
    Settings:CreateColorPicker({ Name = "Warna aksen 2", Default = Library.Theme.Accent2, Callback = debounced("Accent2") })
end
Settings:CreateSection("Keybind UI")
Settings:CreateKeybind({
    Name = "Buka / tutup UI", Default = Window.ToggleKey, Flag = "UIKey",
    Changed = function(k) Window.ToggleKey = k end,
})
Settings:CreateLabel("Keybind fitur: klik kotak kecil di sebelah switch toggle (Backspace = hapus).")
Settings:CreateSection("Config")
do
    local cfgName = "eggthrow"
    Settings:CreateInput({
        Name = "Nama config", Default = "eggthrow", Placeholder = "nama...",
        Callback = function(t) if t ~= "" then cfgName = t end end,
    })
    Settings:CreateButton({
        Name = "Simpan config", Icon = "save", Text = "SAVE",
        Callback = function()
            local ok = Library:SaveConfig(cfgName)
            Note(ok and "Tersimpan" or "Gagal", ok and ("Config '" .. cfgName .. "' disimpan.") or "Executor tidak support writefile.", ok and "success" or "error")
        end,
    })
    Settings:CreateButton({
        Name = "Muat config", Icon = "save", Text = "LOAD",
        Callback = function()
            local ok = Library:LoadConfig(cfgName)
            Note(ok and "Dimuat" or "Gagal", ok and ("Config '" .. cfgName .. "' dimuat.") or "File config tidak ditemukan.", ok and "success" or "error")
        end,
    })
end
Settings:CreateSection("UI")
Settings:CreateButton({ Name = "Tutup & hapus UI", Icon = "power", Text = "UNLOAD", Callback = function() Library:Destroy() end })

--==========================================================
--  JALANKAN: hubungkan ke KickController + update info
--==========================================================
if On("ForcePerfect") then patchKick() end

task.spawn(function()
    local tries = 0
    while Alive() and not Mod.S and tries < 20 do
        tries = tries + 1
        pcall(scanHandlers)
        if Mod.S then break end
        task.wait(1.5)
    end
    if Mod.S then
        Note("KickController", "State terhubung. Auto Throw, Fast Throw, dan Anti Catch siap.", "success")
    else
        Note("KickController", "State tidak ditemukan (butuh getconnections + debug.getupvalues). Beberapa fitur dibatasi.", "warn")
    end
end)

task.spawn(function()
    while Alive() do
        local md = maxThrowDist()
        local ps = LP:FindFirstChild("PlayerStats")
        local pw = ps and ps:FindFirstChild("Power")
        infoPower:Set(string.format("Power: %s (limit %s) | jarak perfect: %s",
            pw and tostring(pw.Value) or "?", tostring(LP:GetAttribute("StrengthLimit") or "-"),
            md and (math.floor(md) .. "m") or "?"))
        infoMod:Set(string.format("State: %s | Patch jarak: %s | Hook: %s",
            Mod.S and "OK" or "belum", Mod.patched and "OK" or "belum", Hooks.installed and "OK" or "belum"))
        local S = Mod.S
        local roll = S and S.ServerRoll
        if type(roll) == "table" then
            infoRoll:Set(string.format("Roll terakhir: %s | %s | x%.2f",
                tostring(roll.Rarity), tostring(roll.Mutation), tonumber(roll.RelScale) or 1))
        end
        task.wait(1)
    end
end)

Note("Paramek Hub", "Loaded! RightShift atau tombol logo buat buka/tutup.", "success")
