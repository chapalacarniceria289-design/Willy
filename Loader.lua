-- ==========================================
-- WILLY HUB | Loader con ventana de key
-- La key se liga al HWID del primer jugador que la usa (lo valida el servidor)
-- ==========================================
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local LocalPlayer = Players.LocalPlayer
local playerGui = LocalPlayer:WaitForChild("PlayerGui")

-- IMPORTANTE: cambia por la URL PUBLICADA de tu web cuando la publiques
local ENDPOINT = "https://keygarden-access-hub.lovable.app/api/public/validate"
local SAVE_FILE = "willyhub_key.txt"
local req = (syn and syn.request) or http_request or request
local DEBUG = true -- muestra la respuesta cruda del servidor; ponlo en false al terminar
local lastRaw = ""

-- Script de Willy Hub (se usa si el servidor no manda uno en data.script)
local WILLY_SCRIPT = [==[
-- Willy Hub Premium (Soft Aim Movil, Chams, Farm Hop)
local success, err = pcall(function()
    local Players    = game:GetService("Players")
    local RunService = game:GetService("RunService")
    local HttpService = game:GetService("HttpService")
    local Workspace  = game:GetService("Workspace")
    local UserInput  = game:GetService("UserInputService")
    local Lighting   = game:GetService("Lighting")
    local SoundService = game:GetService("SoundService")
    local LP = Players.LocalPlayer
    local CAM = Workspace.CurrentCamera
    local PG = LP:WaitForChild("PlayerGui")

    -- 1. MÚSICA DE INICIO (5 SEGUNDOS)
    local introSound = Instance.new("Sound")
    introSound.Name = "WillyHubIntro"
    introSound.SoundId = "rbxassetid://11265148479"
    introSound.Volume = 1
    introSound.Parent = SoundService
    introSound:Play()
    task.delay(5, function() if introSound then introSound:Stop(); introSound:Destroy() end end)

    local function safeHttpGet(url, timeout)
        timeout = timeout or 6; local result, done = nil, false
        task.spawn(function() local ok, res = pcall(function() return game:HttpGet(url) end); if ok and res and res ~= "" then result = res end; done = true end)
        local t0 = tick(); while not done and (tick() - t0) < timeout do task.wait(0.1) end; return result
    end

    local WindUI = _G.WindUI
    if not WindUI then
        local url = "https://github.com/Footagesus/WindUI/releases/latest/download/main.lua"
        local src = safeHttpGet(url, 8)
        if src then local fn = loadstring(src); if fn then local ok, res = pcall(fn); if ok and res then WindUI = res; _G.WindUI = res end end end
    end
    if not WindUI then error("No se pudo cargar WindUI") end

    local S = {
        aim_enabled=false, aim_smooth=0.18, aim_fov=180, aim_part="Head", fov_visible=true,
        esp_enabled=false, esp_names=true, esp_health=true, esp_weapons=true, esp_distance=true, esp_chams=true,
        jump_power=50, walk_speed=16, noclip=false, hide_name=false,
        fly_enabled=false, fly_speed=50, fps_boost=false, inf_ammo=false,
        gun_color = "Gris", gun_scope = "Ninguna", gun_barrel = "Ninguno",
        gun_grip = "Ninguna", gun_drum = "Ninguno", gun_laser = "Ninguno",
        selected_weapon = "Equipada"
    }

    local ORIGINAL_NAME = LP.DisplayName
    local noclipConn, hideNameConn, speedConn, flyConn, flyBodyVel, ammoConn

    local Window = WindUI:CreateWindow({
        Title = "Willy Hub Premium", Author = "ratman4080", Icon = "gamepad-2", Size = UDim2.fromOffset(550, 600), Theme = "Dark", ToggleKeybind = Enum.KeyCode.RightShift,
    })

    local CombatTab = Window:Tab({ Title = "Combat", Icon = "swords" })
    local VisualTab = Window:Tab({ Title = "Visual", Icon = "eye" })
    local PlayerTab = Window:Tab({ Title = "Player", Icon = "user" })
    local ServerTab = Window:Tab({ Title = "Server", Icon = "server" })
    local ConfigTab = Window:Tab({ Title = "Configuración", Icon = "settings" })
    local ShopTab = Window:Tab({ Title = "Gunsmith", Icon = "wrench" })

    local CS = CombatTab:Section({ Title = "Soft Aim (Magic Bullet)" })
    CS:Toggle({ Title = "Enable Soft Aim", Value = S.aim_enabled, Callback = function(v) S.aim_enabled = v end })
    CS:Slider({ Title = "Smoothness", Value = { Min = 0.01, Max = 1, Default = S.aim_smooth }, Callback = function(v) S.aim_smooth = v end })
    CS:Slider({ Title = "FOV Radius", Value = { Min = 30, Max = 500, Default = S.aim_fov }, Callback = function(v) S.aim_fov = v end })
    CS:Toggle({ Title = "Show FOV Circle", Value = S.fov_visible, Callback = function(v) S.fov_visible = v end })
    CS:Dropdown({ Title = "Aim Part", Values = { "Head", "HumanoidRootPart", "UpperTorso" }, Value = S.aim_part, Callback = function(v) S.aim_part = v end })

    -- FOV Circle
    local oldFov = PG:FindFirstChild("WindUI_FOV"); if oldFov then oldFov:Destroy() end
    local fovGui = Instance.new("ScreenGui"); fovGui.Name = "WindUI_FOV"; fovGui.ResetOnSpawn = false; fovGui.Parent = PG
    local fovCircle = Instance.new("Frame"); fovCircle.AnchorPoint = Vector2.new(0.5, 0.5); fovCircle.Position = UDim2.fromScale(0.5, 0.5); fovCircle.Size = UDim2.fromOffset(S.aim_fov*2, S.aim_fov*2); fovCircle.BackgroundTransparency = 1; fovCircle.Visible = false; fovCircle.Parent = fovGui
    Instance.new("UICorner", fovCircle).CornerRadius = UDim.new(1, 0)
    local st = Instance.new("UIStroke", fovCircle); st.Color = Color3.fromRGB(255,60,60); st.Thickness = 1.5
    RunService.RenderStepped:Connect(function() fovCircle.Size = UDim2.fromOffset(S.aim_fov*2, S.aim_fov*2); fovCircle.Visible = S.fov_visible and S.aim_enabled end)

    -- Soft Aim Mejorado (Apunta al enemigo más cercano sin importar si vuelas o corres)
    RunService.RenderStepped:Connect(function()
        if not S.aim_enabled then return end
        local center = CAM.ViewportSize / 2
        local bestTarget = nil
        local shortestDist = math.huge

        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP then
                local char = plr.Character
                if char then
                    local part = char:FindFirstChild(S.aim_part) or char:FindFirstChild("HumanoidRootPart")
                    if part then
                        local sp, onScreen = CAM:WorldToViewportPoint(part.Position)
                        if onScreen then
                            local dist = (Vector2.new(sp.X, sp.Y) - center).Magnitude
                            if dist < S.aim_fov and dist < shortestDist then
                                shortestDist = dist
                                bestTarget = part
                            end
                        end
                    end
                end
            end
        end

        if bestTarget then
            local goal = CFrame.lookAt(CAM.CFrame.Position, bestTarget.Position)
            CAM.CFrame = CAM.CFrame:Lerp(goal, math.clamp(1 - S.aim_smooth, 0.01, 1))
        end
    end)

    -------------------------------------------------------------------
    -- GUNSMITH
    -------------------------------------------------------------------
    local GSSec = ShopTab:Section({ Title = "Selector de Arma" })
    local function getWeaponsList()
        local list = {"Equipada"}; local char = LP.Character
        if char then for _, v in ipairs(char:GetChildren()) do if v:IsA("Tool") then table.insert(list, v.Name) end end end
        local backpack = LP:FindFirstChild("Backpack"); if backpack then for _, v in ipairs(backpack:GetChildren()) do if v:IsA("Tool") then table.insert(list, v.Name) end end end
        return list
    end

    local weaponDropdown = GSSec:Dropdown({ Title = "Elige el Arma", Values = getWeaponsList(), Value = "Equipada", Callback = function(v) S.selected_weapon = v end })
    LP.CharacterAdded:Connect(function() task.wait(1); if weaponDropdown then weaponDropdown:Refresh(getWeaponsList()) end end)

    local GSSec2 = ShopTab:Section({ Title = "Customización Visual" })
    GSSec2:Dropdown({ Title = "Color del Arma", Values = {"Gris", "Rojo", "Azul", "Verde", "Amarillo", "Morado", "Negro", "Blanco", "Oro"}, Value = "Gris", Callback = function(v) S.gun_color = v end })
    GSSec2:Dropdown({ Title = "Mira (Scope)", Values = {"Ninguna", "Reflex", "Red Dot", "Holo", "Sniper (10x)", "ACOG"}, Value = "Ninguna", Callback = function(v) S.gun_scope = v end })
    GSSec2:Dropdown({ Title = "Cañón / Silenciador", Values = {"Ninguno", "Silenciador", "Cañón Corto", "Freno de Boca"}, Value = "Ninguno", Callback = function(v) S.gun_barrel = v end })
    GSSec2:Dropdown({ Title = "Empuñadura (Grip)", Values = {"Ninguna", "Vertical", "Stubby", "Ergonomic"}, Value = "Ninguna", Callback = function(v) S.gun_grip = v end })
    GSSec2:Dropdown({ Title = "Tambor (Drum)", Values = {"Ninguno", "Tambor 45", "Tambor 60"}, Value = "Ninguno", Callback = function(v) S.gun_drum = v end })
    GSSec2:Dropdown({ Title = "Láser", Values = {"Ninguno", "Rojo", "Verde", "Azul"}, Value = "Ninguno", Callback = function(v) S.gun_laser = v end })

    GSSec2:Button({
        Title = "Añadir Accesorios",
        Callback = function()
            local char = LP.Character; if not char then return end
            local tool = nil
            if S.selected_weapon == "Equipada" then tool = char:FindFirstChildOfClass("Tool")
            else tool = char:FindFirstChild(S.selected_weapon); if not tool then local bp = LP:FindFirstChild("Backpack"); if bp then tool = bp:FindFirstChild(S.selected_weapon) end end end
            if not tool then WindUI:Notify({Title="Error", Content="No se encontró el arma", Duration=3}) return end
            local handle = tool:FindFirstChild("Handle"); if not handle then for _, p in ipairs(tool:GetChildren()) do if p:IsA("BasePart") then handle = p; break end end end
            if not handle then return end

            local function equipToAttachment(partName, part, attachmentName, fallbackOffset)
                local att = handle:FindFirstChild(attachmentName)
                part.Name = partName; part.Parent = tool; part.CanCollide = false; part.Massless = true
                local weld = Instance.new("Weld"); weld.Part0 = handle; weld.Part1 = part
                weld.C0 = (att and att:IsA("Attachment")) and att.CFrame or fallbackOffset; weld.Parent = part
            end
            
            for _, v in ipairs(tool:GetChildren()) do if v.Name:match("Wind_") then v:Destroy() end end
            
            local colorMap = {["Gris"] = Color3.fromRGB(163, 162, 165), ["Rojo"] = Color3.fromRGB(150, 0, 0), ["Azul"] = Color3.fromRGB(0, 0, 150), ["Verde"] = Color3.fromRGB(0, 150, 0), ["Amarillo"] = Color3.fromRGB(200, 180, 0), ["Morado"] = Color3.fromRGB(100, 0, 100), ["Negro"] = Color3.fromRGB(20, 20, 20), ["Blanco"] = Color3.fromRGB(240, 240, 240), ["Oro"] = Color3.fromRGB(180, 140, 20)}
            local chosenColor = colorMap[S.gun_color] or Color3.fromRGB(163, 162, 165)
            for _, part in ipairs(tool:GetDescendants()) do if part:IsA("BasePart") then part.Color = chosenColor; part.Material = Enum.Material.Plastic end end

            if S.gun_scope ~= "Ninguna" then
                local sight = Instance.new("Part"); sight.Size = Vector3.new(0.2, 0.2, 0.4); sight.Color = Color3.fromRGB(20, 20, 20); sight.Material = Enum.Material.Metal
                if S.gun_scope:match("Sniper") then sight.Size = Vector3.new(0.3, 0.3, 0.7) end
                equipToAttachment("Wind_Sight", sight, "ScopeAttachment", CFrame.new(0, 0.5, 0))
            end

            if S.gun_barrel ~= "Ninguno" then
                local barrel = Instance.new("Part"); barrel.Size = Vector3.new(0.25, 0.25, 0.8); barrel.Color = Color3.fromRGB(20, 20, 20); barrel.Material = Enum.Material.Metal
                if S.gun_barrel == "Silenciador" then barrel.Size = Vector3.new(0.35, 0.35, 1.2) end
                equipToAttachment("Wind_Barrel", barrel, "BarrelAttachment", CFrame.new(0, 0, -1))
                if S.gun_barrel == "Silenciador" then for _, sound in ipairs(tool:GetDescendants()) do if sound:IsA("Sound") then sound.Volume = 0.1; sound.PlaybackSpeed = 0.8 end end
                else for _, sound in ipairs(tool:GetDescendants()) do if sound:IsA("Sound") then sound.Volume = 1; sound.PlaybackSpeed = 1 end end end
            end

            if S.gun_grip ~= "Ninguna" then
                local grip = Instance.new("Part"); grip.Size = Vector3.new(0.2, 0.4, 0.2); grip.Color = Color3.fromRGB(40, 40, 40); grip.Material = Enum.Material.Plastic
                equipToAttachment("Wind_Grip", grip, "GripAttachment", CFrame.new(0, -0.4, 0))
            end

            if S.gun_drum ~= "Ninguno" then
                local drum = Instance.new("Part"); drum.Shape = Enum.PartType.Cylinder; drum.Size = Vector3.new(0.4, 0.6, 0.6); drum.Color = Color3.fromRGB(30, 30, 30); drum.Material = Enum.Material.Metal
                local ammoAmount = 45; if S.gun_drum == "Tambor 60" then drum.Size = Vector3.new(0.6, 0.8, 0.8); ammoAmount = 60 end
                equipToAttachment("Wind_Drum", drum, "MagAttachment", CFrame.new(0, -0.4, 0) * CFrame.Angles(0, 0, math.rad(90)))
                for _, v in pairs(tool:GetDescendants()) do if v:IsA("IntValue") or v:IsA("NumberValue") then local n = v.Name:lower(); if n:match("ammo") or n:match("clip") or n:match("mag") or n:match("max") or n:match("reserve") then pcall(function() v.Value = ammoAmount end) end end end
                for _, attr in ipairs(tool:GetAttributes()) do if type(attr) == "string" and (attr:lower():match("ammo") or attr:lower():match("clip") or attr:lower():match("mag") or attr:lower():match("max")) then pcall(function() tool:SetAttribute(attr, ammoAmount) end) end end
                WindUI:Notify({ Title = "Tambor", Content = "Cargador ajustado a " .. ammoAmount .. " balas.", Duration = 3 })
            end

            if S.gun_laser ~= "Ninguno" then
                local laser = Instance.new("Part"); laser.Size = Vector3.new(0.05, 0.05, 1); laser.Transparency = 0.3; laser.Material = Enum.Material.Neon
                if S.gun_laser == "Rojo" then laser.Color = Color3.fromRGB(255, 0, 0) elseif S.gun_laser == "Verde" then laser.Color = Color3.fromRGB(0, 255, 0) elseif S.gun_laser == "Azul" then laser.Color = Color3.fromRGB(0, 0, 255) end
                local light = Instance.new("PointLight", laser); light.Color = laser.Color; light.Range = 10; light.Brightness = 2
                equipToAttachment("Wind_Laser", laser, "UnderbarrelAttachment", CFrame.new(0, -0.3, -0.5))
            end
            WindUI:Notify({ Title = "Gunsmith", Content = "Accesorios aplicados a " .. tool.Name, Duration = 3 })
        end
    })

    GSSec2:Button({
        Title = "Restablecer Arma",
        Callback = function()
            local char = LP.Character; if not char then return end
            local tool = nil
            if S.selected_weapon == "Equipada" then tool = char:FindFirstChildOfClass("Tool")
            else tool = char:FindFirstChild(S.selected_weapon); if not tool then local bp = LP:FindFirstChild("Backpack"); if bp then tool = bp:FindFirstChild(S.selected_weapon) end end end
            if not tool then return end
            for _, v in ipairs(tool:GetDescendants()) do if v.Name:match("Wind_") then v:Destroy() end; if v:IsA("BasePart") then v.Color = Color3.fromRGB(163, 162, 165); v.Material = Enum.Material.Plastic end; if v:IsA("Sound") then v.Volume = 1; v.PlaybackSpeed = 1 end end
        end
    })

    -------------------------------------------------------------------
    -- VISUAL (CON CHAMS ROJO / SKELETON)
    -------------------------------------------------------------------
    local espList = {}
    local function clearESP() 
        for _, d in pairs(espList) do 
            if d.billboard then d.billboard:Destroy() end 
            if d.highlight then d.highlight:Destroy() end
        end
        espList = {} 
    end

    local VS = VisualTab:Section({ Title = "ESP" })
    VS:Toggle({ Title = "Enable ESP", Value = S.esp_enabled, Callback = function(v) S.esp_enabled = v; if not v then clearESP() end end })
    VS:Toggle({ Title = "Chams (Cuerpo Rojo)", Value = S.esp_chams, Callback = function(v) S.esp_chams = v end })
    VS:Toggle({ Title = "Names", Value = S.esp_names, Callback = function(v) S.esp_names = v end })
    VS:Toggle({ Title = "Health Bar", Value = S.esp_health, Callback = function(v) S.esp_health = v end })
    VS:Toggle({ Title = "Weapons (image only)", Value = S.esp_weapons, Callback = function(v) S.esp_weapons = v end })
    VS:Toggle({ Title = "Distance", Value = S.esp_distance, Callback = function(v) S.esp_distance = v end })

    local weaponIconCache = {}
    local function getWeaponIcon(name)
        if weaponIconCache[name] ~= nil then return weaponIconCache[name] end
        local id = nil; local ok, assetId = pcall(function() local url = ("https://catalog.roblox.com/v1/search/items/details?Keyword=%s&Category=1&Limit=1"):format(name); local data = HttpService:JSONDecode(game:HttpGet(url)); if data.data and data.data[1] then return data.data[1].id end end)
        if ok and assetId then id = ("rbxthumb://type=Asset&id=%d&w=150&h=150"):format(assetId) end; weaponIconCache[name] = id; return id
    end

    local function makeESP(plr, char)
        local head = char:FindFirstChild("Head"); if not head then return end
        
        -- Billboard (UI)
        local bb = Instance.new("BillboardGui", head)
        bb.Name = "WindESP_"..plr.Name; bb.Size = UDim2.fromOffset(200, 90); bb.AlwaysOnTop = true; bb.StudsOffset = Vector3.new(0, 2.6, 0)
        local holder = Instance.new("Frame", bb); holder.Size = UDim2.fromScale(1,1); holder.BackgroundTransparency = 1
        local ll = Instance.new("UIListLayout", holder); ll.Padding = UDim.new(0,2); ll.HorizontalAlignment = Enum.HorizontalAlignment.Center
        local name = Instance.new("TextLabel", holder); name.Size = UDim2.new(1,0,0,15); name.BackgroundTransparency = 1; name.Font = Enum.Font.GothamBold; name.TextSize = 12; name.TextColor3 = Color3.new(1,1,1); name.TextStrokeTransparency = 0.4; name.Text = plr.Name
        local dist = Instance.new("TextLabel", holder); dist.Size = UDim2.new(1,0,0,12); dist.BackgroundTransparency = 1; dist.Font = Enum.Font.Gotham; dist.TextSize = 10; dist.TextColor3 = Color3.fromRGB(200,200,210)
        local wepBox = Instance.new("Frame", holder); wepBox.Size = UDim2.fromOffset(42, 42); wepBox.BackgroundColor3 = Color3.fromRGB(240, 240, 245); wepBox.BorderSizePixel = 0; wepBox.Visible = false
        Instance.new("UICorner", wepBox).CornerRadius = UDim.new(0, 4)
        local wepStroke = Instance.new("UIStroke", wepBox); wepStroke.Color = Color3.fromRGB(255, 200, 120); wepStroke.Thickness = 1
        local wepImg = Instance.new("ImageLabel", wepBox); wepImg.Size = UDim2.new(1, -4, 1, -4); wepImg.Position = UDim2.new(0, 2, 0, 2); wepImg.BackgroundTransparency = 1; wepImg.Image = ""; wepImg.ScaleType = Enum.ScaleType.Fit
        local hpBack = Instance.new("Frame", holder); hpBack.Size = UDim2.new(0.75,0,0,6); hpBack.BackgroundColor3 = Color3.fromRGB(30,30,38); hpBack.BorderSizePixel = 0
        Instance.new("UICorner", hpBack).CornerRadius = UDim.new(0,3)
        local hpFill = Instance.new("Frame", hpBack); hpFill.Size = UDim2.new(1,0,1,0); hpFill.BackgroundColor3 = Color3.fromRGB(80,220,120); hpFill.BorderSizePixel = 0
        Instance.new("UICorner", hpFill).CornerRadius = UDim.new(0,3)

        -- Highlight (Chams)
        local hl = Instance.new("Highlight", char)
        hl.Name = "WindHL_"..plr.Name
        hl.FillColor = Color3.fromRGB(255, 0, 0)
        hl.FillTransparency = 0.5
        hl.OutlineColor = Color3.fromRGB(255, 0, 0)
        hl.OutlineTransparency = 0
        hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop

        return { billboard=bb, name=name, dist=dist, wepBox=wepBox, wepImg=wepImg, hpBack=hpBack, hpFill=hpFill, highlight=hl, lastWep=nil }
    end

    local function updateESP()
        if not S.esp_enabled then return end
        for _, plr in ipairs(Players:GetPlayers()) do
            if plr ~= LP then
                local char = plr.Character; local head = char and char:FindFirstChild("Head")
                if head then
                    if not head:FindFirstChild("WindESP_"..plr.Name) then espList[plr] = makeESP(plr, char) end
                    local d = espList[plr]
                    if d then
                        local hrp = char:FindFirstChild("HumanoidRootPart"); local dist = hrp and math.floor((hrp.Position - CAM.CFrame.Position).Magnitude) or 0
                        d.name.Visible = S.esp_names; d.dist.Visible = S.esp_distance; d.hpBack.Visible = S.esp_health; d.dist.Text = ("%d m"):format(dist)
                        
                        if d.highlight then
                            d.highlight.Enabled = S.esp_chams
                        end
                        
                        local hum = char:FindFirstChildOfClass("Humanoid")
                        if hum then local t = hum.Health / hum.MaxHealth; d.hpFill.Size = UDim2.new(t,0,1,0); d.hpFill.BackgroundColor3 = Color3.fromRGB(math.floor(255*(1-t)), math.floor(80+140*t), 80) end
                        local tool = char:FindFirstChildOfClass("Tool")
                        if tool and S.esp_weapons then
                            local img = tool.TextureId
                            if not img or img == "" then local bp = plr:FindFirstChild("Backpack"); local bpt = bp and bp:FindFirstChild(tool.Name); if bpt and bpt.TextureId ~= "" then img = bpt.TextureId end end
                            if not img or img == "" then img = getWeaponIcon(tool.Name) or "" end
                            if img ~= "" then d.wepBox.Visible = true; d.wepImg.Image = img else d.wepBox.Visible = false end
                        else d.wepBox.Visible = false end
                    end
                end
            end
        end
    end

    Players.PlayerRemoving:Connect(function(p) if espList[p] and espList[p].billboard then espList[p].billboard:Destroy() end; if espList[p] and espList[p].highlight then espList[p].highlight:Destroy() end; espList[p] = nil end)
    RunService.RenderStepped:Connect(function() if not S.esp_enabled then clearESP() return end; updateESP() end)

    -------------------------------------------------------------------
    -- PLAYER
    -------------------------------------------------------------------
    local PS = PlayerTab:Section({ Title = "Movement" })
    PS:Slider({ Title = "Jump Power (0-100)", Value = { Min = 0, Max = 100, Default = S.jump_power }, Callback = function(v) S.jump_power = v end })
    PS:Slider({ Title = "Walk Speed (0-100)", Value = { Min = 0, Max = 100, Default = S.walk_speed }, Callback = function(v) S.walk_speed = v end })
    PS:Toggle({ Title = "Noclip", Value = S.noclip, Callback = function(v)
        S.noclip = v; if v then if not noclipConn then noclipConn = RunService.Stepped:Connect(function() local c = LP.Character; if c then for _, p in ipairs(c:GetDescendants()) do if p:IsA("BasePart") then p.CanCollide = false end end end end) end else if noclipConn then noclipConn:Disconnect(); noclipConn = nil end end
    end })

    PS:Toggle({ Title = "Hide Name (shiesty)", Value = S.hide_name, Callback = function(v)
        S.hide_name = v
        if v then if not hideNameConn then hideNameConn = task.spawn(function()
            while S.hide_name do
                local nums = tostring(math.random(100000, 999999)); local letters = ""; for i = 1, 6 do letters = letters .. string.char(math.random(65, 90)) end; local fakeName = letters .. " " .. nums
                pcall(function() LP.DisplayName = fakeName end)
                local char = LP.Character; local head = char and char:FindFirstChild("Head")
                if head then
                    local realNameGui = head:FindFirstChild("WindESP_" .. LP.Name); if realNameGui then realNameGui.Enabled = false end
                    local hum = char:FindFirstChildOfClass("Humanoid"); if hum then hum.DisplayName = fakeName end
                    local cover = head:FindFirstChild("WindUI_Cover")
                    if not cover then cover = Instance.new("BillboardGui", head); cover.Name = "WindUI_Cover"; cover.Size = UDim2.fromOffset(250, 40); cover.AlwaysOnTop = true; cover.StudsOffset = Vector3.new(0, 2.1, 0)
                        local f = Instance.new("Frame", cover); f.Size = UDim2.fromScale(1, 1); f.BackgroundColor3 = Color3.fromRGB(30, 30, 35); f.BackgroundTransparency = 0; Instance.new("UICorner", f).CornerRadius = UDim.new(0, 4)
                        local lbl = Instance.new("TextLabel", f); lbl.Name = "Tag"; lbl.Size = UDim2.fromScale(1, 1); lbl.BackgroundTransparency = 1; lbl.Font = Enum.Font.GothamBold; lbl.TextSize = 14; lbl.TextColor3 = Color3.fromRGB(255, 60, 60); lbl.TextStrokeTransparency = 0.3
                    end; cover.Frame.Tag.Text = fakeName
                end; task.wait(0.15)
            end
        end) end else
            S.hide_name = false; local char = LP.Character; if char then local head = char:FindFirstChild("Head"); if head then local cover = head:FindFirstChild("WindUI_Cover"); if cover then cover:Destroy() end; local rng = head:FindFirstChild("WindESP_" .. LP.Name); if rng then rng.Enabled = true end end; local hum = char:FindFirstChildOfClass("Humanoid"); if hum then hum.DisplayName = ORIGINAL_NAME end end; pcall(function() LP.DisplayName = ORIGINAL_NAME end)
        end
    end })

    PS:Section({ Title = "Combat Extras" })
    PS:Toggle({ Title = "Balas Infinitas (Ammo)", Value = S.inf_ammo, Callback = function(v)
        S.inf_ammo = v; if v then if not ammoConn then ammoConn = RunService.Heartbeat:Connect(function()
            if not S.inf_ammo then return end; local char = LP.Character; if not char then return end; local tool = char:FindFirstChildOfClass("Tool"); if not tool then return end
            for _, v in pairs(tool:GetDescendants()) do if v:IsA("IntValue") or v:IsA("NumberValue") then if v.Name:lower():match("ammo") or v.Name:lower():match("clip") or v.Name:lower():match("mag") or v.Name == "Value" then v.Value = 999 end end end
        end) end else if ammoConn then ammoConn:Disconnect(); ammoConn = nil end end
    end })

    speedConn = RunService.Heartbeat:Connect(function()
        local c = LP.Character; if not c then return end; local hum = c:FindFirstChildOfClass("Humanoid"); if not hum then return end; local hrp = c:FindFirstChild("HumanoidRootPart"); if not hrp then return end
        hum.UseJumpPower = true; local targetJump = 50 + (S.jump_power/100)*450; local targetSpeed = 16 + (S.walk_speed/100)*184
        if math.abs(hum.JumpPower - targetJump) > 0.1 then hum.JumpPower = targetJump end
        if not S.fly_enabled then if math.abs(hum.WalkSpeed - targetSpeed) > 0.1 then hum.WalkSpeed = targetSpeed end; if S.walk_speed > 20 and hum.MoveDirection.Magnitude > 0 then local cv = hrp.AssemblyLinearVelocity; local mv = hum.MoveDirection * targetSpeed; hrp.AssemblyLinearVelocity = Vector3.new(mv.X, cv.Y, mv.Z) end end
    end)

    LP.CharacterAdded:Connect(function(char) task.wait(0.5); local hum = char:WaitForChild("Humanoid", 5); if hum then hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function() if S.fly_enabled then return end; local target = 16 + (S.walk_speed/100)*184; if math.abs(hum.WalkSpeed - target) > 0.1 then hum.WalkSpeed = target end end) end end)

    local oldFly = PG:FindFirstChild("WindUI_Fly"); if oldFly then oldFly:Destroy() end
    local flyGui = Instance.new("ScreenGui", PG); flyGui.Name = "WindUI_Fly"; flyGui.ResetOnSpawn = false; flyGui.IgnoreGuiInset = true
    local flyFrame = Instance.new("Frame", flyGui); flyFrame.Size = UDim2.fromOffset(140, 90); flyFrame.Position = UDim2.new(0, 20, 0, 20); flyFrame.BackgroundColor3 = Color3.fromRGB(18, 18, 24); flyFrame.BorderSizePixel = 0
    Instance.new("UICorner", flyFrame).CornerRadius = UDim.new(0, 8)
    local flyStroke = Instance.new("UIStroke", flyFrame); flyStroke.Color = Color3.fromRGB(120, 90, 255)
    local dragging, dragStart, startPos
    flyFrame.InputBegan:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = true; dragStart = input.Position; startPos = flyFrame.Position end end)
    UserInput.InputChanged:Connect(function(input) if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then local delta = input.Position - dragStart; flyFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y) end end)
    UserInput.InputEnded:Connect(function(input) if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end end)
    local flyTitle = Instance.new("TextLabel", flyFrame); flyTitle.Size = UDim2.new(1, 0, 0, 20); flyTitle.BackgroundTransparency = 1; flyTitle.Font = Enum.Font.GothamBold; flyTitle.TextSize = 12; flyTitle.TextColor3 = Color3.new(1,1,1); flyTitle.Text = "FLY MENU"
    local flyBtn = Instance.new("TextButton", flyFrame); flyBtn.Size = UDim2.new(1, -20, 0, 30); flyBtn.Position = UDim2.new(0, 10, 0, 25); flyBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75); flyBtn.BorderSizePixel = 0; flyBtn.Font = Enum.Font.GothamBold; flyBtn.TextSize = 12; flyBtn.TextColor3 = Color3.new(1,1,1); flyBtn.Text = "Fly: OFF"
    Instance.new("UICorner", flyBtn).CornerRadius = UDim.new(0, 6)
    local flySpeedSlider = Instance.new("TextButton", flyFrame); flySpeedSlider.Size = UDim2.new(1, -20, 0, 20); flySpeedSlider.Position = UDim2.new(0, 10, 0, 60); flySpeedSlider.BackgroundColor3 = Color3.fromRGB(40, 40, 50); flySpeedSlider.BorderSizePixel = 0; flySpeedSlider.Font = Enum.Font.Gotham; flySpeedSlider.TextSize = 10; flySpeedSlider.TextColor3 = Color3.fromRGB(200,200,200); flySpeedSlider.Text = "Speed: 50"
    Instance.new("UICorner", flySpeedSlider).CornerRadius = UDim.new(0, 4)
    flySpeedSlider.MouseButton1Click:Connect(function() local speeds = {20, 50, 80, 120, 200}; local idx = 1; for i, v in ipairs(speeds) do if v == S.fly_speed then idx = i; break end end; idx = (idx % #speeds) + 1; S.fly_speed = speeds[idx]; flySpeedSlider.Text = "Speed: " .. S.fly_speed end)
    local function stopFly() if flyConn then flyConn:Disconnect(); flyConn = nil end; if flyBodyVel then flyBodyVel:Destroy(); flyBodyVel = nil end; local char = LP.Character; if char then local hrp = char:FindFirstChild("HumanoidRootPart"); local hum = char:FindFirstChildOfClass("Humanoid"); if hrp then hrp.AssemblyLinearVelocity = Vector3.zero end; if hum then pcall(function() hum.PlatformStand = false; hum:ChangeState(Enum.HumanoidStateType.GettingUp) end) end end end
    flyBtn.MouseButton1Click:Connect(function()
        S.fly_enabled = not S.fly_enabled
        if S.fly_enabled then
            flyBtn.Text = "Fly: ON"; flyBtn.BackgroundColor3 = Color3.fromRGB(120, 90, 255)
            local char = LP.Character; if not char then return end; local hrp = char:FindFirstChild("HumanoidRootPart"); local hum = char:FindFirstChildOfClass("Humanoid"); if not hrp or not hum then return end
            pcall(function() hum.PlatformStand = false; hum:ChangeState(Enum.HumanoidStateType.Physics) end)
            flyBodyVel = Instance.new("BodyVelocity", hrp); flyBodyVel.MaxForce = Vector3.new(math.huge, math.huge, math.huge); flyBodyVel.Velocity = Vector3.zero
            flyConn = RunService.Heartbeat:Connect(function()
                if not S.fly_enabled then return end; local c = LP.Character; if not c then return end; local r = c:FindFirstChild("HumanoidRootPart"); if not r then return end; local h = c:FindFirstChildOfClass("Humanoid"); if not h then return end
                pcall(function() if h:GetState() ~= Enum.HumanoidStateType.Physics then h:ChangeState(Enum.HumanoidStateType.Physics) end end)
                local camCF = CAM.CFrame; local speed = S.fly_speed * 2; local forward, right = 0, 0
                if UserInput:IsKeyDown(Enum.KeyCode.W) or UserInput:IsKeyDown(Enum.KeyCode.Up) then forward = forward + 1 end; if UserInput:IsKeyDown(Enum.KeyCode.S) or UserInput:IsKeyDown(Enum.KeyCode.Down) then forward = forward - 1 end; if UserInput:IsKeyDown(Enum.KeyCode.D) or UserInput:IsKeyDown(Enum.KeyCode.Right) then right = right + 1 end; if UserInput:IsKeyDown(Enum.KeyCode.A) or UserInput:IsKeyDown(Enum.KeyCode.Left) then right = right - 1 end
                if forward == 0 and right == 0 and h.MoveDirection.Magnitude > 0 then local lm = camCF:VectorToObjectSpace(h.MoveDirection); right = lm.X; forward = -lm.Z end
                local moveVec = (camCF.LookVector * forward + camCF.RightVector * right); if moveVec.Magnitude > 0 then moveVec = moveVec.Unit end
                local yVel = 0; if UserInput:IsKeyDown(Enum.KeyCode.Space) or UserInput:IsKeyDown(Enum.KeyCode.ButtonA) then yVel = speed end; if UserInput:IsKeyDown(Enum.KeyCode.LeftShift) or UserInput:IsKeyDown(Enum.KeyCode.ButtonL2) then yVel = -speed end
                flyBodyVel.Velocity = moveVec * speed + Vector3.new(0, yVel, 0); r.CFrame = CFrame.new(r.Position, r.Position + camCF.LookVector)
            end)
        else flyBtn.Text = "Fly: OFF"; flyBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75); stopFly() end
    end)
    LP.CharacterAdded:Connect(function() if S.fly_enabled then S.fly_enabled = false; flyBtn.Text = "Fly: OFF"; flyBtn.BackgroundColor3 = Color3.fromRGB(60, 60, 75); stopFly() end end)

    -------------------------------------------------------------------
    -- SERVER (FARM HOP)
    -------------------------------------------------------------------
    local SS = ServerTab:Section({ Title = "Server Actions" })
    SS:Button({ Title = "Rejoin Current Server", Callback = function() game:GetService("TeleportService"):Teleport(game.PlaceId, LP) end })
    
    SS:Button({ Title = "Server Hop (Farmear - Casi Solo)", Callback = function()
        WindUI:Notify({ Title = "Server Hop", Content = "Buscando servidores CASI VACÍOS (1-2 jugadores)...", Duration = 4 })
        local function fetchServers(cursor) 
            local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?limit=100"
            if cursor then url = url .. "&cursor=" .. cursor end
            local success, result = pcall(function() return HttpService:JSONDecode(game:HttpGet(url)) end)
            if success and result and result.data then return result.data, result.nextPageCursor end
            return nil, nil
        end
        
        local allServers, cursor = {}, nil
        for i = 1, 5 do
            local servers, nextCursor = fetchServers(cursor)
            if servers then
                for _, srv in ipairs(servers) do table.insert(allServers, srv) end
                cursor = nextCursor
                if not cursor then break end
            else break end
            task.wait(0.5)
        end
        
        local candidates = {}
        for _, srv in ipairs(allServers) do
            if srv.id ~= game.JobId and srv.playing < srv.maxPlayers then table.insert(candidates, srv) end
        end
        
        if #candidates == 0 then WindUI:Notify({ Title = "Error", Content = "No se encontraron servidores disponibles.", Duration = 3 }) return end
        
        -- Buscar estrictamente 1 o 2 jugadores para farmear sin interrupciones
        local targetServer = nil
        for _, srv in ipairs(candidates) do 
            if srv.playing == 1 or srv.playing == 2 then 
                targetServer = srv; break 
            end 
        end
        
        -- Si no hay de 1 o 2, buscar el que tenga menos gente (hasta 4)
        if not targetServer then 
            table.sort(candidates, function(a, b) return a.playing < b.playing end)
            for _, srv in ipairs(candidates) do
                if srv.playing <= 4 then targetServer = srv; break end
            end
            if not targetServer then targetServer = candidates[1] end
        end
        
        if targetServer then
            WindUI:Notify({ Title = "Conectando", Content = "Servidor con " .. targetServer.playing .. " jugadores (Farmeo)...", Duration = 3 })
            task.wait(1)
            pcall(function() game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, targetServer.id, LP) end)
        end
    end })

    SS:Button({ Title = "Server Hop (Aleatorio)", Callback = function()
        WindUI:Notify({ Title = "Server Hop", Content = "Buscando cualquier servidor...", Duration = 3 })
        local function fetchServers(cursor) local url = "https://games.roblox.com/v1/games/" .. game.PlaceId .. "/servers/Public?limit=100"; if cursor then url = url .. "&cursor=" .. cursor end; local s, r = pcall(function() return HttpService:JSONDecode(game:HttpGet(url)) end); if s and r and r.data then return r.data, r.nextPageCursor end; return nil, nil end
        local all, cursor = {}, nil
        for i = 1, 3 do local s, nc = fetchServers(cursor); if s then for _, v in ipairs(s) do table.insert(all, v) end; cursor = nc; if not cursor then break end else break end; task.wait(0.5) end
        local c = {}; for _, v in ipairs(all) do if v.id ~= game.JobId and v.playing < v.maxPlayers then table.insert(c, v) end end
        if #c == 0 then WindUI:Notify({ Title = "Error", Content = "No hay servidores.", Duration = 3 }) return end
        local targetServer = c[math.random(1, #c)]
        if targetServer then WindUI:Notify({ Title = "Conectando", Content = "Uniéndose a servidor aleatorio...", Duration = 3 }); task.wait(1); pcall(function() game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId, targetServer.id, LP) end) end
    end })

    -------------------------------------------------------------------
    -- CONFIG & FPS
    -------------------------------------------------------------------
    local ConfigSec = ConfigTab:Section({ Title = "Configuración" })
    local FpsSec = ConfigTab:Section({ Title = "Rendimiento (FPS Boost)" })
    local CONFIG_FILE = "windui_config.json"
    ConfigSec:Button({ Title = "Guardar Configuración", Callback = function() if writefile then writefile(CONFIG_FILE, HttpService:JSONEncode(S)); WindUI:Notify({ Title = "Config", Content = "Guardado exitosamente.", Duration = 3 }) else WindUI:Notify({ Title = "Error", Content = "writefile no soportado.", Duration = 3 }) end end })
    ConfigSec:Button({ Title = "Reset Configuración", Callback = function() if isfile and isfile(CONFIG_FILE) then if delfile then delfile(CONFIG_FILE) end; WindUI:Notify({ Title = "Config", Content = "Reiniciando...", Duration = 3 }); task.wait(1); LP:Kick("Configuración borrada.") else WindUI:Notify({ Title = "Error", Content = "No hay archivo de config.", Duration = 3 }) end end })
    local function applyFpsBoost(state) if state then for _, v in ipairs(Lighting:GetChildren()) do if v:IsA("BlurEffect") or v:IsA("BloomEffect") or v:IsA("SunRaysEffect") then v.Enabled = false end end; Lighting.GlobalShadows = false; Lighting.FogEnd = 100000; Lighting.EnvironmentDiffuseScale = 0; Lighting.EnvironmentSpecularScale = 0; for _, v in ipairs(Workspace:GetDescendants()) do if v:IsA("ParticleEmitter") or v:IsA("Trail") or v:IsA("Smoke") or v:IsA("Fire") then v.Enabled = false end end; WindUI:Notify({ Title = "Rendimiento", Content = "FPS Boost Activado.", Duration = 3 }) else Lighting.GlobalShadows = true; Lighting.FogEnd = 100000; Lighting.EnvironmentDiffuseScale = 1; Lighting.EnvironmentSpecularScale = 1; WindUI:Notify({ Title = "Rendimiento", Content = "FPS Boost Desactivado.", Duration = 3 }) end end
    FpsSec:Toggle({ Title = "Enable FPS Boost", Value = S.fps_boost, Callback = function(v) S.fps_boost = v; applyFpsBoost(v) end })
    task.spawn(function() task.wait(1); if isfile and isfile(CONFIG_FILE) then local data = readfile(CONFIG_FILE); local ok, decoded = pcall(function() return HttpService:JSONDecode(data) end); if ok and decoded then for k, v in pairs(decoded) do S[k] = v end; WindUI:Notify({ Title = "Config", Content = "Cargada (lógica). Toca un toggle si no se actualizó.", Duration = 5 }) end end end)

    WindUI:Notify({ Title = "Willy Hub Premium", Content = "Listo. RightShift para abrir.", Duration = 3 })
    print("[Willy Hub Premium] Cargado.")
end)

