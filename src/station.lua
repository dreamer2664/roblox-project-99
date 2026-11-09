--!nocheck
-- station.lua : procedural railway station architecture
-- Terminus hall (trainshed + trusses + clock tower), through station with island
-- platform, canopy, footbridge, and platform furniture. Everything is generated from
-- the track alignment so platforms always line up with the rails.
local station = {}

local kit, track

function station.init(k, t)
	kit, track = k, t
end

--------------------------------------------------------------------------- small parts

local function girderTruss(store, cf, span, depth, color, segs)
	-- a pitched parallel-chord truss lying in the XY plane of cf, spanning local Z
	segs = segs or 6
	local half = span / 2
	local chord = 0.34
	local top = cf * CFrame.new(0, depth, 0)
	kit.b(store, cf * CFrame.new(0, 0, 0), Vector3.new(chord, chord * 0.8, span), color,
		Enum.Material.Metal)
	kit.b(store, top, Vector3.new(chord * 0.7, chord * 0.7, span), color, Enum.Material.Metal)
	local step = span / segs
	for i = 0, segs do
		local z = -half + i * step
		kit.b(store, cf * CFrame.new(0, depth / 2, z), Vector3.new(chord * 0.6, depth, chord * 0.6),
			color, Enum.Material.Metal)
		if i < segs then
			local a = cf * CFrame.new(0, 0.0, z)
			local b = top * CFrame.new(0, 0, z + step)
			local d = b.Position - a.Position
			local mid = (a.Position + b.Position) / 2
			local rot = CFrame.lookAt(mid, mid + d)
			kit.b(store, rot, Vector3.new(chord * 0.45, chord * 0.45, d.Magnitude), color,
				Enum.Material.Metal)
		end
	end
end

local function fenceRun(store, cf, length, height, color, spacing)
	spacing = spacing or 4
	local n = math.max(1, math.floor(length / spacing))
	for i = 0, n do
		local z = -length / 2 + i * (length / n)
		kit.b(store, cf * CFrame.new(0, height / 2, z), Vector3.new(0.18, height, 0.18), color,
			Enum.Material.Metal)
	end
	kit.b(store, cf * CFrame.new(0, height, 0), Vector3.new(0.1, 0.12, length), color, Enum.Material.Metal)
	kit.b(store, cf * CFrame.new(0, height * 0.55, 0), Vector3.new(0.08, 0.08, length), color,
		Enum.Material.Metal)
end

local function lampPost(store, cf, color, height)
	height = height or 6.4
	kit.b(store, cf * CFrame.new(0, height / 2, 0), Vector3.new(0.3, height, 0.3), color or "steelDark",
		Enum.Material.Metal)
	kit.b(store, cf * CFrame.new(0, height + 0.1, 0.5), Vector3.new(0.22, 0.22, 1.2),
		color or "steelDark", Enum.Material.Metal)
	kit.lamp(store, cf * CFrame.new(0, height - 0.1, 1.05), "lampWarm", 24, 1.4)
end

--------------------------------------------------------------------------- platform furniture

-- Bench: seat + back + legs
function station.bench(store, cf, color)
	color = color or "wood"
	kit.b(store, cf * CFrame.new(0, 0.95, 0), Vector3.new(0.7, 0.14, 2.6), color, Enum.Material.WoodPlanks)
	kit.b(store, cf * CFrame.new(-0.3, 1.35, 0), Vector3.new(0.12, 0.8, 2.6), color,
		Enum.Material.WoodPlanks)
	for _, z in ipairs({ -1.0, 1.0 }) do
		for _, x in ipairs({ -0.22, 0.22 }) do
			kit.b(store, cf * CFrame.new(x, 0.47, z), Vector3.new(0.1, 0.94, 0.1), "steelDark",
				Enum.Material.Metal)
		end
	end
end

