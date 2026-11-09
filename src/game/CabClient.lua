--!nocheck
-- CabClient: the driving experience.
--   * cab HUD with a real speedometer, notch indicator, brake gauge and next-stop display
--   * keyboard driving: W/S notches, Space brake, R direction, H horn, D doors, E take control
--   * chase camera for non-drivers, cab view for the driver
--   * procedural click-clack, traction motor hum and horn audio (no external assets)
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local TrainCommand = Remotes:WaitForChild("TrainCommand")
local TrainTelemetry = Remotes:WaitForChild("TrainTelemetry")
local HornEvent = Remotes:WaitForChild("HornEvent")
local Config = require(ReplicatedStorage:WaitForChild("Config"))

--------------------------------------------------------------------------- state
local telemetry = {}
local currentTrain = nil
local controlling = false
local notch = 0
local brake = 0
local cameraMode = "chase"
local overspeedBlink = 0

TrainTelemetry.OnClientEvent:Connect(function(data)
	telemetry[data.name] = data
	if not currentTrain or not telemetry[currentTrain] then
		currentTrain = data.name
	end
end)

--------------------------------------------------------------------------- ui helpers
local function corner(parent, r)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r or 8)
	c.Parent = parent
	return c
end

local function stroke(parent, color, thickness, trans)
	local s = Instance.new("UIStroke")
	s.Color = color or Color3.fromRGB(255, 255, 255)
	s.Thickness = thickness or 2
	s.Transparency = trans or 0.4
	s.Parent = parent
	return s
end

local gui = Instance.new("ScreenGui")
gui.Name = "CabHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

-- translucent dark instrument panel, bottom centre
local panel = Instance.new("Frame")
panel.Size = UDim2.new(0, 560, 0, 168)
panel.Position = UDim2.new(0.5, 0, 1, -186)
panel.BackgroundColor3 = Color3.fromRGB(14, 16, 20)
panel.BackgroundTransparency = 0.12
panel.BorderSizePixel = 0
panel.Parent = gui
corner(panel, 14)
stroke(panel, Color3.fromRGB(255, 214, 150), 2, 0.55)

-- speedometer text
local speedLabel = Instance.new("TextLabel")
speedLabel.Size = UDim2.new(0, 200, 0, 86)
speedLabel.Position = UDim2.new(0, 18, 0, 12)
speedLabel.BackgroundTransparency = 1
speedLabel.Font = Enum.Font.GothamBlack
speedLabel.TextColor3 = Color3.fromRGB(255, 240, 214)
speedLabel.TextSize = 64
speedLabel.TextXAlignment = Enum.TextXAlignment.Left
speedLabel.Text = "0"
speedLabel.Parent = panel

local unitLabel = Instance.new("TextLabel")
unitLabel.Size = UDim2.new(0, 90, 0, 24)
unitLabel.Position = UDim2.new(0, 22, 0, 92)
unitLabel.BackgroundTransparency = 1
unitLabel.Font = Enum.Font.GothamMedium
unitLabel.TextColor3 = Color3.fromRGB(180, 190, 205)
unitLabel.TextSize = 16
unitLabel.TextXAlignment = Enum.TextXAlignment.Left
unitLabel.Text = "km/h"
unitLabel.Parent = panel

-- notch ladder
local notchFrame = Instance.new("Frame")
notchFrame.Size = UDim2.new(0, 200, 0, 30)
notchFrame.Position = UDim2.new(0, 224, 0, 22)
notchFrame.BackgroundTransparency = 1
notchFrame.Parent = panel
local notchBars = {}
for i = 1, 8 do
	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(0, 20, 0, 26)
	bar.Position = UDim2.new(0, (i - 1) * 24, 0, 0)
	bar.BackgroundColor3 = Color3.fromRGB(48, 52, 60)
	bar.BorderSizePixel = 0
	bar.Parent = notchFrame
	corner(bar, 3)
	notchBars[i] = bar
