local H = require("./spec_helper")
local TrainPhysics = require("./physics_testable")

H.test("new() applies defaults and clamps nothing", function()
	local p = TrainPhysics.new({ mass = 200 })
	H.near(p.mass, 200, 1e-9)
	H.near(p.speed, 0, 1e-9)
	H.near(p.maxSpeed, 55.5, 1e-9)
end)

H.test("resistance grows with speed (Davis curve)", function()
	local p = TrainPhysics.new({ mass = 200 })
	p.speed = 0
	local r0 = p:resistance(0, 0)
	p.speed = 30
	local r30 = p:resistance(0, 0)
	H.ok(r30 > r0 * 2, "resistance must rise: " .. r0 .. " -> " .. r30)
end)

H.test("uphill grade adds resistance, downhill reduces it", function()
	local p = TrainPhysics.new({ mass = 200 })
	p.speed = 10
	local flat = p:resistance(0, 0)
	local up = p:resistance(0.02, 0)
	local down = p:resistance(-0.02, 0)
	H.ok(up > flat and flat > down, string.format("%.2f > %.2f > %.2f", up, flat, down))
	-- 2% grade of a 200 t train: 200 t * 9.81 m/s^2 * 0.02 = 39.24 kN
	H.near(up - flat, 200 * 9.81 * 0.02, 0.05, "grade force")
end)

H.test("curve resistance uses the UIC formula", function()
	local p = TrainPhysics.new({ mass = 100 })
	p.speed = 5
	local flat = p:resistance(0, 0)
	local curved = p:resistance(0, 1 / 300)   -- 300 m radius
	-- Roeckl: 6.3e-3 * (100 t * 9.81) * (573 / 300) = 11.8 kN
	local expected = 6.3e-3 * (100 * 9.81) * (573 / 300)
	H.near(curved - flat, expected, 0.05, "curve resistance")
end)

H.test("tractive effort is power-limited at speed", function()
	local p = TrainPhysics.new({ mass = 200, powerRating = 2400, tractiveEffort = 260 })
	local e0 = p:availableEffort(0)
	local e10 = p:availableEffort(10)
	local e40 = p:availableEffort(40)
	H.near(e0, 260, 1e-6, "starting effort")
	H.near(e10, 240, 0.001, "2400 kW / 10 m/s = 240 kN")
	H.near(e40, 60, 0.001, "2400 kW / 40 m/s = 60 kN")
end)

H.test("adhesion clips effort and sand helps", function()
	-- 200 t at mu = 0.05 gives 98.1 kN of grip, below the 260 kN nominal effort
	local p = TrainPhysics.new({ mass = 200, adhesion = 0.05 })
	local lim = p:availableEffort(0)
	H.near(lim, 0.05 * 200 * 9.81, 0.02, "adhesion limit")
	p.sandarActive = true
	local lim2 = p:availableEffort(0)
	H.near(lim2, 0.05 * 1.3 * 200 * 9.81, 0.02, "sanded limit")
	-- with plenty of grip the nominal effort is the binding constraint
	local q = TrainPhysics.new({ mass = 200, adhesion = 0.5 })
	H.near(q:availableEffort(0), 260, 1e-6, "tractive effort binds")
end)

H.test("full throttle accelerates, and acceleration is jerk limited", function()
	local p = TrainPhysics.new({ mass = 180 })
	p.throttle = 1
	local lastA = 0
	for i = 1, 300 do
		local r = p:step(0.05, 0, 0)
		H.ok(r.accel - lastA <= p.jerkLimit * 0.05 + 1e-6, "jerk exceeded")
		lastA = r.accel
	end
	H.ok(p.speed > 10, "should have accelerated: " .. p.speed)
end)

H.test("braking brings the train to a complete stop, not past zero", function()
	local p = TrainPhysics.new({ mass = 200 })
	p.speed = 25
	p.throttle = 0
	p.brake = 1
	for i = 1, 600 do
		p:step(0.05, 0, 0)
	end
	H.near(p.speed, 0, 1e-6, "final speed")
	H.ok(p.speed >= 0, "must not reverse")
end)

H.test("air brake lag means stopping takes longer than the ideal distance", function()
	local p = TrainPhysics.new({ mass = 200 })
	p.speed = 20
	p.brake = 1
	local d0 = p.distance
	for i = 1, 800 do
		p:step(0.05, 0, 0)
		if p.speed == 0 then break end
	end
	local travelled = p.distance - d0
	local ideal = (20 * 20) / (2 * p.brakeRate)
	H.ok(travelled > ideal, string.format("lag included: %.1f m vs ideal %.1f m", travelled, ideal))
	H.ok(travelled < ideal * 2.2, "but not absurdly long: " .. travelled)
end)

H.test("emergency braking stops sooner than service braking", function()
	local function stopDist(emergency)
		local p = TrainPhysics.new({ mass = 200 })
		p.speed = 25
		p.emergency = emergency
		p.brake = 1
		local d0 = p.distance
		for i = 1, 900 do
			p:step(0.05, 0, 0)
			if p.speed == 0 then break end
		end
		return p.distance - d0
	end
	local service = stopDist(false)
	local emerg = stopDist(true)
	H.ok(emerg < service, string.format("emergency %.1f m < service %.1f m", emerg, service))
end)

H.test("reverse direction: traction pushes the other way", function()
	local p = TrainPhysics.new({ mass = 150 })
	p.direction = -1
	p.throttle = 1
	for i = 1, 100 do
		p:step(0.05, 0, 0)
	end
	H.ok(p.speed < 0, "should be moving backwards: " .. p.speed)
end)

H.test("brakingDistance matches kinematics", function()
	H.near(TrainPhysics.brakingDistance(20, 1.0, 0), 200, 1e-6, "v^2/2a")
	H.near(TrainPhysics.brakingDistance(20, 1.0, 1.5), 230, 1e-6, "with reaction time")
end)

H.test("stoppingCurve demands more brake the closer the stop", function()
	local far = TrainPhysics.stoppingCurve(400, 20, 0.9)
	local near = TrainPhysics.stoppingCurve(30, 20, 0.9)
	H.near(far, 0, 1e-9, "no braking needed far out")
	H.ok(near > 0.5, "hard braking close in: " .. near)
end)

H.test("energy metering only counts tractive work", function()
	local p = TrainPhysics.new({ mass = 200 })
	p.throttle = 1
	for i = 1, 200 do
		p:step(0.05, 0, 0)
	end
	local kWhAfterPower = p.energyUsed
	H.ok(kWhAfterPower > 0, "traction used energy")
	p.throttle = 0
	p.brake = 1
	for i = 1, 200 do
		p:step(0.05, 0, 0)
	end
	H.near(p.energyUsed, kWhAfterPower, 1e-9, "braking adds no traction energy")
end)

H.done()
