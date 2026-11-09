--!nocheck
-- rollingstock.lua : build physically-correct train vehicles from the CC0 kits.
--
-- Each vehicle is a Model with a PrimaryPart and a root Attachment ("Root") at the
-- rail centreline. Wheels are real cylinders on HingeConstraints, so the driving
-- script can spin them at v/r. Body shells come from the voxelised Kenney trains.
local rollingstock = {}

local kit, assets

rollingstock.SCALE = 4.55      -- studs per source unit: ~11 m vehicle, 4.35 m wide body
rollingstock.RAIL_TOP = 0.62   -- rail head height above ground (matches track module)
rollingstock.WHEEL_R = 0.46
rollingstock.BOGIE = 1.85

function rollingstock.init(k, a)
	kit, assets = k, a
end

local vehMeta = {}

local function newModel(parent, name)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

local function rootAttachment(m, cf)
	local parentPart = kit.firstBasePart(m)
	if not parentPart then
		return nil
	end
	local a = Instance.new("Attachment")
	a.Name = "Root"
	a.CFrame = cf
	a.Parent = parentPart
	return a
end

--------------------------------------------------------------------------- wheels

-- One axle: two wheel discs joined by a hinge so they spin together.
function rollingstock.axle(model, cf, gauge, radius, color)
	local r = radius
	local axle = Instance.new("Part")
	axle.Name = "Axle"
	axle.Shape = Enum.PartType.Cylinder
	axle.Size = Vector3.new(0.14, r * 0.55, r * 0.55)
	axle.CFrame = cf * CFrame.Angles(0, 0, math.rad(90))
	axle.Color = kit.col("steelDark")
	axle.Material = Enum.Material.Metal
	axle.CanCollide = false
	axle.Massless = true
	axle.Anchored = true
	axle.Parent = model

	local wheels = {}
	for _, side in ipairs({ -1, 1 }) do
		local w = Instance.new("Part")
		w.Name = "Wheel"
		w.Shape = Enum.PartType.Cylinder
		w.Size = Vector3.new(0.18, r * 2, r * 2)
		w.CFrame = cf * CFrame.new(side * gauge / 2, 0, 0) * CFrame.Angles(0, 0, math.rad(90))
		w.Color = kit.col(color or "steelDark")
		w.Material = Enum.Material.Metal
		w.CanCollide = false
		w.Massless = true
		w.Anchored = true
		w.Parent = model
		-- spoke detail so rotation is visible
		local spoke = Instance.new("Part")
		spoke.Name = "Spoke"
		spoke.Size = Vector3.new(0.06, r * 1.6, 0.2)
		spoke.CFrame = w.CFrame * CFrame.Angles(0, math.rad(90), 0)
		spoke.Color = kit.col("steel")
		spoke.Material = Enum.Material.Metal
		spoke.CanCollide = false
		spoke.Massless = true
		spoke.Anchored = true
		spoke.Parent = model
		wheels[#wheels + 1] = w
	end
	return axle, wheels
end

--------------------------------------------------------------------------- vehicle

-- spec = {
--   key = "loco_city_a", name = "Class 88 Electric",
--   kind = "loco" | "coach" | "wagon",
--   scale = 4.55, gauge = 1.435,
--   accent = "trainRed",   -- optional colour band
--   number = "88 014",
--   cabBoth = false, litWindows = true,
-- }
function rollingstock.vehicle(parent, spec)
	local data = assets[spec.key]
	assert(data, "missing vox asset " .. tostring(spec.key))
	local scale = spec.scale or rollingstock.SCALE
	-- Kenney's trains are toy-proportioned (height ≈ 0.7 × length). Squash them into a
	-- realistic loading gauge: 2.95 m wide, ~4.1 m tall, 10.5-11 m long.
	local target = spec.envelope or (spec.kind == "loco"
		and { w = 2.95, h = 4.10, l = 11.0 }
		or { w = 2.90, h = 4.05, l = 10.4 })
	local gauge = spec.gauge or 1.435
	local m = newModel(parent, spec.name or spec.key)
	kit.setAttr(m, "VehicleKind", spec.kind or "coach")

	-- ---------------------------------------------------------------- body shell
	local scale3 = {
		target.w / data.size[1],
		target.h / data.size[3],
		target.l / data.size[2],
	}
	local body = kit.vox(m, data, CFrame.new(0, rollingstock.RAIL_TOP, 0), scale, {
		name = "Shell",
		material = spec.material,
		scale3 = scale3,
	})
	-- seat the shell exactly on the rail head: measure, then shift
	do
		local minY, maxY = math.huge, -math.huge
		for _, d in ipairs(body:GetDescendants()) do
			if kit.isPart(d) then
				local y = d.CFrame.Position.Y
				local h = d.Size.Y / 2
				minY = math.min(minY, y - h)
				maxY = math.max(maxY, y + h)
			end
		end
		if minY < math.huge then
			local dy = rollingstock.RAIL_TOP - minY
			for _, d in ipairs(body:GetDescendants()) do
				if kit.isPart(d) then
					d.CFrame = CFrame.new(d.CFrame.Position + Vector3.new(0, dy, 0))
				end
			end
			print(string.format("  %s: shell %.2f..%.2f -> lifted %.2f", spec.name or spec.key,
				minY, maxY, dy))
		end
	end
	local shell = body:FindFirstChildWhichIsA("BasePart")
	if shell then
		pcall(function()
			m.PrimaryPart = shell
		end)
	end
	local root = rootAttachment(m, CFrame.new(0, rollingstock.RAIL_TOP + 1.1, 0))

	-- ---------------------------------------------------------------- wheels
	local halfLen = target.l / 2
	local rr = rollingstock.WHEEL_R
	local wheelY = rollingstock.RAIL_TOP + rr -- wheel tread sits ON the rail head
	local hingeList = {}
	for _, zsign in ipairs({ 1, -1 }) do
		local z = zsign * rollingstock.BOGIE
		for _, off in ipairs({ -0.62, 0.62 }) do
			local cf = CFrame.new(0, wheelY, z + off)
			local axle, wheels = rollingstock.axle(m, cf, gauge, rr, spec.wheelColor)
			local h = Instance.new("HingeConstraint")
			h.Name = "AxleHinge"
			pcall(function()
				h.ActuatorType = Enum.ActuatorType.Motor
				h.MotorMaxAcceleration = 1e6
				h.MotorMaxTorque = 1e6
				h.MotorMaxVelocity = 200
			end)
			local a0 = Instance.new("Attachment")
			a0.CFrame = CFrame.new(0, 0, 0)
			a0.Parent = axle
			local a1 = Instance.new("Attachment")
			a1.CFrame = CFrame.new(0, 0, 0)
			a1.Parent = wheels[1]
			pcall(function()
				h.Attachment0 = a0
				h.Attachment1 = a1
			end)
			h.Parent = axle
			hingeList[#hingeList + 1] = h
			-- mirror attachment axis for the far wheel
			local wc = Instance.new("WeldConstraint")
			pcall(function()
				wc.Part0 = wheels[1]
				wc.Part1 = wheels[2]
			end)
			wc.Parent = wheels[1]
		end
		-- bogie frame
		kit.b(m, CFrame.new(0, wheelY + 0.55, z), Vector3.new(gauge + 0.9, 0.5, 2.6),
			"steelDark", Enum.Material.Metal, { cast = false })
	end
	kit.setAttr(m, "HingeCount", #hingeList)

	-- ---------------------------------------------------------------- running gear detail
	-- buffer beam + buffers at both ends
	for _, zsign in ipairs({ 1, -1 }) do
		local z = zsign * (halfLen - 0.15)
		kit.b(m, CFrame.new(0, rollingstock.RAIL_TOP + 0.85, z), Vector3.new(gauge + 1.4, 0.55, 0.4),
			"trainDark", Enum.Material.Metal)
		for _, x in ipairs({ -0.85, 0.85 }) do
			kit.cyl(m, CFrame.new(x, rollingstock.RAIL_TOP + 0.85, z + zsign * 0.35), 0.42, 0.55,
				"steel", Enum.Material.Metal)
		end
		-- coupler
		kit.b(m, CFrame.new(0, rollingstock.RAIL_TOP + 0.45, z + zsign * 0.5),
			Vector3.new(0.35, 0.35, 0.9), "steelDark", Enum.Material.Metal)
	end

	-- gangway bellows for coaches
	if spec.kind == "coach" then
		for _, zsign in ipairs({ 1, -1 }) do
			local z = zsign * (halfLen - 0.05)
			kit.b(m, CFrame.new(0, rollingstock.RAIL_TOP + 1.9, z), Vector3.new(1.9, 2.3, 0.5),
				"trainDark", Enum.Material.Fabric)
		end
	end

	-- headlights + tail lights (loco only): neon lenses with point lights
	if spec.kind == "loco" then
		for _, zsign in ipairs({ 1, -1 }) do
			local z = zsign * (halfLen - 0.2)
			for _, x in ipairs({ -0.75, 0.75 }) do
				local lens = kit.cyl(m, CFrame.new(x, rollingstock.RAIL_TOP + 1.35, z)
					* CFrame.Angles(0, math.rad(90), 0), 0.34, 0.16, "lampWarm",
					Enum.Material.Neon, { cast = false })
				local pl = Instance.new("SpotLight")
				pl.Color = kit.col("lampWarm")
				pl.Range = 60
				pl.Angle = 55
				pl.Brightness = 2.4
				pl.Face = zsign > 0 and Enum.NormalId.Front or Enum.NormalId.Back
				pl.Parent = lens
			end
			-- number plate
			kit.surfaceText(m, CFrame.new(0, rollingstock.RAIL_TOP + 1.9, z),
				Vector3.new(2.2, 0.5, 0.1), zsign > 0 and Enum.NormalId.Front or Enum.NormalId.Back,
				spec.number or "88 014", "white", "trainDark", Enum.Font.GothamBold)
		end
	end

	-- power / pantograph on the loco roof
	if spec.kind == "loco" then
		local roofY = rollingstock.RAIL_TOP + target.h - 0.1
		kit.b(m, CFrame.new(0, roofY + 0.25, 0), Vector3.new(2.2, 0.5, 3.4), "trainDark",
			Enum.Material.Metal)
		-- pantograph arms (two angled beams + contact bar)
		local base = Vector3.new(0, roofY + 0.5, -0.6)
		kit.beam(m, base, base + Vector3.new(0, 1.5, 1.6), 0.18, "steel", Enum.Material.Metal)
		kit.beam(m, base + Vector3.new(0, 1.5, 1.6), base + Vector3.new(0, 2.2, 0.2), 0.16,
			"steel", Enum.Material.Metal)
		kit.b(m, CFrame.new(base + Vector3.new(0, 2.25, 0.2)), Vector3.new(2.4, 0.12, 0.3),
			"railTop", Enum.Material.Metal)
	end

	-- accent stripe (livery) on coaches
	if spec.accent then
		for _, side in ipairs({ -1, 1 }) do
			kit.b(m, CFrame.new(side * (target.w / 2 - 0.05),
				rollingstock.RAIL_TOP + 1.55, 0), Vector3.new(0.1, 0.42, target.l - 0.8),
				spec.accent, Enum.Material.SmoothPlastic, { cast = false })
		end
	end

	-- interior glow for lit coaches
	if spec.litWindows then
		local l = Instance.new("PointLight")
		l.Color = Color3.fromRGB(255, 236, 200)
		l.Range = 9
		l.Brightness = 0.5
		l.Parent = shell
	end

	-- physics: mass makes the loco genuinely heavy to stop
	local mass = spec.mass or (spec.kind == "loco" and 180 or 90)
	for _, d in ipairs(m:GetDescendants()) do
		if kit.isPart(d) then
			d.Massless = true
		end
	end
	pcall(function()
		shell.CustomPhysicalProperties = PhysicalProperties.new(7.85, 0.4, 0.3, mass, mass)
	end)

	-- air brake attributes read by the train controller
	kit.setAttr(m, "BrakeForce", spec.brakeForce or (spec.kind == "loco" and 260 or 120))
	kit.setAttr(m, "RollingResistance", 0.9)
	kit.setAttr(m, "Length", target.l)
	kit.setAttr(m, "HalfLength", halfLen)
	kit.setAttr(m, "Gauge", gauge)
	kit.setAttr(m, "Mass", mass)

	pcall(function()
		m.Description = string.format("%s (%s) - voxelised from %s, CC0",
			spec.name or spec.key, spec.kind or "coach", data.source)
	end)
	local meta = { model = m, length = target.l, halfLength = halfLen,
		mass = mass, key = spec.key }
	return m, root, meta
end

--------------------------------------------------------------------------- consists

-- Build an entire train. Returns model + ordered list of vehicle models.
-- spec = { vehicles = { {key=..., kind=..., name=...}, ... }, gap = 0.6, name = ... }
function rollingstock.consist(parent, spec)
	local m = newModel(parent, spec.name or "Train")
	kit.setAttr(m, "IsTrain", true)
	local list = {}
	local metas = {}
	local cursor = 0
	for i, v in ipairs(spec.vehicles) do
		local vspec = {}
		for k, val in pairs(v) do
			vspec[k] = val
		end
		vspec.kind = vspec.kind or (i == 1 and "loco" or "coach")
		vspec.name = vspec.name or string.format("Vehicle%d", i)
		local veh, _, meta = rollingstock.vehicle(m, vspec)
		list[#list + 1] = veh
		metas[#metas + 1] = meta
	end
	-- stack them nose to tail along -Z, centred on the consist origin
	local total = 0
	local lens = {}
	for i, veh in ipairs(list) do
		local L = metas[i].length
		lens[i] = L
		total = total + L + (i > 1 and (spec.gap or 0.7) or 0)
	end
	local z = -total / 2
	for i, veh in ipairs(list) do
		local L = lens[i]
		local target = z + L / 2
		kit.pivotTo(veh, CFrame.new(0, 0, target))
		z = z + L + (spec.gap or 0.7)
	end
	pcall(function()
		m.PrimaryPart = kit.firstBasePart(list[1])
	end)
	m.Name = spec.name or "Train"
	local firstPart = kit.firstBasePart(m)
	local root = Instance.new("Attachment")
	root.Name = "TrainRoot"
	root.CFrame = CFrame.new(0, rollingstock.RAIL_TOP + 1.1, 0)
	if firstPart then
		root.Parent = firstPart
	end
	kit.setAttr(m, "VehicleCount", #list)
	kit.setAttr(m, "ConsistLength", total)
	return m, list, metas
end

return rollingstock
