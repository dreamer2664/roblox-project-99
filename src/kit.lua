--!nocheck
-- kit.lua : low-level construction helpers (parts, palettes, primitives)
local kit = {}

kit.stats = { parts = 0 }

kit.COL = {
	rail        = Color3.fromRGB(126, 116, 108),
	railTop     = Color3.fromRGB(196, 196, 202),
	sleeper     = Color3.fromRGB(74, 52, 38),
	ballast     = Color3.fromRGB(96, 94, 92),
	concrete    = Color3.fromRGB(188, 186, 180),
	concreteDark= Color3.fromRGB(150, 148, 144),
	asphalt     = Color3.fromRGB(58, 58, 62),
	tactile     = Color3.fromRGB(226, 186, 60),
	steel       = Color3.fromRGB(132, 138, 146),
	steelDark   = Color3.fromRGB(78, 84, 92),
	glass       = Color3.fromRGB(176, 208, 220),
	glassDark   = Color3.fromRGB(120, 156, 172),
	white       = Color3.fromRGB(242, 244, 246),
	cream       = Color3.fromRGB(232, 224, 206),
	ochre       = Color3.fromRGB(196, 148, 86),
	brick       = Color3.fromRGB(148, 84, 62),
	terracotta  = Color3.fromRGB(178, 98, 70),
	slate       = Color3.fromRGB(72, 78, 86),
	wood        = Color3.fromRGB(122, 88, 58),
	woodDark    = Color3.fromRGB(86, 60, 40),
	signalRed   = Color3.fromRGB(220, 60, 52),
	signalGreen = Color3.fromRGB(72, 200, 126),
	amber       = Color3.fromRGB(246, 178, 62),
	lampWarm    = Color3.fromRGB(255, 226, 176),
	signBlue    = Color3.fromRGB(30, 66, 122),
	grass       = Color3.fromRGB(104, 138, 82),
	dirt        = Color3.fromRGB(112, 96, 74),
	roofGrey    = Color3.fromRGB(96, 100, 106),
	trainRed    = Color3.fromRGB(176, 46, 52),
	trainBlue   = Color3.fromRGB(38, 84, 150),
	trainSilver = Color3.fromRGB(206, 210, 214),
	trainDark   = Color3.fromRGB(42, 44, 50),
}

function kit.col(c)
	if type(c) == "string" then
		local v = kit.COL[c]
		if not v then
			error("unknown colour '" .. c .. "'", 2)
		end
		return v
	end
	return c
end

--------------------------------------------------------------------------- primitives

-- Kit.b: rigid part from CFrame + size
function kit.b(parent, cf, size, color, material, opts)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CastShadow = true
	p.Size = size
	p.CFrame = cf
	p.Color = kit.col(color)
	p.Material = material or Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = false
	if opts then
		if opts.collide ~= nil then p.CanCollide = opts.collide end
		if opts.trans ~= nil then p.Transparency = opts.trans end
		if opts.name then p.Name = opts.name end
		if opts.reflect then p.Reflectance = opts.reflect end
		if opts.shape then p.Shape = opts.shape end
		if opts.massless then p.Massless = true end
		if opts.cast ~= nil then p.CastShadow = opts.cast end
		if opts.color2 then p.Color = kit.col(opts.color2) end
	end
	p.Parent = parent
	kit.stats.parts = kit.stats.parts + 1
	return p
end

-- Kit.wedge: ramp / chamfer helper (WedgePart)
function kit.wedge(parent, cf, size, color, material, opts)
	local p = Instance.new("WedgePart")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = kit.col(color)
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if opts and opts.collide ~= nil then p.CanCollide = opts.collide end
	if opts and opts.trans then p.Transparency = opts.trans end
	p.Parent = parent
	kit.stats.parts = kit.stats.parts + 1
	return p
end

