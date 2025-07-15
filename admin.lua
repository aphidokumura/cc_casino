-- Admin Computer with Radar-Restricted Access + Rednet + Local File Player Management

-- === Peripheral Setup ===
local radar = peripheral.wrap("radar_37")
local monitor = peripheral.wrap("top")
local modem = peripheral.wrap("bottom")

if not modem then error("? No modem on bottom") end
rednet.open("bottom")

-- Constants
local adminDistanceThreshold = 3

-- Allowed admin usernames
local ALLOWED_ADMINS = {
    EmTheTurtle03 = true,
    RadoslawGuzior = true,
    HughJaynis1234 = true,
}

-- UI and state
local playerList = {}
local currentPage = 1
local playersPerPage = 8
local selectedPlayer = nil
local message = ""
local adminLoggedIn = false
local adminName = nil

-- Helpers for file management
local function getPlayerFile(player)
    return "/accounts/" .. player .. ".txt"
end

local function getLogFile(player)
    return "/accounts/logs/" .. player .. ".txt"
end

local function fileExists(path)
    return fs.exists(path)
end

local function readBalance(player)
    local path = getPlayerFile(player)
    if fs.exists(path) then
        local f = fs.open(path, "r")
        local val = tonumber(f.readAll())
        f.close()
        return val or 0
    end
    return 0
end

local function writeBalance(player, amount)
    local f = fs.open(getPlayerFile(player), "w")
    f.write(tostring(amount))
    f.close()
end

local function readLogs(player)
    local logs = {}
    local path = getLogFile(player)
    if fs.exists(path) then
        local f = fs.open(path, "r")
        while true do
            local line = f.readLine()
            if not line then break end
            table.insert(logs, line)
        end
        f.close()
    end
    return logs
end

local function clearLogs(player)
    local path = getLogFile(player)
    if fs.exists(path) then
        fs.delete(path)
    end
end

-- Radar admin check
local function isAdminPresent()
    local players = radar.getPlayers()
    for _, p in ipairs(players) do
        if p.distance <= adminDistanceThreshold and ALLOWED_ADMINS[p.name] then
            return p.name
        end
    end
    return nil
end

-- Load player list from local accounts folder
local function loadPlayerList()
    playerList = {}
    for _, fileName in ipairs(fs.list("/accounts")) do
        if fileName:match("%.txt$") and not fileName:match("logs") then
            table.insert(playerList, fileName:gsub("%.txt$", ""))
        end
    end
    table.sort(playerList)
end