if not success then
    game:GetService("StarterGui"):SetCore("SendNotification", {
        Title = "Error en el Script",
        Text = tostring(err),
        Duration = 10
    })
    warn("Error en Willy Hub Premium: " .. tostring(err))
end
]==]

local BLUE = Color3.fromRGB(59, 130, 246)
local BG = Color3.fromRGB(16, 22, 36)
local PANEL = Color3.fromRGB(28, 36, 54)
local MUTED = Color3.fromRGB(140, 150, 170)

-- limpiar ventana anterior
pcall(function() playerGui:FindFirstChild("WillyKeyWindow"):Destroy() end)
pcall(function() game:GetService("CoreGui"):FindFirstChild("WillyKeyWindow"):Destroy() end)
pcall(function() gethui():FindFirstChild("WillyKeyWindow"):Destroy() end)

-- ==========================================
-- HWID
-- ==========================================
local function getHwid()
    local ok, id = pcall(function()
        return game:GetService("RbxAnalyticsService"):GetClientId()
    end)
    if ok and id and id ~= "" then return id end
    return "unknown-" .. tostring(LocalPlayer.UserId)
end

-- ==========================================
-- LLAMADA AL SERVIDOR
-- ==========================================
local function call(key, heartbeat)
    if not req then return nil, "Tu executor no soporta requests" end
    local ok, r = pcall(req, {
        Url = ENDPOINT,
        Method = "POST",
        Headers = { ["Content-Type"] = "application/json" },
        Body = HttpService:JSONEncode({
            key = key,
            hwid = getHwid(),
            heartbeat = heartbeat or nil,
        }),
    })
    if not ok or not r then return nil, "No se pudo conectar al servidor" end
    lastRaw = tostring(r.StatusCode) .. " | " .. tostring(r.Body)
    if r.StatusCode ~= 200 then return nil, "Servidor no disponible (" .. tostring(r.StatusCode) .. ")" end
    local ok2, data = pcall(HttpService.JSONDecode, HttpService, r.Body)
    if not ok2 or type(data) ~= "table" then return nil, "Respuesta inválida del servidor" end
    -- normalizar: tu web responde success/message/expires_at
    data.ok = (data.ok == true) or (data.success == true)
    data.msg = data.msg or data.message
    if not data.remaining and tonumber(data.expires_at) then
        data.remaining = math.max(0, tonumber(data.expires_at) - os.time())
    end
    return data
