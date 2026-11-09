local H = require("./spec_helper")
local V = H.V
local track = require("./track_testable")

H.test("straight 100 studs reaches 100 along +X", function()
	local p = track.newPath()
	local e = track.straight(p, V.new(0, 0, 0), 0, 100)
	H.near(e.X, 100, 1e-6, "x")
	H.near(e.Z, 0, 1e-6, "z")
	local b = track.bake(p)
	H.near(b.length, 100, 0.1, "baked length")
	local s = track.sample(b, 100)
	H.near(s.p.X, 100, 0.2, "sample end x")
end)

H.test("90 deg left arc of radius 60 ends heading +Z", function()
	local p = track.newPath()
	local e = track.straight(p, V.new(0, 0, 0), 0, 50)
	track.arc(p, e, 0, 60, 90)
	local b = track.bake(p)
	local last = b.points[#b.points]
	H.near(math.cos(last.h), 0, 0.05, "final heading cos")
	H.near(math.sin(last.h), 1, 0.05, "final heading sin")
	H.near(b.length, 50 + math.pi / 2 * 60, 1.5, "total length")
end)

H.test("negative radius turns the other way", function()
	local p = track.newPath()
	local e = track.straight(p, V.new(0, 0, 0), 0, 10)
	track.arc(p, e, 0, -50, 90)
	local b = track.bake(p)
	local last = b.points[#b.points]
	H.ok(math.sin(last.h) < -0.9, "turned right: " .. last.h)
end)

H.test("baked arclength matches sum of segments", function()
	local p = track.newPath()
	local s1 = track.straight(p, V.new(0, 0, 0), math.rad(37), 80)
	local s2, h2 = track.arc(p, s1, math.rad(37), 45, -70)
	track.straight(p, s2, h2, 40, 0.02)
	local b = track.bake(p)
	local total = 0
	for i = 2, #b.points do
		local d = b.points[i].p - b.points[i - 1].p
		total = total + math.sqrt(d.X ^ 2 + d.Z ^ 2)
	end
	H.near(total, b.length, 1.0, "sum of segments")
end)

H.test("project() returns arclength of the closest point", function()
	local p = track.newPath()
	track.straight(p, V.new(0, 0, 0), 0, 200)
	local b = track.bake(p)
	local s, d = track.project(b, V.new(57.2, 0, 2.0))
	H.near(s, 57.2, 2.5, "projected s")
	H.ok(d < 3, "distance small")
end)

H.test("geometry build is deterministic for the same path", function()
	local function build()
		local p = track.newPath()
		local s1 = track.straight(p, V.new(0, 0, 0), 0, 40)
		track.arc(p, s1, 0, 30, 45)
		local b = track.bake(p)
		return string.format("%.3f/%.3f", b.length, #b.points)
	end
	H.ok(build() == build(), "deterministic")
end)

H.done()
