--!nocheck
-- TrainPhysics: longitudinal dynamics for a train on rails.
--
-- This is a proper single-degree-of-freedom model of a train along its route:
--   * Davis resistance  F_res = A + B v + C v^2  (kN)
--   * grade force       F_grade = m g sin(theta)
--   * curve resistance  F_curve = 6.3 * m / R      (kN, R in metres, UIC formula)
--   * tractive effort from a power/tractive curve with adhesion clipping
--   * blended brake with build-up lag + emergency rate
--   * jerk limiting so the ride feels like a train, not a car
--
-- Pure Lua on purpose: the same module is unit tested offline.
local TrainPhysics = {}
TrainPhysics.__index = TrainPhysics

local DEFAULT = {
	A = 3.2, B = 0.085, C = 0.0058,
	gravity = 9.81,
	tractiveEffort = 260,       -- kN
	powerRating = 2400,         -- kW
	maxSpeed = 55.5,            -- m/s
	brakeRate = 0.9,            -- m/s^2
	emergencyBrakeRate = 1.35,
	brakeBuildUp = 1.6,
	adhesion = 0.28,
	jerkLimit = 0.65,
}

function TrainPhysics.new(cfg)
	cfg = cfg or {}
	local self = setmetatable({}, TrainPhysics)
	for k, v in pairs(DEFAULT) do
		self[k] = cfg[k] ~= nil and cfg[k] or v
	end
	self.mass = cfg.mass or 220          -- tonnes
	self.speed = 0                       -- m/s along route (+ = forwards)
	self.accel = 0
	self.distance = 0                    -- metres travelled (route arclength)
	self.direction = 1                   -- +1 forward, -1 reverse
	self.throttle = 0                    -- 0..1 requested
	self.brake = 0                       -- 0..1 requested (service)
	self.emergency = false
	self.brakeApplied = 0                -- actual, after build-up
	self.appliedTractive = 0
	self.powerLimited = false
	self.sandarActive = false
	self.odometer = 0
	self.energyUsed = 0                  -- kWh
	return self
end

--------------------------------------------------------------------------- resistance

-- total resistance force in kN for the current state
function TrainPhysics:resistance(grade, curvature)
	local v = math.abs(self.speed)
	local f = self.A + self.B * v + self.C * v * v
	-- grade: sin(theta) approximated by grade (rise/run); mass[t]*9.81 = weight in kN
	local g = (grade or 0)
	f = f + self.mass * self.gravity * g
	-- Röckl/UIC curve resistance: R[kN] = 6.3e-3 * W[kN] * (573 / R[m])
	if curvature and curvature ~= 0 then
		local radius = 1 / math.abs(curvature)
		local weightKN = self.mass * self.gravity
		f = f + 6.3e-3 * weightKN * (573 / radius)
	end
	return f
end

--------------------------------------------------------------------------- traction

-- available tractive effort (kN) at speed v, clipped by adhesion
function TrainPhysics:availableEffort(v)
	v = math.abs(v)
	local powerEffort = math.huge
	if v > 0.5 then
		powerEffort = (self.powerRating / v) -- kW / (m/s) = kN
	end
	local effort = math.min(self.tractiveEffort, powerEffort)
	self.powerLimited = powerEffort < self.tractiveEffort
	-- adhesion limit: mu * mass * g  (kN)
	local adhesionLimit = self.adhesion * self.mass * self.gravity
	-- apply sand: 30% more grip
	if self.sandarActive then
		adhesionLimit = adhesionLimit * 1.3
	end
	return math.min(effort, adhesionLimit), effort, adhesionLimit
end

--------------------------------------------------------------------------- step

