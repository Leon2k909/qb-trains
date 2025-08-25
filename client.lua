-- qb-trains — client.lua
-- Requires config.lua with stations and flags noted below.

local QBCore = exports['qb-core']:GetCoreObject()

-- =========================
-- Config flags expected
-- =========================
-- Config.RequireTrainPresence = true
-- Config.TrainDetectRadius    = 7.5
-- Config.TrainBoardSpeedKmh   = 3.0
-- Config.TrainTarget          = true/false
-- Config.TrainTargetIgnoreDwell = true/false
-- Config.AlwaysAllowBoard     = false
-- Config.Headway              = 60
-- Config.DwellTime            = 12
-- Config.RefreshScheduleMs    = 1500
-- Config.ShowBlips            = true/false
-- Optional spawner:
-- Config.SpawnMissionMetroAtStations = true
-- Config.SpawnedTrainFrozen          = true   -- freeze spawned trains for static presence
-- Config.LSTrackIndex                = 24     -- LS metro track id for CreateMissionTrain

-- =========================
-- Ambient trains (freight etc.)
-- =========================
CreateThread(function()
    SetRandomTrains(true)
    SwitchTrainTrack(0, true)
    SwitchTrainTrack(3, true)
    SetTrainTrackSpawnFrequency(0, 120000)
    SetTrainTrackSpawnFrequency(3, 120000)
end)

-- =========================
-- State / helpers
-- =========================
local boarding, inTransit = false, false
local hasTicket = false
local uiOpen = false
local spawnedTrains = {} -- station index -> entity id

local function wrapIndex(i, len) if i < 1 then return len elseif i > len then return 1 else return i end end
local function DrawTxtCenter(x,y,text)
    SetTextFont(4); SetTextScale(0.35,0.35); SetTextColour(255,255,255,215); SetTextCentre(true)
    SetTextOutline(); BeginTextCommandDisplayText('STRING'); AddTextComponentSubstringPlayerName(text); EndTextCommandDisplayText(x,y)
end
local function nearestStationIndex(pos)
    local best, bestD = 1, 1e9
    for i, st in ipairs(Config.Stations) do
        local d = #(pos - st.coords)
        if d < bestD then bestD = d; best = i end
    end
    return best
end
local function isTrain(ent)
    return DoesEntityExist(ent) and IsThisModelATrain(GetEntityModel(ent))
end

-- stopped train near a position
local function getStoppedTrainNear(pos)
    local radius = Config.TrainDetectRadius or 7.5
    local limit  = Config.TrainBoardSpeedKmh or 3.0
    for _, v in ipairs(GetGamePool('CVehicle')) do
        if isTrain(v) then
            local d = #(GetEntityCoords(v) - pos)
            if d < radius then
                local kmh = GetEntitySpeed(v) * 3.6
                if kmh <= limit or IsEntityPositionFrozen(v) then
                    return v
                end
            end
        end
    end
    return 0
end

-- =========================
-- Mission-train spawner (aligned to rails)
-- =========================
local function spawnMissionMetroAtStation(i)
    if spawnedTrains[i] and DoesEntityExist(spawnedTrains[i]) then return end
    local st = Config.Stations[i]; if not st then return end
    local track = Config.LSTrackIndex or 24
    -- CreateMissionTrain places the consist on the nearest rail segment to coords
    local train = CreateMissionTrain(track, st.coords.x + 0.0, st.coords.y + 0.0, st.coords.z + 0.0, true)
    if train and train ~= 0 then
        SetEntityAsMissionEntity(train, true, false)
        if Config.SpawnedTrainFrozen then
            FreezeEntityPosition(train, true)
            SetVehicleDoorsLocked(train, 1)
            -- open a couple of doors to signal boarding
            SetVehicleDoorOpen(train, 0, false, false)
            SetVehicleDoorOpen(train, 1, false, false)
        end
        spawnedTrains[i] = train
        print(('[qb-trains] mission metro spawned at %s (id %s)'):format(st.name, tostring(train)))
    else
        print(('[qb-trains] failed CreateMissionTrain at %s'):format(st.name))
    end
end

