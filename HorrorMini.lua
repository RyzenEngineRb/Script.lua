local URL = "https://raw.githubusercontent.com/RyzenEngineRb/UnflyProject/refs/heads/main/UnflyUi.lua"
local LOCAL_FILE = "UnflyUi.lua"

local function fetchUi()
	local ok, src = pcall(function() return game:HttpGet(URL) end)
	if ok and type(src) == "string" and #src > 100 then return src end
	if isfile and readfile and isfile(LOCAL_FILE) then
		local ok2, src2 = pcall(readfile, LOCAL_FILE)
		if ok2 and type(src2) == "string" and #src2 > 100 then return src2 end
	end
	error("UnflyUi not found")
end

local ok, Library = pcall(function() return loadstring(fetchUi())() end)
if not ok or type(Library) ~= "table" then
	warn("[HorrorMini] UnflyUi load failed: " .. tostring(Library))
	return
end

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LP = Players.LocalPlayer

local MUTANT_NAMES = {
	"GhostChild", "GhostChild2", "Pine", "LowPine", "Intruder",
	"WeirdDad", "Winterhorn", "Mutant", "Dad",
}

local State = {
	InfStamina = false,
	InfBreath = false,
	InfCold = false,
	Noclip = false,
	InfJump = false,
	Speed = false,
	SpeedValue = 22,
	JumpPower = false,
	JumpValue = 50,
	Fly = false,
	FlySpeed = 40,
	ESP = false,
	ChinaHat = false,
	Aura = false,
	FOV = false,
	FOVValue = 70,
	FreeCam = false,
	FreeCamSpeed = 60,
}

local function getChar()
	return LP.Character
end

local function getHum()
	local c = getChar()
	return c and c:FindFirstChildOfClass("Humanoid")
end

local function findVal(path)
	local c = getChar()
	if not c then return end
	local cur = c
	for _, part in ipairs(path) do
		cur = cur:FindFirstChild(part)
		if not cur then return end
	end
	if cur:IsA("NumberValue") or cur:IsA("IntValue") then
		return cur
	end
	return nil
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

local COLD_KEYS = { "cold", "temp", "temperature", "freeze", "warmth", "heat", "frost", "chill" }
local COLD_PATHS = {
	{ "Cold" },
	{ "Temperature" },
	{ "Temp" },
	{ "Warmth" },
	{ "Freeze" },
	{ "Stats", "Cold" },
	{ "Stats", "Temperature" },
	{ "Status", "Cold" },
	{ "Status", "Temperature" },
	{ "Values", "Cold" },
	{ "Values", "Temperature" },
	{ "Survival", "Cold" },
	{ "Survival", "Temperature" },
}

