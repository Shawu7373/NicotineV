--// ====================================================================
--// NICOTINE | Emergency Hamburg | Full Hub + PC/Mobile Edition
--// Made by: Shaw | Discord: Shaw6000
--// Fixed for Delta Executor + GitHub
--// ====================================================================

print("[NICOTINE] Loading...")

if not getgenv then getgenv = function() return _G end end
pcall(function() if getgenv().Nicotine then getgenv().Nicotine() end end)
getgenv().Nicotine = function() end

local function main()
    local Players = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local UIS = game:GetService("UserInputService")
    local StarterGui = game:GetService("StarterGui")
    local Workspace = game:GetService("Workspace")
    local Lighting = game:GetService("Lighting")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local TweenService = game:GetService("TweenService")

    local LP = Players.LocalPlayer
    local PG = LP:WaitForChild("PlayerGui", 15)
    if not PG then error("PlayerGui not found") end

    for _, v in ipairs(PG:GetChildren()) do
        if v.Name:match("^Nicotine") then pcall(function() v:Destroy() end) end
    end

    local function notify(t, x, d)
        pcall(function()
            StarterGui:SetCore("SendNotification", {Title = t or "Nicotine", Text = x or "", Duration = d or 3})
        end)
    end

    -- ============================================================
    -- PLATFORM DETECTION
    -- ============================================================
    local IS_PC = UIS.KeyboardEnabled and not UIS.TouchEnabled
    local IS_MOBILE = UIS.TouchEnabled and not UIS.KeyboardEnabled
    local IS_CONSOLE = UIS.GamepadEnabled and not UIS.KeyboardEnabled and not UIS.TouchEnabled
    local PLATFORM = IS_PC and "PC" or (IS_MOBILE and "Mobile") or (IS_CONSOLE and "Console") or "Unknown"

    print("[NICOTINE] Platform: " .. PLATFORM)

    local hasHook = type(hookfunction) == "function"
    local hasGetGC = type(getgc) == "function"
    local hasRequire = type(require) == "function"

    -- ============================================================
    -- RAYFIELD LOADER (Delta-compatible)
    -- ============================================================
    local function httpGet(url)
        local ok, res = pcall(function() return game:HttpGet(url) end)
        if ok and res and #res > 100 then return res end
        if type(request) == "function" then
            local ok2, res2 = pcall(function() return request({Url = url, Method = "GET"}).Body end)
            if ok2 and res2 and #res2 > 100 then return res2 end
        end
        return nil
    end

    local Rayfield
    for _, url in ipairs({
        "https://sirius.menu/rayfield",
        "https://raw.githubusercontent.com/shlexware/Rayfield/main/source",
    }) do
        local src = httpGet(url)
        if src then
            local fn = loadstring(src)
            if fn then
                local ok2, result = pcall(fn)
                if ok2 and type(result) == "table" and result.CreateWindow then
                    Rayfield = result
                    break
                end
            end
        end
    end
    if not Rayfield then error("Rayfield failed to load") end

    -- ======================== STATE ========================
    local S = {
        Unloaded = false,
        Platform = PLATFORM,
        ACBypassDone = false, ACHookedCount = 0,

        Invisible = false,

        SavedLocations = {},
        SaveKey = "P",
        TeleportKey = "T",

        BringCarEnabled = false,
        CarGodMode = false,

        AntiArrest = false,
        AntiTaser = false,
        AntiDowned = false,
        AntiFall = false,
        AntiAFK = false,
        AntiVoid = false,
        GodMode = false,

        AutoFarmMoney = false,
        AutoServerHop = false,
        AutoRespawn = false,

        SmartRob = false,
        FleeDistance = 120,
        SafeDistance = 400,
        ResumeDelay = 6,
        RobState = "IDLE",
        LastFleeTime = 0,
        FleeCount = 0,
        LootCount = 0,
        RobberyCache = {},
        SellerCache = nil,
        CacheLastRefresh = 0,
        PunchRemotes = {},
        SellRemotes = {},
        LastManualFlee = 0,

        InfStamina = false, StaminaModule = nil, OriginalUseStamina = nil,
        ESP = false, ESPCops = true, ESPCriminals = true,
        WalkSpeed = 16, WalkSpeedOn = false, DefaultWalkSpeed = 16,
        JumpPower = 50, JumpPowerOn = false, DefaultJumpPower = 50,
        InfJump = false, Noclip = false,
        Fullbright = false, NoFog = false,
        ChatSpy = false, AdminDetector = false,
        _fullbrightApplied = false, _nofogApplied = false,
        OriginalLighting = {
            Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient,
            Brightness = Lighting.Brightness, FogEnd = Lighting.FogEnd, FogStart = Lighting.FogStart
        },
        Conn = {}
    }

    local function trk(c) if c then table.insert(S.Conn, c) end; return c end
    local function getChar() return LP.Character end
    local function getHum() local c = getChar(); return c and c:FindFirstChildOfClass("Humanoid") end
    local function getRoot() local c = getChar(); return c and c:FindFirstChild("HumanoidRootPart") end

    -- ============================================================
    -- ROLE DETECTION
    -- ============================================================
    local roleCache = setmetatable({}, {__mode = "k"})
    local COP_KEYWORDS = {"police","sheriff","swat","trooper","officer","cop","deputy","fbi","polizei","sek"}
    local CRIM_KEYWORDS = {"criminal","gang","mafia","thief","robber","bandit"}

    local function getRole(p)
        local cached = roleCache[p]
        if cached then return cached end
        local r = "civilian"
        if p.Team then
            local t = p.Team.Name:lower()
            for _, k in ipairs(COP_KEYWORDS) do if t:find(k) then r = "cop"; break end end
            if r == "civilian" then
                for _, k in ipairs(CRIM_KEYWORDS) do if t:find(k) then r = "criminal"; break end end
            end
        end
        roleCache[p] = r
        return r
    end

    -- ============================================================
    -- COP CACHE
    -- ============================================================
    local copList = {}
    local function refreshCopList()
        table.clear(copList)
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LP and getRole(p) == "cop" and p.Character then
                local root = p.Character:FindFirstChild("HumanoidRootPart")
                if root then table.insert(copList, root) end
            end
        end
    end

    local function getNearestCopDist()
        local myRoot = getRoot()
        if not myRoot then return math.huge, nil end
        local nearest, nd = nil, math.huge
        for i = 1, #copList do
            local croot = copList[i]
            if croot and croot.Parent then
                local d = (myRoot.Position - croot.Position).Magnitude
                if d < nd then nd = d; nearest = croot end
            end
        end
        return nd, nearest
    end

    trk(Players.PlayerAdded:Connect(function() task.wait(1); refreshCopList() end))
    trk(Players.PlayerRemoving:Connect(function() refreshCopList() end))
    trk(RunService.Heartbeat:Connect(function()
        if S.Unloaded then return end
        if tick() - (S._lastCopRefresh or 0) > 0.25 then
            refreshCopList()
            S._lastCopRefresh = tick()
        end
    end))

    -- ============================================================
    -- ANTI-CHEAT BYPASS (Enhanced for Delta)
    -- ============================================================
    local function bypassAntiCheat()
        if S.ACBypassDone then return true end

        local acModule
        pcall(function()
            local c = LP.PlayerScripts:FindFirstChild("Code")
            if not c then return end
            c = c:FindFirstChild("controllers")
            if not c then return end
            acModule = c:FindFirstChild("antiCheatController")
        end)

        if not acModule then
            -- Fallback: scan all descendants for anti-cheat module
            pcall(function()
                for _, d in ipairs(LP.PlayerScripts:GetDescendants()) do
                    if d.Name:lower():find("anticheat") or d.Name:lower():find("anti_cheat") then
                        acModule = d
                        break
                    end
                end
            end)
        end

        if not acModule then return false end
        pcall(function() require(acModule) end)

        local hooked = 0
        if hasGetGC and hasHook then
            for _, v in pairs(getgc(true)) do
                if type(v) == "function" then
                    local okEnv, env = pcall(getfenv, v)
                    if okEnv and env and env.script == acModule then
                        local okName, name = pcall(function() return getinfo(v).name end)
                        if (okName and name ~= "onStart") or not okName then
                            pcall(function() hookfunction(v, function() return end) end)
                            hooked = hooked + 1
                            -- Modify upvalue tables
                            local okUV, upvalues = pcall(getupvalues, v)
                            if okUV and upvalues then
                                for _, b in pairs(upvalues) do
                                    if type(b) == "table" then
                                        for c, _ in pairs(b) do
                                            local k = tostring(c):lower()
                                            if k:find("max") or k:find("limit") then
                                                pcall(function() rawset(b, c, math.huge) end)
                                            elseif k:find("disallow") or k:find("blacklist") or k:find("banned") then
                                                pcall(function() rawset(b, c, {}) end)
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        S.ACBypassDone = true
        S.ACHookedCount = hooked
        notify("Nicotine", "AC bypass: " .. hooked .. " hooks", 3)
        return true
    end

    -- ============================================================
    -- INVISIBILITY
    -- ============================================================
    local function setInvisible(state)
        S.Invisible = state
        local char = getChar()
        if not char then return end
        for _, part in ipairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                if state then
                    part.Transparency = 1
                    part.LocalTransparencyModifier = 1
                else
                    part.Transparency = 0
                    part.LocalTransparencyModifier = 0
                end
            end
        end
        notify("Nicotine", state and "INVISIBLE" or "VISIBLE", 2)
    end

    -- ============================================================
    -- SAVED LOCATIONS
    -- ============================================================
    local function saveLocation(name)
        local root = getRoot()
        if not root then return end
        S.SavedLocations[name] = root.CFrame
        notify("Nicotine", "Saved: " .. name, 2)
    end

    local function teleportToLocation(name)
        local loc = S.SavedLocations[name]
        if not loc then
            notify("Nicotine", "No saved location: " .. name, 3)
            return
        end
        local root = getRoot()
        if root then
            root.CFrame = loc + Vector3.new(0, 3, 0)
            root.AssemblyLinearVelocity = Vector3.zero
            notify("Nicotine", "Teleported to: " .. name, 2)
        end
    end

    -- ============================================================
    -- TELEPORT HELPER
    -- ============================================================
    local function tp(pos)
        local root = getRoot()
        if root and pos then
            root.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
            root.AssemblyLinearVelocity = Vector3.zero
        end
    end

    -- ============================================================
    -- VEHICLE COMMANDS
    -- ============================================================
    local function bringOwnCar()
        local myRoot = getRoot()
        if not myRoot then return end
        local nearest, nd = nil, math.huge
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if obj:IsA("Model") and obj:FindFirstChildOfClass("VehicleSeat") then
                local part = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
                if part then
                    local d = (myRoot.Position - part.Position).Magnitude
                    if d < nd then nd = d; nearest = obj end
                end
            end
        end
        if nearest then
            local part = nearest.PrimaryPart or nearest:FindFirstChildWhichIsA("BasePart")
            if part then
                part.CFrame = myRoot.CFrame + myRoot.CFrame.LookVector * 5
                notify("Nicotine", "Car brought to you", 2)
            end
        else
            notify("Nicotine", "No car found nearby", 3)
        end
    end

    local function enterOwnCar()
        local hum = getHum()
        local myRoot = getRoot()
        if not hum or not myRoot then return end
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if obj:IsA("Model") and obj:FindFirstChildOfClass("VehicleSeat") then
                local part = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
                if part and (myRoot.Position - part.Position).Magnitude < 10 then
                    local seat = obj:FindFirstChildOfClass("VehicleSeat")
                    if seat then
                        hum.Sit = true
                        seat:Sit(hum)
                        notify("Nicotine", "Entered car", 2)
                        return
                    end
                end
            end
        end
        notify("Nicotine", "No nearby car to enter", 3)
    end

    -- ============================================================
    -- ANTI-DETECTION
    -- ============================================================
    trk(RunService.Heartbeat:Connect(function()
        if S.Unloaded then return end
        if S.AntiTaser then
            local hum = getHum()
            if hum and hum.Health < hum.MaxHealth then
                pcall(function() hum.Health = hum.MaxHealth end)
            end
        end
        if S.AntiDowned then
            local hum = getHum()
            if hum and hum:GetState() == Enum.HumanoidStateType.Physics then
                pcall(function()
                    hum:ChangeState(Enum.HumanoidStateType.GettingUp)
                    hum.Health = hum.MaxHealth
                end)
            end
        end
        if S.AntiFall then
            local hum = getHum()
            if hum then
                pcall(function()
                    hum:SetStateEnabled(Enum.HumanoidStateType.FallingDown, false)
                    hum:SetStateEnabled(Enum.HumanoidStateType.Ragdoll, false)
                end)
            end
        end
    end))

    -- ============================================================
    -- AUTO-FARM MONEY
    -- ============================================================
    local function runAutoFarmMoney()
        if not S.AutoFarmMoney then return end
        if not S.ACBypassDone then bypassAntiCheat() end
        local hum = getHum()
        if not hum then return end
        pcall(function()
            for _, remote in ipairs(ReplicatedStorage:GetDescendants()) do
                if remote:IsA("RemoteEvent") or remote:IsA("RemoteFunction") then
                    local n = remote.Name:lower()
                    if n:find("shift") or n:find("start") or n:find("deliver") or n:find("route") then
                        pcall(function() remote:FireServer() end)
                    end
                end
            end
        end)
        if S.AutoRespawn and hum.Health < hum.MaxHealth * 0.3 then
            pcall(function() hum.Health = 0 end)
        end
    end

    trk(RunService.Heartbeat:Connect(function()
        if S.Unloaded then return end
        if S.AutoFarmMoney then runAutoFarmMoney() end
    end))

    -- ============================================================
    -- REMOTE SCANNER (defined before use)
    -- ============================================================
    local function refreshRemotes()
        table.clear(S.PunchRemotes)
        table.clear(S.SellRemotes)
        pcall(function()
            for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
                if d:IsA("RemoteEvent") or d:IsA("RemoteFunction") then
                    local n = d.Name:lower()
                    if n:find("punch") or n:find("hit") or n:find("break") or n:find("damage") then
                        table.insert(S.PunchRemotes, d)
                    elseif n:find("sell") or n:find("vendor") or n:find("shop") or n:find("trade") then
                        table.insert(S.SellRemotes, d)
                    end
                end
            end
        end)
        S.CacheLastRefresh = tick()
    end

    local function scanRobberyLocations()
        table.clear(S.RobberyCache)
        pcall(function()
            for _, obj in ipairs(Workspace:GetDescendants()) do
                if obj:IsA("Model") then
                    local n = obj.Name:lower()
                    if n:find("jewel") or n:find("case") or n:find("vault") or n:find("safe") or n:find("register") then
                        local part = obj.PrimaryPart or obj:FindFirstChildWhichIsA("BasePart")
                        if part then
                            table.insert(S.RobberyCache, {obj = obj, part = part})
                        end
                    end
                end
            end
        end)
        S.CacheLastRefresh = tick()
    end

    local function refreshSellerCache()
        S.SellerCache = nil
        pcall(function()
            for _, obj in ipairs(Workspace:GetDescendants()) do
                if obj:IsA("Model") or obj:IsA("BasePart") then
                    local n = obj.Name:lower()
                    if n:find("seller") or n:find("dealer") or n:find("vendor") or n:find("fence") then
                        S.SellerCache = obj.PrimaryPart or obj
                        break
                    end
                end
            end
        end)
    end

    -- ============================================================
    -- FLEE / PUNCH / SELL HELPERS
    -- ============================================================
    local function fleeNow(copRoot)
        local myRoot = getRoot()
        if not myRoot then return end
        local dir = Vector3.new(0, 0, 0)
        if copRoot then
            dir = (myRoot.Position - copRoot.Position).Unit
        else
            dir = myRoot.CFrame.LookVector * -1
        end
        local target = myRoot.Position + dir * S.SafeDistance
        tp(target)
        S.LastFleeTime = tick()
        S.FleeCount = S.FleeCount + 1
    end

    local function burstPunch(targetObj)
        for _, remote in ipairs(S.PunchRemotes) do
            pcall(function() remote:FireServer(targetObj) end)
            pcall(function() remote:FireServer() end)
        end
    end

    local function burstSell()
        for _, remote in ipairs(S.SellRemotes) do
            pcall(function() remote:FireServer() end)
        end
    end

    -- ============================================================
    -- TURBO ROB HEARTBEAT
    -- ============================================================
    local lastActionTime = 0
    local punchIndex = 1
    local ACTION_INTERVAL = 0.03

    local function runTurboRob()
        if tick() - lastActionTime < ACTION_INTERVAL then return end
        lastActionTime = tick()
        if not S.ACBypassDone then bypassAntiCheat(); return end
        if tick() - S.CacheLastRefresh > 5 then refreshRemotes() end

        local copDist, copRoot = getNearestCopDist()
        if copDist < S.FleeDistance then
            fleeNow(copRoot)
            S.RobState = "FLEEING"
            return
        end

        if S.RobState == "FLEEING" then
            if tick() - S.LastFleeTime < S.ResumeDelay then return end
            S.RobState = "IDLE"
        end

        if S.RobState == "IDLE" then
            if #S.RobberyCache == 0 then
                scanRobberyLocations()
                if #S.RobberyCache == 0 then return end
            end
            S.RobState = "ROBBING"
            punchIndex = 1
        elseif S.RobState == "ROBBING" then
            if punchIndex > #S.RobberyCache then
                S.LootCount = S.LootCount + 1
                notify("Auto-Rob", "Looted! (" .. S.LootCount .. ")", 2)
                refreshSellerCache()
                if S.SellerCache then S.RobState = "SELLING"
                else S.RobState = "IDLE"; table.clear(S.RobberyCache) end
                return
            end
            local entry = S.RobberyCache[punchIndex]
            if not entry or not entry.part or not entry.part.Parent then
                punchIndex = punchIndex + 1
                return
            end
            tp(entry.part.Position)
            burstPunch(entry.obj)
            punchIndex = punchIndex + 1
        elseif S.RobState == "SELLING" then
            if not S.SellerCache or not S.SellerCache.Parent then
                S.RobState = "IDLE"; table.clear(S.RobberyCache); return
            end
            tp(S.SellerCache.Position)
            burstSell()
            S.RobState = "IDLE"
            table.clear(S.RobberyCache)
            scanRobberyLocations()
        end
    end

    trk(RunService.Heartbeat:Connect(function()
        if S.Unloaded or not S.SmartRob then return end
        pcall(runTurboRob)
    end))

    -- ============================================================
    -- PC HOTKEYS
    -- ============================================================
    if IS_PC then
        trk(UIS.InputBegan:Connect(function(input, gpe)
            if gpe or S.Unloaded then return end
            if input.KeyCode == Enum.KeyCode.F then
                if tick() - S.LastManualFlee < 1 then return end
                S.LastManualFlee = tick()
                local copDist, copRoot = getNearestCopDist()
                if copRoot then fleeNow(copRoot); notify("Nicotine", "Flee (cop " .. math.floor(copDist) .. "m)", 2)
                else local mr = getRoot(); if mr then tp(mr.Position + Vector3.new(0, 0, S.SafeDistance)) end end
            end
        end))
        trk(UIS.InputBegan:Connect(function(input, gpe)
            if gpe or S.Unloaded then return end
            if input.UserInputType == Enum.UserInputType.MouseButton2 then
                if S.SmartRob then S.SmartRob = false; S.RobState = "IDLE"; notify("Nicotine", "STOP", 2) end
            end
        end))
        trk(UIS.InputBegan:Connect(function(input, gpe)
            if gpe or S.Unloaded then return end
            if input.KeyCode == Enum.KeyCode.R then
                S.SmartRob = not S.SmartRob
                if S.SmartRob then
                    if not bypassAntiCheat() then S.SmartRob = false; return end
                    scanRobberyLocations(); refreshRemotes(); S.RobState = "IDLE"
                    notify("Nicotine", "Turbo Rob ON (R)", 2)
                else
                    S.RobState = "IDLE"; notify("Nicotine", "Turbo Rob OFF (R)", 2)
                end
            end
        end))
        trk(UIS.InputBegan:Connect(function(input, gpe)
            if gpe or S.Unloaded then return end
            if input.KeyCode == Enum.KeyCode.X then
                S.ESP = not S.ESP; notify("Nicotine", "ESP " .. (S.ESP and "ON" or "OFF"), 2)
            end
        end))
        trk(UIS.InputBegan:Connect(function(input, gpe)
            if gpe or S.Unloaded then return end
            if input.KeyCode == Enum.KeyCode.P then
                saveLocation("Loc" .. math.floor(tick() % 1000))
            end
        end))
        trk(UIS.InputBegan:Connect(function(input, gpe)
            if gpe or S.Unloaded then return end
            if input.KeyCode == Enum.KeyCode.T then
                local keys = {}
                for k in pairs(S.SavedLocations) do table.insert(keys, k) end
                if #keys > 0 then teleportToLocation(keys[1]) end
            end
        end))
    end

    -- ============================================================
    -- STAMINA
    -- ============================================================
    local function enableInfStamina()
        if not S.StaminaModule then
            local ok, result = pcall(function()
                local c = LP.PlayerScripts:FindFirstChild("Code")
                if not c then return nil end
                c = c:FindFirstChild("controllers")
                if not c then return nil end
                local ch = c:FindFirstChild("character")
                if not ch then return nil end
                local m = ch:FindFirstChild("characterStaminaController")
                if not m then return nil end
                return require(m)
            end)
            if not ok or not result then return false end
            S.StaminaModule = result
        end
        local cc = S.StaminaModule.CharacterStaminaController or S.StaminaModule
        if not cc or not cc.useStamina then return false end
        if not S.OriginalUseStamina then S.OriginalUseStamina = cc.useStamina end
        if hasHook then
            pcall(function() hookfunction(cc.useStamina, function() return true end) end)
        end
        return true
    end

    local function disableInfStamina()
        if S.OriginalUseStamina and S.StaminaModule and hasHook then
            local cc = S.StaminaModule.CharacterStaminaController or S.StaminaModule
            if cc and cc.useStamina then
                pcall(function() hookfunction(cc.useStamina, S.OriginalUseStamina) end)
            end
        end
    end

    -- ============================================================
    -- ESP
    -- ============================================================
    local espObjects = {}
    local function cleanESP()
        for _, d in pairs(espObjects) do
            if d.h then pcall(function() d.h:Destroy() end) end
            if d.b then pcall(function() d.b:Destroy() end) end
        end
        espObjects = {}
    end

    trk(RunService.Heartbeat:Connect(function()
        if S.Unloaded then return end
        if not S.ESP then
            if next(espObjects) then cleanESP() end
            return
        end
        for _, p in ipairs(Players:GetPlayers()) do
            if p == LP then
                -- skip self
            else
                local char = p.Character
                if char then
                    local role = getRole(p)
                    local show, color = false, Color3.new(1, 1, 1)
                    if role == "cop" and S.ESPCops then show = true; color = Color3.fromRGB(80, 160, 255) end
                    if role == "criminal" and S.ESPCriminals then show = true; color = Color3.fromRGB(255, 80, 80) end
                    if show then
                        if not espObjects[char] then
                            local h = Instance.new("Highlight")
                            h.Adornee = char; h.FillColor = color; h.FillTransparency = 0.55
                            h.OutlineColor = Color3.new(1, 1, 1)
                            h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                            h.Parent = char
                            local root = char:FindFirstChild("HumanoidRootPart")
                            local b
                            if root then
                                b = Instance.new("BillboardGui")
                                b.Adornee = root; b.Size = UDim2.new(0, 200, 0, 40)
                                b.StudsOffset = Vector3.new(0, 3, 0); b.AlwaysOnTop = true; b.Parent = char
                                local lbl = Instance.new("TextLabel")
                                lbl.Size = UDim2.new(1, 0, 1, 0); lbl.BackgroundTransparency = 1
                                lbl.TextColor3 = color; lbl.TextStrokeTransparency = 0
                                lbl.Font = Enum.Font.GothamBold; lbl.Text = p.DisplayName
                                lbl.Parent = b
                            end
                            espObjects[char] = {h = h, b = b}
                        end
                    elseif espObjects[char] then
                        pcall(function() espObjects[char].h:Destroy() end)
                        pcall(function() if espObjects[char].b then espObjects[char].b:Destroy() end end)
                        espObjects[char] = nil
                    end
                end
            end
        end
    end))

    -- ============================================================
    -- MISC HEARTBEAT
    -- ============================================================
    trk(RunService.Heartbeat:Connect(function()
        if S.Unloaded then return end
        if S.InfStamina then enableInfStamina() end
        if S.GodMode then
            local h = getHum()
            if h and h.Health < h.MaxHealth then pcall(function() h.Health = h.MaxHealth end) end
        end
        if S.AntiVoid then
            local r = getRoot()
            if r and r.Position.Y < -100 then
                local s = Workspace:FindFirstChildOfClass("SpawnLocation")
                r.CFrame = s and (s.CFrame + Vector3.new(0, 5, 0)) or CFrame.new(0, 50, 0)
            end
        end
        if S.WalkSpeedOn then
            local h = getHum(); if h then h.WalkSpeed = S.WalkSpeed end
        end
        if S.JumpPowerOn then
            local h = getHum(); if h then pcall(function() h.UseJumpPower = true; h.JumpPower = S.JumpPower end) end
        end
        if S.Noclip then
            local c = getChar()
            if c then for _, p in ipairs(c:GetDescendants()) do
                if p:IsA("BasePart") then p.CanCollide = false end
            end end
        end
        if S.Fullbright then
            if not S._fullbrightApplied then
                pcall(function()
                    Lighting.Ambient = Color3.fromRGB(255, 255, 255)
                    Lighting.OutdoorAmbient = Color3.fromRGB(255, 255, 255)
                    Lighting.Brightness = 3
                end)
                S._fullbrightApplied = true
            end
        elseif S._fullbrightApplied then
            pcall(function()
                Lighting.Ambient = S.OriginalLighting.Ambient
                Lighting.OutdoorAmbient = S.OriginalLighting.OutdoorAmbient
                Lighting.Brightness = S.OriginalLighting.Brightness
            end)
            S._fullbrightApplied = false
        end
        if S.NoFog then
            if not S._nofogApplied then
                pcall(function() Lighting.FogEnd = 100000; Lighting.FogStart = 0 end)
                S._nofogApplied = true
            end
        elseif S._nofogApplied then
            pcall(function()
                Lighting.FogEnd = S.OriginalLighting.FogEnd
                Lighting.FogStart = S.OriginalLighting.FogStart
            end)
            S._nofogApplied = false
        end
    end))

    trk(UIS.JumpRequest:Connect(function()
        if S.Unloaded or not S.InfJump then return end
        local h = getHum()
        if h then pcall(function() h:ChangeState(Enum.HumanoidStateType.Jumping) end) end
    end))

    task.spawn(function()
        while not S.Unloaded do
            task.wait(60)
            if S.AntiAFK and type(mousemoverel) == "function" then
                pcall(function() mousemoverel(0, 1); task.wait(0.05); mousemoverel(0, -1) end)
            end
        end
    end)

    trk(Players.PlayerAdded:Connect(function(p)
        if not S.AdminDetector then return end
        local n = p.Name:lower()
        if n:find("admin") or n:find("moderator") or n:find("_mod") or n:find("official") then
            notify("Possible Staff", p.DisplayName, 8)
        end
    end))

    refreshRemotes()
    scanRobberyLocations()

    -- ============================================================
    -- UI
    -- ============================================================
    local Window = Rayfield:CreateWindow({
        Name = "Nicotine",
        LoadingTitle = "Nicotine",
        LoadingSubtitle = "Turbo Auto-Rob | " .. PLATFORM,
        ConfigurationSaving = {Enabled = true, FolderName = "NicotineEH", FileName = "Config"},
        KeySystem = false,
        ToggleUIKeybind = "K"
    })

    -- ===== AUTO-ROB TAB =====
    local RobTab = Window:CreateTab("Auto-Rob", 4483362458)
    RobTab:CreateSection("Turbo Robbery")
    RobTab:CreateToggle({
        Name = "TURBO AUTO-ROB (Jeweler → Sell → Flee)",
        CurrentValue = false, Flag = "SmartRobFlag",
        Callback = function(v)
            S.SmartRob = v
            if v then
                if not bypassAntiCheat() then
                    notify("Nicotine", "AC bypass failed", 4)
                    S.SmartRob = false
                    return
                end
                scanRobberyLocations(); refreshRemotes(); S.RobState = "IDLE"
                notify("Auto-Rob", "Turbo Rob ON", 2)
            else
                S.RobState = "IDLE"
                notify("Auto-Rob", "Turbo Rob OFF", 2)
            end
        end
    })

    if IS_PC then
        RobTab:CreateSection("PC Hotkeys")
        RobTab:CreateParagraph({Title = "Shortcuts",
            Content = "R = Turbo Rob\nF = Flee\nX = ESP\nP = Save Location\nT = Teleport to first saved"})
    else
        RobTab:CreateSection("Mobile Controls")
        RobTab:CreateButton({Name = "🚨 QUICK FLEE", Callback = function()
            local cd, cr = getNearestCopDist()
            if cr then fleeNow(cr); notify("Nicotine", "Flee! " .. math.floor(cd) .. "m", 2) end
        end})
        RobTab:CreateButton({Name = "🚨 QUICK STOP", Callback = function()
            S.SmartRob = false; S.RobState = "IDLE"; notify("Nicotine", "STOPPED", 2)
        end})
    end

    RobTab:CreateSection("Flee")
    RobTab:CreateSlider({Name = "Flee Distance", Range = {40, 300}, Increment = 10, Suffix = "studs",
        CurrentValue = 120, Flag = "FleeDistFlag", Callback = function(v) S.FleeDistance = v end})
    RobTab:CreateSlider({Name = "Safe Distance", Range = {200, 800}, Increment = 25, Suffix = "studs",
        CurrentValue = 400, Flag = "SafeDistFlag", Callback = function(v) S.SafeDistance = v end})
    RobTab:CreateSlider({Name = "Resume Delay", Range = {3, 20}, Increment = 1, Suffix = "s",
        CurrentValue = 6, Flag = "ResumeFlag", Callback = function(v) S.ResumeDelay = v end})

    RobTab:CreateSection("Manual Cache")
    RobTab:CreateButton({Name = "Rescan Locations", Callback = function()
        scanRobberyLocations(); notify("Auto-Rob", "Found " .. #S.RobberyCache .. " cases", 2)
    end})
    RobTab:CreateButton({Name = "Rescan Remotes", Callback = function()
        refreshRemotes(); notify("Auto-Rob", "P:" .. #S.PunchRemotes .. " S:" .. #S.SellRemotes, 3)
    end})

    local statusLabel = RobTab:CreateParagraph({Title = "Status", Content = "IDLE"})
    task.spawn(function()
        while not S.Unloaded do
            task.wait(0.5)
            pcall(function()
                statusLabel:Set({
                    Title = "Status (" .. PLATFORM .. ")",
                    Content = string.format("State: %s | Loot: %d | Flees: %d | Cases: %d | Punch: %d | Sell: %d",
                        S.RobState, S.LootCount, S.FleeCount, #S.RobberyCache, #S.PunchRemotes, #S.SellRemotes)
                })
            end)
        end
    end)

    -- ===== MAIN TAB =====
    local MainTab = Window:CreateTab("Main", 4483362458)
    MainTab:CreateSection("Anti-Cheat")
    MainTab:CreateToggle({Name = "Anti-Cheat Bypass", CurrentValue = false, Flag = "ACBypassFlag",
        Callback = function(v) if v then bypassAntiCheat() end end})
    MainTab:CreateButton({Name = "Re-run AC Bypass",
        Callback = function() S.ACBypassDone = false; bypassAntiCheat() end})

    MainTab:CreateSection("Invisibility")
    MainTab:CreateToggle({Name = "Invisible", CurrentValue = false, Flag = "InvisFlag",
        Callback = function(v) setInvisible(v) end})

    MainTab:CreateSection("Saved Locations")
    MainTab:CreateInput({Name = "Location Name", PlaceholderText = "MyBase",
        CurrentValue = "MyBase", Flag = "SaveLocNameFlag", RemoveTextAfterFocusLost = false,
        Callback = function(txt) S.TempSaveName = txt end})
    MainTab:CreateButton({Name = "Save Current Location", Callback = function()
        saveLocation(S.TempSaveName or "Default")
    end})
    MainTab:CreateButton({Name = "Teleport to Saved", Callback = function()
        teleportToLocation(S.TempSaveName or "Default")
    end})

    MainTab:CreateSection("Vehicle")
    MainTab:CreateButton({Name = "Bring My Car", Callback = function() bringOwnCar() end})
    MainTab:CreateButton({Name = "Enter My Car", Callback = function() enterOwnCar() end})

    MainTab:CreateSection("Anti-Detection")
    MainTab:CreateToggle({Name = "Anti-Arrest", CurrentValue = false, Flag = "AntiArrestFlag",
        Callback = function(v) S.AntiArrest = v end})
    MainTab:CreateToggle({Name = "Anti-Taser", CurrentValue = false, Flag = "AntiTaserFlag",
        Callback = function(v) S.AntiTaser = v end})
    MainTab:CreateToggle({Name = "Anti-Downed", CurrentValue = false, Flag = "AntiDownedFlag",
        Callback = function(v) S.AntiDowned = v end})
    MainTab:CreateToggle({Name = "Anti-Fall Damage", CurrentValue = false, Flag = "AntiFallFlag",
        Callback = function(v) S.AntiFall = v end})
    MainTab:CreateToggle({Name = "Anti-Void", CurrentValue = false, Flag = "AntiVoidFlag",
        Callback = function(v) S.AntiVoid = v end})
    MainTab:CreateToggle({Name = "God Mode", CurrentValue = false, Flag = "GodModeFlag",
        Callback = function(v) S.GodMode = v end})
    MainTab:CreateToggle({Name = "Anti-AFK", CurrentValue = false, Flag = "AntiAFKFlag",
        Callback = function(v) S.AntiAFK = v end})

    MainTab:CreateSection("Auto-Farm Money")
    MainTab:CreateToggle({Name = "Auto-Farm (Truck/Bus)", CurrentValue = false, Flag = "AutoFarmFlag",
        Callback = function(v) S.AutoFarmMoney = v end})
    MainTab:CreateToggle({Name = "Auto-Respawn on Low HP", CurrentValue = false, Flag = "AutoRespawnFlag",
        Callback = function(v) S.AutoRespawn = v end})

    MainTab:CreateSection("Stamina")
    MainTab:CreateToggle({Name = "Infinite Stamina", CurrentValue = false, Flag = "InfStaminaFlag",
        Callback = function(v) S.InfStamina = v; if v then enableInfStamina() else disableInfStamina() end end})

    -- ===== VISUAL TAB =====
    local VisualTab = Window:CreateTab("Visual", 4483362458)
    VisualTab:CreateToggle({Name = "Enable ESP", CurrentValue = false, Flag = "ESPFlag",
        Callback = function(v) S.ESP = v; if not v then cleanESP() end end})
    VisualTab:CreateToggle({Name = "Show Cops", CurrentValue = true, Flag = "ESPCopsFlag",
        Callback = function(v) S.ESPCops = v end})
    VisualTab:CreateToggle({Name = "Show Criminals", CurrentValue = true, Flag = "ESPCrimsFlag",
        Callback = function(v) S.ESPCriminals = v end})
    VisualTab:CreateToggle({Name = "Fullbright", CurrentValue = false, Flag = "BrightFlag",
        Callback = function(v) S.Fullbright = v end})
    VisualTab:CreateToggle({Name = "No Fog", CurrentValue = false, Flag = "NoFogFlag",
        Callback = function(v) S.NoFog = v end})

    -- ===== PLAYER TAB =====
    local PlayerTab = Window:CreateTab("Player", 4483362458)
    PlayerTab:CreateToggle({Name = "Walk Speed", CurrentValue = false, Flag = "WSOnFlag",
        Callback = function(v)
            S.WalkSpeedOn = v
            if not v then local h = getHum(); if h then h.WalkSpeed = S.DefaultWalkSpeed end end
        end})
    PlayerTab:CreateSlider({Name = "Speed Value", Range = {16, 200}, Increment = 1, Suffix = "studs",
        CurrentValue = 16, Flag = "WSValueFlag", Callback = function(v) S.WalkSpeed = v end})
    PlayerTab:CreateToggle({Name = "Infinite Jump", CurrentValue = false, Flag = "InfJumpFlag",
        Callback = function(v) S.InfJump = v end})
    PlayerTab:CreateToggle({Name = "Noclip", CurrentValue = false, Flag = "NoclipFlag",
        Callback = function(v) S.Noclip = v end})

    -- ===== MISC TAB =====
    local MiscTab = Window:CreateTab("Misc", 4483362458)
    MiscTab:CreateToggle({Name = "Chat Spy", CurrentValue = false, Flag = "ChatSpyFlag",
        Callback = function(v) S.ChatSpy = v end})
    MiscTab:CreateToggle({Name = "Admin Detector", CurrentValue = false, Flag = "AdminDetFlag",
        Callback = function(v) S.AdminDetector = v end})

    -- ===== INFO TAB =====
    local InfoTab = Window:CreateTab("Info", 4483362458)
    InfoTab:CreateParagraph({Title = "Nicotine Turbo Auto-Rob", Content = "Emergency Hamburg | Shaw#6000"})
    InfoTab:CreateParagraph({Title = "Platform", Content = "Detected: " .. PLATFORM})
    InfoTab:CreateParagraph({Title = "WARNING", Content = "Use an alt account."})

    print("[NICOTINE] Loaded on " .. PLATFORM)
    notify("Nicotine", "Loaded! " .. PLATFORM .. ". Press K.", 5)
end

local ok, err = pcall(main)
if not ok then
    warn("[NICOTINE] FATAL: " .. tostring(err))
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "Nicotine CRASH", Text = tostring(err):sub(0, 120), Duration = 15
        })
    end)
end