-- Platform name sign on twin posts
function station.nameSign(store, cf, text, width)
	width = width or 9
	for _, x in ipairs({ -width / 2 + 0.4, width / 2 - 0.4 }) do
		kit.b(store, cf * CFrame.new(x, 1.6, 0), Vector3.new(0.22, 3.2, 0.22), "steelDark",
			Enum.Material.Metal)
	end
	kit.surfaceText(store, cf * CFrame.new(0, 3.2, 0), Vector3.new(width, 1.5, 0.24),
		Enum.NormalId.Front, text, "white", "signBlue")
	kit.surfaceText(store, cf * CFrame.new(0, 3.2, 0), Vector3.new(width, 1.5, 0.24),
		Enum.NormalId.Back, text, "white", "signBlue")
end

-- Ticket machine / departure board / bin
function station.furnitureSet(store, cf)
	-- ticket machine
	local tm = cf * CFrame.new(-1.6, 0, 0)
	kit.b(store, tm * CFrame.new(0, 0.9, 0), Vector3.new(0.9, 1.8, 0.7), "steelDark", Enum.Material.Metal)
	kit.b(store, tm * CFrame.new(0, 1.45, 0.36), Vector3.new(0.62, 0.5, 0.06), "glass",
		Enum.Material.Neon)
	kit.surfaceText(store, tm * CFrame.new(0, 1.45, 0.4), Vector3.new(0.6, 0.48, 0.04),
		Enum.NormalId.Front, "TICKETS", "signalGreen", "trainDark", Enum.Font.GothamBold)
	-- bin
	kit.cyl(store, cf * CFrame.new(1.5, 0.55, 0) * CFrame.Angles(0, math.rad(90), 0), 0.7, 1.1,
		"signBlue", Enum.Material.SmoothPlastic)
	-- departure board on posts
	local db = cf * CFrame.new(3.6, 0, 0)
	kit.b(store, db * CFrame.new(0, 1.3, 0), Vector3.new(0.16, 2.6, 0.16), "steelDark", Enum.Material.Metal)
	kit.surfaceText(store, db * CFrame.new(0, 2.7, 0), Vector3.new(3.2, 1.1, 0.16),
		Enum.NormalId.Front, "DEPARTURES  09:42  PLATFORM 1", "amber", "trainDark",
		Enum.Font.Code)
end

--------------------------------------------------------------------------- canopy