local function buildAllMissionMetros()
    if not Config.SpawnMissionMetroAtStations then return end
    for i=1,#Config.Stations do spawnMissionMetroAtStation(i) Wait(100) end
end

local function keepMissionMetrosAlive()
    if not Config.SpawnMissionMetroAtStations then return end
    for i=1,#Config.Stations do
        local ent = spawnedTrains[i]
        if not ent or not DoesEntityExist(ent) then spawnMissionMetroAtStation(i) end
    end
end

CreateThread(function()
    while not LocalPlayer or not LocalPlayer.state or not LocalPlayer.state.isLoggedIn do Wait(250) end
    Wait(500)
    buildAllMissionMetros()
    while true do
        keepMissionMetrosAlive()
        Wait(15000)
    end
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    for i, ent in pairs(spawnedTrains) do
        if DoesEntityExist(ent) then DeleteEntity(ent) end
        spawnedTrains[i] = nil
    end
end)

-- =========================
-- Server RPC helpers
-- =========================
-- server charges $1000 from BANK
local function lib_Charge(stationName)
    local ok, fare = nil, nil
    QBCore.Functions.TriggerCallback('qb-trains:charge', function(_ok, _fare)
        ok, fare = _ok, _fare
    end, stationName)
    while ok == nil do Wait(0) end
    return ok, fare
end

-- build a schedule based on actual train entities
local function buildLiveSchedule()
    local n = #Config.Stations
    local timesFwd, timesBack = {}, {}
    for i=1,n do timesFwd[i]=9999; timesBack[i]=9999 end
    for _, v in ipairs(GetGamePool('CVehicle')) do
        if isTrain(v) then
            local pos = GetEntityCoords(v)
            local idx = nearestStationIndex(pos)
            local nextPos = Config.Stations[wrapIndex(idx+1,n)].coords
            local prevPos = Config.Stations[wrapIndex(idx-1,n)].coords
            local vel = GetEntityVelocity(v)
            local dotF = (nextPos.x-pos.x)*vel.x + (nextPos.y-pos.y)*vel.y + (nextPos.z-pos.z)*vel.z
            local dotB = (prevPos.x-pos.x)*vel.x + (prevPos.y-pos.y)*vel.y + (prevPos.z-pos.z)*vel.z
            local dirFwd = dotF >= dotB
            local t = 0
            local i = idx
            repeat
                if dirFwd then
                    if t < timesFwd[i] then timesFwd[i]=t end
                    t = t + (Config.DwellTime or 12) + (Config.SegmentTravelTime or 25)
                    i = wrapIndex(i+1, n)
                else
                    if t < timesBack[i] then timesBack[i]=t end
                    t = t + (Config.DwellTime or 12) + (Config.SegmentTravelTime or 25)
                    i = wrapIndex(i-1, n)
                end
            until i == idx
        end
    end
    local sched = {}
    for i=1,n do
        sched[i] = { fwd = timesFwd[i], back = timesBack[i] }
    end
    return sched
end

local function canBoardAtStation(idx)
    if Config.RequireTrainPresence then
        if getStoppedTrainNear(Config.Stations[idx].coords) == 0 then return false end
    end
    if Config.AlwaysAllowBoard then return true end
    local s = buildLiveSchedule()
    if not s or not s[idx] then return false end
    local secs = math.min(s[idx].fwd, s[idx].back)
    return secs <= (Config.DwellTime or 12)
end

-- =========================
-- Boarding (charge only)
-- =========================
function startBoarding(stIndex)
    if boarding or inTransit then return end
    local ped = PlayerPedId()
    if IsPedInAnyVehicle(ped, false) then
        QBCore.Functions.Notify('Exit your vehicle to board', 'error'); return
    end
    if Config.RequireTrainPresence and getStoppedTrainNear(Config.Stations[stIndex].coords) == 0 then
        QBCore.Functions.Notify('No train present', 'error'); return
    end

    boarding = true
    local ok, fare = lib_Charge(Config.Stations[stIndex].name)
    if ok then
        QBCore.Functions.Notify(('Fare deducted: $%d'):format(fare or 1000), 'success', 2500)
        hasTicket = true
        local train = getStoppedTrainNear(Config.Stations[stIndex].coords)
        if train ~= 0 then
            TaskEnterVehicle(ped, train, -1, 0, 2.0, 1, 0)
        end
    else
        QBCore.Functions.Notify('Insufficient bank balance ($1000 required)', 'error')
        hasTicket = false
    end
    SetTimeout(400, function() boarding = false end)