end

-- ==========================================
-- ARRANCAR WILLY HUB (key válida)
-- ==========================================
local function failLoad(err)
    warn("[WILLY HUB] Error al cargar el script: " .. tostring(err))
    pcall(function()
        game:GetService("StarterGui"):SetCore("SendNotification", {
            Title = "Willy Hub",
            Text = "Error al cargar: " .. tostring(err):sub(1, 150),
            Duration = 20,
        })
    end)
end

local function launch(data, key)
    pcall(function() if writefile then writefile(SAVE_FILE, key) end end)

    if data.permanent then
        getgenv().KeyRemaining = -1
    else
        getgenv().KeyExpireAt = tick() + (data.remaining or 0)
    end

    -- revalida cada 2 minutos (pausas, bans, expiración y cambio de HWID en vivo)
    task.spawn(function()
        while task.wait(120) do
            local hb = call(key, true)
            if hb and not hb.ok then
                LocalPlayer:Kick("[WILLY HUB] " .. tostring(hb.msg))
                break
            end
        end
    end)

    local src = (type(data.script) == "string" and data.script ~= "") and data.script or WILLY_SCRIPT
    local fn, lerr = loadstring(src)
    if fn then
        task.spawn(fn)
        return true
    end
    return false, lerr
end

-- ==========================================
-- VENTANA DE KEY
-- ==========================================
local function showWindow(prefill)
    local gui = Instance.new("ScreenGui")
    gui.Name = "WillyKeyWindow"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = true
    gui.DisplayOrder = 999
    gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

    local parented = pcall(function()
        local h = gethui and gethui()
        gui.Parent = h or game:GetService("CoreGui")
    end)
    if not parented or not gui.Parent then gui.Parent = playerGui end

    local W, H = 340, 250

    local frame = Instance.new("Frame")
    frame.AnchorPoint = Vector2.new(0.5, 0.5)
    frame.Position = UDim2.new(0.5, 0, 0.5, 0)
    frame.Size = UDim2.new(0, W, 0, H)
    frame.BackgroundColor3 = BG
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.ClipsDescendants = true
    frame.Parent = gui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 16)
    local st = Instance.new("UIStroke", frame)
    st.Color = BLUE
    st.Thickness = 2

    local title = Instance.new("TextLabel")
    title.Position = UDim2.new(0, 20, 0, 16)
    title.Size = UDim2.new(1, -70, 0, 24)
    title.BackgroundTransparency = 1
    title.Text = "Willy Hub | Key"
    title.TextColor3 = Color3.new(1, 1, 1)
    title.TextSize = 20
    title.Font = Enum.Font.GothamBold
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = frame

    local sub = Instance.new("TextLabel")
    sub.Position = UDim2.new(0, 20, 0, 42)
    sub.Size = UDim2.new(1, -40, 0, 16)
    sub.BackgroundTransparency = 1
    sub.Text = "Pega tu key para activar el hub"
    sub.TextColor3 = MUTED
    sub.TextSize = 12
    sub.Font = Enum.Font.Gotham
    sub.TextXAlignment = Enum.TextXAlignment.Left
    sub.Parent = frame

    local close = Instance.new("TextButton")
    close.Size = UDim2.new(0, 28, 0, 28)
    close.Position = UDim2.new(1, -42, 0, 14)
    close.BackgroundColor3 = PANEL
    close.Text = "X"
    close.TextColor3 = MUTED
    close.TextSize = 13
    close.Font = Enum.Font.GothamBold
    close.Parent = frame
    Instance.new("UICorner", close).CornerRadius = UDim.new(0, 8)

    local box = Instance.new("TextBox")
    box.Position = UDim2.new(0, 20, 0, 74)
    box.Size = UDim2.new(1, -40, 0, 44)
    box.BackgroundColor3 = PANEL
    box.Text = prefill or ""
    box.PlaceholderText = "XXXXXX-XXXXXX-XXXXXX-XXXXXX"
    box.PlaceholderColor3 = Color3.fromRGB(90, 100, 120)
    box.TextColor3 = Color3.new(1, 1, 1)
    box.TextSize = 14
    box.Font = Enum.Font.Code
    box.ClearTextOnFocus = false
    box.TextTruncate = Enum.TextTruncate.AtEnd
    box.Parent = frame
    Instance.new("UICorner", box).CornerRadius = UDim.new(0, 10)

    local status = Instance.new("TextLabel")
    status.Position = UDim2.new(0, 20, 0, 126)
    status.Size = UDim2.new(1, -40, 0, 40)
    status.BackgroundTransparency = 1
    status.Text = ""
    status.TextColor3 = Color3.fromRGB(255, 120, 130)
    status.TextSize = 12
    status.TextWrapped = true
    status.Font = Enum.Font.Gotham
    status.Parent = frame

    local btn = Instance.new("TextButton")
    btn.Position = UDim2.new(0, 20, 1, -66)
    btn.Size = UDim2.new(1, -40, 0, 46)
    btn.BackgroundColor3 = BLUE
    btn.Text = "Activar"
    btn.TextColor3 = Color3.new(1, 1, 1)
    btn.TextSize = 15
    btn.Font = Enum.Font.GothamBold
    btn.AutoButtonColor = true
    btn.Parent = frame
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 12)

    -- arrastrar la ventana (desde la parte de arriba)
    do
        local dragging, dragStart, startPos
        frame.InputBegan:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                if input.Position.Y - frame.AbsolutePosition.Y < 70 then
                    dragging, dragStart, startPos = true, input.Position, frame.Position
                end
            end
        end)
        UserInputService.InputChanged:Connect(function(input)
            if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
                local d = input.Position - dragStart
                frame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + d.X, startPos.Y.Scale, startPos.Y.Offset + d.Y)
            end
        end)
        UserInputService.InputEnded:Connect(function(input)
            if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
                dragging = false
            end
        end)
    end

    -- animación de entrada
    frame.Size = UDim2.new(0, W, 0, 0)
    TweenService:Create(frame, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Size = UDim2.new(0, W, 0, H) }):Play()

    local busy, fails, lockedUntil = false, 0, 0
    local function setStatus(text, color)
        status.Text = text
        status.TextColor3 = color or Color3.fromRGB(255, 120, 130)
    end

    local function submit()
        if busy then return end
        if tick() < lockedUntil then
            setStatus("Demasiados intentos. Espera " .. math.ceil(lockedUntil - tick()) .. "s", Color3.fromRGB(255, 190, 90))
            return
        end
        local key = box.Text:gsub("%s+", ""):upper()
        if key == "" then setStatus("Escribe tu key") return end

        busy = true
        btn.Text = "Verificando..."
        setStatus("Conectando con el servidor...", MUTED)

        local data, err = call(key, false)
        if not data then
            setStatus(err or "Error de conexión")
        elseif not data.ok then
            fails = fails + 1
            setStatus(tostring(data.msg or "Key inválida") .. (DEBUG and ("\n[" .. lastRaw:sub(1, 90) .. "]") or ""))
            if fails >= 5 then
                lockedUntil = tick() + 30
                fails = 0
            end
        else
            setStatus("Acceso concedido", Color3.fromRGB(90, 230, 140))
            task.wait(0.4)
            gui:Destroy()
            local okL, lerr = launch(data, key)
            if not okL then failLoad(lerr) end
            return
        end
        busy = false
        btn.Text = "Activar"
    end

    btn.Activated:Connect(submit)
    box.FocusLost:Connect(function(enter) if enter then submit() end end)
    close.Activated:Connect(function() gui:Destroy() end)
end

-- ==========================================
-- INICIO
-- ==========================================
-- 1) Si ya viene una key preconfigurada (getgenv().Key o script_key), entra sin ventana
local preset = getgenv().Key or script_key
if preset and preset ~= "" then
    local key = tostring(preset):gsub("%s+", ""):upper()
    local data = call(key, false)
    if data and data.ok then
        local okL, lerr = launch(data, key)
        if not okL then failLoad(lerr) end
        return
    end
end

-- 2) Si no, abre la ventana con la última key guardada
local saved = ""
pcall(function()
    if isfile and readfile and isfile(SAVE_FILE) then saved = readfile(SAVE_FILE) end
end)
showWindow(saved)