-- Pagination helper
local function getPlayersForPage(page)
    local startIndex = (page - 1) * playersPerPage + 1
    local endIndex = math.min(startIndex + playersPerPage - 1, #playerList)
    local subset = {}
    for i = startIndex, endIndex do
        table.insert(subset, playerList[i])
    end
    return subset
end

-- Draw centered text helper
local function drawCentered(y, text, fg, bg)
    fg = fg or colors.white
    bg = bg or colors.black
    local w, h = monitor.getSize()
    local x = math.floor((w - #text) / 2) + 1
    monitor.setBackgroundColor(bg)
    monitor.setTextColor(fg)
    monitor.setCursorPos(x, y)
    monitor.clearLine()
    monitor.write(text)
end

-- Draw buttons helper
local function drawButton(x, y, width, label, fg, bg)
    fg = fg or colors.white
    bg = bg or colors.gray
    monitor.setBackgroundColor(bg)
    monitor.setTextColor(fg)
    monitor.setCursorPos(x, y)
    local padding = width - #label
    local leftPad = math.floor(padding / 2)
    local rightPad = padding - leftPad
    monitor.write(string.rep(" ", leftPad) .. label .. string.rep(" ", rightPad))
end

-- Draw admin UI
local function drawAdminUI()
    monitor.clear()
    monitor.setTextScale(1)

    if not adminLoggedIn then
        drawCentered(5, "ADMIN ACCESS RESTRICTED", colors.red)
        drawCentered(7, "Stand near radar to login", colors.yellow)
        if adminName then
            drawCentered(9, "Welcome, " .. adminName, colors.lime)
        end
        return
    end

    drawCentered(2, "ADMIN PANEL - User: " .. adminName, colors.lime)

    -- Player list pagination
    drawCentered(4, "Players List - Page " .. currentPage .. "/" .. math.max(1, math.ceil(#playerList / playersPerPage)), colors.cyan)

    local yStart = 6
    local pagePlayers = getPlayersForPage(currentPage)
    for i, pname in ipairs(pagePlayers) do
        local y = yStart + i - 1
        local fg = (pname == selectedPlayer) and colors.yellow or colors.white
        monitor.setCursorPos(10, y)
        monitor.setBackgroundColor(colors.black)
        monitor.setTextColor(fg)
        monitor.clearLine()
        monitor.write(pname)
    end

    -- Buttons
    local w, h = monitor.getSize()
    -- Pagination buttons
    drawButton(5, h - 6, 10, "< Prev", colors.white, colors.blue)
    drawButton(w - 14, h - 6, 10, "Next >", colors.white, colors.blue)

    -- Adjust balance buttons
    if selectedPlayer then
        local bal = readBalance(selectedPlayer)
        drawCentered(h - 10, "Selected Player: " .. selectedPlayer .. " | Balance: $" .. bal, colors.lime)
        drawButton(5, h - 8, 14, " -100 ", colors.white, colors.red)
        drawButton(20, h - 8, 14, " -1000 ", colors.white, colors.red)
        drawButton(35, h - 8, 14, " -10000 ", colors.white, colors.red)

        drawButton(50, h - 8, 14, " +100 ", colors.white, colors.green)
        drawButton(65, h - 8, 14, " +1000 ", colors.white, colors.green)
        drawButton(80, h - 8, 14, " +10000 ", colors.white, colors.green)

        -- Reset balance button
        drawButton(5, h - 4, 28, " Reset Balance ", colors.white, colors.orange)
        -- View logs button
        drawButton(40, h - 4, 28, " View Logs ", colors.white, colors.purple)
    end

    -- Message
    if message and message ~= "" then
        drawCentered(h - 2, message, colors.yellow)
    end
end

-- Adjust balance function
local function adjustBalance(player, amount)
    local bal = readBalance(player)
    bal = math.max(0, bal + amount)
    writeBalance(player, bal)
    message = "Balance updated: $" .. bal
end

-- Reset balance function with confirmation
local resetConfirm = false
local function resetBalance(player)
    if not resetConfirm then
        message = "Press Reset again to confirm"
        resetConfirm = true
        return
    end
    writeBalance(player, 0)
    clearLogs(player)
    message = "Balance and logs reset for " .. player
    resetConfirm = false
end

-- View logs UI state
local viewingLogs = false
local logs = {}
local logIndex = 1
local logsPerPage = 15

local function drawLogsUI()
    monitor.clear()
    monitor.setTextScale(1)
    drawCentered(1, "Logs for " .. selectedPlayer, colors.cyan)

    local h = select(2, monitor.getSize())
    local yStart = 3

    for i = 0, logsPerPage - 1 do
        local idx = logIndex + i
        local logLine = logs[idx]
        if not logLine then break end
        monitor.setCursorPos(2, yStart + i)
        monitor.setBackgroundColor(colors.black)
        monitor.setTextColor(colors.white)
        monitor.clearLine()
        monitor.write(logLine)
    end

    -- Scroll buttons
    local w = select(1, monitor.getSize())
    drawButton(5, h - 3, 10, "< Prev", colors.white, colors.blue)
    drawButton(w - 14, h - 3, 10, "Next >", colors.white, colors.blue)
    drawButton(math.floor(w/2 - 7), h - 1, 14, " Back to Admin ", colors.white, colors.red)

    if message and message ~= "" then
        drawCentered(h - 2, message, colors.yellow)
    end
end

-- Touch handling for admin UI
local function adminTouch(x, y)
    local w, h = monitor.getSize()
    if not adminLoggedIn then
        return -- no touch actions unless logged in
    end

    if viewingLogs then
        if y == h - 3 then
            if x >= 5 and x <= 14 then -- Prev logs page
                logIndex = math.max(1, logIndex - logsPerPage)
            elseif x >= w - 14 and x <= w - 5 then -- Next logs page
                if logIndex + logsPerPage <= #logs then
                    logIndex = logIndex + logsPerPage
                end
            end
        elseif y == h - 1 and x >= math.floor(w/2 - 7) and x <= math.floor(w/2 + 7) then
            viewingLogs = false
            message = ""
        end
        return
    end

    -- Player list pagination buttons
    if y == h - 6 then
        if x >= 5 and x <= 14 then -- Prev page
            currentPage = math.max(1, currentPage - 1)
            message = ""
            return
        elseif x >= w - 14 and x <= w - 5 then -- Next page
            if currentPage * playersPerPage < #playerList then
                currentPage = currentPage + 1
                message = ""
            end
            return
        end
    end

    local pagePlayers = getPlayersForPage(currentPage)
    local yStart = 6
    for i, pname in ipairs(pagePlayers) do
        local py = yStart + i - 1
        if y == py and x >= 10 and x <= 10 + #pname then
            selectedPlayer = pname
            message = ""
            resetConfirm = false
            return
        end
    end

    if not selectedPlayer then return end

    -- Balance adjust buttons
    if y == h - 8 then
        if x >= 5 and x <= 18 then
            adjustBalance(selectedPlayer, -100)
        elseif x >= 20 and x <= 33 then
            adjustBalance(selectedPlayer, -1000)
        elseif x >= 35 and x <= 48 then
            adjustBalance(selectedPlayer, -10000)
        elseif x >= 50 and x <= 63 then
            adjustBalance(selectedPlayer, 100)
        elseif x >= 65 and x <= 78 then
            adjustBalance(selectedPlayer, 1000)
        elseif x >= 80 and x <= 93 then
            adjustBalance(selectedPlayer, 10000)
        end
    end

    -- Reset balance button
    if y == h - 4 and x >= 5 and x <= 32 then
        resetBalance(selectedPlayer)
    end

    -- View logs button
    if y == h - 4 and x >= 40 and x <= 68 then
        logs = readLogs(selectedPlayer)
        logIndex = 1
        viewingLogs = true
        message = ""
    end
end

-- Main loop
local function mainLoop()
    while true do
        -- Check for admin presence
        local detectedAdmin = isAdminPresent()
        if detectedAdmin and not adminLoggedIn then
            adminLoggedIn = true
            adminName = detectedAdmin
            message = "Admin logged in: " .. adminName
            loadPlayerList()
            selectedPlayer = nil
            viewingLogs = false
        elseif not detectedAdmin and adminLoggedIn then
            adminLoggedIn = false
            adminName = nil
            message = "Admin logged out."
            selectedPlayer = nil
            viewingLogs = false
        end

        if adminLoggedIn then
            if viewingLogs then
                drawLogsUI()
            else
                drawAdminUI()
            end
        else
            monitor.clear()
            monitor.setTextScale(1)
            drawCentered(5, "ADMIN ACCESS RESTRICTED", colors.red)
            drawCentered(7, "Stand near radar to login", colors.yellow)
            if adminName then
                drawCentered(9, "Welcome, " .. adminName, colors.lime)
            end
        end

        -- Handle touch input non-blocking
        local event, side, x, y = os.pullEventRaw("monitor_touch")
        if event == "monitor_touch" then
            adminTouch(x, y)
        end

        sleep(0.1)
    end
end

-- Run main loop
mainLoop()