-- Platform canopy: columns, arched roof, glazing.  cf = centre of the platform at ground level.
function station.canopy(store, cf, length, width, opts)
	opts = opts or {}
	local spacing = opts.spacing or 9
	local height = opts.height or 7.2
	local n = math.max(1, math.floor(length / spacing))
	local roofY = height
	for i = 0, n do
		local z = -length / 2 + i * (length / n)
		local col = cf * CFrame.new(0, 0, z)
		if opts.island then
			for _, x in ipairs({ -width / 2 + 0.8, width / 2 - 0.8 }) do
				kit.b(store, col * CFrame.new(x, height / 2, 0), Vector3.new(0.42, height, 0.42),
					"steelDark", Enum.Material.Metal)
			end
		else
			kit.b(store, col * CFrame.new(-width / 2 + 1.2, height / 2, 0),
				Vector3.new(0.42, height, 0.42), "steelDark", Enum.Material.Metal)
		end
		-- cross beam
		local spanW = opts.island and (width - 1.6) or (width / 2 + 1.2)
		local beamCf = opts.island and col * CFrame.new(0, height, 0)
			or col * CFrame.new(-width / 4 + 0.6, height, 0)
		kit.b(store, beamCf, Vector3.new(spanW, 0.42, 0.42), "steelDark", Enum.Material.Metal)
		-- arched ribs
		local ribs = 5
		for r = 0, ribs do
			local t = r / ribs
			local x = (t - 0.5) * spanW
			local y = height + 1.6 * (1 - (2 * t - 1) ^ 2)
			kit.b(store, beamCf * CFrame.new(x, y - height, 0), Vector3.new(0.22, 0.22, 0.3),
				"steel", Enum.Material.Metal)
		end
	end
	-- roof deck (arched, made of stepped slabs) + glazing strips
	local segs = math.max(4, math.floor(length / 3))
	local ribs = 8
	for i = 1, segs do
		local z0 = -length / 2 + (i - 1) * (length / segs)
		local z1 = -length / 2 + i * (length / segs)
		local zc = (z0 + z1) / 2
		local spanW = opts.island and (width - 0.8) or (width / 2 + 2.2)
		local ctrX = opts.island and 0 or (-width / 4 + 0.6)
		for r = 0, ribs - 1 do
			local t0 = r / ribs
			local t1 = (r + 1) / ribs
			local x0 = (t0 - 0.5) * spanW
			local x1 = (t1 - 0.5) * spanW
			local y = height + 1.6 * (1 - (2 * ((t0 + t1) / 2) - 1) ^ 2)
			local glass = (r % 2 == 0)
			kit.b(store, cf * CFrame.new(ctrX + (x0 + x1) / 2, y, zc),
				Vector3.new(math.abs(x1 - x0) + 0.05, 0.16, (z1 - z0) + 0.05),
				glass and "glassDark" or "steel", Enum.Material.Glass,
				{ trans = glass and 0.35 or 0, cast = false, reflect = 0.1 })
		end
	end
	-- fascia + platform lighting
	kit.b(store, cf * CFrame.new(opts.island and 0 or (-width / 4 + 0.6), height + 0.15, 0),
		Vector3.new(opts.island and (width - 0.8) or (width / 2 + 2.2), 0.5, length),
		"trainBlue", Enum.Material.SmoothPlastic, { cast = false })
	for i = 1, math.floor(length / 12) do
		local z = -length / 2 + (i - 0.5) * (length / math.floor(length / 12))
		for _, x in ipairs(opts.island and { -width / 3, width / 3 } or { -width / 4 }) do
			kit.lamp(store, cf * CFrame.new(x, height - 0.2, z), "lampWarm", 30, 1.9)
		end
		for _, x in ipairs(opts.island and { -width / 3, width / 3 } or { -width / 4 }) do
			kit.b(store, cf * CFrame.new(x, height - 0.05, z), Vector3.new(0.5, 0.18, 0.5),
				"trainDark", Enum.Material.Metal)
		end
	end
end

--------------------------------------------------------------------------- through station

