-- RaceMP (Server)

local settings = {}
--[[
    settings["lapCount"]
    settings["track"]   
    settings["raceName"]
]]

local players = {}
local explodeWait = 30
local explodeTime = explodeWait

local function prettyTime(seconds)
    local thousandths = seconds * 1000
    local mm = math.floor((thousandths / (60 * 1000))) % 60
    local ss = math.floor(thousandths / 1000) % 60
    local ms = math.floor(thousandths % 1000)
    return string.format("%02d:%02d.%d", mm, ss, ms)
end

local function tableLength(t)
    local counter = 0
    for k,v in pairs(t) do
        counter = counter + 1
    end
    return counter
end

function dump(o)
    if type(o) == 'table' then
       local s = '{ '
       for k,v in pairs(o) do
          if type(k) ~= 'number' then k = '"'..k..'"' end
          s = s .. '['..k..'] = ' .. dump(v) .. ','
       end
       return s .. '} '
    else
       return tostring(o)
    end
end

function dumpPretty(o, ind)
    if type(o) == 'table' then
       local s = string.rep(" ", ind) .. '{ \n'
       for k,v in pairs(o) do
          if type(k) ~= 'number' then k = '"'..k..'"' end
          s = s .. string.rep(" ", ind) .. '['..k..'] = ' .. dumpPretty(v, ind + 1) .. ',\n'
       end
       return s .. string.rep(" ", ind) .. '} '
    else
       return tostring(o)
    end
end

function splitPosition(player, pTable, lap)
    player = tonumber(player)
    local lastLap   = #pTable[player]
    local lastSplit = #pTable[player][lastLap]
    local position  = 1

    if lap then
        for p, laps in pairs(pTable) do
            if players[p][lastLap] then
                position = position + 1
            end
            pTable[player][lastLap]['position'] = position
        end
    else
        for p, laps in pairs(pTable) do
            if pTable[p][lastLap] then if pTable[p][lastLap][lastSplit] then
                position = position + 1
            end end
            pTable[player][lastLap][lastSplit]['position'] = position
        end
    end
    return pTable
end

function addCurrentPostition(pTable)
    local location = {} -- 'total' 'player'
    --print(Util.JsonEncode(pTable))
    for id,player in pairs(pTable) do
        local total = player['splits']
        local lastLap   = #player
        local lastSplit = tableLength(player[lastLap])
        local dec = 0

        if next(player[lastLap]) == nil then
            lastLap = lastLap - 1 -- accounting for initialized laps
        end
        if lastLap < 1 then
            goto continue -- Don't add postition data for players that haven't gone through a checkpoint
        end

        if player[lastLap]['position'] then
            dec = player[lastLap]['position'] / 100
        else
            dec = player[lastLap][lastSplit]['position'] / 100
        end

        --[[ Old and not working properly
        if player[lastLap][lastSplit] then
            dec = player[lastLap][lastSplit]['position'] / 100
        elseif player[lastLap - 1] then
            dec = player[lastLap - 1]['position'] / 100
        else
            dec = player[lastLap]['position'] / 100
        end
        ]]
        total = total - dec
        table.insert(location, {['total'] = total, ['player'] = id})
        ::continue::
    end

    local function sortTotal(k1,k2) return k1.total > k2.total end
    table.sort(location, sortTotal)

    local maxPosition = 0
    for position, t in pairs(location) do
        pTable[t['player']]['position'] = position
        if position > maxPosition then
            maxPosition
        end
    end

    for position, t in pairs(location) do
        if timer > explodeTime and position == maxPosition then
            explodeTime = timer + explodeWait
            MP.TriggerClientEvent(player, "explodeRaceMPCar", players[player].vehID)
        end
    end

    print(Util.JsonEncode(pTable))
    return pTable
end

local function raceEnd(player, position)
    print(MP.GetPlayerName(player) .. " finished")
    MP.SendChatMessage(-1, MP.GetPlayerName(player) .. " finished")
    local send = {
        ['trigger'] = 'ChangeState',
        ['state'] = 'scenario-start',
        ['title'] = "Race Finished",
        ['buttonText'] = "Okay",
        ['description'] = string.format([[
            Congratulations
            You finished in position %s
        ]],tostring(position))
    }
    send = Util.JsonEncode(send)
    --print(send)
    MP.TriggerClientEvent(player, "RaceMPMessage", send)
