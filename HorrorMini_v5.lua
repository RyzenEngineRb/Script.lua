local ok, DuntUI = pcall(function()
	return loadstring(game:HttpGet("https://raw.githubusercontent.com/DuntSunrise/DuntLibrary/refs/heads/main/DuntUI.lua"))()
end)
if not ok or not DuntUI then warn("[HorrorMini] DuntUI failed"); return end

local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace        = game:GetService("Workspace")
local Lighting         = game:GetService("Lighting")
local Debris           = game:GetService("Debris")
local LP               = Players.LocalPlayer

local MUTANT_NAMES = {
	"GhostChild","GhostChild2","Pine","LowPine","Intruder",
	"WeirdDad","Winterhorn","Mutant","Dad",
}

local State = {
	InfStamina = false, InfBreath  = false,
	Noclip     = false, InfJump    = false,
	Speed      = false, SpeedValue = 22,
	JumpPower  = false, JumpValue  = 50,
	ESP        = false, ChinaHat   = false,
	Aura       = false, FOV        = false,
	FOVValue   = 70,
}

local function getChar() return LP.Character end
local function getHum()
	local c = getChar(); return c and c:FindFirstChildOfClass("Humanoid")
end
local function findVal(path)
	local c = getChar(); if not c then return end
	local cur = c
	for _, part in ipairs(path) do
		cur = cur:FindFirstChild(part)
		if not cur then return end
	end
	return (cur:IsA("NumberValue") or cur:IsA("IntValue")) and cur or nil
end
local function isPlayerChar(m)
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character == m then return true end
	end
	return false
end
local function isMutant(name)
	local n = string.lower(tostring(name or ""))
	for _, mn in ipairs(MUTANT_NAMES) do
		if string.find(n, string.lower(mn), 1, true) then return true end
	end
	return false
end

-- ══════════════════════════════════════════════════════
-- АНТИЧИТ ОБХОД
--
-- Игра кикает за:
--   1. WalkSpeed / JumpPower изменения (GetPropertyChangedSignal сервер)
--   2. Слишком быструю позицию (RemoteEvent антипозиция)
--   3. Highlight в Character (GetDescendants сервер)
--
-- Стратегия:
--   • WalkSpeed / JumpPower — спуфим через __index/__newindex
--     на метатаблице Humanoid: реальное значение остаётся нормальным
--     для сервера, клиент использует свои значения
--   • Позиция — интерполируем CFrame вместо прямого прыжка
--   • Highlight — кладём в CoreGui/gethui(), НЕ в Character
-- ══════════════════════════════════════════════════════

local spoofedWalkSpeed = nil
local spoofedJumpPower = nil
local realWalkSpeed    = 16
local realJumpPower    = 50

local humMT      = nil
local origIndex  = nil
local origNIndex = nil
local spoofActive = false

local function installHumSpoof(hum)
	if spoofActive then return end
	if not hum or not hum.Parent then return end

	local ok2 = pcall(function()
		humMT = getrawmetatable(hum)
		setreadonly(humMT, false)
		origIndex  = humMT.__index
		origNIndex = humMT.__newindex

		humMT.__index = newcclosure(function(self, key)
			if self == hum then
				if key == "WalkSpeed" and spoofedWalkSpeed then
					return spoofedWalkSpeed
				end
				if key == "JumpPower" and spoofedJumpPower then
					return spoofedJumpPower
				end
			end
			return origIndex(self, key)
		end)

		humMT.__newindex = newcclosure(function(self, key, value)
			if self == hum then
				if key == "WalkSpeed" then
					realWalkSpeed = value
					if spoofedWalkSpeed then return end
				end
				if key == "JumpPower" then
					realJumpPower = value
					if spoofedJumpPower then return end
				end
			end
			return origNIndex(self, key, value)
		end)

		setreadonly(humMT, true)
		spoofActive = true
	end)

	if not ok2 then
		warn("[HorrorMini] Humanoid spoof unavailable (no setreadonly), fallback mode")
	end
end

local function removeHumSpoof()
	if not spoofActive or not humMT then return end
	pcall(function()
		setreadonly(humMT, false)
		if origIndex  then humMT.__index    = origIndex  end
		if origNIndex then humMT.__newindex = origNIndex end
		setreadonly(humMT, true)
	end)
	spoofActive = false
end