end

-- kick players who didn't pay
CreateThread(function()
    while true do
        Wait(1000)
        local ped = PlayerPedId()
        if IsPedInAnyVehicle(ped, false) then
            local veh = GetVehiclePedIsIn(ped, false)
            if isTrain(veh) then
                if not hasTicket then
                    TaskLeaveVehicle(ped, veh, 16)
                    QBCore.Functions.Notify('You need to pay the fare to ride', 'error')
                end
            else
                hasTicket = false
            end
        else
            hasTicket = false
        end
    end
end)

-- =========================
-- Station marker + E prompt
-- =========================
CreateThread(function()
    while true do
        local sleep = 750
        if not inTransit and not boarding then
            local ped = PlayerPedId()
            local p = GetEntityCoords(ped)
            local sched = buildLiveSchedule()
            for idx, st in ipairs(Config.Stations) do
                if #(p - st.coords) < ((Config.MarkerRadius or 2.5) + 0.6) then
                    sleep = 0
                    DrawMarker(2, st.coords.x, st.coords.y, st.coords.z+0.1, 0,0,0, 0,0,0,
                               0.26,0.26,0.26, 255,120,30, 180, false,false,2,false,nil,nil,false)
                    if canBoardAtStation(idx) then
                        local msg = ('Press ~INPUT_CONTEXT~ to board %s ($1000)'):format(st.name)
                        if Config.HelpText then Config.HelpText(msg) else DrawTxtCenter(0.5,0.90,msg) end
                        if IsControlJustReleased(0, 38) then startBoarding(idx) end
                    else
                        if Config.RequireTrainPresence and getStoppedTrainNear(st.coords) == 0 then
                            local msg = ('%s — no train present'):format(st.name)
                            if Config.HelpText then Config.HelpText(msg) else DrawTxtCenter(0.5,0.90,msg) end
                        else
                            if sched and sched[idx] then
                                local secs = math.min(sched[idx].fwd, sched[idx].back)
                                local msg = ('%s — arrives in %ds'):format(st.name, math.floor(secs))
                                if Config.HelpText then Config.HelpText(msg) else DrawTxtCenter(0.5,0.90,msg) end
                            end
                        end
                    end
                    break
                end
            end
        end
        Wait(sleep)
    end
end)

-- =========================
-- qb-target on trains
-- =========================
CreateThread(function()
    if not Config.TrainTarget then return end
    local state = (GetResourceState and GetResourceState('qb-target')) or 'missing'
    if not (state == 'started' or state == 'starting') then return end

    local added = {}
    while true do
        local ped = PlayerPedId()
        local p = GetEntityCoords(ped)
        for _, v in ipairs(GetGamePool('CVehicle')) do
            if not added[v] and isTrain(v) and #(GetEntityCoords(v) - p) < 60.0 then
                exports['qb-target']:AddTargetEntity(v, {
                    options = {
                        {
                            icon = 'fas fa-subway',
                            label = 'Board Train ($1000)',
                            canInteract = function(ent)
                                if inTransit or boarding then return false end
                                if not DoesEntityExist(ent) then return false end
                                local kmh = GetEntitySpeed(ent) * 3.6
                                if kmh > (Config.TrainBoardSpeedKmh or 3.0) and not IsEntityPositionFrozen(ent) then return false end
                                local idx = nearestStationIndex(GetEntityCoords(PlayerPedId()))
                                -- near any configured platform
                                if #(GetEntityCoords(PlayerPedId()) - Config.Stations[idx].coords) > ((Config.MarkerRadius or 2.5) + 6.0) then
                                    return false
                                end
                                if Config.RequireTrainPresence and getStoppedTrainNear(Config.Stations[idx].coords) == 0 then
                                    return false
                                end
                                if Config.TrainTargetIgnoreDwell then
                                    return true
                                else
                                    return canBoardAtStation(idx)
                                end
                            end,
                            action = function()
                                local idx = nearestStationIndex(GetEntityCoords(PlayerPedId()))
                                startBoarding(idx)
                            end
                        }
                    },
                    distance = 3.0
                })
                added[v] = true
            end
        end
        Wait(Config.TrainScanIntervalMs or 2000)
    end
end)

