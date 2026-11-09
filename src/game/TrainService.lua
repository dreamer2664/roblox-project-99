--!nocheck
-- TrainService: the railway controller.
--  * runs every consist along the alignment with TrainPhysics
--  * automatic timetable driving (brake curves into stations, dwell, reverse at termini)
--  * hands control to a player who sits in a cab seat
--  * signalling: line speed from curvature, overspeed protection, AWS-style warning
--  * broadcasts telemetry so clients can render HUDs, sounds and door lights
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Config = require(ReplicatedStorage:WaitForChild("Config"))
local TrainPhysics = require(ReplicatedStorage:WaitForChild("TrainPhysics"))
local TrackFollow = require(ReplicatedStorage:WaitForChild("TrackFollow"))
local TrackData = require(ReplicatedStorage:WaitForChild("TrackData"))

local Remotes = ReplicatedStorage:WaitForChild("Remotes")
local TrainCommand = Remotes:WaitForChild("TrainCommand")
local TrainTelemetry = Remotes:WaitForChild("TrainTelemetry")
local HornEvent = Remotes:WaitForChild("HornEvent")

local track = TrackFollow.new(TrackData)
local rollingStock = Workspace:WaitForChild("RollingStock")

--------------------------------------------------------------------------- stations
local stops = {}
for _, st in ipairs(TrackData.Stations) do
	local s = st.s
	if type(s) ~= "number" then
		if st.name:find("Viaduct") then
			s = (#TrackData.Points > 0) and TrackData.Length * 0.42 or 400
		elseif st.name:find("Harbour") then
			s = TrackData.Length - 120
		end
	end
	stops[#stops + 1] = {
		name = st.name,
		s = s,
		stopAt = st.stopAt or s,
		dwell = st.dwell or 20,
		terminus = (st.name:find("Terminus") ~= nil),
	}
end
table.sort(stops, function(a, b)
	return a.s < b.s
end)

--------------------------------------------------------------------------- speed limits
-- Lateral acceleration limit per unit curvature gives a realistic line speed.
local LAT_ACCEL = 1.45
local function lineSpeedAt(s)
	local smp = track:sample(s)
	local k = math.abs(smp.k)
	local v = 45
	if k > 1e-6 then
		v = math.min(v, math.sqrt(LAT_ACCEL / k))
	end
	-- approach restrictions: termini and the tunnel mouth
	for _, st in ipairs(stops) do
		if st.terminus then
			local d = math.abs(s - st.s)
			if d < 220 then
				v = math.min(v, 14 + d * 0.12)
			end
		end
	end
	return math.max(6, v)
end

--------------------------------------------------------------------------- controllers
local controllers = {}

local function collectVehicles(model)
	local list = {}
	for _, v in ipairs(model:GetChildren()) do
		if v:IsA("Model") and v:GetAttribute("Length") then
			list[#list + 1] = v
		end
	end
	table.sort(list, function(a, b)
		local na = tonumber(a.Name:match("%d+")) or 0
		local nb = tonumber(b.Name:match("%d+")) or 0
		return na < nb
	end)
	return list
end

local function newController(model, index)
	local vehicles = collectVehicles(model)
	local mass = 0
	local length = 0
	for _, v in ipairs(vehicles) do
		mass = mass + (v:GetAttribute("Mass") or 90)
		length = length + (v:GetAttribute("Length") or 10) + 0.8
	end
	local c = {
		model = model,
		name = model.Name,
		index = index,
		vehicles = vehicles,
		length = length,
		s = model:GetAttribute("StartS") or 40,
		dir = 1,
		mode = "auto",          -- auto | manual
		driver = nil,
		nextStop = 1,
		dwellUntil = 0,
		doorsOpen = false,
		physics = TrainPhysics.new({
			mass = mass,
			A = Config.Davis.A, B = Config.Davis.B, C = Config.Davis.C,
			tractiveEffort = Config.TractiveEffort,
			powerRating = Config.PowerRating,
			maxSpeed = Config.MaxSpeed,
			brakeRate = Config.BrakeRate,
			emergencyBrakeRate = Config.EmergencyBrakeRate,
			brakeBuildUp = Config.BrakeBuildUp,
			adhesion = Config.Adhesion,
			jerkLimit = Config.JerkLimit,
		}),
		notch = 0,
		brakeNotch = 0,
		emergency = false,
		lastUpdate = os.clock(),
		stopsMade = 0,
		distance = 0,
		hornUntil = 0,
		overspeed = false,
		awsWarning = false,
		lastSpeed = 0,
	}
	c.physics.direction = 1
	-- make sure every vehicle is anchored & welded (they ride on the alignment, not physics)
	for _, v in ipairs(vehicles) do
		for _, d in ipairs(v:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
			end
		end
	end
	return c
end

for i, model in ipairs(rollingStock:GetChildren()) do
	if model:IsA("Model") and model:GetAttribute("IsTrain") then
		local c = newController(model, i)
		controllers[#controllers + 1] = c
		print(string.format("[TrainService] %s ready: %d vehicles, %.0f t, %.0f m",
			c.name, #c.vehicles, c.physics.mass, c.length))
	end
end

--------------------------------------------------------------------------- helpers

local function stationFor(s)
	for i, st in ipairs(stops) do
		if math.abs(st.s - s) < 200 then
			return i, st
		end
	end
	return nil, nil
end

local function pickNextStop(c)
	local best, bestIdx = nil, nil
	for i, st in ipairs(stops) do
		local d = (st.s - c.s) * c.dir
		if d > 2 then
			if not best or d < best then
				best, bestIdx = d, i
			end
		end
	end
	return bestIdx or 1, best
end

local function applyVehicleDoorLights(c, open)
	for _, v in ipairs(c.vehicles) do
		local light = v:FindFirstChild("DoorLight", true)
		if light and light:IsA("BasePart") then
			light.Color = open and Color3.fromRGB(80, 230, 120) or Color3.fromRGB(220, 70, 60)
			light.Material = open and Enum.Material.Neon or Enum.Material.SmoothPlastic
		end
	end
end

local function honk(c, remote)
	c.hornUntil = os.clock() + Config.HornDuration
	HornEvent:FireAllClients(c.name, c.s)
end

--------------------------------------------------------------------------- driving

-- Automatic timetable driver: returns (throttle 0..1, brake 0..1)
local function autoDrive(c, dt, lineLimit)
	local target = c.nextStop or pickNextStop(c)
	local st = stops[target]
	if not st then
		-- nothing left in this direction: reverse at the end of the line
		c.dir = -c.dir
		return 0, 0.6
	end
	local remaining = (st.stopAt - c.s) * c.dir
	-- are we inside the dwell window?
	if c.dwellUntil > os.clock() then
		c.notch, c.brakeNotch = 0, 1
		if not c.doorsOpen and c.physics.speed < 0.15 then
			c.doorsOpen = true
			applyVehicleDoorLights(c, true)
			honk(c, true)
		end
		c.physics.brake = 1
		c.physics.throttle = 0
		return 0, 1
	end
	if c.doorsOpen then
		c.doorsOpen = false
		applyVehicleDoorLights(c, false)
	end

	-- arrival detection
	if remaining < 2.5 and math.abs(c.physics.speed) < 0.5 then
		c.dwellUntil = os.clock() + st.dwell
		c.stopsMade = c.stopsMade + 1
		-- score/stat bookkeeping handled by leaderstats below
		if c.driver then
			local ds = c.driver:FindFirstChild("leaderstats")
			if ds then
				local stops = ds:FindFirstChild("Stops")
				if stops then stops.Value = stops.Value + 1 end
			end
		end
		-- choose the next stop in the direction of travel, reversing at termini
		if st.terminus then
			c.dir = -c.dir
			c.nextStop = pickNextStop(c)
		else
			c.nextStop = pickNextStop(c)
			if not c.nextStop then
				c.dir = -c.dir
				c.nextStop = pickNextStop(c)
			end
		end
		return 0, 1
	end

	local v = math.abs(c.physics.speed)
	local limit = math.min(lineLimit, Config.PlayerTrainSpeedLimit)
	-- stopping curve
	local brakeDist = TrainPhysics.brakingDistance(v, Config.BrakeRate * 0.85, 1.0)
	local toStop = remaining - 0.5
	local targetSpeed
	if toStop <= 0 then
		targetSpeed = 0
	elseif brakeDist >= toStop then
		targetSpeed = math.max(0, math.sqrt(math.max(0, 2 * Config.BrakeRate * 0.85 * toStop)))
	else
		targetSpeed = limit
	end
	if c.dir < 0 then
		targetSpeed = math.min(targetSpeed, limit)
	end

	local err = targetSpeed - v
	local throttle, brake = 0, 0
	if err > 1.5 then
		throttle = math.clamp(err / 8, 0.15, 1)
	elseif err > 0.2 then
		throttle = 0.12
	elseif err < -1.0 then
		brake = math.clamp(-err / 6, 0.15, 1)
	else
		-- hold speed: coast with a nudge of power
		throttle = 0.08
	end
	-- smooth notches for realism
	c.notch = c.notch + math.clamp(throttle - c.notch, -dt * 2.2, dt * 2.2)
	c.brakeNotch = c.brakeNotch + math.clamp(brake - c.brakeNotch, -dt * 3.5, dt * 3.5)
	c.physics.throttle = c.notch
	c.physics.brake = c.brakeNotch
	return c.notch, c.brakeNotch
end

--------------------------------------------------------------------------- player control

function TrainCommand.OnServerEvent(player, trainName, command, value)
	local c
	for _, ctl in ipairs(controllers) do
		if ctl.name == trainName then
			c = ctl
		end
	end
	if not c then
		return
	end
	if command == "claim" then
		if c.driver == nil or c.driver == player then
			c.driver = player
			c.mode = "manual"
			c.nextStop = pickNextStop(c)
			c.dwellUntil = 0
			print("[TrainService] " .. player.Name .. " took control of " .. c.name)
		end
		return
	elseif command == "release" then
		if c.driver == player then
			c.driver = nil
			c.mode = "auto"
			c.notch = 0
			c.brakeNotch = 0
			c.physics.throttle = 0
			c.physics.brake = 0.6
		end
		return
	end
	if c.driver ~= player then
		return
	end
	if command == "throttle" then
		local notch = math.clamp(math.floor(tonumber(value) or 0), 0, Config.NotchCount)
		c.notch = notch / Config.NotchCount
		c.physics.throttle = c.notch
		c.brakeNotch = 0
		c.physics.brake = 0
	elseif command == "brake" then
		local b = math.clamp(tonumber(value) or 0, 0, 1)
		c.brakeNotch = b
		c.physics.brake = b
		if b > 0.05 then
			c.notch = 0
			c.physics.throttle = 0
		end
	elseif command == "direction" then
		if math.abs(c.physics.speed) < 0.4 then
			local d = tonumber(value)
			if d == 1 or d == -1 then
				c.dir = d
			else
				c.dir = -c.dir
			end
			c.nextStop = pickNextStop(c)
		end
	elseif command == "emergency" then
		c.emergency = not c.emergency
		c.physics.emergency = c.emergency
		if c.emergency then
			c.notch = 0
			c.physics.throttle = 0
		end
	elseif command == "horn" then
		honk(c, false)
	elseif command == "doors" then
		if math.abs(c.physics.speed) < 0.3 then
			c.doorsOpen = not c.doorsOpen
			applyVehicleDoorLights(c, c.doorsOpen)
			if c.doorsOpen then
				c.dwellUntil = os.clock() + 12
			end
		end
	elseif command == "dwellSkip" then
		c.dwellUntil = 0
		c.doorsOpen = false
		applyVehicleDoorLights(c, false)
	end
end

--------------------------------------------------------------------------- main loop

local telemetryClock = 0
local function updateTrain(c, dt)
	local p = c.physics
	local lineLimit = lineSpeedAt(c.s)
	local grade = track:sample(c.s).grade or 0
	local curv = track:sample(c.s).k or 0

	-- overspeed protection (like TPWS): a hard brake applies automatically
	if math.abs(p.speed) > math.max(Config.AwsSpeed, lineLimit) + Config.OverspeedTolerance * 2 then
		c.awsWarning = true
		p.brake = math.max(p.brake, 0.85)
		p.throttle = 0
	else
		c.awsWarning = math.abs(p.speed) > lineLimit + Config.OverspeedTolerance
	end

	if c.mode == "auto" then
		local throttle, brake = autoDrive(c, dt, lineLimit)
		if c.awsWarning and not c.dwellUntil or (c.dwellUntil > 0 and os.clock() < c.dwellUntil) then
			-- respect dwell braking, do not interfere
		end
		if c.awsWarning and os.clock() > (c.dwellUntil or 0) then
			p.throttle, p.brake = 0, math.max(brake, 0.85)
		else
			p.throttle, p.brake = throttle, brake
		end
	end

	local result = p:step(dt, grade * c.dir, curv)
	local moved = result.moved
	c.s = c.s + moved
	c.distance = c.distance + math.abs(moved)

	-- end of line protection
	if c.s > TrackData.Length - 12 then
		c.s = TrackData.Length - 12
		p.speed = 0
		c.dir = -1
		c.nextStop = pickNextStop(c)
	elseif c.s < 12 then
		c.s = 12
		p.speed = 0
		c.dir = 1
		c.nextStop = pickNextStop(c)
	end

	-- place the vehicles along the alignment
	track:placeConsist(c.model, c.s, 0)
	-- spin wheels at v / r
	track:spinWheels(c.model, p.speed, 0.46)

	c.lastSpeed = p.speed
	return result
end

local accum = 0
local UPDATE_HZ = 30
RunService.Heartbeat:Connect(function(dt)
	accum = accum + dt
	local step = 1 / UPDATE_HZ
	if accum < step then
		return
	end
	local frames = math.min(3, math.floor(accum / step))
	accum = accum - frames * step
	local useDt = math.min(0.12, dt * frames)
	for _, c in ipairs(controllers) do
		updateTrain(c, useDt)
	end

	-- telemetry to whoever cares (client HUD, cab screens)
	telemetryClock = telemetryClock + dt
	if telemetryClock > 0.1 then
		telemetryClock = 0
		for _, c in ipairs(controllers) do
			local target = stops[c.nextStop or 1]
			local remaining = target and (target.stopAt - c.s) * c.dir or 0
			TrainTelemetry:FireAllClients({
				name = c.name,
				s = c.s,
				speed = c.physics.speed * c.dir,
				kmh = math.abs(c.physics.speed) * 3.6,
				mph = math.abs(c.physics.speed) * 2.23694,
				throttle = c.notch,
				brake = math.max(c.brakeNotch, c.physics.brakeApplied),
				notch = math.round(c.notch * Config.NotchCount),
				direction = c.dir,
				doors = c.doorsOpen,
				mode = c.mode,
				driver = c.driver and c.driver.Name or "Auto",
				nextStop = target and target.name or "-",
				nextStopDist = math.floor(remaining),
				dwell = math.max(0, (c.dwellUntil or 0) - os.clock()),
				stops = c.stopsMade,
				energy = c.physics.energyUsed,
				lineLimit = lineSpeedAt(c.s),
				warning = c.awsWarning,
				emergency = c.emergency,
				horn = c.hornUntil > os.clock(),
				trackLength = TrackData.Length,
				grade = track:sample(c.s).grade or 0,
				traction = c.physics.appliedTractive,
			})
		end
	end
end)

--------------------------------------------------------------------------- leaderstats + cab seats

local function addLeaderstats(player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	stats.Parent = player
	local stopsV = Instance.new("IntValue")
	stopsV.Name = "Stops"
	stopsV.Value = 0
	stopsV.Parent = stats
	local distV = Instance.new("IntValue")
	distV.Name = "Distance"
	distV.Value = 0
	distV.Parent = stats
	player:SetAttribute("IsDriver", false)
end
Players.PlayerAdded:Connect(addLeaderstats)
for _, p in ipairs(Players:GetPlayers()) do
	addLeaderstats(p)
end

-- update Distance leaderstat from the train a player drives
task.spawn(function()
	while true do
		task.wait(2)
		for _, c in ipairs(controllers) do
			if c.driver and c.driver.Parent then
				local ds = c.driver:FindFirstChild("leaderstats")
				if ds then
					local dv = ds:FindFirstChild("Distance")
					if dv then
						dv.Value = math.floor(c.distance)
					end
				end
			end
		end
	end
end)

print("[TrainService] running with " .. #controllers .. " consist(s)")
