-- Admin Computer Script with Radar-Based Login and Rednet Control

-- === Peripheral Setup ===
local monitor = peripheral.wrap("top")
local radar = peripheral.wrap("radar_37")
local modem = peripheral.wrap("bottom")

if not monitor or not radar or not modem then
    error("Missing peripheral: monitor, radar, or modem")
end

rednet.open("bottom")

-- === Config ===
local ACCOUNT_ID = 8166
local ADMIN_USERS = {
    EmTheTurtle03 = true,
    RadoslawGuzior = true,
    HughJaynis1234 = true
}

-- === UI State ===
local currentPage = 1
local accounts = {}
local selectedPlayer = nil
local selectedBalance = 0
local lastUpdate = os.clock()
local screenW, screenH = monitor.getSize()

-- === Radar Login ===
local isLoggedIn = false
local function checkAdminProximity()
    local players = radar.getPlayers()
    for _, p in ipairs(players) do
        if p.distance <= 6 and ADMIN_USERS[p.name] then
            return true
        end
    end
    return false
end

-- === Rednet Communication ===
local function requestAccounts()
    rednet.send(ACCOUNT_ID, {action = "get_players"}, "casino")
end

local function requestBalance(player)
    rednet.send(ACCOUNT_ID, {action = "get_balance", player = player}, "casino")
end

local function transferBalance(player, delta, note)
    rednet.send(ACCOUNT_ID, {
        action = "transfer",
        player = player,
        delta = delta,
        note = note
    }, "casino")
end

-- === UI Drawing ===
local function drawUI()
    monitor.clear()
    monitor.setCursorPos(1, 1)
    if not isLoggedIn then
        monitor.write("Admin Login Required - Step in front")
        return
    end

    monitor.setCursorPos(1, 1)
    monitor.write("Admin Panel - Page " .. currentPage)

    for i = 1, 10 do
        local idx = (currentPage - 1) * 10 + i
        local name = accounts[idx]
        if name then
            monitor.setCursorPos(2, i + 1)
            monitor.write((name == selectedPlayer and "> " or "  ") .. name)
        end
    end

    monitor.setCursorPos(1, 13)
    monitor.write("[<] Prev Page   [>] Next Page")

    if selectedPlayer then
        monitor.setCursorPos(1, 15)
        monitor.write("Selected: " .. selectedPlayer .. " ($" .. selectedBalance .. ")")
        monitor.setCursorPos(1, 17)
        monitor.write("[-100] [+100] [-1000] [+1000] [-10000] [+10000]")
        monitor.setCursorPos(1, 19)
        monitor.write("[Reset Balance]")
    end
end

-- === Monitor Touch Handler ===
local function handleTouch(_, _, x, y)
    if not isLoggedIn then return end

    if y >= 2 and y <= 11 then
        local idx = (currentPage - 1) * 10 + (y - 1)
        local player = accounts[idx]
        if player then
            selectedPlayer = player
            requestBalance(player)
        end
    elseif y == 13 then
        if x <= 5 then currentPage = math.max(1, currentPage - 1)
        elseif x >= 18 then currentPage = currentPage + 1 end
    elseif y == 17 and selectedPlayer then
        if x <= 6 then transferBalance(selectedPlayer, -100, "Admin Adjust")
        elseif x <= 13 then transferBalance(selectedPlayer, 100, "Admin Adjust")
        elseif x <= 21 then transferBalance(selectedPlayer, -1000, "Admin Adjust")
        elseif x <= 30 then transferBalance(selectedPlayer, 1000, "Admin Adjust")
        elseif x <= 40 then transferBalance(selectedPlayer, -10000, "Admin Adjust")
        elseif x <= 51 then transferBalance(selectedPlayer, 10000, "Admin Adjust") end
    elseif y == 19 and selectedPlayer then
        transferBalance(selectedPlayer, -selectedBalance, "Admin Reset")
    end
end

-- === Rednet Receive Loop ===
local function listenRednet()
    while true do
        local sender, msg = rednet.receive("casino")
        if type(msg) == "table" then
            if msg.action == "players_list" then
                accounts = msg.players or {}
            elseif msg.player == selectedPlayer and msg.balance then
                selectedBalance = msg.balance
            end
        end
    end
end

-- === Login Check ===
local function loginLoop()
    while true do
        local login = checkAdminProximity()
        if login ~= isLoggedIn then
            isLoggedIn = login
            if isLoggedIn then requestAccounts() end
        end
        sleep(0.5)
    end
end

-- === UI Loop ===
local function uiLoop()
    while true do
        drawUI()
        sleep(0.2)
    end
end

-- === Touch Listener ===
local function touchLoop()
    while true do
        local e = {os.pullEvent("monitor_touch")}
        handleTouch(table.unpack(e))
    end
end

parallel.waitForAny(
    listenRednet,
    uiLoop,
    loginLoop,
    touchLoop
)