-- Kit.cyl: cylinder whose axis runs along the part's X axis (Roblox cylinder)
function kit.cyl(parent, cf, diameter, length, color, material, opts)
	local p = kit.b(parent, cf * CFrame.Angles(0, 0, math.rad(90)),
		Vector3.new(length, diameter, diameter), color, material, opts)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- Kit.u: uniform box given centre + size in world space (most common call)
function kit.u(parent, centre, size, color, material, opts)
	return kit.b(parent, CFrame.new(centre), size, color, material, opts)
end

-- Kit.box: axis-aligned box given min/max corners
function kit.box(parent, mn, mx, color, material, opts)
	local c = (mn + mx) / 2
	return kit.b(parent, CFrame.new(c), mx - mn, color, material, opts)
end

-- Kit.beam: box stretched between two points (used for cables, handrails, stairs)
function kit.beam(parent, a, b, thickness, color, material, opts)
	local d = b - a
	local mid = (a + b) / 2
	local len = d.Magnitude
	if len < 1e-4 then
		return nil
	end
	local cf = CFrame.lookAt(mid - d.Unit * (len / 2), mid + d.Unit * (len / 2))
	local t = thickness
	return kit.b(parent, cf, Vector3.new(t, t, len), color, material, opts)
end

-- Kit.preview/folder helpers
function kit.model(parent, name)
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end

function kit.folder(parent, name)
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

function kit.attach(parent, pos, axis)
	local a = Instance.new("Attachment")
	if axis then
		a.Axis = axis
	end
	a.CFrame = CFrame.new(pos)
	a.Parent = parent
	return a
end

-- Kit.lamp: emissive lamp head + optional PointLight
function kit.lamp(parent, cf, color, range, brightness)
	local bulb = kit.b(parent, cf, Vector3.new(0.5, 0.16, 0.9), color or "lampWarm", Enum.Material.Neon)
	local light = Instance.new("PointLight")
	light.Color = kit.col(color or "lampWarm")
	light.Range = range or 26
	light.Brightness = brightness or 1.6
	light.Shadows = true
	light.Parent = bulb
	return bulb
end

-- Kit.surfaceText: SurfaceGui label (station signage, train numbers)
function kit.surfaceText(parent, cf, size, face, text, textColor, bgColor, font, textSize)
	local part = kit.b(parent, cf, size, bgColor or "signBlue", Enum.Material.SmoothPlastic)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face or Enum.NormalId.Front
	sg.CanvasSize = Vector2.new(400, math.floor(400 * size.Y / math.max(size.X, size.Z)))
	sg.LightInfluence = 0.15
	sg.Parent = part
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.TextColor3 = kit.col(textColor or "white")
	label.Font = font or Enum.Font.GothamBold
	label.TextScaled = true
	label.Parent = sg
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.04, 0)
	pad.PaddingRight = UDim.new(0.04, 0)
	pad.Parent = label
	return part
end