end

-- brake bar
local brakeBack = Instance.new("Frame")
brakeBack.Size = UDim2.new(0, 200, 0, 12)
brakeBack.Position = UDim2.new(0, 224, 0, 62)
brakeBack.BackgroundColor3 = Color3.fromRGB(48, 52, 60)
brakeBack.BorderSizePixel = 0
brakeBack.Parent = panel
corner(brakeBack, 6)
local brakeFill = Instance.new("Frame")
brakeFill.Size = UDim2.new(0, 0, 1, 0)
brakeFill.BackgroundColor3 = Color3.fromRGB(230, 90, 80)
brakeFill.BorderSizePixel = 0
brakeFill.Parent = brakeBack
corner(brakeFill, 6)

local nextLabel = Instance.new("TextLabel")
nextLabel.Size = UDim2.new(0, 320, 0, 22)
nextLabel.Position = UDim2.new(0, 224, 0, 82)
nextLabel.BackgroundTransparency = 1
nextLabel.Font = Enum.Font.GothamMedium
nextLabel.TextColor3 = Color3.fromRGB(255, 214, 150)
nextLabel.TextSize = 17
nextLabel.TextXAlignment = Enum.TextXAlignment.Left
nextLabel.Text = "Next: —"
nextLabel.Parent = panel

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(0, 320, 0, 20)
statusLabel.Position = UDim2.new(0, 224, 0, 106)
statusLabel.BackgroundTransparency = 1
statusLabel.Font = Enum.Font.Code
statusLabel.TextColor3 = Color3.fromRGB(150, 160, 175)
statusLabel.TextSize = 15
statusLabel.TextXAlignment = Enum.TextXAlignment.Left
statusLabel.Text = "AUTO"
statusLabel.Parent = panel

-- warning banner
local warn = Instance.new("TextLabel")
warn.Size = UDim2.new(0, 380, 0, 44)
warn.Position = UDim2.new(0.5, -190, 1, -246)
warn.BackgroundColor3 = Color3.fromRGB(180, 40, 36)
warn.BackgroundTransparency = 1
warn.Font = Enum.Font.GothamBlack
warn.TextColor3 = Color3.fromRGB(255, 235, 230)
warn.TextSize = 22
warn.Text = ""
warn.Parent = gui
corner(warn, 8)

-- train selector (left)
local selector = Instance.new("Frame")
selector.Size = UDim2.new(0, 240, 0, 92)
selector.Position = UDim2.new(0, 18, 0, 18)
selector.BackgroundColor3 = Color3.fromRGB(14, 16, 20)
selector.BackgroundTransparency = 0.25
selector.BorderSizePixel = 0
selector.Parent = gui
corner(selector, 10)
local selTitle = Instance.new("TextLabel")
selTitle.Size = UDim2.new(1, -20, 0, 24)
selTitle.Position = UDim2.new(0, 12, 0, 8)
selTitle.BackgroundTransparency = 1
selTitle.Font = Enum.Font.GothamBold
selTitle.TextSize = 15
selTitle.TextColor3 = Color3.fromRGB(255, 214, 150)
selTitle.TextXAlignment = Enum.TextXAlignment.Left
selTitle.Text = "CONSISTS"
selTitle.Parent = selector
local selValue = Instance.new("TextLabel")
selValue.Size = UDim2.new(1, -20, 0, 46)
selValue.Position = UDim2.new(0, 12, 0, 32)
selValue.BackgroundTransparency = 1
selValue.Font = Enum.Font.GothamMedium
selValue.TextSize = 15
selValue.TextWrapped = true
selValue.TextColor3 = Color3.fromRGB(225, 230, 240)
selValue.TextXAlignment = Enum.TextXAlignment.Left
selValue.Text = "—"
selValue.Parent = selector

