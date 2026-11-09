--!nocheck
-- Config: shared tunables for trains, signalling and stations.
local Config = {}

Config.RailTop = 0.62
Config.Gauge = 1.435

-- physics ----------------------------------------------------------------
Config.Davis = {
	-- F = A + B*v + C*v^2  (kN, v in m/s) - a plausible modern EMU/DMU resistance curve
	A = 3.2,
	B = 0.085,
	C = 0.0058,
}
Config.Gravity = 9.81
Config.TractiveEffort = 260      -- kN: starting effort of a 4-axle electric loco
Config.PowerRating = 2400        -- kW at rail
Config.MaxSpeed = 55.5           -- m/s (~200 km/h)
Config.BrakeRate = 0.9           -- m/s^2 service braking (blended)
Config.EmergencyBrakeRate = 1.35 -- m/s^2
Config.BrakeBuildUp = 1.6        -- s for brake pressure to build
Config.Adhesion = 0.28           -- wheel/rail friction coefficient
Config.RollingResistance = 0.9   -- kN constant
Config.JerkLimit = 0.65          -- m/s^3 acceleration change limit
Config.NotchCount = 8            -- power notches

Config.AwsSpeed = 22             -- m/s warning threshold for "caution"

-- stations ---------------------------------------------------------------
Config.Stations = {
	{ name = "Grand Central Terminus", s = 60, stopAt = 40, dwell = 25, terminus = true },
	{ name = "Glanne Viaduct Halt", s = "viaduct", dwell = 18 },
	{ name = "Harbour Terminus", s = "harbour", dwell = 30, terminus = true },
}

-- gameplay ---------------------------------------------------------------
Config.PlayerTrainSpeedLimit = 45   -- m/s (~160 km/h) enforced with audible warning
Config.OverspeedTolerance = 2
Config.HornDuration = 1.1
Config.DoorAnimTime = 2.2
Config.CoinlessScorePerStop = 25
Config.RoseGold = Color3.fromRGB(255, 214, 150)

return Config
