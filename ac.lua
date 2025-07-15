-- Account Computer with Radar + Deposit + Rednet Transfer + Background Support

-- === Peripheral Setup ===
local shulkerBox = peripheral.wrap("minecraft:ironshulkerbox_gold_1")
local obCN = "minecraft:ironchest_obsidian_105"
local dropper = "minecraft:dropper_3"
local radar = peripheral.wrap("radar_15")
local monitor = peripheral.wrap("top")
local modem = peripheral.wrap("bottom")
local ri = "redstone_integrator_4025"
local rip = peripheral.wrap(ri)

if not modem then error("? No modem on bottom") end
rednet.open("bottom")

if not fs.exists("/accounts") then fs.makeDir("/accounts") end

local VALID_ITEMS = {
    ["01cf97"] = 500,
    ["dd703d"] = 15000,
    ["e61758"] = 1000,
    ["1fafe1"] = 5000,
    ["6d281b"] = 10000,
}

-- === UI State ===
local PAYOUT_OPTIONS = {500, 1000, 5000, 10000, 15000}
local selectedValueIndex = 1
local selectedQty = 1
local payoutMode = false

-- === Helpers ===
local function getPlayerFile(player)
    return "/accounts/" .. player .. ".txt"
end

local function getBalance(player)
    local path = getPlayerFile(player)
    if fs.exists(path) then
        local f = fs.open(path, "r")
        local val = tonumber(f.readAll())
        f.close()
        return val or 0
    end
    return 0
end

local function setBalance(player, amount)
    local f = fs.open(getPlayerFile(player), "w")
    f.write(tostring(amount))
    f.close()
end

local function logTransaction(player, message, change)
    if not fs.exists("/accounts/logs") then fs.makeDir("/accounts/logs") end
    local logPath = "/accounts/logs/" .. player .. ".txt"
    local time = textutils.formatTime(os.time(), true)
    local newBalance = getBalance(player)
    local delta = (change >= 0 and "+" or "") .. tostring(change)
    local entry = "[" .. time .. "] " .. message .. " " .. delta .. " (Balance: " .. newBalance .. ")"

    local lines = {}
    if fs.exists(logPath) then
        local file = fs.open(logPath, "r")
        while true do
            local line = file.readLine()
            if not line then break end
            table.insert(lines, line)
        end
        file.close()
    end

    table.insert(lines, entry)
    while #lines > 500 do table.remove(lines, 1) end

    local file = fs.open(logPath, "w")
    for _, line in ipairs(lines) do file.writeLine(line) end
    file.close()
end

-- === Deposit Logic ===
local function processDeposit(player)
    local total = 0
    for slot, item in pairs(shulkerBox.list()) do
        if item.nbtHash then
            local prefix = string.sub(item.nbtHash, 1, 6)
            local value = VALID_ITEMS[prefix]
            if value then
                local moved = shulkerBox.pushItems(obCN, slot, item.count)
                total = total + (moved * value)
            end
        end
    end
    if total > 0 then
        local newBal = getBalance(player) + total
        setBalance(player, newBal)
        logTransaction(player, "DEPOSIT: Book tokens deposited", total)
        return newBal, "? Deposited!"
    end
    return getBalance(player), "?? No valid tokens."
end

-- === Payout Logic ===
local function processPayout(player)
    local value = PAYOUT_OPTIONS[selectedValueIndex]
    local qtyToMove = selectedQty
    local total = value * qtyToMove
    local bal = getBalance(player)

    if bal < total then
        message = "Insufficient balance."
        return bal
    end

    local prefix = nil
    for k, v in pairs(VALID_ITEMS) do
        if v == value then
            prefix = k
            break
        end
    end
    if not prefix then
        message = "Token type error."
        return bal
    end

    local chest = peripheral.wrap(obCN)
    local movedTotal = 0

    for slot, item in pairs(chest.list()) do
        if item.nbtHash and string.sub(item.nbtHash, 1, 6) == prefix then
            while movedTotal < qtyToMove and item.count > 0 do
                local moved = chest.pushItems(dropper, slot, 1)
                if moved > 0 then
                    movedTotal = movedTotal + 1
                    sleep(0.05)
                else
                    break
                end
            end
        end
        if movedTotal >= qtyToMove then break end
    end

    if movedTotal < qtyToMove then
        message = "Only moved " .. movedTotal .. "/" .. qtyToMove
        return bal
    end

    setBalance(player, bal - total)
    logTransaction(player, "PAYOUT: " .. qtyToMove .. " x $" .. value, -total)
    message = "Dispensed " .. qtyToMove .. " x $" .. value
    return getBalance(player)
end

-- === Radar Loop ===
local activePlayer, balance, distance, message = nil, 0, nil, ""
local smalrad, largerad = 1.75, 4

local function radarLoop()
    while true do
        local players = radar.getPlayers()
        local valP, cP = {}, nil
        for _, p in ipairs(players) do
            if p.distance <= largerad then
                table.insert(valP, p)
                if p.distance <= smalrad then
                    if not cP or p.distance < cP.distance then
                        cP = p
                    end
                end 
            end
        end
        if not rip then print("no rip")
        elseif #valP == 1 and cP then
            activePlayer = cP.name
            distance = cP.distance
            balance = getBalance(activePlayer)
            rip.setOutput("bottom", true)
            message = ""
        elseif #valP == 1 and not cP then
            activePlayer, distance = nil, nil
            rip.setOutput("bottom", false)
            message = "Not Close Enough!"
        elseif #valP > 1 then
            activePlayer, distance = nil, nil
            rip.setOutput("bottom", false)
            message = "Too Many Players!"
        else
            activePlayer, distance = nil, nil
            rip.setOutput("bottom", false)
            message = ""
        end
        sleep(0.05)
    end