end

function lapStop(player, data)
    player = tonumber(player)
    --print(data)
    data = Util.JsonDecode(data)
    players[player][#players[player]]['lapTime'] = data['lapTime']
    players[player][#players[player]]['penalty'] = data['penalty']
    players[player][#players[player]]['position'] = data['position']
    time = prettyTime(data["lapTime"])

    players[player]['splits'] = players[player]['splits'] + 1

    local penalty = ""
    if ( data["penalty"] > 0 ) then penalty = " Penalty" end

    players = splitPosition(player, players, true)
    players = addCurrentPostition(players)

    MP.SendChatMessage(-1, MP.GetPlayerName(player) .. ": " .. time .. penalty)
    if settings["lapCount"] then
        print(MP.GetPlayerName(player) .. ": " .. #players[player] .. "/" .. settings["lapCount"] .. " laps")
        if #players[player] == settings["lapCount"] then
            raceEnd(player, players[player]['position'])
        end
    end
    local send = Util.JsonEncode(players)
    MP.TriggerClientEvent(-1, "clientRaceboardData", send)
end

function onChatMessage(senderID, name, message)
    if message == "/start" then
        MP.SendChatMessage(-1, "Race is about to start!")
        MP.TriggerGlobalEvent("onCountdown")
        return 1
    elseif message == "/list"   then
        MP.TriggerClientEvent(senderID,"ListRaces","")
        return 1
    elseif string.find(message,"/set") then
        args = {}
        for k, v in string.gmatch(message, "(%w+)=([%w_]+)") do
            args[k] = v
        end
        --raceName = string.match(message,' (.*)$')
        --MP.TriggerGlobalEvent("setTrack", raceName)
        settings["lapCount"] = tonumber(args["laps"])
        settings["track"]    = args["track"]
        settings["raceName"] = args["raceName"]

        local send = Util.JsonEncode( settings )
        --print(send)
        MP.TriggerClientEvent(-1, "ConfigRace", send)

        return 1
    end
end

function resetLaps()
    for player, laps in pairs(players) do
        players[player] = {['name'] = MP.GetPlayerName(player), ['splits'] = 0}
    end
end

function lapStart(player, data)
    player = tonumber(player)
    players[player][#players[player]+1] = {}
end

function countdown()
    resetLaps()
    local length = 5
    for i = 0,length do
        if i < length then MP.SendChatMessage(-1, "Race Starts in "..length-i) end
        if i == length then MP.SendChatMessage(-1, "Go!") end
        MP.Sleep(1000)
    end
end

function onLapSplit(player, data)
    player = tonumber(player)
    --print(data)
    data = Util.JsonDecode(data)
    local lastLap   = #players[player]
    local lastSplit = #players[player][lastLap] + 1
    players[player]['splits'] = players[player]['splits'] + 1

    players[player][lastLap][lastSplit] = data

    players = splitPosition(player, players, false)
    players = addCurrentPostition(players)
    local send = Util.JsonEncode(players)
    --print(send)
    MP.TriggerClientEvent(-1, "clientRaceboardData", send)
end

function clientRaceMPLoaded(player)
    print(MP.GetPlayerName(player) .. ": RaceMP loaded")
    player = tonumber(player)
    local send = Util.JsonEncode(settings)
    --print(send)
    MP.TriggerClientEvent(player, "ConfigRace", send)
    players[player] = {['name'] = MP.GetPlayerName(player), ['splits'] = 0}
end

function setVehicleID(player, vehID)
	players[player].vehID = vehID
end

print("RaceMP loaded")


MP.RegisterEvent("onLapStart", "lapStart")
MP.RegisterEvent("onLapStop", "lapStop")
MP.RegisterEvent("onChatMessage", "onChatMessage")
MP.RegisterEvent("onCountdown", "countdown")
MP.RegisterEvent("setTrack", "setTrack")
MP.RegisterEvent("clientRaceMPReady", "clientRaceMPReady")
MP.RegisterEvent("onPlayerJoin", "clientRaceMPLoaded")
MP.RegisterEvent("onLapSplit", "onLapSplit")
MP.RegisterEvent("setVehicleID", "setVehicleID")