-- Builds an island platform between two parallel tracks.
-- bakedA/bakedB : alignments of the two tracks
-- s0            : arclength of platform start, length : platform length
function station.islandPlatform(store, bakedA, bakedB, s0, length, opts)
	opts = opts or {}
	local width = opts.width or 11
	local height = opts.height or 1.15
	local m = kit.model(store, opts.name or "IslandPlatform")

	-- centre point midway between the two tracks at the platform middle
	local aMid = track.cframe(bakedA, s0 + length / 2)
	local bMid = track.cframe(bakedB, s0 + length / 2)
	local mid = (aMid.Position + bMid.Position) / 2
	local heading = aMid.LookVector
	local cf = CFrame.lookAt(Vector3.new(mid.X, opts.base or 0, mid.Z),
		Vector3.new(mid.X, opts.base or 0, mid.Z) + heading)

	-- deck (in segments so it can follow a curve)
	local segs = math.max(6, math.floor(length / 6))
	for i = 1, segs do
		local t0 = (i - 1) / segs
		local t1 = i / segs
		local sA = s0 + length * (t0 + t1) / 2
		local ca = track.cframe(bakedA, sA)
		local cb = track.cframe(bakedB, sA)
		local c = (ca.Position + cb.Position) / 2
		local segLen = length / segs + 0.15
		local segCf = CFrame.lookAt(Vector3.new(c.X, opts.base or 0, c.Z),
			Vector3.new(c.X, opts.base or 0, c.Z) + ca.LookVector)
		kit.b(m, segCf * CFrame.new(0, height / 2, 0),
			Vector3.new(width, height, segLen), "concrete", Enum.Material.Concrete)
		-- coping stones along both edges
		for _, x in ipairs({ -width / 2 + 0.35, width / 2 - 0.35 }) do
			kit.b(m, segCf * CFrame.new(x, height + 0.06, 0),
				Vector3.new(0.7, 0.14, segLen), "concreteDark", Enum.Material.Concrete)
		end
		-- yellow tactile edge strips (the detail that sells a station)
		for _, x in ipairs({ -width / 2 + 1.5, width / 2 - 1.5 }) do
			kit.b(m, segCf * CFrame.new(x, height + 0.14, 0),
				Vector3.new(0.55, 0.05, segLen), "tactile", Enum.Material.SmoothPlastic,
				{ cast = false })
		end
	end

	-- platform furniture along the centreline
	for i = 1, math.floor(length / 18) do
		local s = s0 + (i - 0.5) * (length / math.floor(length / 18))
		local ca = track.cframe(bakedA, s)
		local cb = track.cframe(bakedB, s)
		local c = (ca.Position + cb.Position) / 2
		local fcf = CFrame.lookAt(Vector3.new(c.X, opts.base or 0, c.Z),
			Vector3.new(c.X, opts.base or 0, c.Z) + ca.LookVector)
		station.bench(m, fcf * CFrame.new(0, height, 0))
		station.bench(m, fcf * CFrame.new(0, height, 0) * CFrame.Angles(0, math.rad(180), 0))
	end

	station.canopy(m, cf + Vector3.new(0, height, 0) + Vector3.new(0, 0, 0), length, width,
		{ island = true, height = opts.canopyHeight or 6.4 })

	for i = 1, math.floor(length / 40) do
		local s = s0 + (i - 0.5) * (length / math.floor(length / 40))
		local ca = track.cframe(bakedA, s)
		local cb = track.cframe(bakedB, s)
		local c = (ca.Position + cb.Position) / 2
		local fcf = CFrame.lookAt(Vector3.new(c.X, height, c.Z),
			Vector3.new(c.X, height, c.Z) + ca.LookVector)
		station.nameSign(m, fcf * CFrame.new(0, 0, 0), opts.signText or "CENTRAL  1  |  2")
	end
	return m
end

--------------------------------------------------------------------------- terminus hall