end

-- === Display Loop (Added) ===
local function displayLoop()
    monitor.setTextScale(1)
    while true do
        monitor.clear()

        if activePlayer and not payoutMode then
            monitor.setCursorPos(15, 24)
            monitor.setBackgroundColor(colors.yellow)
            monitor.setTextColor(colors.purple)
            monitor.write("Instructions: With Empty Hand, Open Shulker Box and Put Credits In")
            monitor.setCursorPos(15, 25)
            monitor.write("Then, aiming carefully, right click 'deposit' to transfer")
            monitor.setCursorPos(15, 26)
            monitor.write("Use 'Pull Out Books' to convert Balance back to books")
            monitor.setCursorPos(30, 34)
            monitor.setBackgroundColor(colors.orange)
            monitor.setTextColor(colors.black)
            monitor.write("Welcome, " .. activePlayer)
            monitor.setCursorPos(30, 35)
            monitor.write("Balance: $" .. balance)
            monitor.setBackgroundColor(colors.green)
            monitor.setCursorPos(30, 37)
            monitor.write("[ Deposit Books ]")

            if message then
                monitor.setCursorPos(30, 38)
                monitor.write(message)
            end

            monitor.setCursorPos(30, 30)
            monitor.setBackgroundColor(colors.lime)
            monitor.setTextColor(colors.black)
            monitor.write("[ Pull Out Books ]")

        elseif activePlayer and payoutMode then
            monitor.setCursorPos(30, 30)
            monitor.setBackgroundColor(colors.black)
            monitor.setTextColor(colors.white)
            monitor.write("Select Book Value and Quantity with + and -")

            monitor.setCursorPos(30, 28)
            monitor.write("Balance $" .. balance)

            monitor.setCursorPos(20, 32)
            monitor.setBackgroundColor(colors.gray)
            monitor.setTextColor(colors.white)
            monitor.write("[-]")

            monitor.setCursorPos(25, 32)
            monitor.setBackgroundColor(colors.black)
            monitor.write("Book: $" .. PAYOUT_OPTIONS[selectedValueIndex])

            monitor.setCursorPos(42, 32)
            monitor.setBackgroundColor(colors.gray)
            monitor.write("[+]")

            monitor.setCursorPos(48, 32)
            monitor.setBackgroundColor(colors.gray)
            monitor.write("[-]")

            monitor.setCursorPos(53, 32)
            monitor.setBackgroundColor(colors.black)
            monitor.write("Qty: " .. selectedQty)

            monitor.setCursorPos(62, 32)
            monitor.setBackgroundColor(colors.gray)
            monitor.write("[+]")

            monitor.setCursorPos(35, 35)
            monitor.setBackgroundColor(colors.lime)
            monitor.setTextColor(colors.black)
            monitor.write("[ Payout ]")

            monitor.setCursorPos(35, 37)
            monitor.setBackgroundColor(colors.red)
            monitor.setTextColor(colors.white)
            monitor.write("[ Back ]")

            if message then
                monitor.setCursorPos(25, 39)
                monitor.setBackgroundColor(colors.black)
                monitor.setTextColor(colors.yellow)
                monitor.write(message)
            end
        else
            monitor.setCursorPos(30, 35)
            monitor.write("Stand on the block...")
            monitor.setCursorPos(30, 36)
            monitor.write("Only 1 Player Inside Marked Area!")
        end

        sleep(0.1)
    end
end

-- === Rednet Listener ===
local function rednetListener()
    while true do
        local sender, msg = rednet.receive("casino")
        if type(msg) == "table" then
            if msg.action == "get_players" then
                local players = {}
                for _, name in ipairs(fs.list("/accounts")) do
                    if name:match("%.txt$") and not name:match("logs") then
                        table.insert(players, name:gsub("%.txt$", ""))
                    end
                end
                table.sort(players)
                rednet.send(sender, {action = "players_list", players = players}, "casino")

            elseif msg.action == "get_balance" then
                rednet.send(sender, {player = msg.player, balance = getBalance(msg.player)}, "casino")

            elseif msg.action == "transfer" then
                local old = getBalance(msg.player)
                local new = math.max(0, old + msg.delta)
                setBalance(msg.player, new)
                logTransaction(msg.player, msg.note or "Transfer", msg.delta)
                rednet.send(sender, {player = msg.player, balance = new}, "casino")

            elseif msg.action == "list_accounts" then
                local files = fs.list("/accounts")
                local result = {}
                for _, name in ipairs(files) do
                    if name:match("%.txt$") and not name:match("logs") then
                        table.insert(result, name:gsub("%.txt$", ""))
                    end
                end
                rednet.send(sender, {accounts = result}, "casino")
            end
        end
    end
end

-- === Main Execution ===
parallel.waitForAny(
    radarLoop,
    displayLoop,
    rednetListener
)
