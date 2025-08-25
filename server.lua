-- qb-trains — server.lua
local QBCore = exports['qb-core']:GetCoreObject()

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
