Config = {}
-- force-spawn a static metro train at each platform for presence/boarding
Config.ForceSpawnStaticMetro  = true
Config.StaticTrainHeading     = 0.0     -- set per-station if you need exact alignment
Config.StaticTrainDoorIndex   = 0       -- 0..7; try 0 or 1 for metro door

Config.RequireTrainPresence = true      -- only allow boarding if a train is physically here
Config.TrainDetectRadius    = 7.5       -- meters around platform to look for a train
Config.TrainBoardSpeedKmh   = 3.0       -- must be basically stopped

-- boarding behavior
Config.AlwaysAllowBoard     = false   -- true = allow E/target anytime at platform (ignores dwell)
Config.TrainTarget          = true    -- add qb-target on actual train vehicles
Config.TrainScanIntervalMs  = 2000    -- how often to scan for trains
Config.TrainTargetIgnoreDwell = true
-- Fare (cash charged when doors close)
Config.BaseFare = 50

-- Time in seconds doors stay “open” at stations
Config.DwellTime = 12

-- Time in seconds between departures in each direction
Config.Headway = 60

-- Time in seconds to simulate travel between stations
Config.SegmentTravelTime = 25

-- Radius around platform coords for prompts/blips
Config.MarkerRadius = 2.5

-- Blips
Config.ShowBlips  = true
Config.BlipSprite = 795   -- subway icon (use 280 if this doesn’t show)
Config.BlipColor  = 47
Config.BlipScale  = 0.75

-- Require player to pick forward/backward direction
Config.RequireDirectionChoice = true

-- Allow qb-target boarding as well as E key prompt
Config.UseTarget = true

-- How often (ms) to refresh the cached schedule client-side
Config.RefreshScheduleMs = 1500

-- Station list (replace coords with your actual platform locations)
Config.Stations = {
    { name = 'Pillbox Hill', coords = vec3(278.88, -1205.54, 38.89) },
    { name = 'Little Seoul', coords = vec3(-507.60, -670.56, 33.08) },
    { name = 'Del Perro',    coords = vec3(-1355.23, -544.77, 30.56) },
    { name = 'Vespucci',     coords = vec3(-1082.90, -1481.45, 5.11) },
    { name = 'Davis',        coords = vec3(98.44, -1726.48, 28.26) },
    { name = 'LSIA',         coords = vec3(-1038.90, -2738.30, 13.76) },
}

-- Optional per-station fare overrides
Config.Fares = {
    -- ['LSIA'] = 80,
}

-- Draw helptext on screen
function Config.HelpText(msg)
    SetTextComponentFormat('STRING')
    AddTextComponentString(msg)
    DisplayHelpTextFromStringLabel(0, false, true, -1)
end