local function findColdValues()
	local found = {}
	for _, path in ipairs(COLD_PATHS) do
		local v = findVal(path)
		if v then found[#found + 1] = v end
	end
	local c = getChar()
	if not c then return found end
	for _, d in ipairs(c:GetDescendants()) do
		if d:IsA("NumberValue") or d:IsA("IntValue") then
			local n = string.lower(d.Name)
			for _, k in ipairs(COLD_KEYS) do
				if string.find(n, k, 1, true) then
					local already = false
					for _, x in ipairs(found) do
						if x == d then already = true break end
					end
					if not already then found[#found + 1] = d end
					break
				end
			end
		end
	end
	return found
end

local function protectCold()
	for _, v in ipairs(findColdValues()) do
		pcall(function()
			local n = string.lower(v.Name)
			if string.find(n, "cold", 1, true) or string.find(n, "freeze", 1, true) or string.find(n, "frost", 1, true) or string.find(n, "chill", 1, true) then
				if v.Value > 0 then v.Value = 0 end
			elseif string.find(n, "warm", 1, true) then
				if v.Value < 100 then v.Value = 100 end
			else
				if v.Value < 50 then
					v.Value = math.max(v.Value, 70)
				elseif v.Value > 80 and v.Value < 200 then
					v.Value = math.min(v.Value, 20)
				end
			end
		end)
	end
end

local realWalkSpeed = 16
local realJumpPower = 50

-- Без getrawmetatable / __newindex — игра кикает: "newindexInstance detector detected"
local function safeSetWalkSpeed(hum, value)
	if not hum then return end
	pcall(function()
		-- только клиентское значение, без хука метатаблицы
		hum.WalkSpeed = value
	end)
end

local function safeSetJumpPower(hum, value)
	if not hum then return end
	pcall(function()
		hum.UseJumpPower = true
		hum.JumpPower = value
	end)
end

local patchedRemotes = {}
-- Не патчим FireServer через rawset — тоже ловится детекторами instance newindex
local function scanAntiCheatRemotes()
	local n = 0
	for _, obj in ipairs(game:GetDescendants()) do
		if obj:IsA("RemoteEvent") then
			n = n + 1
		end
	end
	return n
end

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
	local old = host:FindFirstChild("_hm")
	if old then old:Destroy() end
	ROOT_FOLDER = Instance.new("Folder")
	ROOT_FOLDER.Name = "_hm"
	ROOT_FOLDER.Parent = host
	return ROOT_FOLDER
end

local espFolder, espMap = nil, {}

local function getEspFolder()
	if espFolder and espFolder.Parent then return espFolder end
	local root = ensureRoot()
	local old = root:FindFirstChild("esp")
	if old then old:Destroy() end
	local f = Instance.new("Folder")
	f.Name = "esp"
	f.Parent = root
	espFolder = f
	return f
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
	sg.IgnoreGuiInset = true
	sg.ResetOnSpawn = false
	sg.Name = "e"
	sg.Parent = cont

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
	Instance.new("UICorner", bg).CornerRadius = UDim.new(0, 5)

	local lbl = Instance.new("TextLabel", bb)
	lbl.Size = UDim2.new(1, 0, 0.6, 0)
	lbl.BackgroundTransparency = 1
	lbl.Text = model.Name
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
	if not State.ESP then clearESP() return end
	getEspFolder()
	local c = getChar()
	local myHRP = c and c:FindFirstChild("HumanoidRootPart")
	local seen = {}
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Model") and not isPlayerChar(d) and isMutant(d.Name) then
			if d:FindFirstChildOfClass("Humanoid") then
				seen[d] = true
				addESP(d)
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

local auraHL = nil
local function setAura(on)
	State.Aura = on
	if auraHL then pcall(function() auraHL:Destroy() end) auraHL = nil end
	if not on then return end
	local c = getChar()
	if not c then return end
	local hl = Instance.new("Highlight")
	hl.Adornee = c
	hl.FillColor = Color3.fromRGB(80, 180, 255)
	hl.OutlineColor = Color3.fromRGB(180, 230, 255)
	hl.FillTransparency = 0.65
	hl.OutlineTransparency = 0.1
	hl.Parent = ensureRoot()
	auraHL = hl
end

local hatTri = {}
local hatConn = nil

local function destroyChinaHat()
	for _, t in ipairs(hatTri) do
		for _, o in ipairs(t) do pcall(function() o:Remove() end) end
	end
	hatTri = {}
	if hatConn then hatConn:Disconnect() hatConn = nil end
end

local function createChinaHat()
	destroyChinaHat()
	if not Drawing then return end
	for i = 1, 6 do
		local f = Drawing.new("Triangle")
		f.Filled = true
		f.Thickness = 1
		f.Visible = false
		local o = Drawing.new("Triangle")
		o.Filled = false
		o.Thickness = 1.2
		o.Visible = false
		hatTri[i] = { f, o }
	end
	hatConn = RunService.RenderStepped:Connect(function()
		if not State.ChinaHat then return end
		local c = getChar()
		if not c then return end
		local head = c:FindFirstChild("Head")
		if not head then return end
		local cam = Workspace.CurrentCamera
		if not cam then return end
		local center = head.CFrame * CFrame.new(0, 1.1, 0)
		local t = tick()
		local spokes = 6
		local r = 2.2
		local tilt = 0.35
		local colors = {
			Color3.fromRGB(0, 200, 255),
			Color3.fromRGB(80, 240, 180),
			Color3.fromRGB(255, 180, 0),
		}
		for i, tbl in ipairs(hatTri) do
			local ang = (i - 1) / spokes * math.pi * 2 + t
			local tip = center.Position
			local base1 = center.Position + Vector3.new(math.cos(ang - 0.45) * r * 0.55, -tilt * r, math.sin(ang - 0.45) * r * 0.55)
			local base2 = center.Position + Vector3.new(math.cos(ang) * r, -tilt * r, math.sin(ang) * r)
			local p1s, p1v = cam:WorldToViewportPoint(tip)
			local p2s, p2v = cam:WorldToViewportPoint(base1)
			local p3s, p3v = cam:WorldToViewportPoint(base2)
			if p1v and p2v and p3v then
				local col = colors[(i - 1) % 3 + 1]
				for j = 1, 2 do
					if tbl[j] then
						tbl[j].PointA = Vector2.new(p1s.X, p1s.Y)
						tbl[j].PointB = Vector2.new(p2s.X, p2s.Y)
						tbl[j].PointC = Vector2.new(p3s.X, p3s.Y)
						tbl[j].Color = col
						tbl[j].Transparency = j == 1 and 0.55 or 0.85
						tbl[j].Visible = true
					end
				end
			else
				for j = 1, 2 do
					if tbl[j] then tbl[j].Visible = false end
				end
			end
		end
	end)
end

local defaultFOV = 70
pcall(function()
	if Workspace.CurrentCamera then defaultFOV = Workspace.CurrentCamera.FieldOfView end
end)

local function applyFOV()
	local cam = Workspace.CurrentCamera
	if not cam then return end
	cam.FieldOfView = State.FOV and State.FOVValue or defaultFOV
end

-- Полёт без BodyVelocity / без анимаций / без new Instance на персонаже
local keysDown = {}
UserInputService.InputBegan:Connect(function(input, gp)
	if gp then return end
	if input.UserInputType == Enum.UserInputType.Keyboard then
		keysDown[input.KeyCode] = true
	end
end)
UserInputService.InputEnded:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.Keyboard then
		keysDown[input.KeyCode] = nil
	end
end)

local function flyStep(dt)
	if not State.Fly then return end
	local c = getChar()
	if not c then return end
	local hrp = c:FindFirstChild("HumanoidRootPart")
	local hum = c:FindFirstChildOfClass("Humanoid")
	if not hrp then return end

	local cam = Workspace.CurrentCamera
	if not cam then return end

	-- без Animate / без ChangeState Jumping каждый кадр
	if hum then
		pcall(function()
			hum.PlatformStand = false
			hum.AutoRotate = true
		end)
	end

	local look = cam.CFrame.LookVector
	local right = cam.CFrame.RightVector
	local move = Vector3.zero
	if keysDown[Enum.KeyCode.W] then move = move + look end
	if keysDown[Enum.KeyCode.S] then move = move - look end
	if keysDown[Enum.KeyCode.A] then move = move - right end
	if keysDown[Enum.KeyCode.D] then move = move + right end
	if keysDown[Enum.KeyCode.Space] or keysDown[Enum.KeyCode.E] then move = move + Vector3.new(0, 1, 0) end
	if keysDown[Enum.KeyCode.LeftControl] or keysDown[Enum.KeyCode.Q] then move = move - Vector3.new(0, 1, 0) end

	if move.Magnitude > 0 then
		move = move.Unit * State.FlySpeed
	end

	-- только скорость сборки, без BodyMovers (не создаём Instance)
	pcall(function()
		hrp.AssemblyLinearVelocity = move
		hrp.AssemblyAngularVelocity = Vector3.zero
	end)
end

local freecamConn = nil
local freecamSaved = nil

local function stopFreeCam()
	State.FreeCam = false
	if freecamConn then freecamConn:Disconnect() freecamConn = nil end
	local cam = Workspace.CurrentCamera
	if cam and freecamSaved then
		pcall(function()
			cam.CameraType = freecamSaved.Type
			cam.CameraSubject = freecamSaved.Subject
			cam.FieldOfView = freecamSaved.FOV
		end)
	end
	freecamSaved = nil
end

local function startFreeCam()
	stopFreeCam()
	local cam = Workspace.CurrentCamera
	if not cam then return end
	freecamSaved = {
		Type = cam.CameraType,
		Subject = cam.CameraSubject,
		FOV = cam.FieldOfView,
	}
	State.FreeCam = true
	-- Scriptable только пока включено; при выключении возвращаем как было
	pcall(function() cam.CameraType = Enum.CameraType.Scriptable end)

	local yaw, pitch = 0, 0
	local cf = cam.CFrame
	yaw = math.atan2(-cf.LookVector.X, -cf.LookVector.Z)
	pitch = math.asin(math.clamp(cf.LookVector.Y, -1, 1))

	freecamConn = RunService.RenderStepped:Connect(function(dt)
		if not State.FreeCam then return end
		local cam2 = Workspace.CurrentCamera
		if not cam2 then return end

		local delta = UserInputService:GetMouseDelta()
		yaw = yaw - delta.X * 0.004
		pitch = math.clamp(pitch - delta.Y * 0.004, -1.4, 1.4)

		local rot = CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)
		local look = rot.LookVector
		local right = rot.RightVector
		local move = Vector3.zero
		if keysDown[Enum.KeyCode.W] then move = move + look end
		if keysDown[Enum.KeyCode.S] then move = move - look end
		if keysDown[Enum.KeyCode.A] then move = move - right end
		if keysDown[Enum.KeyCode.D] then move = move + right end
		if keysDown[Enum.KeyCode.Space] or keysDown[Enum.KeyCode.E] then move = move + Vector3.yAxis end
		if keysDown[Enum.KeyCode.LeftControl] or keysDown[Enum.KeyCode.Q] then move = move - Vector3.yAxis end

		local pos = cam2.CFrame.Position
		if move.Magnitude > 0 then
			pos = pos + move.Unit * State.FreeCamSpeed * dt
		end
		cam2.CFrame = CFrame.new(pos) * rot
		if State.FOV then
			cam2.FieldOfView = State.FOVValue
		end
	end)