-- dt seconds.  grade: rise/run (+ = uphill forwards), curvature: rad/m signed
function TrainPhysics:step(dt, grade, curvature)
	dt = math.min(dt, 0.1)
	local v = self.speed
	local vAbs = math.abs(v)

	-- ---- brake build-up (air brake lag makes stopping feel heavy)
	local targetBrake = self.emergency and 1 or self.brake
	local rate = dt / math.max(0.15, self.brakeBuildUp)
	if targetBrake > self.brakeApplied then
		self.brakeApplied = math.min(targetBrake, self.brakeApplied + rate)
	else
		self.brakeApplied = math.max(targetBrake, self.brakeApplied - rate * 2.5)
	end

	-- ---- forces (kN), forward positive in the direction of travel
	local effortAvailable, rawEffort, adhesionLimit = self:availableEffort(vAbs)
	local throttleEffort = 0
	if not self.emergency then
		throttleEffort = effortAvailable * self.throttle
	end
	-- reversing: traction acts the other way
	local dirToTravel = (v == 0) and self.direction or (v > 0 and 1 or -1)
	local fDrive = throttleEffort * dirToTravel

	local fBrake = 0
	local brakeRate = self.emergency and self.emergencyBrakeRate or self.brakeRate
	if vAbs > 0.05 and self.brakeApplied > 0 then
		-- brake force scaled by mass (kN) = m * a
		local maxF = self.mass * brakeRate * self.brakeApplied
		fBrake = -math.sign(v) * math.min(maxF, (vAbs / dt) * self.mass + 200)
	end

	local fRes = self:resistance(grade, curvature)
	local fResSigned = 0
	if vAbs > 0.02 then
		fResSigned = -math.sign(v) * fRes
	elseif fDrive ~= 0 then
		-- static resistance must be overcome before rolling
		local static = math.sign(fDrive) * math.min(math.abs(fDrive), fRes)
		fResSigned = -static
	else
		fResSigned = 0
	end

	local fTotal = fDrive + fBrake + fResSigned
	local a = (fTotal * 1000) / (self.mass * 1000)   -- kN/t -> m/s^2
	-- jerk limiting
	if math.abs(v) < 0.02 and math.abs(fDrive) < 1e-6 then
		-- at a stand with no traction: nothing should keep nudging us
		a = 0
	else
		local aMax = self.accel + self.jerkLimit * dt
		local aMin = self.accel - self.jerkLimit * dt
		a = math.clamp(a, aMin, aMax)
	end

	local newV = v + a * dt
	-- stop cleanly at zero when braking
	if vAbs > 0 and self.brakeApplied > 0 and math.sign(newV) ~= math.sign(v) and fDrive * math.sign(v) <= 0 then
		newV = 0
	end
	if math.abs(newV) > self.maxSpeed then
		newV = math.sign(newV) * self.maxSpeed
	end

	if math.abs(newV) < 0.05 and self.brakeApplied > 0.05 and math.abs(fDrive) < 1e-6 then
		newV = 0
		self.accel = 0
	end

	local moved = (v + newV) / 2 * dt
	self.accel = a
	self.speed = newV
	self.distance = self.distance + moved

	-- energy metering (only positive traction power)
	local p = math.abs(throttleEffort) * vAbs           -- kW (kN * m/s)
	self.energyUsed = self.energyUsed + (p * dt) / 3600

	return {
		speed = self.speed,
		accel = self.accel,
		moved = moved,
		brakeApplied = self.brakeApplied,
		effort = throttleEffort,
		effortMax = rawEffort,
		adhesionLimit = adhesionLimit,
		powerLimited = self.powerLimited,
		resistance = fRes,
		wheelSlip = (throttleEffort >= adhesionLimit - 0.001) and self.throttle > 0.4,
	}
end

--------------------------------------------------------------------------- helpers

-- braking distance (m) from speed v at a given deceleration
function TrainPhysics.brakingDistance(v, decel, reaction)
	reaction = reaction or 0
	if decel <= 0 then
		return math.huge
	end
	return v * reaction + (v * v) / (2 * decel)
end

-- the speed you must be at now to stop within `dist`
function TrainPhysics.speedForStop(dist, decel, reaction)
	reaction = reaction or 0
	local d = dist - 0
	if d <= 0 then
		return 0
	end
	local vReaction = d / math.max(0.1, (reaction * 2)) -- keep reaction term sane
	local v = math.sqrt(2 * decel * d)
	return math.min(v, vReaction)
end

-- automatic brake controller: returns 0..1 brake demand for a station stop
function TrainPhysics.stoppingCurve(distanceToStop, currentSpeed, decel)
	decel = decel or 0.9
	local needed = TrainPhysics.brakingDistance(currentSpeed, decel, 0.8)
	if needed >= distanceToStop then
		-- brake harder the closer we are
		local over = (needed - distanceToStop) / math.max(1, needed)
		return math.clamp(0.35 + over * 1.4, 0, 1)
	end
	return 0
end

-- coasting target: notches
function TrainPhysics.notchToThrottle(notch, count)
	count = count or 8
	notch = math.clamp(notch, 0, count)
	return notch / count
end

return TrainPhysics
