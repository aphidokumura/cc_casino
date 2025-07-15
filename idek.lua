-- Admin Computer for Casino Accounts (Rednet-based)
local monitor = peripheral.wrap("top")
local modem = peripheral.wrap("bottom")
rednet.open("bottom")

-- Config
local ACCOUNTS_COMPUTER_ID = 8166
local MAX_LOG_LINES = 10

-- State
local players = {}
local selectedPlayer = nil
local logs = {}
local scroll = 0
local currentBalance = 0

-- Fetch player list from local files
local function getPlayerList()
    players = {}
    for _, name in ipairs(fs.list("/accounts")) do
        if name:match("%.txt$") and not name:match("logs") then
            table.insert(players, name:gsub("%.txt$", ""))
        end
    end
    table.sort(players)
end

-- Ask accounts computer for balance
local function fetchBalance(player)
    rednet.send(ACCOUNTS_COMPUTER_ID, { action = "get_balance", player = player }, "casino")
    local id, res = rednet.receive("casino", 2)
    if id == ACCOUNTS_COMPUTER_ID and res and res.balance then
        currentBalance = res.balance
    else
        currentBalance = 0
    end
end

-- Ask accounts computer for logs
local function fetchLogs(player)
    rednet.send(ACCOUNTS_COMPUTER_ID, { action = "get_logs", player = player }, "casino")
    local id, res = rednet.receive("casino", 2)
    if id == ACCOUNTS_COMPUTER_ID and res and res.logs then
        logs = res.logs
    else
        logs = {}
    end
end

-- UI: Draw main player list
local function drawMainMenu()
    monitor.clear()
    monitor.setCursorPos(2, 1)
    monitor.write("== Account Viewer ==")

    for i, player in ipairs(players) do
        monitor.setCursorPos(2, i + 2)
        monitor.write((selectedPlayer == player and "-> " or "   ") .. player)
    end
end

-- UI: Draw selected player's details
local function drawPlayerDetails()
    monitor.clear()
    monitor.setCursorPos(2, 1)
    monitor.write("Account: " .. selectedPlayer)
    monitor.setCursorPos(2, 2)
    monitor.write("Balance: $" .. currentBalance)
    monitor.setCursorPos(2, 3)
    monitor.write("[+100] [-100] [+1000] [-1000] [Back]")

    monitor.setCursorPos(2, 5)
    monitor.write("Recent Transactions:")

    for i = 1, MAX_LOG_LINES do
        local line = logs[i + scroll]
        if line then
            monitor.setCursorPos(2, i + 5)
            monitor.write(line:sub(1, 40))
        end
    end

    -- Scroll arrows
    monitor.setCursorPos(38, 6)
    monitor.write("^")
    monitor.setCursorPos(38, 15)
    monitor.write("v")
end

-- Send transfer command
local function adjustBalance(delta)
    rednet.send(ACCOUNTS_COMPUTER_ID, {
        action = "transfer",
        player = selectedPlayer,
        delta = delta,
        note = "Admin Console"
    }, "casino")
    local id, res = rednet.receive("casino", 2)
    if id == ACCOUNTS_COMPUTER_ID and res and res.balance then
        currentBalance = res.balance
    end
    fetchLogs(selectedPlayer)
end

-- Handle screen touches
local function handleTouch(x, y)
    if not selectedPlayer then
        if y >= 3 then
            local idx = y - 2
            local name = players[idx]
            if name then
                selectedPlayer = name
                fetchBalance(name)
                fetchLogs(name)
                scroll = 0
            end
        end
    else
        if y == 3 then
            if x >= 2 and x <= 6 then adjustBalance(100)
            elseif x >= 8 and x <= 13 then adjustBalance(-100)
            elseif x >= 15 and x <= 21 then adjustBalance(1000)
            elseif x >= 23 and x <= 30 then adjustBalance(-1000)
            elseif x >= 32 and x <= 37 then
                selectedPlayer = nil
                scroll = 0
            end
        elseif y == 6 and x >= 38 then
            scroll = math.max(0, scroll - 1)
        elseif y == 15 and x >= 38 then
            if #logs > MAX_LOG_LINES + scroll then
                scroll = scroll + 1
            end
        end
    end
end

-- === Start ===
getPlayerList()
monitor.setTextScale(0.5)

while true do
    if selectedPlayer then
        drawPlayerDetails()
    else
        drawMainMenu()
    end

    local e = { os.pullEvent() }
    if e[1] == "monitor_touch" then
        handleTouch(e[3], e[4])
    end
end