end

local jumpConn = nil
local function setInfJump(on)
	State.InfJump = on
	if jumpConn then jumpConn:Disconnect() jumpConn = nil end
	if not on then return end
	jumpConn = UserInputService.JumpRequest:Connect(function()
		if not State.InfJump then return end
		local hum = getHum()
		if not hum then return end
		pcall(function() hum:ChangeState(Enum.HumanoidStateType.Jumping) end)
	end)
end

local espAcc = 0

RunService.Heartbeat:Connect(function(dt)
	local c = getChar()
	if not c then return end
	local hum = c:FindFirstChildOfClass("Humanoid")

	if State.InfStamina then
		local stam = findVal({ "Sprint", "Stam" })
		if stam then pcall(function() if stam.Value < 5 then stam.Value = 5 end end) end
		local od = findVal({ "Sprint", "Overdrive" })
		if od then pcall(function() od.Value = 0 end) end
	end

	if State.InfBreath then
		local breath = findVal({ "Breath" })
		if breath then pcall(function() if breath.Value < 20 then breath.Value = 20 end end) end
	end

	if State.InfCold then
		protectCold()
	end

	if State.Speed and hum then
		-- мягкий буст: не каждый кадр, реже дергает детектор
		if (tick() * 10) % 3 < 1 then
			safeSetWalkSpeed(hum, State.SpeedValue)
		end
	end

	if State.JumpPower and hum then
		if (tick() * 10) % 3 < 1 then
			safeSetJumpPower(hum, State.JumpValue)
		end
	end

	if State.Noclip then
		for _, p in ipairs(c:GetDescendants()) do
			if p:IsA("BasePart") then pcall(function() p.CanCollide = false end) end
		end
	end

	if State.FOV and not State.FreeCam then pcall(applyFOV) end

	if State.Fly then
		flyStep(dt)
		-- лёгкий noclip на время полёта (только CanCollide, без новых Instance)
		for _, p in ipairs(c:GetDescendants()) do
			if p:IsA("BasePart") then pcall(function() p.CanCollide = false end) end
		end
	end

	espAcc = espAcc + dt
	if State.ESP and espAcc >= 1.25 then
		espAcc = 0
		pcall(refreshESP)
	end
end)

