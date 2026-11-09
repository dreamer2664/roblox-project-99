--!nocheck
-- StationService: platform screens, announcements, signal aspects and crowd behaviour.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local TrackData = require(ReplicatedStorage:WaitForChild("TrackData"))
local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local TrainTelemetry = Remotes:WaitForChild("TrainTelemetry")

local stationsFolder = Workspace:WaitForChild("Stations")
local infra = Workspace:WaitForChild("Infrastructure")

--------------------------------------------------------------------------- signal aspects
-- Drives the neon lenses we generated: find every signal head and remember its lenses.
local signals = {}
for _, d in ipairs(infra:GetDescendants()) do
	if d:IsA("Part") and d.Shape == Enum.PartType.Cylinder and d.Material == Enum.Material.Neon then
		local head = d.Parent
		if head then
			local key = tostring(head)
			signals[key] = signals[key] or { lenses = {}, head = head }
			table.insert(signals[key].lenses, d)
		end
	end
end

local function setAspect(entry, aspect)
	-- lenses are ordered red, amber, green, green in creation order
	local palette = {
		{ "signalRed", 2 }, { "amber", 3 }, { "signalGreen", 4 }, { "signalGreen", 4 },
	}
	for i, lens in ipairs(entry.lenses) do
		local def = palette[i] or palette[3]
		local on = (def[2] == aspect)
		lens.Material = on and Enum.Material.Neon or Enum.Material.Metal
		lens.Color = on and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(40, 42, 46)
		if on then
			lens.Color = (aspect == 1) and Color3.fromRGB(255, 70, 60)
				or (aspect == 2) and Color3.fromRGB(255, 180, 60)
				or Color3.fromRGB(80, 235, 140)
		end
	end
end

--------------------------------------------------------------------------- platform screens
local boards = {}
for _, d in ipairs(stationsFolder:GetDescendants()) do
	if d:IsA("SurfaceGui") then
		local label = d:FindFirstChildWhichIsA("TextLabel")
		if label and (label.Text:find("DEPART") or label.Text:find("PLATFORM")) then
			boards[#boards + 1] = label
		end
	end
end
print("[StationService] found " .. #boards .. " departure boards and " .. #signals .. " signal heads")

local function fmtTime(offset)
	local t = os.date("*t")
	local mins = t.min + offset
	local h = t.hour + math.floor(mins / 60)
	mins = mins % 60
	return string.format("%02d:%02d", h % 24, mins)
end

local rows = {
	{ dest = "GRAND CENTRAL", plat = 1, offset = 4 },
	{ dest = "HARBOUR TERM", plat = 2, offset = 9 },
	{ dest = "GLANNE HALT", plat = 3, offset = 14 },
	{ dest = "GRAND CENTRAL", plat = 4, offset = 21 },
}

task.spawn(function()
	while true do
		for i, board in ipairs(boards) do
			local row = rows[((i - 1) % #rows) + 1]
			board.Text = string.format("%s  %s  PLT %d", row.dest, fmtTime(row.offset), row.plat)
			board.TextColor3 = Config.RoseGold
		end
		task.wait(6)
	end
end)

--------------------------------------------------------------------------- announcements
local sound = Instance.new("Sound")
sound.Name = "StationChime"
sound.SoundId = "rbxasset://sounds/electronicpingshort.wav"
sound.Volume = 0.55
sound.RollOffMode = Enum.RollOffMode.InverseTapered
sound.Parent = Workspace

local announceAt = {}
for _, st in ipairs(TrackData.Stations) do
	announceAt[#announceAt + 1] = type(st.s) == "number" and st.s or nil
end

local lastTelemetry = {}
TrainTelemetry.OnServerEvent:Connect(function() end) -- no client->server telemetry needed

--------------------------------------------------------------------------- crowd
-- Idle people sway slightly and turn to face arriving trains.
local crowds = Workspace:FindFirstChild("Crowds")
if crowds then
	for _, person in ipairs(crowds:GetChildren()) do
		if person:IsA("Model") then
			local base = person:GetPivot()
			person:SetAttribute("HomeY", base.Position.Y)
			person:SetAttribute("Phase", math.random() * math.pi * 2)
			task.spawn(function()
				local t0 = os.clock()
				while person.Parent do
					task.wait(0.12)
					local ph = person:GetAttribute("Phase") or 0
					local bob = math.sin((os.clock() + ph) * 2.4) * 0.02
					local piv = person:GetPivot()
					person:PivotTo(CFrame.new(piv.Position + Vector3.new(0, bob, 0))
						* (piv - piv.Position))
				end
			end)
		end
	end
end

--------------------------------------------------------------------------- main loop
local cycle = 0
task.spawn(function()
	while true do
		cycle = cycle + 1
		-- stagger signal aspects so the line reads as "occupied ahead"
		for key, entry in pairs(signals) do
			local aspect = ((cycle + #key) % 4) + 1
			setAspect(entry, math.min(3, aspect))
		end
		if cycle % 5 == 0 then
			sound.PlaybackSpeed = 1 + (cycle % 3) * 0.03
			sound:Play()
		end
		task.wait(4)
	end
end)

print("[StationService] online")