-- Grand terminus: trainshed roof over the tracks, head-house facade with clock tower,
-- concourse, and side platforms.
--   baked : alignment; sConcourse : arclength of the station head; tracks : {baked...}
function station.terminus(store, baked, sHead, opts)
	opts = opts or {}
	local hallLength = opts.hallLength or 150
	local hallWidth = opts.hallWidth or 64
	local height = opts.height or 19
	local m = kit.model(store, opts.name or "Terminus")

	local cf0 = track.cframe(baked, sHead)
	local origin = Vector3.new(cf0.Position.X, 0, cf0.Position.Z)
	local fwd = cf0.LookVector -- trainshed extends along the direction of travel
	local cf = CFrame.lookAt(origin, origin + fwd)

	-- ---------------------------------------------------------------- trainshed structure
	local bays = math.max(4, math.floor(hallLength / 25))
	local bayLen = hallLength / bays
	for i = 0, bays do
		local z = -i * bayLen
		-- main columns along both sides
		for _, x in ipairs({ -hallWidth / 2, hallWidth / 2 }) do
			if i < bays then
				kit.b(m, cf * CFrame.new(x, height / 2, z), Vector3.new(1.1, height, 1.1),
					"steelDark", Enum.Material.Metal)
				-- capital detail
				kit.b(m, cf * CFrame.new(x, height - 0.6, z), Vector3.new(1.5, 0.7, 1.5),
					"steel", Enum.Material.Metal)
				kit.b(m, cf * CFrame.new(x, 1.0, z), Vector3.new(1.6, 2.0, 1.6), "concreteDark",
					Enum.Material.Concrete)
			end
		end
		-- main arched truss across the hall
		if i < bays then
			local z2 = z - bayLen / 2
			-- lower chord
			kit.b(m, cf * CFrame.new(0, height, z2), Vector3.new(hallWidth, 0.6, 0.6), "steelDark",
				Enum.Material.Metal)
			-- arch ribs (stepped approximation of an arc)
			local steps = 16
			for s = 0, steps do
				local t = s / steps
				local x = (t - 0.5) * hallWidth
				local y = height + 7.5 * math.sin(math.pi * t)
				kit.b(m, cf * CFrame.new(x, y, z2), Vector3.new(0.7, 0.7, 0.7), "steel",
					Enum.Material.Metal)
				if s < steps then
					local t2 = (s + 1) / steps
					local x2 = (t2 - 0.5) * hallWidth
					local y2 = height + 7.5 * math.sin(math.pi * t2)
					kit.beam(m, cf * CFrame.new(x, y, z2).Position, cf * CFrame.new(x2, y2, z2).Position,
						0.34, "steelDark", Enum.Material.Metal)
					-- hanger to lower chord
					if s % 2 == 0 then
						kit.b(m, cf * CFrame.new(x, (y + height) / 2, z2),
							Vector3.new(0.22, y - height, 0.22), "steelDark", Enum.Material.Metal)
					end
				end
			end
		end
		-- glazed roof deck between bays
		if i < bays then
			local z2 = z - bayLen / 2
			local steps = 14
			for s = 0, steps - 1 do
				local t0 = s / steps
				local t1 = (s + 1) / steps
				local x0 = (t0 - 0.5) * hallWidth
				local x1 = (t1 - 0.5) * hallWidth
				local y0 = height + 7.5 * math.sin(math.pi * t0)
				local y1 = height + 7.5 * math.sin(math.pi * t1)
				local glass = s % 3 ~= 0
				local mid = cf * CFrame.new((x0 + x1) / 2, (y0 + y1) / 2 - 0.4, z2)
				local d = Vector3.new(x1 - x0, y1 - y0, 0)
				local rot = CFrame.lookAt(mid.Position, mid.Position + d.Unit)
				kit.b(m, rot, Vector3.new(d.Magnitude + 0.1, 0.14, bayLen + 0.1),
					glass and "glassDark" or "steel", glass and Enum.Material.Glass or Enum.Material.Metal,
					{ trans = glass and 0.4 or 0, cast = false, reflect = 0.08 })
			end
			-- purlins
			for s = 1, 3 do
				local t = s / 4
				local x = (t - 0.5) * hallWidth
				local y = height + 7.5 * math.sin(math.pi * t) - 0.25
				kit.b(m, cf * CFrame.new(x, y, z2), Vector3.new(0.2, 0.2, bayLen), "steel",
					Enum.Material.Metal)
			end
		end
	end

	-- hall side walls: brick piers + arched windows + buttresses
	local wallN = math.floor(hallLength / 8)
	for i = 0, wallN do
		local z = -i * (hallLength / wallN)
		for _, x in ipairs({ -hallWidth / 2, hallWidth / 2 }) do
			if i < wallN then
				local segLen = hallLength / wallN
				-- spandrel wall above platform level with tall windows
				kit.b(m, cf * CFrame.new(x, height / 2, z - segLen / 2),
					Vector3.new(1.0, height, segLen - 1.0), "brick", Enum.Material.Brick,
					{ cast = false })
				-- window (arched top approximated with 3 pieces)
				local wz = z - segLen / 2
				local wx = x - math.sign(x) * 0.55
				kit.b(m, cf * CFrame.new(wx, height * 0.55, wz), Vector3.new(0.2, height * 0.42, segLen * 0.45),
					"glassDark", Enum.Material.Glass, { trans = 0.25, reflect = 0.1 })
				kit.b(m, cf * CFrame.new(wx, height * 0.55 + height * 0.21 + 0.3, wz),
					Vector3.new(0.2, 0.6, segLen * 0.3), "glassDark", Enum.Material.Glass,
					{ trans = 0.25 })
				-- buttress
				kit.b(m, cf * CFrame.new(x - math.sign(x) * 0.8, height * 0.35, z),
					Vector3.new(1.4, height * 0.7, 1.2), "brick", Enum.Material.Brick)
				-- sill + string course
				kit.b(m, cf * CFrame.new(wx, height * 0.32, wz), Vector3.new(0.45, 0.25, segLen * 0.55),
					"concrete", Enum.Material.Concrete)
			end
		end
	end

	-- ---------------------------------------------------------------- head house (facade)
	local facadeZ = 6
	local facadeH = 26
	local facadeW = hallWidth + 16
	-- main block
	kit.b(m, cf * CFrame.new(0, facadeH / 2, facadeZ), Vector3.new(facadeW, facadeH, 14),
		"cream", Enum.Material.Concrete)
	-- rusticated base
	kit.b(m, cf * CFrame.new(0, 3, facadeZ + 7.2), Vector3.new(facadeW + 1, 6, 1.2), "concreteDark",
		Enum.Material.Concrete)
	-- entrance colonnade
	local cols = 10
	for i = 0, cols do
		local x = -facadeW / 2 + 4 + (i / cols) * (facadeW - 8)
		kit.b(m, cf * CFrame.new(x, 6.5, facadeZ + 7.6), Vector3.new(1.3, 13, 1.3), "cream",
			Enum.Material.Concrete)
		kit.b(m, cf * CFrame.new(x, 13.2, facadeZ + 7.6), Vector3.new(1.9, 0.8, 1.9), "cream",
			Enum.Material.Concrete)
	end
	-- entablature + cornice
	kit.b(m, cf * CFrame.new(0, 14.0, facadeZ + 7.6), Vector3.new(facadeW - 1, 1.6, 2.4), "cream",
		Enum.Material.Concrete)
	kit.b(m, cf * CFrame.new(0, 15.2, facadeZ + 7.8), Vector3.new(facadeW, 0.8, 3.0), "concreteDark",
		Enum.Material.Concrete)
	-- arched window course above the colonnade
	local wins = 12
	for i = 0, wins - 1 do
		local x = -facadeW / 2 + 5 + (i + 0.5) / wins * (facadeW - 10)
		kit.b(m, cf * CFrame.new(x, 18.6, facadeZ + 7.1), Vector3.new(2.6, 4.2, 0.3), "glassDark",
			Enum.Material.Glass, { trans = 0.2, reflect = 0.12 })
		kit.b(m, cf * CFrame.new(x, 20.7, facadeZ + 7.15), Vector3.new(2.0, 0.9, 0.3), "glassDark",
			Enum.Material.Glass, { trans = 0.2 })
		kit.b(m, cf * CFrame.new(x, 16.4, facadeZ + 7.2), Vector3.new(2.9, 0.3, 0.45), "concreteDark",
			Enum.Material.Concrete)
	end
	-- attic + parapet
	kit.b(m, cf * CFrame.new(0, 23.6, facadeZ), Vector3.new(facadeW, 4.0, 15), "cream",
		Enum.Material.Concrete)
	kit.b(m, cf * CFrame.new(0, 25.8, facadeZ + 7.4), Vector3.new(facadeW + 2, 0.9, 1.2),
		"concreteDark", Enum.Material.Concrete)

	-- clock tower
	local tw = 13
	kit.b(m, cf * CFrame.new(0, 14 + tw * 0.9, facadeZ + 2), Vector3.new(tw, tw * 1.8, tw),
		"cream", Enum.Material.Concrete)
	for level = 1, 3 do
		local y = 14 + 4.2 * level
		kit.b(m, cf * CFrame.new(0, y, facadeZ + 2), Vector3.new(tw + 0.8, 0.5, tw + 0.8),
			"concreteDark", Enum.Material.Concrete)
	end
	-- clock faces (4)
	local clockY = 14 + tw * 1.35
	for _, spec in ipairs({
		{ off = Vector3.new(0, 0, tw / 2 + 0.1), face = Enum.NormalId.Front },
		{ off = Vector3.new(0, 0, -tw / 2 - 0.1), face = Enum.NormalId.Back },
		{ off = Vector3.new(tw / 2 + 0.1, 0, 0), face = Enum.NormalId.Right },
		{ off = Vector3.new(-tw / 2 - 0.1, 0, 0), face = Enum.NormalId.Left },
	}) do
		local base = cf * CFrame.new(0, clockY, facadeZ + 2) + spec.off
		kit.b(m, base, Vector3.new(tw * 0.62, tw * 0.62, 0.4), "white", Enum.Material.SmoothPlastic)
		kit.b(m, base, Vector3.new(tw * 0.52, tw * 0.52, 0.5), "cream", Enum.Material.SmoothPlastic)
		-- hands
		local handCf = CFrame.lookAt(base.Position + Vector3.new(0, 0, 0), base.Position + spec.off.Unit)
		kit.b(m, base + spec.off.Unit * 0.35 + Vector3.new(0, 1.1, 0),
			Vector3.new(0.16, 2.4, 0.12), "trainDark", Enum.Material.Metal)
		kit.b(m, base + spec.off.Unit * 0.35 + Vector3.new(0, 0.6, 0),
			Vector3.new(1.8, 0.16, 0.12), "trainDark", Enum.Material.Metal)
	end
	-- tower roof (pyramid via stacked wedges)
	local baseY = 14 + tw * 1.8
	for i = 0, 7 do
		local t = i / 8
		local w = tw * (1 - t) + 0.5
		kit.b(m, cf * CFrame.new(0, baseY + i * 1.5, facadeZ + 2), Vector3.new(w, 1.6, w),
			"slate", Enum.Material.Slate)
	end
	kit.b(m, cf * CFrame.new(0, baseY + 12.4, facadeZ + 2), Vector3.new(0.5, 3.2, 0.5), "amber",
		Enum.Material.Metal)
	-- station clock text on facade
	kit.surfaceText(m, cf * CFrame.new(0, 17.4, facadeZ + 8.5), Vector3.new(facadeW * 0.55, 2.2, 0.3),
		Enum.NormalId.Front, "GRAND CENTRAL TERMINUS", "trainDark", "cream", Enum.Font.Antique)

	-- ---------------------------------------------------------------- platform slabs
	local platY = 1.15
	for side = -1, 1, 2 do
		local x = side * (hallWidth / 2 - 7)
		for i = 1, bays do
			local z = -(i - 0.5) * bayLen
			kit.b(m, cf * CFrame.new(x, platY / 2, z), Vector3.new(12, platY, bayLen - 0.2),
				"concrete", Enum.Material.Concrete)
			kit.b(m, cf * CFrame.new(x - side * 5.5, platY + 0.05, z), Vector3.new(0.6, 0.1, bayLen - 0.2),
				"tactile", Enum.Material.SmoothPlastic, { cast = false })
		end
	end
	-- buffer stops at the head end of each platform road
	for _, x in ipairs({ -18, -6, 6, 18 }) do
		local bz = -6
		kit.b(m, cf * CFrame.new(x, 1.4, bz), Vector3.new(3.2, 2.8, 2.0), "trainRed",
			Enum.Material.SmoothPlastic)
		kit.b(m, cf * CFrame.new(x, 3.1, bz), Vector3.new(3.6, 0.5, 2.2), "trainDark",
			Enum.Material.Metal)
		kit.b(m, cf * CFrame.new(x, 2.0, bz + 1.2), Vector3.new(0.7, 0.7, 0.7), "signalRed",
			Enum.Material.Neon)
	end

	-- concourse floor + info boards
	kit.b(m, cf * CFrame.new(0, 0.15, facadeZ - 2), Vector3.new(facadeW - 4, 0.3, 20), "concreteDark",
		Enum.Material.Concrete)
	for i = -3, 3 do
		local x = i * 7
		kit.surfaceText(m, cf * CFrame.new(x, 5.2, facadeZ + 7.0), Vector3.new(5.2, 1.6, 0.2),
			Enum.NormalId.Back, string.format("PLATFORM %d   %02d:%02d", math.abs(i) + 1,
				9 + (i % 3), 12 + math.abs(i) * 7), "amber", "trainDark", Enum.Font.Code)
	end
	lampPost(m, cf * CFrame.new(0, 0, facadeZ + 9), "steelDark", 7)
	return m
end

return station