LP.CharacterAdded:Connect(function()
	task.wait(0.6)
	destroyChinaHat()
	if auraHL then pcall(function() auraHL:Destroy() end) auraHL = nil end
	if State.Fly then
		State.Fly = false
	end
	if State.FreeCam then
		stopFreeCam()
	end
	if State.ChinaHat then createChinaHat() end
	if State.Aura then setAura(true) end
	if State.InfJump then setInfJump(true) end
	if State.ESP then task.defer(refreshESP) end
end)

local Window = Library:CreateWindow({
	Name = "Horror Mini",
	Tagline = "v5 — Unfly",
	Role = "User",
	Logo = "",
	Discord = "",
	Telegram = "https://t.me/KvantTon",
	LockBranding = false,
	ToggleKey = Enum.KeyCode.RightShift,
})

local PlayerTab = Window:AddTab({ Name = "Player", Icon = "person" })
local VisualTab = Window:AddTab({ Name = "Visual", Icon = "eye" })
local DebugTab = Window:AddTab({ Name = "Debug", Icon = "code" })

PlayerTab:AddBanner({ Title = "Welcome to", Highlight = "Horror Mini", Subtitle = "Survival + movement" })

local secS = PlayerTab:AddSection({ Name = "Survival", Icon = "shield", Position = "left" })
local secP = PlayerTab:AddSection({ Name = "Movement", Icon = "bolt", Position = "right" })

