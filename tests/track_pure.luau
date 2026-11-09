--!nocheck
-- track.lua : railway alignment maths + roadbed generation
-- The alignment is the single source of truth for rails, platforms, catenary and the
-- train's motion. Logic here is pure Lua so it can be unit tested outside Roblox.
local V3 = ...
if V3 then _G.Vector3 = V3 end

local track = {}

track.GAUGE = 1.435        -- standard gauge in metres (1 stud = 1 m in this place)
track.RAIL_HEAD = 0.62     -- rail top height above sleeper base
track.SLEEPER_SPACING = 0.65
track.CANT = 0.06

--------------------------------------------------------------------------- vector maths
local function v(x, y, z)
	return Vector3.new(x, y, z)
end

function track.dist(a, b)
	local d = a - b
	return math.sqrt(d.X * d.X + d.Z * d.Z)
end

--------------------------------------------------------------------------- alignment

-- path: { {p=Vector3, k=curvature}, ... } curvature in rad per stud (+ = left turn)
function track.newPath()
	return { length = 0, points = {} }
end

-- Add a straight run
function track.straight(path, start, heading, length, grade)
	local n = math.max(1, math.floor(length / 2))
	local segs = {}
	for i = 1, n do
		local t = i / n
		local p = start + v(math.cos(heading) * length * t, (grade or 0) * length * t,
			math.sin(heading) * length * t)
		path.points[#path.points + 1] = { p = p, h = heading, k = 0 }
	end
	path.length = path.length + length
	return path.points[#path.points].p, heading
end

-- Add a circular arc: radius negative = right turn.
function track.arc(path, start, heading, radius, angleDeg)
	local angle = math.rad(angleDeg)
	local sgn = radius > 0 and 1 or -1
	local radiusAbs = math.abs(radius)
	local steps = math.max(2, math.floor(math.abs(angle) * radiusAbs / 2))
	local centre = start + v(math.cos(heading + sgn * math.pi / 2) * radiusAbs, 0,
		math.sin(heading + sgn * math.pi / 2) * radiusAbs)
	local a0 = math.atan2(start.Z - centre.Z, start.X - centre.X)
	for i = 1, steps do
		local a = a0 + sgn * angle * (i / steps)
		local p = v(centre.X + math.cos(a) * radiusAbs, start.Y,
			centre.Z + math.sin(a) * radiusAbs)
		path.points[#path.points + 1] = {
			p = p,
			h = heading + sgn * angle * (i / steps),
			k = sgn / radiusAbs,
		}
	end
	path.length = path.length + math.abs(angle) * radiusAbs
	local endHeading = heading + sgn * angle
	return path.points[#path.points].p, endHeading
end

-- Resample an alignment into fine stations for physics queries.
function track.bake(path, step)
	step = step or 0.5
	local pts = path.points
	local out = { points = {}, length = 0 }
	local acc = 0
	out.points[1] = { s = 0, p = pts[1].p, h = pts[1].h, k = pts[1].k or 0 }
	local prev = pts[1].p
	out.length = 0
	for i = 2, #pts do
		local a, b = pts[i - 1].p, pts[i].p
		local d = track.dist(a, b)
		local n = math.max(1, math.ceil(d / step))
		for j = 1, n do
			local t = j / n
			local p = a:Lerp(b, t)
			local h = pts[i - 1].h + ((pts[i].h - pts[i - 1].h) * t)
			if pts[i].h - pts[i - 1].h > math.pi then
				h = pts[i - 1].h + ((pts[i].h - pts[i - 1].h - 2 * math.pi) * t)
			elseif pts[i].h - pts[i - 1].h < -math.pi then
				h = pts[i - 1].h + ((pts[i].h - pts[i - 1].h + 2 * math.pi) * t)
			end
			out.length = out.length + d / n
			out.points[#out.points + 1] = {
				s = out.length,
				p = p,
				h = h,
				k = (pts[i - 1].k + pts[i].k) / 2,
			}
		end
	end
	-- tidy heading wrap so the direction vector stays continuous
	for i = 2, #out.points do
		local prevH = out.points[i - 1].h
		local h = out.points[i].h
		while h - prevH > math.pi do h = h - 2 * math.pi end
		while h - prevH < -math.pi do h = h + 2 * math.pi end
		out.points[i].h = h
	end
	return out
end

-- Sample the baked alignment at arclength s (linear interpolation + heading interpolation)
function track.sample(baked, s)
	local pts = baked.points
	s = math.max(0, math.min(baked.length, s))
	-- binary search
	local lo, hi = 1, #pts
	while hi - lo > 1 do
		local mid = (lo + hi) // 2
		if pts[mid].s <= s then lo = mid else hi = mid end
	end
	local a, b = pts[lo], pts[hi] or pts[lo]
	local span = (b.s - a.s)
	local t = span > 1e-6 and ((s - a.s) / span) or 0
	return {
		p = a.p:Lerp(b.p, t),
		h = a.h + (b.h - a.h) * t,
		k = a.k + (b.k - a.k) * t,
	}
end

-- Distance along the alignment closest to a world position (used for junctions/braking)
function track.project(baked, pos)
	local best, bestS = math.huge, 0
	for i = 1, #baked.points, 4 do
		local d = (baked.points[i].p - pos).Magnitude
		if d < best then best, bestS = d, baked.points[i].s end
	end
	return bestS, best
end

-- CFrame of the track centreline at arclength s (Y up, -Z forward)
function track.cframe(baked, s, heightOffset)
	local sample = track.sample(baked, s)
	local dir = v(math.cos(sample.h), 0, math.sin(sample.h))
	local up = v(0, 1, 0)
	local right = dir:Cross(up)
	local cf = CFrame.fromMatrix(sample.p + up * (heightOffset or 0), right, up, -dir)
	return cf, sample
end


return track