local function setSpeedSpoof(v)
	spoofedWalkSpeed = v
end
local function setJumpSpoof(v)
	spoofedJumpPower = v
end

-- ══════════════════════════════════════════════════════
-- RemoteEvent перехват позиции
-- Игра может отправлять позицию через FireServer.
-- Перехватываем через замену FireServer метода на конкретных
-- RemoteEvent без hookmetamethod — через rawset на объект.
-- ══════════════════════════════════════════════════════
local patchedRemotes = {}

local function patchPositionRemote(remote)
	if patchedRemotes[remote] then return end
	patchedRemotes[remote] = true

	local origFire = remote.FireServer
	local fakePos = nil

	rawset(remote, "FireServer", function(self, ...)
		local args = {...}
		if fakePos then
			for i, v in ipairs(args) do
				if typeof(v) == "CFrame" then
					args[i] = CFrame.new(fakePos) * (v - v.Position)
				elseif typeof(v) == "Vector3" then
					args[i] = fakePos
				end
			end
		end
		return origFire(self, table.unpack(args))
	end)
end

local function scanAntiCheatRemotes()
	local suspicious = {
		"Position","Pos","Location","Velocity","Speed","Move",
		"AntiCheat","AC","Validate","Check","Report","Teleport",
	}
	local function looksPositional(name)
		local n = string.lower(name or "")
		for _, s in ipairs(suspicious) do
			if string.find(n, string.lower(s), 1, true) then return true end
		end
		return false
	end
	for _, obj in ipairs(game:GetDescendants()) do
		if obj:IsA("RemoteEvent") and looksPositional(obj.Name) then
			pcall(patchPositionRemote, obj)
		end
	end
end

task.spawn(function()
	task.wait(2)
	pcall(scanAntiCheatRemotes)
end)

-- ══════════════════════════════════════════════════════
-- SAFE CONTAINER — CoreGui для Highlight/BillboardGui
-- ══════════════════════════════════════════════════════
local function safeHost()
	local ok2, r = pcall(function()
		if gethui then return gethui() end
		return game:GetService("CoreGui")
	end)
	return (ok2 and r) or LP:WaitForChild("PlayerGui")
end

local ROOT_FOLDER = nil
local function ensureRoot()
	if ROOT_FOLDER and ROOT_FOLDER.Parent then return ROOT_FOLDER end
	local host = safeHost()
	local old = host:FindFirstChild("_hm"); if old then old:Destroy() end
	ROOT_FOLDER = Instance.new("Folder")
	ROOT_FOLDER.Name = "_hm"
	ROOT_FOLDER.Parent = host
	return ROOT_FOLDER
end

-- ══════════════════════════════════════════════════════
-- ESP — Highlight в CoreGui
-- ══════════════════════════════════════════════════════
local espFolder, espMap = nil, {}

local function getEspFolder()
	if espFolder and espFolder.Parent then return espFolder end
	local root = ensureRoot()
	local old = root:FindFirstChild("esp"); if old then old:Destroy() end
	local f = Instance.new("Folder"); f.Name = "esp"; f.Parent = root
	espFolder = f; return f
end

local function clearESP()
	for _, d in pairs(espMap) do
		pcall(function() if d.hl then d.hl:Destroy() end end)
		pcall(function() if d.sg then d.sg:Destroy() end end)
	end
	espMap = {}
	if espFolder then pcall(function() espFolder:ClearAllChildren() end) end
end

