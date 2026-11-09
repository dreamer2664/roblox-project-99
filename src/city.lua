--!nocheck
-- city.lua : surrounding town - CC0 buildings stamped from voxel blueprints,
-- procedural streets, street furniture, and crowds of CC0 characters.
local city = {}

local kit, track

function city.init(k, t, assets)
	kit, track = k, t
	city.assets = assets
end

local function pick(rng, list)
	return list[rng:NextInteger(1, #list)]
end

--------------------------------------------------------------------------- buildings

-- Place a voxel building with a given (X,Z) footprint and target height.
-- voxData is authored +Y forward; rotY rotates it in 90-ish degree steps.
function city.building(store, key, pos, targetHeight, rotY, opts)
	opts = opts or {}
	local data = city.assets[key]
	if not data then
		return nil
	end
	local cf = CFrame.new(pos) * CFrame.Angles(0, rotY or 0, 0)
	local m = kit.voxHeight(store, data, cf, targetHeight, {
		name = opts.name or key,
		material = opts.material,
	})
	-- plinth so buildings never float on sloped ground
	local sz = data.size
	local scale = targetHeight / sz[3]
	local w, d = sz[1] * scale, sz[2] * scale
	kit.b(m, cf * CFrame.new(0, 0.3, 0), Vector3.new(w + 0.6, 0.6, d + 0.6), "concreteDark",
		Enum.Material.Concrete, { cast = false })
	return m
end

--------------------------------------------------------------------------- streets

-- Grid of asphalt streets + pavements + markings, sized to the city blocks.
function city.streetGrid(store, origin, cols, rows, blockW, blockD, roadW, opts)
	opts = opts or {}
	local m = kit.model(store, opts.name or "Streets")
	local totalW = cols * blockW + (cols + 1) * roadW
	local totalD = rows * blockD + (rows + 1) * roadW
	local function road(x0, z0, x1, z1)
		local c = Vector3.new((x0 + x1) / 2, opts.y or 0.05, (z0 + z1) / 2)
		local s = Vector3.new(math.abs(x1 - x0), 0.3, math.abs(z1 - z0))
		kit.b(m, CFrame.new(c), s, "asphalt", Enum.Material.Asphalt, { cast = false })
		-- centre line
		if s.X > s.Z then
			for x = x0 + 2, x1 - 2, 8 do
				kit.b(m, CFrame.new(Vector3.new(x, (opts.y or 0.05) + 0.16, c.Z)),
					Vector3.new(3.4, 0.06, 0.24), "tactile", Enum.Material.SmoothPlastic,
					{ cast = false })
			end
		else
			for z = z0 + 2, z1 - 2, 8 do
				kit.b(m, CFrame.new(Vector3.new(c.X, (opts.y or 0.05) + 0.16, z)),
					Vector3.new(0.24, 0.06, 3.4), "tactile", Enum.Material.SmoothPlastic,
					{ cast = false })
			end
		end
	end
	for i = 0, cols do
		local x = origin.X - totalW / 2 + roadW / 2 + i * (blockW + roadW)
		road(x - roadW / 2, origin.Z - totalD / 2, x + roadW / 2, origin.Z + totalD / 2)
	end
	for j = 0, rows do
		local z = origin.Z - totalD / 2 + roadW / 2 + j * (blockD + roadW)
		road(origin.X - totalW / 2, z - roadW / 2, origin.X + totalW / 2, z + roadW / 2)
	end
	-- sidewalks around each block
	for i = 0, cols - 1 do
		for j = 0, rows - 1 do
			local x = origin.X - totalW / 2 + roadW + i * (blockW + roadW) + blockW / 2
			local z = origin.Z - totalD / 2 + roadW + j * (blockD + roadW) + blockD / 2
			kit.b(m, CFrame.new(Vector3.new(x, (opts.y or 0) + 0.12, z)),
				Vector3.new(blockW + 5, 0.36, blockD + 5), "concreteDark", Enum.Material.Concrete,
				{ cast = false })
		end
	end
	return m, totalW, totalD
end

-- Fill a rectangular block with buildings facing the nearest street.
function city.block(store, rng, centre, blockW, blockD, opts)
	opts = opts or {}
	local m = kit.model(store, opts.name or "CityBlock")
	local kinds = opts.kinds or { "bld_com_a", "bld_com_c", "bld_com_f", "bld_com_h", "bld_com_k", "bld_com_n" }
	local minH = opts.minH or 14
	local maxH = opts.maxH or 46
	local footprint = opts.footprint or 12
	local gap = opts.gap or 3
	local nx = math.max(1, math.floor((blockW - gap) / (footprint + gap)))
	local nz = math.max(1, math.floor((blockD - gap) / (footprint + gap)))
	local stepX = blockW / nx
	local stepZ = blockD / nz
	for i = 0, nx - 1 do
		for j = 0, nz - 1 do
			local x = centre.X - blockW / 2 + stepX * (i + 0.5)
			local z = centre.Z - blockD / 2 + stepZ * (j + 0.5)
			if rng:NextNumber() > (opts.vacancy or 0.12) then
				local h = rng:NextNumber(minH, maxH)
				local key = pick(rng, kinds)
				local rot = (rng:NextInteger(0, 3)) * math.pi / 2
				city.building(m, key, Vector3.new(x, 0, z), h, rot)
			end
		end
	end
	return m
end

--------------------------------------------------------------------------- street furniture

function city.furnish(store, rng, origin, cols, rows, blockW, blockD, roadW, opts)
	opts = opts or {}
	local m = kit.model(store, opts.name or "StreetFurniture")
	local totalW = cols * blockW + (cols + 1) * roadW
	local totalD = rows * blockD + (rows + 1) * roadW
	local props = opts.props or { "prop_lamp", "prop_tree_s", "prop_tree_l", "prop_planter",
		"prop_dumpster", "prop_traffic", "prop_bench" }
	local heights = {
		prop_lamp = 7.5, prop_tree_s = 6.5, prop_tree_l = 11, prop_planter = 1.4,
		prop_dumpster = 1.6, prop_traffic = 5.2, prop_bench = 1.2,
		prop_pole = 8.5, prop_container = 2.8, prop_sign_hw = 4.2, prop_cone = 0.8,
	}
	-- walk the sidewalks: alternate sides of each road
	for i = 0, cols do
		local x = origin.X - totalW / 2 + roadW / 2 + i * (blockW + roadW)
		for _, off in ipairs({ -roadW / 2 - 2.2, roadW / 2 + 2.2 }) do
			for z = origin.Z - totalD / 2 + 6, origin.Z + totalD / 2 - 6, 14 do
				if rng:NextNumber() > 0.55 then
					local key = pick(rng, props)
					local data = city.assets[key]
					if data then
						local h = heights[key] or 3
						local cf = CFrame.new(Vector3.new(x + off, 0.3, z))
							* CFrame.Angles(0, rng:NextInteger(0, 3) * math.pi / 2, 0)
						kit.voxHeight(m, data, cf, h)
					end
				end
			end
		end
	end
	return m
end

--------------------------------------------------------------------------- crowds

-- Two-part people (body + head+arms) so they can be posed/walked by a script later.
function city.person(store, key, pos, height, facing)
	local data = city.assets[key]
	if not data then
		return nil
	end
	local cf = CFrame.new(pos) * CFrame.Angles(0, facing or 0, 0)
	return kit.voxHeight(store, data, cf, height or 1.85, { name = "Person_" .. key })
end

-- Scatter crowds: platform queues, station concourse, plaza. Returns folder + manifest
function city.crowd(store, rng, spots, opts)
	opts = opts or {}
	local m = kit.folder(store, opts.name or "Crowd")
	local people = {
		"per_m_a", "per_m_c", "per_m_e", "per_m_g", "per_f_a", "per_f_c", "per_f_e",
		"per_worker", "per_soldier",
	}
	local manifest = {}
	for i, spot in ipairs(spots) do
		local key = people[rng:NextInteger(1, #people)]
		local h = rng:NextNumber(1.65, 1.95)
		local facing = spot.rot or rng:NextNumber(0, math.pi * 2)
		local p = city.person(m, key, spot.pos, h, facing)
		if p then
			manifest[#manifest + 1] = { key = key, pos = { spot.pos.X, spot.pos.Y, spot.pos.Z }, facing = facing }
		end
	end
	return m, manifest
end

return city
