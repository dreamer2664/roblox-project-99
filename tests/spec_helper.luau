-- Vector3 shim + micro test framework for running pure modules under the luau CLI
local V = {}
local VK = {}
VK.__index = VK
VK.__add = function(a, b) return V.new(a.X + b.X, a.Y + b.Y, a.Z + b.Z) end
VK.__sub = function(a, b) return V.new(a.X - b.X, a.Y - b.Y, a.Z - b.Z) end
VK.__mul = function(a, b)
	if type(b) == "number" then return V.new(a.X * b, a.Y * b, a.Z * b) end
	return V.new(a.X * b.X, a.Y * b.Y, a.Z * b.Z)
end
VK.__div = function(a, b) return V.new(a.X / b, a.Y / b, a.Z / b) end
VK.__unm = function(a) return V.new(-a.X, -a.Y, -a.Z) end
VK.__eq = function(a, b) return a.X == b.X and a.Y == b.Y and a.Z == b.Z end
local function mag(t) return math.sqrt(t.X ^ 2 + t.Y ^ 2 + t.Z ^ 2) end
function VK.Lerp(a, b, t) return V.new(a.X + (b.X - a.X) * t, a.Y + (b.Y - a.Y) * t, a.Z + (b.Z - a.Z) * t) end
function VK.Cross(a, b) return V.new(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end
function VK.Dot(a, b) return a.X * b.X + a.Y * b.Y + a.Z * b.Z end
VK.__index = function(t, k)
	if k == "Magnitude" then return mag(t) end
	if k == "Unit" then local m = mag(t); return V.new(t.X / m, t.Y / m, t.Z / m) end
	return VK[k]
end
function V.new(x, y, z) return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, VK) end

local H = {}
H.V = V

local pass, fail = 0, 0
function H.test(name, fn)
	local ok, err = pcall(fn)
	if ok then
		pass = pass + 1
		print(string.format("  ok   %s", name))
	else
		fail = fail + 1
		print(string.format("  FAIL %s\n       %s", name, tostring(err)))
	end
end
function H.near(a, b, eps, msg)
	eps = eps or 1e-4
	if math.abs(a - b) > eps then
		error(string.format("%s: expected %.5f ~ %.5f (eps %.5f)", msg or "near", a, b, eps), 2)
	end
end
function H.nearV(a, b, eps, msg)
	eps = eps or 1e-4
	if mag(a - b) > eps then
		error(string.format("%s: expected (%.3f,%.3f,%.3f) got (%.3f,%.3f,%.3f)",
			msg or "nearV", b.X, b.Y, b.Z, a.X, a.Y, a.Z), 2)
	end
end
function H.ok(cond, msg)
	if not cond then error(msg or "assertion failed", 2) end
end
function H.done()
	print(string.format("\n%d passed, %d failed", pass, fail))
	if fail > 0 then error("tests failed") end
end
return H