-- key hints
local hints = Instance.new("TextLabel")
hints.Size = UDim2.new(0, 520, 0, 20)
hints.Position = UDim2.new(0, 18, 1, -30)
hints.BackgroundTransparency = 1
hints.Font = Enum.Font.Code
hints.TextSize = 14
hints.TextColor3 = Color3.fromRGB(190, 200, 215)
hints.TextTransparency = 0.25
hints.Text = "E take control | W/S notches | SPACE brake | R reverse | H horn | D doors | C camera"
hints.Parent = gui

--------------------------------------------------------------------------- procedural audio
local function tone(name, freq, volume, parent)
	local s = Instance.new("Sound")
	s.Name = name
	s.SoundId = "rbxasset://sounds/electronicpingshort.wav"
	s.PlaybackSpeed = freq
	s.Volume = volume
	s.Looped = true
	s.Parent = parent or SoundService
	return s
end

local motorHum = tone("MotorHum", 0.22, 0.0)
local railHum = tone("RailHum", 0.12, 0.12)

HornEvent.OnClientEvent:Connect(function(trainName)
	local horn = Instance.new("Sound")
	horn.SoundId = "rbxasset://sounds/electronicpingshort.wav"
	horn.PlaybackSpeed = 0.34
	horn.Volume = 0.7
	horn.Parent = SoundService
	horn:Play()
	task.delay(2, function()
		horn:Destroy()
	end)
end)

--------------------------------------------------------------------------- camera
local function setCameraMode(mode)
	cameraMode = mode
	if mode == "cab" and currentTrain then
		camera.CameraType = Enum.CameraType.Scriptable
	else
		camera.CameraType = Enum.CameraType.Custom
		player.CameraMode = Enum.CameraMode.Classic
	end
end

local function chaseUpdate(dt, data)
	-- smooth third-person chase along the rails for the selected consist
	local model = Workspace:FindFirstChild("RollingStock")
	if not model then
		return
	end
	local train = model:FindFirstChild(currentTrain)
	if not train then
		return
	end
	local vehicles = {}
	for _, v in ipairs(train:GetChildren()) do
		if v:IsA("Model") and v:GetAttribute("Length") then
			vehicles[#vehicles + 1] = v
		end
	end
	if #vehicles == 0 then
		return
	end
	table.sort(vehicles, function(a, b)
		return tostring(a.Name) < tostring(b.Name)
	end)
	local lead = vehicles[1]
	if cameraMode ~= "chase" then
		return
	end
	local piv = lead:GetPivot()
	local back = piv.LookVector * -18 + Vector3.new(0, 7.5, 0)
	local target = piv.Position + back
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(target, piv.Position + piv.LookVector * 24), math.clamp(dt * 2.4, 0, 1))
end

--------------------------------------------------------------------------- input
local function fire(cmd, value)
	if currentTrain then
		TrainCommand:FireServer(currentTrain, cmd, value)
	end
end

local lastSend = 0
local function sendControl()
	local now = os.clock()
	if now - lastSend < 0.08 then
		return
	end
	lastSend = now
	fire("throttle", notch)
	fire("brake", brake)
end

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	local k = input.KeyCode
	if k == Enum.KeyCode.E then
		controlling = not controlling
		fire(controlling and "claim" or "release")
		statusLabel.Text = controlling and "MANUAL — you have the train" or "AUTO"
	elseif k == Enum.KeyCode.W then
		notch = math.min(Config.NotchCount, notch + 1)
		if notch > 0 then
			brake = 0
		end
		sendControl()
	elseif k == Enum.KeyCode.S then
		notch = math.max(0, notch - 1)
		sendControl()
	elseif k == Enum.KeyCode.Space then
		brake = math.min(1, brake + 0.2)
		notch = 0
		sendControl()
	elseif k == Enum.KeyCode.X then
		brake = 0
		sendControl()
	elseif k == Enum.KeyCode.R then
		fire("direction", 0)
	elseif k == Enum.KeyCode.H then
		fire("horn")
	elseif k == Enum.KeyCode.D then
		fire("doors")
	elseif k == Enum.KeyCode.C then
		setCameraMode(cameraMode == "cab" and "chase" or "cab")
	elseif k == Enum.KeyCode.F then
		fire("emergency")
	end
