--!nocheck
-- scenery.lua : railway infrastructure - OLE/catenary, signals, gantries, viaduct,
-- river, tunnel, retaining walls, lineside furniture.
local scenery = {}

local kit, track

function scenery.init(k, t)
	kit, track = k, t
end

--------------------------------------------------------------------------- catenary

-- Overhead line equipment: masts, cantilever arms, messenger + contact wire, droppers.
function scenery.catenary(store, baked, s0, s1, opts)
	opts = opts or {}
	local alt = opts.spacing or 46
	local side = 1
	local mastH = 8.4
	local m = kit.folder(store, opts.name or "OHLE")
	local s = s0
	local masts = {}
	while s < s1 do
		local cf, sample = track.cframe(baked, s, 0)
		side = -side
		local mcf = cf * CFrame.new(side * 4.0, 0, 0)
		-- mast
		kit.b(m, mcf * CFrame.new(0, mastH / 2, 0), Vector3.new(0.34, mastH, 0.34),
			"steelDark", Enum.Material.Metal)
		kit.b(m, mcf * CFrame.new(0, 0.25, 0), Vector3.new(1.0, 0.5, 1.0), "concrete",
			Enum.Material.Concrete)
		-- cantilever arm reaching over the track
		kit.b(m, mcf * CFrame.new(-side * 2.0, mastH - 0.3, 0),
			Vector3.new(4.2, 0.16, 0.16), "steel", Enum.Material.Metal)
		kit.b(m, mcf * CFrame.new(-side * 1.6, mastH - 1.3, 0),
			Vector3.new(3.6, 0.12, 0.12), "steel", Enum.Material.Metal)
		-- registration arm + insulators
		kit.b(m, mcf * CFrame.new(-side * 3.9, mastH - 0.9, 0),
			Vector3.new(0.12, 1.4, 0.12), "steel", Enum.Material.Metal)
		kit.b(m, mcf * CFrame.new(-side * 3.9, mastH - 1.55, 0),
			Vector3.new(0.22, 0.3, 0.22), "cream", Enum.Material.SmoothPlastic)
		masts[#masts + 1] = { s = s, h = sample.h }
		s = s + alt
	end
	-- wires: messenger (droopy) + contact (nearly straight) + droppers
	local span = alt
	local segs = 6
	for i = 1, #masts - 1 do
		local sa, sb = masts[i].s, masts[i + 1].s
		for j = 0, segs - 1 do
			local t0 = j / segs
			local t1 = (j + 1) / segs
			local q0 = track.cframe(baked, sa + (sb - sa) * t0, 0)
			local q1 = track.cframe(baked, sa + (sb - sa) * t1, 0)
			local droop = 0.55
			local y0 = 6.9 - droop * math.sin(math.pi * t0)
			local y1 = 6.9 - droop * math.sin(math.pi * t1)
			kit.beam(m, q0.Position + Vector3.new(0, y0, 0), q1.Position + Vector3.new(0, y1, 0),
				0.07, "steelDark", Enum.Material.Metal)
			kit.beam(m, q0.Position + Vector3.new(0, 5.9, 0), q1.Position + Vector3.new(0, 5.9, 0),
				0.09, "railTop", Enum.Material.Metal)
			-- dropper
			if j % 2 == 0 then
				kit.b(m, CFrame.new(q0.Position + Vector3.new(0, (y0 + 5.9) / 2, 0)),
					Vector3.new(0.05, y0 - 5.9, 0.05), "steelDark", Enum.Material.Metal)
			end
		end
	end
	return m
end

--------------------------------------------------------------------------- signals

-- A four-aspect signal head on a post, mounted at trackside.
function scenery.signal(store, baked, s, aspect, opts)
	opts = opts or {}
	local cf = track.cframe(baked, s, 0)
	local side = opts.side or 1
	local base = cf * CFrame.new(side * 3.4, 0, 0)
	local h = 5.6
	local post = kit.b(store, base * CFrame.new(0, h / 2, 0), Vector3.new(0.28, h, 0.28),
		"steelDark", Enum.Material.Metal)
	kit.b(store, base * CFrame.new(0, 0.2, 0), Vector3.new(0.8, 0.4, 0.8), "concrete",
		Enum.Material.Concrete)
	-- signal head
	local head = base * CFrame.new(0, h + 0.6, 0)
	local headPart = kit.b(store, head, Vector3.new(0.6, 1.9, 0.42), "trainDark",
		Enum.Material.Metal)
	local lights = { "signalRed", "amber", "signalGreen", "signalGreen" }
	for i, c in ipairs(lights) do
		local on = (aspect == i)
		local lens = head * CFrame.new(0, 0.66 - (i - 1) * 0.44, 0.24) * CFrame.Angles(0, math.rad(90), 0)
		kit.cyl(store, lens, 0.26, 0.12, on and c or "trainDark",
			on and Enum.Material.Neon or Enum.Material.Metal, { cast = false })
		if on then
			local pl = Instance.new("PointLight")
			pl.Color = kit.col(c)
			pl.Range = 10
			pl.Brightness = 1.2
			pl.Parent = headPart
		end
	end
	-- identification plate + route indicator box
	kit.b(store, head * CFrame.new(0, 1.05, 0), Vector3.new(0.7, 0.35, 2), "white",
		Enum.Material.SmoothPlastic)
	return head
end

-- Portal signal gantry spanning one or two tracks
function scenery.gantry(store, baked, s, aspects)
	local cf = track.cframe(baked, s, 0)
	local m = kit.model(store, "SignalGantry")
	local span = 15
	local h = 7.6
	for _, x in ipairs({ -span / 2, span / 2 }) do
		kit.b(m, cf * CFrame.new(x, h / 2, 0), Vector3.new(0.5, h, 0.5), "steelDark",
			Enum.Material.Metal)
		kit.b(m, cf * CFrame.new(x, 0.3, 0), Vector3.new(1.2, 0.6, 1.2), "concrete",
			Enum.Material.Concrete)
	end
	kit.b(m, cf * CFrame.new(0, h, 0), Vector3.new(span + 0.6, 0.45, 0.45), "steelDark",
		Enum.Material.Metal)
	kit.b(m, cf * CFrame.new(0, h - 1.2, 0), Vector3.new(span, 0.2, 0.2), "steel", Enum.Material.Metal)
	for i, x in ipairs({ -4.2, 4.2 }) do
		local head = cf * CFrame.new(x, h - 1.5, 0)
		kit.b(m, head, Vector3.new(0.55, 1.7, 0.4), "trainDark", Enum.Material.Metal)
		local aspect = (aspects and aspects[i]) or 3
		for k, c in ipairs({ "signalRed", "amber", "signalGreen", "signalGreen" }) do
			local on = (aspect == k)
			kit.cyl(m, head * CFrame.new(0, 0.6 - (k - 1) * 0.4, 0.22) * CFrame.Angles(0, math.rad(90), 0),
				0.24, 0.12, on and c or "trainDark",
				on and Enum.Material.Neon or Enum.Material.Metal)
		end
	end
	return m
end

--------------------------------------------------------------------------- viaduct + river

-- Masonry viaduct carrying the alignment between s0 and s1, with arches and piers.
function scenery.viaduct(store, baked, s0, s1, deckY, opts)
	opts = opts or {}
	local m = kit.model(store, opts.name or "Viaduct")
	local pierEvery = opts.pierEvery or 34
	local width = opts.width or 13
	local n = math.max(1, math.floor((s1 - s0) / pierEvery))

	-- deck: chained segments following the alignment
	local segEvery = 6
	local nseg = math.max(1, math.floor((s1 - s0) / segEvery))
	for i = 1, nseg do
		local sA = s0 + (i - 1) * segEvery
		local sB = math.min(s0 + i * segEvery, s1)
		local mid = (sA + sB) / 2
		local cf = track.cframe(baked, mid, 0)
		local len = (sB - sA) + 0.2
		-- deck slab
		kit.b(m, CFrame.new(cf.Position + Vector3.new(0, deckY - 0.5, 0)) * (cf - cf.Position),
			Vector3.new(width, 1.0, len), "concreteDark", Enum.Material.Concrete)
		-- parapets
		for _, x in ipairs({ -width / 2 + 0.3, width / 2 - 0.3 }) do
			kit.b(m, CFrame.new(cf.Position + Vector3.new(0, deckY + 0.5, 0)) * (cf - cf.Position)
				* CFrame.new(x, 0, 0), Vector3.new(0.6, 1.0, len), "brick", Enum.Material.Brick)
		end
		-- arch soffit / spandrel walls
		kit.b(m, CFrame.new(cf.Position + Vector3.new(0, deckY - 2.2, 0)) * (cf - cf.Position),
			Vector3.new(width - 1.2, 2.4, len), "brick", Enum.Material.Brick)
	end

	-- piers at regular intervals with arch rings between them
	for i = 0, n do
		local s = s0 + i * pierEvery
		if s <= s1 then
			local cf = track.cframe(baked, s, 0)
			local baseCf = CFrame.new(Vector3.new(cf.Position.X, 0, cf.Position.Z))
				* (cf - cf.Position)
			-- pier body
			kit.b(m, baseCf * CFrame.new(0, deckY / 2, 0), Vector3.new(4.4, deckY, 5.4),
				"brick", Enum.Material.Brick)
			-- plinth + cornice
			kit.b(m, baseCf * CFrame.new(0, 0.6, 0), Vector3.new(5.6, 1.2, 6.6), "concreteDark",
				Enum.Material.Concrete)
			kit.b(m, baseCf * CFrame.new(0, deckY - 1.6, 0), Vector3.new(5.2, 0.8, 6.2),
				"concreteDark", Enum.Material.Concrete)
			-- buttress faces
			for _, zside in ipairs({ -1, 1 }) do
				kit.wedge(m, baseCf * CFrame.new(0, deckY * 0.45, zside * 3.1)
					* CFrame.Angles(math.rad(-90 * zside), 0, 0),
					Vector3.new(4.0, deckY * 0.9, 1.6), "brick", Enum.Material.Brick)
			end
		end
	end
	-- arch rings between piers (semicircular, built from short radial boxes)
	for i = 1, n do
		local s = s0 + (i - 0.5) * pierEvery
		local cf = track.cframe(baked, s, 0)
		local span = pierEvery - 5.4
		local steps = 9
		for j = 0, steps - 1 do
			local t0 = j / steps
			local t1 = (j + 1) / steps
			local z0 = (t0 - 0.5) * span
			local z1 = (t1 - 0.5) * span
			local y0 = deckY - 3.4 + math.sin(math.pi * t0) * 3.2
			local y1 = deckY - 3.4 + math.sin(math.pi * t1) * 3.2
			local p0 = cf.Position + cf.LookVector * z0 + Vector3.new(0, y0, 0)
			local p1 = cf.Position + cf.LookVector * z1 + Vector3.new(0, y1, 0)
			for _, x in ipairs({ -3.6, 3.6 }) do
				local a = p0 + cf.RightVector * x
				local b = p1 + cf.RightVector * x
				kit.beam(m, a, b, 1.1, "brick", Enum.Material.Brick)
			end
		end
	end
	return m
end

-- River below a viaduct: water slab, banks, quay walls, boats.
function scenery.river(store, centre, size, opts)
	opts = opts or {}
	local m = kit.model(store, opts.name or "River")
	local water = kit.b(m, CFrame.new(centre + Vector3.new(0, 0.3, 0)),
		Vector3.new(size.X, 0.6, size.Z), "glassDark", Enum.Material.Glass,
		{ trans = 0.25, reflect = 0.12, cast = false })
	water.Color = Color3.fromRGB(46, 78, 92)
	water.Material = Enum.Material.Glass
	water.Transparency = 0.28
	water.Reflectance = 0.15
	-- banks
	for _, sgn in ipairs({ -1, 1 }) do
		local bankCf = CFrame.new(centre + Vector3.new(sgn * (size.X / 2 + 6), 0, 0))
		kit.b(m, bankCf * CFrame.new(0, 0.5, 0), Vector3.new(12, 1.2, size.Z + 24),
			"dirt", Enum.Material.Grass)
		kit.b(m, bankCf * CFrame.new(-sgn * 6.2, 1.0, 0), Vector3.new(0.8, 1.6, size.Z + 24),
			"concreteDark", Enum.Material.Concrete)
	end
	return m
end

--------------------------------------------------------------------------- tunnel

-- Tunnel: portal facade, bore lining, interior lighting, and a hillside shell.
function scenery.tunnel(store, baked, s0, s1, opts)
	opts = opts or {}
	local m = kit.model(store, opts.name or "Tunnel")
	local boreR = opts.radius or 6.4
	local seg = 5
	local n = math.max(2, math.floor((s1 - s0) / seg))
	-- lining segments (open-topped arch made of boxes)
	for i = 1, n do
		local s = s0 + (i - 0.5) * seg
		local cf = track.cframe(baked, s, 0)
		-- invert (floor)
		kit.b(m, cf * CFrame.new(0, -0.6, 0), Vector3.new(boreR * 2, 0.6, seg + 0.1),
			"concreteDark", Enum.Material.Concrete)
		-- side walls
		for _, x in ipairs({ -boreR, boreR }) do
			kit.b(m, cf * CFrame.new(x, boreR * 0.55, 0), Vector3.new(0.8, boreR * 1.2, seg + 0.1),
				"concreteDark", Enum.Material.Concrete)
		end
		-- crown: stepped arch
		local steps = 7
		for j = 0, steps - 1 do
			local t = (j + 0.5) / steps
			local x = (t - 0.5) * 2 * boreR
			local y = boreR * 1.1 + math.sin(math.pi * t) * boreR * 0.55
			kit.b(m, cf * CFrame.new(x, y, 0), Vector3.new(2 * boreR / steps + 0.2, 0.7, seg + 0.1),
				"concreteDark", Enum.Material.Concrete)
		end
		-- service walkway + cable ducts
		for _, x in ipairs({ -boreR + 1.0, boreR - 1.0 }) do
			kit.b(m, cf * CFrame.new(x, 0.35, 0), Vector3.new(1.2, 0.7, seg), "concrete",
				Enum.Material.Concrete)
		end
		if i % 2 == 0 then
			kit.lamp(m, cf * CFrame.new(0, boreR * 1.45, 0), "lampWarm", 26, 1.2)
		end
	end
	-- portals at both ends
	for _, spec in ipairs({ { s = s0, flip = 1 }, { s = s1, flip = -1 } }) do
		local cf = track.cframe(baked, spec.s, 0)
		local portalCf = cf * CFrame.new(0, 0, 0)
		-- headwall
		kit.b(m, portalCf * CFrame.new(0, boreR * 1.5, 0), Vector3.new(boreR * 2 + 12, boreR * 3, 2.4),
			"concreteDark", Enum.Material.Concrete)
		-- arch ring
		local steps = 9
		for j = 0, steps - 1 do
			local t = (j + 0.5) / steps
			local x = (t - 0.5) * 2 * boreR
			local y = boreR * 1.1 + math.sin(math.pi * t) * boreR * 0.55
			kit.b(m, portalCf * CFrame.new(x, y + 0.9, 0.4), Vector3.new(2 * boreR / steps + 0.4, 1.2, 2.0),
				"concrete", Enum.Material.Concrete)
		end
		-- coping + name plate
		kit.b(m, portalCf * CFrame.new(0, boreR * 3 + 1.2, 0), Vector3.new(boreR * 2 + 14, 1.2, 3.2),
			"concrete", Enum.Material.Concrete)
		kit.surfaceText(m, portalCf * CFrame.new(0, boreR * 3 + 1.2, 1.7) * CFrame.Angles(0, math.rad(180 * (spec.flip > 0 and 1 or 0)), 0),
			Vector3.new(10, 1.6, 0.2), Enum.NormalId.Front, opts.label or "NORTH PORTAL",
			"trainDark", "cream", Enum.Font.Antique)
	end
	return m
end

-- Hillside shell placed over a tunnel bore (chunky rock mass, grass on top)
function scenery.hill(store, baked, s0, s1, opts)
	opts = opts or {}
	local m = kit.model(store, opts.name or "Hillside")
	local width = opts.width or 90
	local height = opts.height or 42
	local seg = 10
	local n = math.max(2, math.floor((s1 - s0) / seg))
	local rng = Random.new(opts.seed or 7)
	for i = 1, n do
		local s = s0 + (i - 0.5) * seg
		local cf = track.cframe(baked, s, 0)
		local t = (i - 0.5) / n
		local prof = math.sin(math.pi * math.clamp(t * 1.15 - 0.05, 0, 1)) -- fatter in the middle
		local hh = height * (0.55 + 0.45 * prof)
		for layer = 0, 5 do
			local frac = layer / 5
			local w = width * (1 - frac * 0.55)
			local y = 0.5 + frac * hh
			local jitter = rng:NextNumber(-2.5, 2.5)
			local mat = frac > 0.62 and Enum.Material.Grass or Enum.Material.Rock
			local col = frac > 0.62 and "grass" or "dirt"
			-- build the mass as two flanks either side of the bore so the tunnel stays open
			local flankW = (w - 28) / 2
			if flankW > 1 then
				for _, x in ipairs({ -(14 + flankW / 2), (14 + flankW / 2) }) do
					kit.b(m, cf * CFrame.new(x + jitter, y, 0),
						Vector3.new(flankW, hh / 5 + 0.4, seg + 1.2), col, mat,
						{ cast = layer < 4 })
				end
			end
			-- roof over the bore once we are above it
			if frac > 0.34 then
				kit.b(m, cf * CFrame.new(jitter, y, 0),
					Vector3.new(2 * (14 + flankW) * 0.98, hh / 5 + 0.4, seg + 1.2), col, mat,
					{ cast = layer < 4 })
			end
		end
		-- trees on the crest
		if i % 2 == 0 then
			for _, x in ipairs({ -22, 22 }) do
				kit.b(m, cf * CFrame.new(x + rng:NextNumber(-4, 4), height * 0.9, 0)
					* CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), Vector3.new(1.0, 6, 1.0),
					"woodDark", Enum.Material.Wood)
				kit.b(m, cf * CFrame.new(x + rng:NextNumber(-4, 4), height * 0.9 + 5, 0),
					Vector3.new(7, 7, 7), "grass", Enum.Material.Grass)
			end
		end
	end
	return m