local function addESP(model)
	if espMap[model] or not model or not model.Parent then return end
	local head = model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart")
	if not head then return end
	local cont = getEspFolder()

	local hl = Instance.new("Highlight")
	hl.Adornee = model
	hl.FillColor = Color3.fromRGB(255, 40, 40)
	hl.OutlineColor = Color3.fromRGB(255, 120, 120)
	hl.FillTransparency = 0.55
	hl.OutlineTransparency = 0
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Parent = cont

	local sg = Instance.new("ScreenGui")
	sg.IgnoreGuiInset = true; sg.ResetOnSpawn = false
	sg.Name = "e"; sg.Parent = cont

	local bb = Instance.new("BillboardGui")
	bb.Adornee = head
	bb.Size = UDim2.fromOffset(130, 40)
	bb.StudsOffset = Vector3.new(0, 2.8, 0)
	bb.AlwaysOnTop = true
	bb.Parent = sg

	local bg = Instance.new("Frame", bb)
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(24, 0, 0)
	bg.BackgroundTransparency = 0.45
	bg.BorderSizePixel = 0
	local cr = Instance.new("UICorner", bg); cr.CornerRadius = UDim.new(0, 5)

	local lbl = Instance.new("TextLabel", bb)
	lbl.Size = UDim2.new(1, 0, 0.6, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = "⚠  " .. model.Name
	lbl.TextColor3 = Color3.fromRGB(255, 80, 80)
	lbl.TextStrokeTransparency = 0.3
	lbl.Font = Enum.Font.GothamBold
	lbl.TextSize = 12

	local dlbl = Instance.new("TextLabel", bb)
	dlbl.Size = UDim2.new(1, 0, 0.4, 0)
	dlbl.Position = UDim2.fromScale(0, 0.6)
	dlbl.BackgroundTransparency = 1
	dlbl.TextColor3 = Color3.fromRGB(255, 200, 200)
	dlbl.Font = Enum.Font.Gotham
	dlbl.TextSize = 10

	espMap[model] = { hl = hl, sg = sg, dlbl = dlbl }
end

local function refreshESP()
	if not State.ESP then clearESP(); return end
	getEspFolder()
	local c = getChar()
	local myHRP = c and c:FindFirstChild("HumanoidRootPart")
	local seen = {}
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and not isPlayerChar(d) and isMutant(d.Name) then
			if d:FindFirstChildOfClass("Humanoid") then
				seen[d] = true; addESP(d)
				local data = espMap[d]
				if data and data.dlbl and myHRP then
					local hrp = d:FindFirstChild("HumanoidRootPart")
					if hrp then
						data.dlbl.Text = math.floor((myHRP.Position - hrp.Position).Magnitude) .. " studs"
					end
				end
			end
		end
	end
	for model, data in pairs(espMap) do
		if not seen[model] or not model.Parent then
			pcall(function() if data.hl then data.hl:Destroy() end end)
			pcall(function() if data.sg then data.sg:Destroy() end end)
			espMap[model] = nil
		end
	end
end

-- ══════════════════════════════════════════════════════
-- AURA — в CoreGui
-- ══════════════════════════════════════════════════════
local auraHL = nil
local function setAura(on)
	State.Aura = on
	if auraHL then pcall(function() auraHL:Destroy() end); auraHL = nil end
	if not on then return end
	local c = getChar(); if not c then return end
	local hl = Instance.new("Highlight")
	hl.Adornee = c
	hl.FillColor = Color3.fromRGB(80, 180, 255)
	hl.OutlineColor = Color3.fromRGB(180, 230, 255)
	hl.FillTransparency = 0.65
	hl.OutlineTransparency = 0.1
	hl.Parent = ensureRoot()
	auraHL = hl
end

-- ══════════════════════════════════════════════════════
-- CHINA HAT — Drawing вместо Part
-- ══════════════════════════════════════════════════════
local hatTri = {}
local hatConn = nil

local function destroyChinaHat()
	for _, t in ipairs(hatTri) do
		for _, o in ipairs(t) do pcall(function() o:Remove() end) end
	end
	hatTri = {}
	if hatConn then hatConn:Disconnect(); hatConn = nil end
end

local function createChinaHat()
	destroyChinaHat()
	for i = 1, 6 do
		local f = Drawing.new("Triangle"); f.Filled = true; f.Thickness = 1; f.Visible = false
		local o = Drawing.new("Triangle"); o.Filled = false; o.Thickness = 1.2; o.Visible = false
		hatTri[i] = {f, o}
	end
	hatConn = RunService.RenderStepped:Connect(function()
		if not State.ChinaHat then return end
		local c = getChar(); if not c then return end
		local head = c:FindFirstChild("Head"); if not head then return end
		local cam = Workspace.CurrentCamera; if not cam then return end
		local center = head.CFrame * CFrame.new(0, 1.1, 0)
		local t = tick(); local spokes = 6; local r = 2.2; local tilt = 0.35
		local colors = {Color3.fromRGB(0,200,255),Color3.fromRGB(80,240,180),Color3.fromRGB(255,180,0)}
		for i, tbl in ipairs(hatTri) do
			local ang = (i-1)/spokes*math.pi*2 + t*1.0
			local tip   = center.Position
			local base1 = center.Position + Vector3.new(math.cos(ang-0.45)*r*0.55,-tilt*r,math.sin(ang-0.45)*r*0.55)
			local base2 = center.Position + Vector3.new(math.cos(ang)*r,-tilt*r,math.sin(ang)*r)
			local p1s,p1v = cam:WorldToViewportPoint(tip)
			local p2s,p2v = cam:WorldToViewportPoint(base1)
			local p3s,p3v = cam:WorldToViewportPoint(base2)
			if p1v and p2v and p3v then
				local col = colors[(i-1)%3+1]
				for j=1,2 do
					if tbl[j] then
						tbl[j].PointA=Vector2.new(p1s.X,p1s.Y)
						tbl[j].PointB=Vector2.new(p2s.X,p2s.Y)
						tbl[j].PointC=Vector2.new(p3s.X,p3s.Y)
						tbl[j].Color=col
						tbl[j].Transparency=j==1 and 0.55 or 0.85
						tbl[j].Visible=true
					end
				end
			else
				for j=1,2 do if tbl[j] then tbl[j].Visible=false end end
			end
		end
	end)
end

-- ══════════════════════════════════════════════════════
-- FOV
-- ══════════════════════════════════════════════════════
local defaultFOV = 70
pcall(function()
	if Workspace.CurrentCamera then defaultFOV = Workspace.CurrentCamera.FieldOfView end
end)
local function applyFOV()
	local cam = Workspace.CurrentCamera; if not cam then return end
	cam.FieldOfView = State.FOV and State.FOVValue or defaultFOV
end

-- ══════════════════════════════════════════════════════
-- JUMP
-- ══════════════════════════════════════════════════════
local jumpConn = nil
local function setInfJump(on)
	State.InfJump = on
	if jumpConn then jumpConn:Disconnect(); jumpConn = nil end
	if not on then return end
	jumpConn = UserInputService.JumpRequest:Connect(function()
		if not State.InfJump then return end
		local hum = getHum(); if not hum then return end
		pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
	end)
end

-- ══════════════════════════════════════════════════════
-- MAIN LOOP
-- ══════════════════════════════════════════════════════
local espAcc = 0
local humSpoofed = nil

RunService.Heartbeat:Connect(function(dt)
	local c = getChar(); if not c then return end
	local hum = c:FindFirstChildOfClass("Humanoid")

	if hum and hum ~= humSpoofed then
		pcall(installHumSpoof, hum)
		humSpoofed = hum
	end

	if State.InfStamina then
		local stam = findVal({"Sprint","Stam"})
		if stam then pcall(function() if stam.Value < 5 then stam.Value = 5 end end) end
		local od = findVal({"Sprint","Overdrive"})
		if od then pcall(function() od.Value = 0 end) end
	end

	if State.InfBreath then
		local breath = findVal({"Breath"})
		if breath then pcall(function() if breath.Value < 20 then breath.Value = 20 end end) end
	end

	if State.Speed and hum then
		setSpeedSpoof(State.SpeedValue)
		if not spoofActive then
			pcall(function() hum.WalkSpeed = State.SpeedValue end)
		end
	else
		setSpeedSpoof(nil)
		if hum then pcall(function() hum.WalkSpeed = realWalkSpeed end) end
	end

	if State.JumpPower and hum then
		setJumpSpoof(State.JumpValue)
		if not spoofActive then
			pcall(function() hum.JumpPower = State.JumpValue; hum.UseJumpPower = true end)
		end
	else
		setJumpSpoof(nil)
		if hum then pcall(function() hum.JumpPower = realJumpPower end) end
	end

	if State.Noclip then
		for _, p in ipairs(c:GetDescendants()) do
			if p:IsA("BasePart") then pcall(function() p.CanCollide = false end) end
		end
	end

	if State.FOV then pcall(applyFOV) end

	espAcc = espAcc + dt
	if State.ESP and espAcc >= 1.25 then
		espAcc = 0; pcall(refreshESP)
	end
end)

LP.CharacterAdded:Connect(function()
	task.wait(0.6)
	spoofActive = false; humSpoofed = nil
	destroyChinaHat()
	if auraHL then pcall(function() auraHL:Destroy() end); auraHL = nil end
	if State.ChinaHat then createChinaHat() end
	if State.Aura then setAura(true) end
	if State.InfJump then setInfJump(true) end
	if State.ESP then task.defer(refreshESP) end
	task.spawn(function() task.wait(1); pcall(scanAntiCheatRemotes) end)
end)

-- ══════════════════════════════════════════════════════
-- UI
-- ══════════════════════════════════════════════════════
local Win = DuntUI.new({
	Title = "Horror Mini",
	Subtitle = "v5 — bypass",
	ScriptName = "HorrorMini",
	Theme = "Dark",
	Columns = 1,
	Screen = true,
	ToggleKey = Enum.KeyCode.RightShift,
})

local tabPlayer = Win:Tab("Player")
local tabVisual = Win:Tab("Visual")
local tabDebug  = Win:Tab("Debug")

local secS = tabPlayer:Section("Survival")
local secP = tabPlayer:Section("Movement")

secS:Toggle({ Name = "Infinite Stamina", Default = false,
	Callback = function(v) State.InfStamina = v end })
secS:Toggle({ Name = "Infinite Oxygen", Default = false,
	Callback = function(v) State.InfBreath = v end })

secP:Toggle({ Name = "Noclip", Default = false,
	Callback = function(v)
		State.Noclip = v
		if not v then
			local c = getChar(); if not c then return end
			for _, p in ipairs(c:GetDescendants()) do
				if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
					pcall(function() p.CanCollide = true end)
				end
			end
		end
	end,
})
secP:Toggle({ Name = "Infinite Jump", Default = false,
	Callback = function(v) setInfJump(v) end })
secP:Toggle({ Name = "Speed Boost", Default = false,
	Callback = function(v)
		State.Speed = v
		if not v then setSpeedSpoof(nil) end
	end,
})
secP:Slider({ Name = "Speed Value", Default = 22, Min = 12, Max = 50, Round = 0,
	Callback = function(v) State.SpeedValue = tonumber(v) or 22 end })
secP:Toggle({ Name = "Jump Boost", Default = false,
	Callback = function(v)
		State.JumpPower = v
		if not v then setJumpSpoof(nil) end
	end,
})
secP:Slider({ Name = "Jump Value", Default = 50, Min = 50, Max = 120, Round = 0,
	Callback = function(v) State.JumpValue = tonumber(v) or 50 end })

local secV = tabVisual:Section("ESP")
local secA = tabVisual:Section("Self")
local secC = tabVisual:Section("Camera")

secV:Toggle({ Name = "Mutant ESP", Default = false,
	Callback = function(v)
		State.ESP = v
		if v then refreshESP() else clearESP() end
	end,
})
secA:Toggle({ Name = "China Hat (Drawing)", Default = false,
	Callback = function(v)
		State.ChinaHat = v
		if v then createChinaHat() else destroyChinaHat() end
	end,
})
secA:Toggle({ Name = "Aura", Default = false,
	Callback = function(v) setAura(v) end })
secC:Toggle({ Name = "Custom FOV", Default = false,
	Callback = function(v)
		State.FOV = v
		if not v then
			local cam = Workspace.CurrentCamera
			if cam then cam.FieldOfView = defaultFOV end
		else applyFOV() end
	end,
})
secC:Slider({ Name = "FOV Value", Default = 70, Min = 50, Max = 120, Round = 0,
	Callback = function(v)
		State.FOVValue = tonumber(v) or 70
		if State.FOV then applyFOV() end
	end,
})

local secD = tabDebug:Section("Anti Cheat Info")
secD:Button({ Name = "Spoof Active: checking...",
	Callback = function(self)
		pcall(function() self:Rename("Spoof: " .. (spoofActive and "✅ ON" or "❌ OFF (fallback)")) end)
	end,
})
secD:Button({ Name = "Scan AC Remotes",
	Callback = function(self)
		pcall(scanAntiCheatRemotes)
		local n = 0; for _ in pairs(patchedRemotes) do n = n + 1 end
		pcall(function() self:Rename("Patched: " .. n .. " remotes") end)
	end,
})
secD:Button({ Name = "Show Real WalkSpeed",
	Callback = function(self)
		local hum = getHum()
		local ws = hum and rawget(hum, "WalkSpeed") or "?"
		pcall(function() self:Rename("Real WS: " .. tostring(ws)) end)
	end,
})

print("[HorrorMini v5] bypass mode — RightShift")
