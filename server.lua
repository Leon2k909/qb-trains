-- qb-trains — server.lua
local QBCore = exports['qb-core']:GetCoreObject()

-- =====================
-- Simple schedule model
-- =====================
local Sched = {}

local function now() return os.time() end

local function initSchedules()
    local t = now()
    Sched = {}
    for i=1,#Config.Stations do
        Sched[i] = {
            fwd  = t + math.random(5, Config.Headway),
            back = t + math.random(5, Config.Headway) + 15
        }
    end
    print(('[qb-trains] schedules initialized for %d stations'):format(#Config.Stations))
end

AddEventHandler('onResourceStart', function(res)
    if res ~= GetCurrentResourceName() then return end
    initSchedules()
end)

CreateThread(function()
    while true do
        local t = now()
        for i=1,#Config.Stations do
            if t >= Sched[i].fwd  then Sched[i].fwd  = t + Config.Headway end
            if t >= Sched[i].back then Sched[i].back = t + Config.Headway end
        end
        Wait(1000)
    end
end)

-- =====================
-- Callbacks
-- =====================
QBCore.Functions.CreateCallback('qb-trains:schedule', function(src, cb)
    cb(Sched, now())
end)

-- Charge EXACTLY $1000 from BANK when doors close
QBCore.Functions.CreateCallback('qb-trains:charge', function(src, cb, stationName)
    local Player = QBCore.Functions.GetPlayer(src)
    if not Player then
        cb(false, 1000)
        return
    end
    local fare = 1000
    local ok = Player.Functions.RemoveMoney('bank', fare, 'metro-fare')
    if ok then
        print(('[qb-trains] charged $%d bank from %s (%s) at %s')
            :format(fare, Player.PlayerData.charinfo.firstname, Player.PlayerData.citizenid, stationName or 'unknown'))
        cb(true, fare)
    else
        print(('[qb-trains] NOT ENOUGH BANK for %s (%s)'):format(Player.PlayerData.charinfo.firstname, Player.PlayerData.citizenid))
        cb(false, fare)
    end
end)

-- =====================
-- Admin
-- =====================
QBCore.Commands.Add('trainreset', 'Reset train schedules', {}, false, function(source)
    initSchedules()
    TriggerClientEvent('QBCore:Notify', source, 'Train schedules reset', 'success')
end, 'admin')

-- quick diagnostic command: test charge now
QBCore.Commands.Add('traintestcharge', 'Test metro charge ($1000 bank)', {}, false, function(source)
    local Player = QBCore.Functions.GetPlayer(source)
    if not Player then return end
    local ok = Player.Functions.RemoveMoney('bank', 1000, 'metro-fare-test')
    if ok then
        TriggerClientEvent('QBCore:Notify', source, 'Charged $1000 from bank', 'success')
    else
        TriggerClientEvent('QBCore:Notify', source, 'Insufficient bank', 'error')
    end
end, 'admin')