secS:AddToggle({
	Name = "Infinite Stamina",
	Icon = "bolt",
	Default = false,
	Callback = function(v) State.InfStamina = v == true end,
})
secS:AddToggle({
	Name = "Infinite Oxygen",
	Icon = "droplet",
	Default = false,
	Callback = function(v) State.InfBreath = v == true end,
})
secS:AddToggle({
	Name = "Cold Protect",
	Icon = "shield",
	Default = false,
	Callback = function(v) State.InfCold = v == true end,
})
secS:AddButton({
	Name = "Scan Cold Values",
	ButtonText = "Scan",
	Callback = function()
		local list = findColdValues()
		local names = {}
		for _, v in ipairs(list) do
			names[#names + 1] = v:GetFullName() .. " = " .. tostring(v.Value)
		end
		Library:Notify({
			Title = "Cold Protect",
			Content = (#names > 0) and table.concat(names, "\n") or "No cold/temp values found",
			Duration = 5,
		})
	end,
})

secP:AddToggle({
	Name = "Noclip",
	Icon = "person",
	Default = false,
	Callback = function(v)
		State.Noclip = v == true
		if not State.Noclip then
			local c = getChar()
			if not c then return end
			for _, p in ipairs(c:GetDescendants()) do
				if p:IsA("BasePart") and p.Name ~= "HumanoidRootPart" then
					pcall(function() p.CanCollide = true end)
				end
			end
		end
	end,
})
secP:AddToggle({
	Name = "Infinite Jump",
	Icon = "person",
	Default = false,
	Callback = function(v) setInfJump(v == true) end,
})
secP:AddToggle({
	Name = "Speed Boost",
	Icon = "bolt",
	Default = false,
	Callback = function(v)
		State.Speed = v == true
		if not State.Speed then
			local hum = getHum()
			if hum then safeSetWalkSpeed(hum, realWalkSpeed) end
		end
	end,
})
secP:AddSlider({
	Name = "Speed Value",
	Icon = "bolt",
	Min = 12,
	Max = 50,
	Default = 22,
	Callback = function(v) State.SpeedValue = tonumber(v) or 22 end,
})
secP:AddToggle({
	Name = "Jump Boost",
	Icon = "person",
	Default = false,
	Callback = function(v)
		State.JumpPower = v == true
		if not State.JumpPower then
			local hum = getHum()
			if hum then safeSetJumpPower(hum, realJumpPower) end
		end
	end,
})
secP:AddSlider({
	Name = "Jump Value",
	Icon = "person",
	Min = 50,
	Max = 120,
	Default = 50,
	Callback = function(v) State.JumpValue = tonumber(v) or 50 end,
})
secP:AddToggle({
	Name = "Fly",
	Icon = "bolt",
	Default = false,
	Callback = function(v)
		State.Fly = v == true
		if not State.Fly then
			local c = getChar()
			local hrp = c and c:FindFirstChild("HumanoidRootPart")
			if hrp then pcall(function() hrp.AssemblyLinearVelocity = Vector3.zero end) end
		end
	end,
})
secP:AddSlider({
	Name = "Fly Speed",
	Icon = "bolt",
	Min = 16,
	Max = 120,
	Default = 40,
	Callback = function(v) State.FlySpeed = tonumber(v) or 40 end,
})

local secV = VisualTab:AddSection({ Name = "ESP", Icon = "eye", Position = "left" })
local secA = VisualTab:AddSection({ Name = "Self", Icon = "star", Position = "right" })
local secC = VisualTab:AddSection({ Name = "Camera", Icon = "image", Position = "left" })

secV:AddToggle({
	Name = "Mutant ESP",
	Icon = "eye",
	Default = false,
	Callback = function(v)
		State.ESP = v == true
		if State.ESP then refreshESP() else clearESP() end
	end,
})
secA:AddToggle({
	Name = "China Hat",
	Icon = "star",
	Default = false,
	Callback = function(v)
		State.ChinaHat = v == true
		if State.ChinaHat then createChinaHat() else destroyChinaHat() end
	end,
})
secA:AddToggle({
	Name = "Aura",
	Icon = "star",
	Default = false,
	Callback = function(v) setAura(v == true) end,
})
secC:AddToggle({
	Name = "Custom FOV",
	Icon = "eye",
	Default = false,
	Callback = function(v)
		State.FOV = v == true
		if not State.FOV then
			local cam = Workspace.CurrentCamera
			if cam and not State.FreeCam then cam.FieldOfView = defaultFOV end
		else
			applyFOV()
		end
	end,
})
secC:AddSlider({
	Name = "FOV Value",
	Icon = "eye",
	Min = 50,
	Max = 120,
	Default = 70,
	Callback = function(v)
		State.FOVValue = tonumber(v) or 70
		if State.FOV then applyFOV() end
	end,
})
secC:AddToggle({
	Name = "Free Camera",
	Icon = "eye",
	Default = false,
	Callback = function(v)
		if v then startFreeCam() else stopFreeCam() end
	end,
})
secC:AddSlider({
	Name = "FreeCam Speed",
	Icon = "bolt",
	Min = 20,
	Max = 150,
	Default = 60,
	Callback = function(v) State.FreeCamSpeed = tonumber(v) or 60 end,
})

local secD = DebugTab:AddSection({ Name = "Anti Cheat", Icon = "shield", Position = "left" })
secD:AddButton({
	Name = "Check Spoof",
	ButtonText = "Check",
	Callback = function()
		Library:Notify({
			Title = "Spoof",
			Content = "Metatable spoof disabled (AC detect)",
			Duration = 3,
		})
	end,
})
secD:AddButton({
	Name = "Scan AC Remotes",
	ButtonText = "Scan",
	Callback = function()
		local n = scanAntiCheatRemotes()
		Library:Notify({
			Title = "AC Remotes",
			Content = "Found remotes: " .. tostring(n) .. " (no patch)",
			Duration = 3,
		})
	end,
})
secD:AddButton({
	Name = "Show WalkSpeed",
	ButtonText = "Show",
	Callback = function()
		local hum = getHum()
		local ws = hum and tostring(hum.WalkSpeed) or "?"
		Library:Notify({
			Title = "WalkSpeed",
			Content = "Client sees: " .. ws .. " | real: " .. tostring(realWalkSpeed),
			Duration = 3,
		})
	end,
})

Library:Notify({
	Title = "Horror Mini",
	Content = "Loaded. RightShift to toggle UI.",
	Duration = 4,
})
print("[HorrorMini] UnflyUi — RightShift")