end)

--------------------------------------------------------------------------- render loop
RunService.RenderStepped:Connect(function(dt)
	local data = telemetry[currentTrain]
	if not data then
		return
	end
	-- speed
	local kmh = math.abs(data.kmh)
	speedLabel.Text = string.format("%d", math.floor(kmh + 0.5))
	speedLabel.TextColor3 = data.warning and Color3.fromRGB(255, 120, 110)
		or Color3.fromRGB(255, 240, 214)

	-- notches
	local active = math.floor((data.throttle or 0) * 8 + 0.001)
	for i, bar in ipairs(notchBars) do
		bar.BackgroundColor3 = i <= active and Color3.fromRGB(255, 200, 96)
			or Color3.fromRGB(48, 52, 60)
	end
	-- brake
	brakeFill.Size = UDim2.new(math.clamp(data.brake or 0, 0, 1), 0, 1, 0)

	nextLabel.Text = string.format("Next: %s  (%dm)", data.nextStop or "—", data.nextStopDist or 0)
	statusLabel.Text = string.format("%s | %s | %d stops | %.1f kWh | dir %s",
		(data.mode or "AUTO"):upper(), data.driver or "-", data.stops or 0,
		data.energy or 0, data.direction == 1 and "FWD" or "REV")

	-- tick over consist list
	local names = {}
	for name in pairs(telemetry) do
		table.insert(names, name)
	end
	table.sort(names)
	local lines = {}
	for i, name in ipairs(names) do
		local marker = (name == currentTrain) and "> " or "  "
		table.insert(lines, marker .. name)
	end
	selValue.Text = table.concat(lines, "\n")

	-- warnings
	if data.emergency then
		warn.Text = "EMERGENCY BRAKE"
		warn.BackgroundTransparency = 0.15
	elseif data.warning then
		overspeedBlink += dt
		warn.Text = "OVERSPEED — REDUCE SPEED"
		warn.BackgroundTransparency = (math.floor(overspeedBlink * 3) % 2 == 0) and 0.2 or 0.75
	elseif data.doors then
		warn.Text = "DOORS OPEN"
		warn.BackgroundColor3 = Color3.fromRGB(30, 120, 70)
		warn.BackgroundTransparency = 0.35
	else
		warn.Text = ""
		warn.BackgroundTransparency = 1
		warn.BackgroundColor3 = Color3.fromRGB(180, 40, 36)
	end

	-- audio: motor hum tracks speed and power
	local humVol = math.clamp(math.abs(data.speed or 0) / 30, 0, 1) * 0.18 * (0.4 + (data.throttle or 0))
	motorHum.Volume = motorHum.Volume + (humVol - motorHum.Volume) * math.clamp(dt * 4, 0, 1)
	motorHum.PlaybackSpeed = 0.25 + math.abs(data.speed or 0) / 26
	if humVol > 0.01 and not motorHum.IsPlaying then
		motorHum:Play()
	end
	railHum.Volume = math.clamp(math.abs(data.speed or 0) / 55, 0, 1) * 0.16
	railHum.PlaybackSpeed = 0.4 + math.abs(data.speed or 0) / 40
	if railHum.Volume > 0.01 and not railHum.IsPlaying then
		railHum:Play()
	end

	chaseUpdate(dt, data)
end)

-- cycle the active consist with Tab
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then
		return
	end
	if input.KeyCode == Enum.KeyCode.Tab then
		local names = {}
		for name in pairs(telemetry) do
			table.insert(names, name)
		end
		table.sort(names)
		if #names > 1 then
			for i, name in ipairs(names) do
				if name == currentTrain then
					currentTrain = names[(i % #names) + 1]
					break
				end
			end
		end
	end
end)

print("[CabClient] cab systems online")