end

--------------------------------------------------------------------------- lineside

-- Cable troughing, relay cabinets, boundary fencing, kilometre posts
function scenery.lineside(store, baked, s0, s1, opts)
	opts = opts or {}
	local m = kit.folder(store, opts.name or "Lineside")
	local s = s0
	local rng = Random.new(opts.seed or 3)
	while s < s1 do
		local cf = track.cframe(baked, s, 0)
		local side = (math.floor(s / 60) % 2 == 0) and 1 or -1
		-- concrete cable trough
		kit.b(m, cf * CFrame.new(side * 3.0, 0.25, 0), Vector3.new(0.9, 0.5, 5.8), "concreteDark",
			Enum.Material.Concrete, { cast = false })
		-- relay cabinet every so often
		if math.floor(s / 60) % 3 == 0 then
			local cab = cf * CFrame.new(side * 5.2, 0, 2)
			kit.b(m, cab * CFrame.new(0, 0.8, 0), Vector3.new(1.4, 1.6, 1.0), "steelDark",
				Enum.Material.Metal)
			kit.b(m, cab * CFrame.new(0, 1.65, 0), Vector3.new(1.6, 0.14, 1.2), "steel",
				Enum.Material.Metal)
		end
		-- boundary fence
		if side == 1 then
			for i = 0, 2 do
				local z = -2.9 + i * 2.9
				kit.b(m, cf * CFrame.new(9.5, 0.9, z), Vector3.new(0.12, 1.8, 0.12), "steelDark",
					Enum.Material.Metal, { cast = false })
			end
			kit.b(m, cf * CFrame.new(9.5, 1.65, 0), Vector3.new(0.06, 0.06, 5.8), "steelDark",
				Enum.Material.Metal, { cast = false })
			kit.b(m, cf * CFrame.new(9.5, 0.95, 0), Vector3.new(0.06, 0.06, 5.8), "steelDark",
				Enum.Material.Metal, { cast = false })
		end
		-- kilometre post
		if math.floor(s / 100) ~= math.floor((s - 6) / 100) then
			local km = math.floor(s / 100)
			kit.surfaceText(m, cf * CFrame.new(-side * 4.4, 1.1, 0), Vector3.new(0.7, 0.9, 0.1),
				Enum.NormalId.Front, tostring(km), "trainDark", "white", Enum.Font.GothamBold)
		end
		s = s + 6
	end
	return m
end

return scenery
