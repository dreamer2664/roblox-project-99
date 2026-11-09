--!nocheck
-- TrackFollow: rebuilds rails from the runtime TrackData compression and answers
-- "where is the train at arclength s?" for every vehicle of a consist.
local TrackFollow = {}

local unpackPoint = function(str)
	local s, x, y, z, h, k = string.match(str, "([%-%d%.]+),([%-%d%.]+),([%-%d%.]+),([%-%d%.]+),([%-%d%.]+),([%-%d%.]+)")
	if not s then
		return nil
	end
	return {
		s = tonumber(s), p = Vector3.new(tonumber(x), tonumber(y), tonumber(z)),
		h = tonumber(h), k = tonumber(k),
	}
end

function TrackFollow.new(data)
	local self = setmetatable({}, { __index = TrackFollow })
	self.length = data.Length
	self.points = {}
	for _, str in ipairs(data.Points) do
		local pt = unpackPoint(str)
		if pt then
			self.points[#self.points + 1] = pt
		end
	end
	self.stride = data.Stride or 1
	return self
end

function TrackFollow:sample(s)
	local pts = self.points
	if #pts == 0 then
		return { p = Vector3.new(), h = 0, k = 0 }
	end
	s = math.clamp(s, 0, self.length)
	local lo, hi = 1, #pts
	while hi - lo > 1 do
		local mid = math.floor((lo + hi) / 2)
		if pts[mid].s <= s then
			lo = mid
		else
			hi = mid
		end
	end
	local a, b = pts[lo], pts[hi] or pts[lo]
	local span = b.s - a.s
	local t = span > 1e-6 and math.clamp((s - a.s) / span, 0, 1) or 0
	local h = a.h + (b.h - a.h) * t
	local p = a.p:Lerp(b.p, t)
	-- vertical grade from the local point pair
	local grade = 0
	if #pts > lo + 1 then
		local q = pts[lo + 1]
		local dz = math.sqrt((q.p.X - a.p.X) ^ 2 + (q.p.Z - a.p.Z) ^ 2)
		if dz > 0.01 then
			grade = (q.p.Y - a.p.Y) / dz
		end
	end
	return { p = p, h = h, k = a.k + (b.k - a.k) * t, grade = grade }
end

function TrackFollow:cframe(s, yOffset)
	local smp = self:sample(s)
	local p = smp.p + Vector3.new(0, yOffset or 0, 0)
	local dir = Vector3.new(math.cos(smp.h), 0, math.sin(smp.h))
	return CFrame.lookAt(p, p + dir), smp
end

-- Place every child vehicle of a consist along the route, nose-first at `s`.
function TrackFollow:placeConsist(consist, s, yOffset)
	local vehicles = {}
	for _, v in ipairs(consist:GetChildren()) do
		if v:IsA("Model") and v:GetAttribute("Length") then
			vehicles[#vehicles + 1] = v
		end
	end
	table.sort(vehicles, function(a, b)
		local na = tonumber(string.match(a.Name, "%d+")) or 0
		local nb = tonumber(string.match(b.Name, "%d+")) or 0
		return na < nb
	end)
	local cursor = s
	for _, v in ipairs(vehicles) do
		local L = v:GetAttribute("Length")
		local centre = cursor + L / 2
		local cf = self:cframe(centre, yOffset or 0)
		v:PivotTo(cf)
		cursor = cursor + L + 0.8
	end
	return vehicles
end

-- Set wheel hinges spinning at v / r (rad/s)
function TrackFollow:spinWheels(consist, speed, radius)
	local omega = speed / math.max(0.05, radius or 0.46)
	for _, d in ipairs(consist:GetDescendants()) do
		if d:IsA("HingeConstraint") and d.Name == "AxleHinge" then
			d.MotorMaxVelocity = math.abs(omega)
		end
	end
	return omega
end

return TrackFollow
