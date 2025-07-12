-- Account Computer with Firebase + Radar + Monitor UI

local depositChest = peripheral.wrap("minecraft:chest_389")
local withdrawalChest = peripheral.wrap("minecraft:chest_388")
local payoutChest = peripheral.wrap("minecraft:chest_390")
local monitor = peripheral.find("monitor")
local radar = peripheral.find("radar")
local logger = require("logger")

local http = http
local API_URL = "https://a8410f940b59.ngrok-free.app/balance/"

local VALID_BOOKS = {
    ["01cf97"] = 500,
    ["e61758"] = 1000,
    ["1fafe1"] = 5000,
    ["6d281b"] = 10000,
    ["dd703d"] = 15000
}
local COIN_ORDER = {15000, 10000, 5000, 1000, 500}

-- Firebase
local function getBalance(username)
    local res = http.get(API_URL .. username)
    if not res then return nil end
    local data = textutils.unserializeJSON(res.readAll())
    res.close()
    return data and data.coins or 0
end

local function setBalance(username, amount)
    local body = textutils.serializeJSON({ coins = amount })
    http.post(API_URL .. username, body, { ["Content-Type"] = "application/json" })
end

-- Book movement
local function giveBooks(amount)
    local prefixMap = {}
    for hash, val in pairs(VALID_BOOKS) do
        prefixMap[val] = hash
    end

    for _, denom in ipairs(COIN_ORDER) do
        while amount >= denom do
            local list = payoutChest.list()
            local foundSlot = nil
            for slot, item in pairs(list) do
                if item.name == "minecraft:written_book" and item.nbtHash then
                    local prefix = string.sub(item.nbtHash, 1, 6)
                    if prefix == prefixMap[denom] then
                        foundSlot = slot
                        break
                    end
                end
            end

            if not foundSlot then break end

            local moved = payoutChest.pushItems(peripheral.getName(withdrawalChest), foundSlot, 1)
            if moved == 0 then break end

            amount = amount - denom
        end
    end
    return amount -- Remaining
end

-- Radar player detection within 5 blocks
local function getNearestPlayerWithinRange(maxDistance)
    if not radar then return nil end
    local players = radar.getPlayers()
    local nearest = nil
    local nearestDist = maxDistance + 1
    for _, player in ipairs(players) do
        local dist = math.sqrt(player.x^2 + player.y^2 + player.z^2)
        if dist <= maxDistance and dist < nearestDist then
            nearest = player.name
            nearestDist = dist
        end
    end
    return nearest
end

-- Monitor UI
local function drawCentered(text, y, color)
    local w, _ = monitor.getSize()
    local x = math.floor((w - #text) / 2) + 1
    monitor.setCursorPos(x, y)
    if color then monitor.setTextColor(color) end
    monitor.write(text)
end

local function drawUI(balance, step, selection)
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
    monitor.clear()

    if step == "main" then
        drawCentered("Welcome to Wavecrest Casino!", 2)
        drawCentered("[Deposit]", 4, colors.green)
        drawCentered("[Withdraw]", 6, colors.cyan)
    elseif step == "denomination" then
        drawCentered("Select denomination", 3)
        local y = 5
        for _, value in ipairs(COIN_ORDER) do
            drawCentered("[ " .. value .. " ]", y)
            y = y + 2
        end
    elseif step == "quantity" then
        drawCentered("Selected: " .. selection .. " coins", 3)
        drawCentered("Select quantity (1-10)", 5)
        for i = 1, 10 do
            monitor.setCursorPos(i * 3, 7)
            monitor.write("[" .. i .. "]")
        end
    elseif step == "confirm" then
        drawCentered("Withdraw " .. selection .. " coins?", 5)
        drawCentered("[ Confirm ]", 7, colors.green)
        drawCentered("[ Cancel ]", 9, colors.red)
    elseif step == "deposit_confirm" then
        drawCentered("Deposit books detected!", 5)
        drawCentered("[ Confirm ]", 7, colors.green)
        drawCentered("[ Cancel ]", 9, colors.red)
    end
end

-- Main loop
local state = "main"
local selectedPlayer = nil
local balance = 0
local selection = { denom = 0, quantity = 0, amount = 0 }

while true do
    local player = getNearestPlayerWithinRange(5)
    if player ~= selectedPlayer then
        selectedPlayer = player
        if selectedPlayer then
            balance = getBalance(selectedPlayer) or 0
            state = "main"
        else
            monitor.clear()
            drawCentered("Insert books or approach", 2, colors.yellow)
        end
    end

    if selectedPlayer then
        if state == "main" then
            drawUI(balance, "main")
            local event, side, x, y = os.pullEvent("monitor_touch")
            if y == 4 then
                local depositTotal = 0
                local list = depositChest.list()
                for _, item in pairs(list) do
                    if item.name == "minecraft:written_book" and item.nbtHash then
                        local prefix = string.sub(item.nbtHash, 1, 6)
                        local value = VALID_BOOKS[prefix]
                        if value then
                            depositTotal = depositTotal + (value * item.count)
                        end
                    end
                end
                if depositTotal > 0 then
                    selection.amount = depositTotal
                    state = "deposit_confirm"
                end
            elseif y == 6 then
                state = "denomination"
            end
        elseif state == "deposit_confirm" then
            drawUI(balance, "deposit_confirm")
            local _, _, x, y = os.pullEvent("monitor_touch")
            if y == 7 then
                for slot, item in pairs(depositChest.list()) do
                    if item.name == "minecraft:written_book" then
                        depositChest.pushItems(peripheral.getName(payoutChest), slot)
                    end
                end
                balance = balance + selection.amount
                setBalance(selectedPlayer, balance)
                logger.logTransaction(selectedPlayer, "Deposit", selection.amount, balance)
                monitor.clear()
                drawCentered("Deposit complete!", 6, colors.green)
                sleep(2)
                state = "main"
                selection = { denom = 0, quantity = 0, amount = 0 }
            elseif y == 9 then
                state = "main"
                selection = { denom = 0, quantity = 0, amount = 0 }
            end
        elseif state == "denomination" or state == "quantity" or state == "confirm" then
            drawUI(balance, state, selection.amount)
            local _, _, x, y = os.pullEvent("monitor_touch")
            if state == "denomination" then
                local denomByY = {
                    [5] = 15000, [7] = 10000, [9] = 5000,
                    [11] = 1000, [13] = 500
                }
                local selected = denomByY[y]
                if selected then
                    selection.denom = selected
                    state = "quantity"
                end
            elseif state == "quantity" then
                for i = 1, 10 do
                    if y == 7 and x >= i * 3 and x <= i * 3 + 2 then
                        selection.quantity = i
                        selection.amount = selection.denom * i
                        state = "confirm"
                    end
                end
            elseif state == "confirm" then
                if y == 7 then
                    if balance >= selection.amount then
                        local leftover = giveBooks(selection.amount)
                        local actual = selection.amount - leftover
                        balance = balance - actual
                        setBalance(selectedPlayer, balance)
                        logger.logTransaction(selectedPlayer, "Withdraw", -actual, balance)
                        monitor.clear()
                        drawCentered("Collect your books", 6, colors.green)
                        sleep(3)
                    else
                        monitor.clear()
                        drawCentered("Insufficient funds", 6, colors.red)
                        sleep(2)
                    end
                    state = "main"
                    selection = { denom = 0, quantity = 0, amount = 0 }
                elseif y == 9 then
                    state = "main"
                    selection = { denom = 0, quantity = 0, amount = 0 }
                end
            end
        end
    end
    sleep(0.5)
end