-- Kit.vox: stamp a voxelised CC0 model (from assets/vox/*.json) into a Model.
-- The source model is authored with +Y forward, +Z up, origin at its base centre.
--   cf       : world CFrame where the model's base centre should sit
--   scale    : world studs per source unit (train kits use ~4.6 for realistic size)
--   mode     : "plastic" (default) or "smooth" material override
function kit.vox(parent, voxData, cf, scale, opts)
	opts = opts or {}
	local m = Instance.new("Model")
	m.Name = opts.name or (voxData.source:gsub("%.glb$", ""))
	m.Parent = parent
	local mat = opts.material or Enum.Material.SmoothPlastic
	local boxes = voxData.boxes
	-- lift so the model's local z=0 sits on the base
	local zmin = math.huge
	for _, b in ipairs(boxes) do
		zmin = math.min(zmin, b.c[3] - b.s[3] / 2)
	end
	-- optional non-uniform scale: {x = width, y = height, z = length}
	local sx, sy, sz3 = scale, scale, scale
	if opts.scale3 then
		sx, sy, sz3 = opts.scale3[1], opts.scale3[2], opts.scale3[3]
	end
	for i, b in ipairs(boxes) do
		-- source axes: x -> right, y -> forward, z -> up
		local localPos = Vector3.new(b.c[1] * sx, (b.c[3] - zmin) * sy, -b.c[2] * sz3)
		local sz = Vector3.new(b.s[1] * sx, b.s[3] * sy, b.s[2] * sz3)
		local col = Color3.new(b.col[1], b.col[2], b.col[3])
		if b.col[1] + b.col[2] + b.col[3] < 0.1 then
			col = Color3.fromRGB(74, 76, 82)   -- texture-miss safety net
		end
		local p = Instance.new("Part")
		p.Anchored = true
		p.CastShadow = false
		p.Size = sz
		p.CFrame = cf * CFrame.new(localPos)
		p.Color = col
		p.Material = mat
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CanCollide = false
		p.Parent = m
		kit.stats.parts = kit.stats.parts + 1
	end
	return m
end

-- Kit.voxAt: convenience for models designed to sit on ground with given height
function kit.voxHeight(parent, voxData, cf, targetHeight, opts)
	local sz = voxData.size
	local k = targetHeight / sz[3]
	return kit.vox(parent, voxData, cf, k, opts)
end

function kit.terrainWall(parent, cf, size, color, studs)
	-- decorative retaining wall with buttresses
	local w = kit.b(parent, cf, size, color, Enum.Material.Concrete)
	local n = math.floor(size.Z / 6)
	for i = 1, n do
		local z = -size.Z / 2 + (i - 0.5) * (size.Z / n)
		kit.b(parent, cf * CFrame.new(0, 0, z), Vector3.new(size.X + 0.6, size.Y * 0.92, 0.9),
			"concreteDark", Enum.Material.Concrete)
	end
	return w
end

--------------------------------------------------------------------------- model pivots
-- rbxmk cannot resolve the abstract BasePart class, so test concrete part classes.
kit.PART_CLASSES = {
	Part = true, WedgePart = true, CornerWedgePart = true, TrussPart = true,
	MeshPart = true, SpawnLocation = true, Seat = true, VehicleSeat = true,
}

function kit.isPart(inst)
	local ok, res = pcall(function()
		return inst:IsA("BasePart")
	end)
	if ok and res then
		return true
	end
	return kit.PART_CLASSES[inst.ClassName] == true
end
-- rbxmk has no Model:PivotTo, so provide a manual rigid move for any Model.
function kit.firstBasePart(model)
	local okPP, pp = pcall(function()
		return model.PrimaryPart
	end)
	if okPP and pp then
		return pp
	end
	for _, d in ipairs(model:GetDescendants()) do
		if kit.isPart(d) then
			return d
		end
	end
	return nil
end

function kit.getPivot(model)
	local pp = kit.firstBasePart(model)
	return pp and pp.CFrame or CFrame.new()
end

-- Translate a whole model so its pivot lands on cf.
-- Built from CFrame multiplication only: CFrame:Inverse() is not available offline.
function kit.pivotTo(model, cf)
	local pp = kit.firstBasePart(model)
	if not pp then
		return
	end
	local base = pp.CFrame
	local basePos = base.Position
	local shift = cf.Position - basePos
	local rel = cf * CFrame.new(-basePos.X, -basePos.Y, -basePos.Z)
	for _, d in ipairs(model:GetDescendants()) do
		if kit.isPart(d) then
			local moved = false
			local ok, newCf = pcall(function()
				return rel * (d.CFrame - basePos)
			end)
			if ok then
				d.CFrame = newCf
				moved = true
			end
			if not moved then
				d.CFrame = CFrame.new(d.CFrame.Position + shift)
			end
		end
	end
end

-- Attributes are metadata: set them when the host supports it, otherwise ignore.
function kit.setAttr(inst, name, value)
	pcall(function()
		inst:SetAttribute(name, value)
	end)
end

function kit.getAttr(inst, name)
	local ok, v = pcall(function()
		return inst:GetAttribute(name)
	end)
	if ok then
		return v
	end
	return nil
end

return kit