-- =========================
-- Blips
-- =========================
local stationBlips = {}
local function clearTrainBlips() for _, b in ipairs(stationBlips) do if DoesBlipExist(b) then RemoveBlip(b) end end stationBlips = {} end
local function buildTrainBlips()
    if not Config.ShowBlips then return end
    clearTrainBlips()
    local spritePrimary, spriteFallback = (Config.BlipSprite or 795), 280
    for _, st in ipairs(Config.Stations or {}) do
        local b = AddBlipForCoord(st.coords.x, st.coords.y, st.coords.z)
        SetBlipSprite(b, spritePrimary); if GetBlipSprite(b) ~= spritePrimary then SetBlipSprite(b, spriteFallback) end
        SetBlipColour(b, Config.BlipColor or 47); SetBlipScale(b, Config.BlipScale or 0.75); SetBlipAsShortRange(b, true)
        BeginTextCommandSetBlipName('STRING'); AddTextComponentString(('Metro: %s'):format(st.name or 'Station')); EndTextCommandSetBlipName(b)
        stationBlips[#stationBlips+1] = b
    end
end
CreateThread(function() while not LocalPlayer or not LocalPlayer.state or not LocalPlayer.state.isLoggedIn do Wait(250) end Wait(500) buildTrainBlips() end)
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', buildTrainBlips)
RegisterNetEvent('QBCore:Client:OnPlayerUnload', clearTrainBlips)
RegisterCommand('trainblips', function() buildTrainBlips() end, false)

local function sendPresenceTick()
    while uiOpen do
        local pres = {}
        for i, st in ipairs(Config.Stations) do
            pres[i] = (getStoppedTrainNear(st.coords) ~= 0)
        end
        SendNUIMessage({ action = 'presence', present = pres })
        Wait(1000)
    end
end

local function openTrainsUI()
    local sched = buildLiveSchedule()
    if not sched then QBCore.Functions.Notify('Schedule unavailable', 'error') return end

    local ped = PlayerPedId()
    local p = GetEntityCoords(ped)

    local rows = {}
    local nearestIdx, nearestDist = 1, 1e9
    for i, st in ipairs(Config.Stations) do
        local d = #(p - st.coords)
        if d < nearestDist then nearestDist = d nearestIdx = i end
        local fwd = sched[i] and sched[i].fwd or 0
        local back = sched[i] and sched[i].back or 0
        rows[#rows+1] = {
            i=i, name=st.name,
            x=st.coords.x, y=st.coords.y, z=st.coords.z,
            fwd=fwd, back=back,
            present = (getStoppedTrainNear(st.coords) ~= 0),
            toNext=Config.Stations[wrapIndex(i+1,#Config.Stations)].name,
            toPrev=Config.Stations[wrapIndex(i-1,#Config.Stations)].name
        }
    end

    uiOpen = true
    SetNuiFocus(true, true)
    SendNUIMessage({
        action  = 'open',
        headway = Config.Headway,
        dwell   = Config.DwellTime,
        nearest = nearestIdx,
        stations = rows
    })
    CreateThread(sendPresenceTick)
end

RegisterCommand('trains', function() openTrainsUI() end, false)

RegisterNUICallback('setWaypoint', function(data, cb)
    if data and data.x and data.y then SetNewWaypoint(data.x + 0.0, data.y + 0.0) end
    cb('ok')
end)

RegisterNUICallback('close', function(_, cb)
    uiOpen = false
    SetNuiFocus(false, false)
    cb('ok')
end)

AddEventHandler('onResourceStop', function(res)
    if res ~= GetCurrentResourceName() then return end
    uiOpen = false
    SetNuiFocus(false, false)
end)
