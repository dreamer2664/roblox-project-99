--!nocheck
-- dump_parts.lua : read the finished place and export every BasePart as compact JSON.
-- This is what makes the renders honest: the offline images are generated from the
-- exact parts that end up in the .rbxl, not from a separate mock-up.
local ROOT = _G.RBLX_ROOT or "/home/user/rblx99"
local SRC = ROOT .. "/out/RobloxProject99.rbxl"
local DST = ROOT .. "/out/parts.json"

local dm = fs.read(SRC)
local ws = nil
for _, c in ipairs(dm:GetChildren()) do
	if c.ClassName == "Workspace" then
		ws = c
	end
end
assert(ws, "no Workspace in place")

local matIndex = {
	[Enum.Material.Neon.Value] = 1,
	[Enum.Material.Glass.Value] = 2,
	[Enum.Material.ForceField.Value] = 2,
}

-- write incrementally: 160k entries in one string overflows the registry
local chunks = {}
local pending = {}
local useIO = io and io.open and true or false
local outFile = nil
if useIO then
	outFile = assert(io.open(DST, "w"))
	outFile:write("[")
else
	chunks[1] = "["
end
local first = true
local counts = { total = 0, neon = 0, glass = 0 }
local function num(v)
	return math.floor(v * 1000 + 0.5) / 1000
end

local stack = { ws }
while #stack > 0 do
	local node = table.remove(stack)
	for _, d in ipairs(node:GetChildren()) do
		local isPart = d:IsA("BasePart")
		if not isPart then
			-- rbxmk cannot resolve the abstract BasePart class, so match concrete types
			local cn = d.ClassName
			isPart = (cn == "Part" or cn == "WedgePart" or cn == "TrussPart"
				or cn == "CornerWedgePart" or cn == "MeshPart" or cn == "SpawnLocation")
		end
		if isPart then
			local cf = d.CFrame
			local sz = d.Size
			local pos = cf.Position
			local rv = cf.RightVector
			local uv = cf.UpVector
			local lv = cf.LookVector
			local kind = 0
			local okMat, mt = pcall(function()
				return d.Material
			end)
			if okMat and mt then
				kind = matIndex[mt.Value] or 0
			end
			if kind == 1 then
				counts.neon = counts.neon + 1
			elseif kind == 2 then
				counts.glass = counts.glass + 1
			end
			local c = d.Color
			local line = string.format(
				"[%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%g,%d]",
				num(pos.X), num(pos.Y), num(pos.Z),
				num(rv.X), num(rv.Y), num(rv.Z),
				num(uv.X), num(uv.Y), num(uv.Z),
				num(lv.X), num(lv.Y), num(lv.Z),
				num(sz.X), num(sz.Y), num(sz.Z),
				num(c.R), num(c.G), num(c.B), kind)
			if useIO then
				if not first then
					outFile:write(",\n")
				end
				outFile:write(line)
			else
				pending[#pending + 1] = (first and "" or ",\n") .. line
				if #pending >= 2000 then
					chunks[#chunks + 1] = table.concat(pending)
					pending = {}
				end
			end
			first = false
			counts.total = counts.total + 1
		elseif d:IsA("Model") or d:IsA("Folder") or d:IsA("BasePart") == false and d.ClassName ~= "Terrain" then
			stack[#stack + 1] = d
		end
	end
end

local size = 0
if useIO then
	outFile:write("]")
	size = outFile:seek("end")
	outFile:close()
else
	pending[#pending + 1] = "]"
	chunks[#chunks + 1] = table.concat(pending)
	local body = table.concat(chunks)
	chunks, pending = {}, {}
	fs.write(DST, body, "txt")
	size = #body
end
print(string.format("DUMP parts=%d neon=%d glass=%d bytes=%d", counts.total, counts.neon,
	counts.glass, size))
