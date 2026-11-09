--!nocheck
-- world.lua : lays out the whole place - alignment, two terminals, viaduct, river,
-- tunnel, city blocks, lighting. Returns handles the game scripts need.
local world = {}

local ROOT

function world.build(ctx)
	local kit, track, station, scenery, city = ctx.kit, ctx.track, ctx.station, ctx.scenery, ctx.city
	ROOT = ctx.root

	local dm = ROOT
	local function service(name)
		local s = dm:FindFirstChild(name)
		if not s then
			s = Instance.new(name)
			s.Parent = dm
		end
		return s
	end
	local workspace = service("Workspace")
	local lighting = service("Lighting")
	local replicated = service("ReplicatedStorage")
	local sss = service("ServerScriptService")
	local starterGui = service("StarterGui")
	local starterPlayer = service("StarterPlayer")
	service("Players")
	service("Teams")
	service("SoundService")
	local materialService = service("MaterialService")
	pcall(function()
		materialService.Use2022Materials = true
	end)

	------------------------------------------------------------------------- lighting / sky
	lighting.Ambient = Color3.fromRGB(58, 62, 72)
	lighting.OutdoorAmbient = Color3.fromRGB(96, 104, 122)
	lighting.Brightness = 2.2
	lighting.ClockTime = 17.35
	lighting.GeographicLatitude = 41.9
	lighting.ExposureCompensation = 0.15
	lighting.EnvironmentDiffuseScale = 0.6
	lighting.EnvironmentSpecularScale = 0.8
	lighting.GlobalShadows = true
	lighting.ShadowSoftness = 0.35
	lighting.FogEnd = 2600
	lighting.FogStart = 700
	lighting.FogColor = Color3.fromRGB(180, 190, 205)
	lighting.OutdoorAmbient = Color3.fromRGB(104, 112, 132)

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.32
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromRGB(198, 208, 222)
	atmosphere.Decay = Color3.fromRGB(96, 110, 128)
	atmosphere.Glare = 0.25
	atmosphere.Haze = 2.2
	atmosphere.Parent = lighting

	local sky = Instance.new("Sky")
	sky.SkyboxBk = "rbxasset://textures/sky/sky512_bk.tex"
	sky.SkyboxDn = "rbxasset://textures/sky/sky512_dn.tex"
	sky.SkyboxFt = "rbxasset://textures/sky/sky512_ft.tex"
	sky.SkyboxLf = "rbxasset://textures/sky/sky512_lf.tex"
	sky.SkyboxRt = "rbxasset://textures/sky/sky512_rt.tex"
	sky.SkyboxUp = "rbxasset://textures/sky/sky512_up.tex"
	sky.SunAngularSize = 14
	sky.MoonAngularSize = 8
	sky.Parent = lighting

	pcall(function()
		local clouds = Instance.new("Clouds")
		clouds.Cover = 0.32
		clouds.Density = 0.55
		clouds.Color = Color3.fromRGB(248, 246, 244)
		clouds.Parent = lighting
	end)
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.42
	bloom.Size = 24
	bloom.Threshold = 1.05
	bloom.Parent = lighting
	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.11
	rays.Spread = 0.9
	rays.Parent = lighting
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Brightness = 0.01
	cc.Contrast = 0.12
	cc.Saturation = 0.06
	cc.TintColor = Color3.fromRGB(255, 250, 245)
	cc.Parent = lighting

	------------------------------------------------------------------------- collections
	local folders = {}
	for _, name in ipairs({ "Tracks", "Stations", "Infrastructure", "Scenery", "City",
		"RollingStock", "Rig", "Crowds" }) do
		folders[name] = kit.folder(workspace, name)
	end
	workspace.Gravity = 196.2

	------------------------------------------------------------------------- alignment
	-- A single continuous main line with a terminus at each end:
	--   GRAND CENTRAL TERMINUS (head at s=0, tracks run -Z into the shed)
	--   -> long straight -> S-bend -> viaduct over the river -> ridge tunnel
	--   -> long curve -> HARBOUR TERMINUS.
	local path = track.newPath()
	local origin = Vector3.new(0, 0, 0)
	local heading = 0
	local sHead = 0
	local marks = {}

	local function seg(fn, ...)
		local pts = track[fn](path, select(1, ...))
	end
	-- head at origin; main line heads +X
	local p, h = track.straight(path, origin, heading, 250)
	marks.straightEnd = path.length
	local p2, h2 = track.arc(path, p, h, 260, -46)
	marks.bendEnd = path.length
	local p3, h3 = track.straight(path, p2, h2, 420)
	marks.approachStart = path.length
	-- viaduct crossing the river (straight)
	local p4, h4 = track.straight(path, p3, h3, 220)
	marks.viaductEnd = path.length
	local p5, h5 = track.arc(path, p4, h4, 420, 28)
	marks.tunnelApproach = path.length
	local p6, h6 = track.straight(path, p5, h5, 320)
	marks.tunnelStart = path.length
	local p7, h7 = track.straight(path, p6, h6, 460)
	marks.tunnelEnd = path.length
	local p8, h8 = track.arc(path, p7, h7, 320, 34)
	marks.curveEnd = path.length
	local p9, h9 = track.straight(path, p8, h8, 300)
	marks.term2 = path.length

	local baked = track.bake(path, 1.0)
	ctx.baked = baked
	ctx.path = path
	ctx.marks = marks

	------------------------------------------------------------------------- ground
	-- Big grass landscape under everything (kept below rail level)
	local ground = kit.b(folders.Scenery, CFrame.new(baked.points[1].p + Vector3.new(900, -1.2, 600)),
		Vector3.new(4200, 2, 3000), "grass", Enum.Material.Grass, { cast = false })
	ground.Name = "Ground"
	ground.CanCollide = true

	-- terrain around the city district
	do
		local c = baked.points[1].p
			local cg = kit.b(folders.Scenery, CFrame.new(c + Vector3.new(120, 0.1, -120)),
			Vector3.new(900, 0.4, 900), "asphalt", Enum.Material.Asphalt, { cast = false })
		cg.Name = "CityGround"
		cg.CanCollide = true
	end

	------------------------------------------------------------------------- track geometry
	local mainTrack = track.build(kit, folders.Tracks, baked, {
		every = 2.2, name = "MainLine", sleeperEvery = 0.65, ballastWidth = 5.4,
	})
	mainTrack.Name = "MainLine"

	------------------------------------------------------------------------- catenary + lineside
	local catStart, catEnd = 20, baked.length - 20
	scenery.catenary(folders.Infrastructure, baked, catStart, baked.length - 20, { spacing = 46 })
	scenery.lineside(folders.Infrastructure, baked, catStart, baked.length - 20, {})

	------------------------------------------------------------------------- signals
	local signalS = { 60, 210, 460, marks.tunnelStart - 60, marks.tunnelEnd + 90,
		marks.curveEnd - 40, marks.term2 - 120 }
	for i, s in ipairs(signalS) do
		if s > 0 and s < baked.length - 10 then
			scenery.signal(folders.Infrastructure, baked, s, (i % 3) + 2, { side = (i % 2 == 0) and 1 or -1 })
		end
	end
	scenery.gantry(folders.Infrastructure, baked, 120, { 3, 2 })
	scenery.gantry(folders.Infrastructure, baked, marks.tunnelStart - 20, { 2, 3 })

	------------------------------------------------------------------------- TERMINUS 1
	local terminus1 = station.terminus(folders.Stations, baked, 0, {
		name = "GrandCentral", hallLength = 170, hallWidth = 62, height = 19,
	})
	-- side platforms for the shed roads (two tracks run through the hall)
	local shedTrackB = track.cframe(baked, 0).RightVector * 12
	do
		local m = kit.model(folders.Stations, "GrandCentralPlatforms")
		local cf = track.cframe(baked, 60)
		for i = 1, 6 do
			local z = 20 + (i - 1) * 24
			for _, x in ipairs({ -9.5, 9.5 }) do
				kit.b(m, cf * CFrame.new(x, 0.575, -z), Vector3.new(11, 1.15, 23.4), "concrete",
					Enum.Material.Concrete)
				kit.b(m, cf * CFrame.new(x - (x > 0 and 4.9 or -4.9), 1.2, -z),
					Vector3.new(0.6, 0.1, 23.4), "tactile", Enum.Material.SmoothPlastic)
			end
		end
		-- platform name signs
		for _, z in ipairs({ 40, 90, 140 }) do
			for _, x in ipairs({ -9.5, 9.5 }) do
				station.nameSign(m, cf * CFrame.new(x, 1.15, -z), "GRAND CENTRAL")
			end
		end
		-- benches
		for _, z in ipairs({ 30, 60, 100, 130 }) do
			for _, x in ipairs({ -9.5, 9.5 }) do
				station.bench(m, cf * CFrame.new(x, 1.15, -z))
				station.bench(m, cf * CFrame.new(x, 1.15, -z - 3) * CFrame.Angles(0, math.pi, 0))
			end
		end
	end

	------------------------------------------------------------------------- VIADUCT + RIVER
	do
		local s0 = marks.approachStart + 20
		local s1 = marks.viaductEnd - 10
		scenery.viaduct(folders.Infrastructure, baked, s0, s1, 0, { pierEvery = 36, width = 13 })
		-- river crossing under the middle of the viaduct, perpendicular to the line
		local midS = (s0 + s1) / 2
		local cf = track.cframe(baked, midS, 0)
		local waterCentre = cf.Position + Vector3.new(0, -9, 0)
		local riverModel = scenery.river(folders.Scenery, Vector3.new(waterCentre.X, -9, waterCentre.Z),
			Vector3.new(150, 1, 420), { name = "RiverGlanne" })
		-- rotate the river to run across the line
		local L = cf.LookVector
		local spin = 0
		if math.abs(L.Z) > 1e-6 then
			spin = math.atan(L.X / L.Z)
			if L.Z < 0 then
				spin = spin + math.pi
			end
		else
			spin = math.pi / 2
		end
		kit.pivotTo(riverModel, CFrame.new(waterCentre.X, -9, waterCentre.Z)
			* CFrame.Angles(0, spin, 0))
		-- river bed + approach embankments
		local bed = kit.b(folders.Scenery, CFrame.new(waterCentre + Vector3.new(0, -3, 0)),
			Vector3.new(320, 12, 460), "dirt", Enum.Material.Rock, { cast = false })
		bed.Name = "RiverBed"
	end

	------------------------------------------------------------------------- TUNNEL + HILL
	do
		local s0 = marks.tunnelStart
		local s1 = marks.tunnelEnd
		scenery.tunnel(folders.Infrastructure, baked, s0, s1, { radius = 6.6, label = "GLANNE RIDGE TUNNEL" })
		scenery.hill(folders.Scenery, baked, s0 - 10, s1 + 10, { width = 110, height = 46, seed = 12 })
	end

	------------------------------------------------------------------------- TERMINUS 2 (harbour)
	do
		local sHead2 = marks.term2 - 4
		station.terminus(folders.Stations, baked, sHead2, {
			name = "HarbourTerminus", hallLength = 130, hallWidth = 54, height = 17,
			signText = "HARBOUR TERMINUS",
		})
		local m = kit.model(folders.Stations, "HarbourPlatforms")
		local cf = track.cframe(baked, sHead2)
		for i = 1, 5 do
			local z = 20 + (i - 1) * 24
			for _, x in ipairs({ -9.5, 9.5 }) do
				kit.b(m, cf * CFrame.new(x, 0.575, -z), Vector3.new(11, 1.15, 23.4), "concrete",
					Enum.Material.Concrete)
			end
		end
	end

	------------------------------------------------------------------------- CITY
	local cityOrigin = baked.points[1].p + Vector3.new(150, 0, -210)
	local blocksW, blocksD = 3, 3
	local blockW, blockD, roadW = 62, 62, 18
	local streets, totalW, totalD = city.streetGrid(folders.City, cityOrigin, blocksW, blocksD,
		blockW, blockD, roadW, {})
	local rng = Random.new(2024)
	for i = 0, blocksW - 1 do
		for j = 0, blocksD - 1 do
			local x = cityOrigin.X - totalW / 2 + roadW + i * (blockW + roadW) + blockW / 2
			local z = cityOrigin.Z - totalD / 2 + roadW + j * (blockD + roadW) + blockD / 2
			local kinds
			if (i + j) % 3 == 0 then
				kinds = { "bld_sky_a", "bld_sky_c", "bld_sky_e" }
			elseif (i + j) % 3 == 1 then
				kinds = { "bld_com_a", "bld_com_c", "bld_com_f", "bld_com_h", "bld_com_k" }
			else
				kinds = { "bld_com_h", "bld_com_n", "bld_sub_d", "bld_sub_f", "bld_ind_b" }
			end
			city.block(folders.City, rng, Vector3.new(x, 0, z), blockW, blockD, {
				kinds = kinds, minH = (i + j) % 3 == 0 and 34 or 16, maxH = (i + j) % 3 == 0 and 62 or 38,
				footprint = 13, gap = 4,
			})
		end
	end
	city.furnish(folders.City, rng, cityOrigin, blocksW, blocksD, blockW, blockD, roadW, {})
	-- suburban ring beyond the city
	for i = 1, 26 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(230, 430)
		local pos = Vector3.new(cityOrigin.X + math.cos(a) * r, 0, cityOrigin.Z + math.sin(a) * r * 0.8)
		city.building(folders.City, rng:NextInteger(1, 2) == 1 and "bld_sub_a" or "bld_sub_p",
			pos, rng:NextNumber(9, 15), rng:NextInteger(0, 3) * math.pi / 2)
	end
	-- industrial strip beside the harbour terminus
	for i = 1, 10 do
		local pos = baked.points[math.max(1, #baked.points - 40)].p + Vector3.new(-40 - i * 26, 0, -70)
		city.building(folders.City, i % 2 == 0 and "bld_ind_b" or "bld_ind_e", pos,
			rng:NextNumber(10, 18), rng:NextInteger(0, 3) * math.pi / 2)
	end

	------------------------------------------------------------------------- crowds
	local spots = {}
	-- platform queues at the terminus (inside the shed, both sides)
	local cfHead = track.cframe(baked, 0)
	for _, x in ipairs({ -9.5, 9.5 }) do
		for z = 34, 140, 26 do
			for k = 1, 2 do
				spots[#spots + 1] = {
					pos = (cfHead * CFrame.new(x + rng:NextNumber(-2.5, 2.5), 1.15,
						-z + rng:NextNumber(-2, 2))).Position,
					rot = rng:NextNumber(0, math.pi * 2),
				}
			end
		end
	end
	-- concourse crowd
	for i = 1, 12 do
		spots[#spots + 1] = {
			pos = (cfHead * CFrame.new(rng:NextNumber(-24, 24), 0.3, rng:NextNumber(6, 18))).Position,
			rot = rng:NextNumber(0, math.pi * 2),
		}
	end
	-- city plaza
	for i = 1, 24 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(6, 120)
		spots[#spots + 1] = {
			pos = cityOrigin + Vector3.new(math.cos(a) * r, 0.3, math.sin(a) * r),
			rot = rng:NextNumber(0, math.pi * 2),
		}
	end
	local crowdModel, crowdManifest = city.crowd(folders.Crowds, rng, spots, { name = "StationUsers" })
	ctx.crowdManifest = crowdManifest

	------------------------------------------------------------------------- spawn
	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "SpawnLocation"
	spawn.Size = Vector3.new(8, 1, 8)
	spawn.Anchored = true
	spawn.CFrame = (cfHead * CFrame.new(0, 0.8, 12)) * CFrame.Angles(0, math.pi, 0)
	spawn.Color = kit.col("trainBlue")
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Transparency = 1
	spawn.CanCollide = true
	spawn.Parent = workspace

	------------------------------------------------------------------------- screenshots rig
	-- A movable "camera card" object the render tool drives for screenshots
	local rig = kit.folder(workspace, "RenderRig")
	ctx.folders = folders
	ctx.services = {
		workspace = workspace, lighting = lighting, replicated = replicated,
		sss = sss, starterGui = starterGui, starterPlayer = starterPlayer, rig = rig,
	}
	return ctx
end

return world
