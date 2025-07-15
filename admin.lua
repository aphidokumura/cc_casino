-- Admin Computer for Tekkit 2 Casino

-- === Peripheral Setup ===
local monitor = peripheral.find("monitor")
local radar = peripheral.wrap("radar_15")
local modem = peripheral.find("modem") or error("No modem found!")
local ACC_COMPUTER_ID = 8166  -- Account computer rednet ID

rednet.open(peripheral.getName(modem))

if not monitor then error("No monitor attached!") end

-- === Constants & State ===
local ADMINS = {}  -- Filled dynamically by radar detection
local loggedInAdmin = nil
local players = {}
local selectedPlayerIndex = 1
local currentPage = 1
local playersPerPage = 10
local playerBalances = {}
local playerLogs = {}
local editingBalance = false
local confirmReset = false
local message = ""

local screenWidth, screenHeight = monitor.getSize()

-- === Helper Functions ===

local function centerText(text, y)
    local x = math.floor((screenWidth - #text) / 2) + 1
    monitor.setCursorPos(x, y)
    monitor.write(text)
end

local function clearArea(x1, y1, x2, y2)
    for y = y1, y2 do
        monitor.setCursorPos(x1, y)
        monitor.write(string.rep(" ", x2 - x1 + 1))
    end
end

local function sendRednetMessage(action, data)
    local msg = { action = action }
    if data then
        for k,v in pairs(data) do msg[k] = v end
    end
    rednet.send(ACC_COMPUTER_ID, msg, "casino")
    local sender, response = rednet.receive(5)
    if sender == ACC_COMPUTER_ID then
        return response
    else
        return nil
    end
end

local function fetchPlayers()
    local resp = sendRednetMessage("get_players")
    if resp and resp.players then
        players = resp.players
    else
        players = {}
    end
end

local function fetchPlayerBalance(player)
    local resp = sendRednetMessage("get_balance", {player = player})
    if resp and resp.balance then
        playerBalances[player] = resp.balance
        return resp.balance
    end
    return 0
end

local function fetchPlayerLogs(player)
    local resp = sendRednetMessage("get_logs", {player = player})
    if resp and resp.logs then
        playerLogs[player] = resp.logs
        return resp.logs
    end
    return {}
end

local function adjustPlayerBalance(player, delta)
    local resp = sendRednetMessage("transfer", {player = player, delta = delta, note = "Admin adjustment"})
    if resp and resp.balance then
        playerBalances[player] = resp.balance
        return resp.balance
    end
    return nil
end

local function resetPlayerBalance(player)
    local resp = sendRednetMessage("transfer", {player = player, delta = -playerBalances[player], note = "Admin reset"})
    if resp and resp.balance then
        playerBalances[player] = resp.balance
        return resp.balance
    end
    return nil
end

local function isAdminNearby()
    local detectedAdmins = {}
    local detected = radar.getPlayers()
    for _, p in ipairs(detected) do
        -- You can define admin whitelist here or detect by radar (for now assume all radar detected are admins)
        table.insert(detectedAdmins, p.name)
    end
    return detectedAdmins
end

local function paginatePlayers()
    local startIdx = (currentPage - 1) * playersPerPage + 1
    local endIdx = math.min(#players, startIdx + playersPerPage - 1)
    local pagePlayers = {}
    for i = startIdx, endIdx do
        table.insert(pagePlayers, {name = players[i], idx = i})
    end
    return pagePlayers
end

-- === UI Drawing ===

local function drawHeader()
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
    clearArea(1,1,screenWidth,3)
    centerText("== Casino Admin Panel ==", 1)
    if loggedInAdmin then
        centerText("Admin: " .. loggedInAdmin, 2)
    else
        centerText("No admin logged in.", 2)
    end
    centerText(message or "", 3)
end

local function drawPlayerList()
    local pagePlayers = paginatePlayers()
    clearArea(1,5,screenWidth,15)
    monitor.setTextColor(colors.yellow)
    centerText("Players (Page " .. currentPage .. "/" .. math.max(1, math.ceil(#players / playersPerPage)) .. "):", 5)
    monitor.setTextColor(colors.white)
    local y = 6
    for _, p in ipairs(pagePlayers) do
        local prefix = (p.idx == selectedPlayerIndex) and "> " or "  "
        local balance = playerBalances[p.name] or fetchPlayerBalance(p.name)
        monitor.setCursorPos(3, y)
        monitor.write(prefix .. p.name .. " - $" .. balance)
        y = y + 1
    end
end

local function drawSelectedPlayerInfo()
    local player = players[selectedPlayerIndex]
    if not player then return end
    local balance = playerBalances[player] or 0
    local logs = playerLogs[player] or {}

    local infoStartY = 16
    clearArea(1, infoStartY, screenWidth, screenHeight - 6)

    monitor.setTextColor(colors.cyan)
    centerText("Player: " .. player, infoStartY)
    monitor.setTextColor(colors.lime)
    centerText("Balance: $" .. balance, infoStartY + 1)

    monitor.setTextColor(colors.white)
    centerText("Adjust Balance:", infoStartY + 3)

    -- Buttons
    local bx = (screenWidth // 2) - 12
    local by = infoStartY + 5

    -- Buttons labels & positions for +/- 100, 1000, 10000
    local buttons = {
        {label = "-100", delta = -100, x=bx, w=6},
        {label = "-1000", delta = -1000, x=bx+7, w=7},
        {label = "-10000", delta = -10000, x=bx+15, w=7},
        {label = "+100", delta = 100, x=bx+23, w=5},
        {label = "+1000", delta = 1000, x=bx+29, w=6},
        {label = "+10000", delta = 10000, x=bx+36, w=6},
    }

    for _, btn in ipairs(buttons) do
        monitor.setBackgroundColor(colors.gray)
        monitor.setTextColor(colors.black)
        monitor.setCursorPos(btn.x, by)
        monitor.write(btn.label)
    end

    -- Reset button
    local resetX = bx + 43
    local resetY = by
    monitor.setBackgroundColor(colors.red)
    monitor.setTextColor(colors.white)
    monitor.setCursorPos(resetX, resetY)
    monitor.write("Reset")

    -- Log display area (last 5 entries)
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
    monitor.setCursorPos(1, by + 2)
    monitor.write("Recent Logs:")
    local logY = by + 3
    local maxLogs = 5
    for i = math.max(1, #logs - maxLogs + 1), #logs do
        if logs[i] then
            clearArea(1, logY, screenWidth, logY)
            monitor.setCursorPos(1, logY)
            local logLine = logs[i]
            if #logLine > screenWidth then
                logLine = logLine:sub(1, screenWidth)
            end
            monitor.write(logLine)
            logY = logY + 1
        end
    end
end

local function drawNavigation()
    local navY = 14
    clearArea(1, navY, screenWidth, navY)
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.yellow)

    -- Page Prev
    monitor.setCursorPos(3, navY)
    monitor.write("[Prev]")

    -- Page Next
    monitor.setCursorPos(screenWidth - 7, navY)
    monitor.write("[Next]")

    -- Logout
    local logoutLabel = loggedInAdmin and "[Logout]" or "[Login]"
    local logoutX = math.floor(screenWidth/2 - #logoutLabel/2)
    monitor.setCursorPos(logoutX, navY)
    monitor.write(logoutLabel)
end

local function drawUI()
    monitor.setBackgroundColor(colors.black)
    monitor.clear()
    drawHeader()
    drawPlayerList()
    drawSelectedPlayerInfo()
    drawNavigation()
    monitor.setBackgroundColor(colors.black)
    monitor.setTextColor(colors.white)
end

-- === Input Handling ===

local function handleLoginInput()
    -- Simple manual login via monitor keyboard
    monitor.clear()
    centerText("Enter Admin Name:", 10)
    monitor.setCursorPos(math.floor(screenWidth/2 - 8), 12)
    monitor.setBackgroundColor(colors.gray)
    monitor.setTextColor(colors.black)
    monitor.write(" " .. string.rep(" ", 14) .. " ")
    monitor.setCursorPos(math.floor(screenWidth/2 - 7), 12)

    local input = ""
    while true do
        local event, side, x, y, key = os.pullEvent()
        if event == "char" then
            if #input < 14 then
                input = input .. key
                monitor.write(key)
            end
        elseif event == "key" then
            if key == keys.backspace and #input > 0 then
                input = input:sub(1, -2)
                monitor.setCursorPos(math.floor(screenWidth/2 - 7) + #input, 12)
                monitor.write(" ")
                monitor.setCursorPos(math.floor(screenWidth/2 - 7) + #input, 12)
            elseif key == keys.enter then
                if #input > 0 then
                    loggedInAdmin = input
                    message = "Logged in as: " .. loggedInAdmin
                    break
                end
            end
        elseif event == "monitor_touch" then
            -- ignore touch while typing
        end
    end
end

local function handleTouch(x, y)
    -- Page navigation area
    local navY = 14
    if y == navY then
        if x >= 3 and x <= 7 then  -- Prev page
            if currentPage > 1 then
                currentPage = currentPage - 1
                message = "Page " .. currentPage
            end
            return
        elseif x >= screenWidth - 7 and x <= screenWidth - 3 then  -- Next page
            local maxPage = math.max(1, math.ceil(#players / playersPerPage))
            if currentPage < maxPage then
                currentPage = currentPage + 1
                message = "Page " .. currentPage
            end
            return
        else
            -- Logout/Login button
            local logoutLabel = loggedInAdmin and "[Logout]" or "[Login]"
            local logoutX = math.floor(screenWidth/2 - #logoutLabel/2)
            if y == navY and x >= logoutX and x <= logoutX + #logoutLabel - 1 then
                if loggedInAdmin then
                    loggedInAdmin = nil
                    message = "Logged out."
                else
                    handleLoginInput()
                end
                return
            end
        end
    end

    if not loggedInAdmin then
        message = "Please login as admin."
        return
    end

    -- Player list selection (y 6..15)
    if y >= 6 and y <= 15 then
        local idxClicked = (currentPage -1)*playersPerPage + (y - 5)
        if players[idxClicked] then
            selectedPlayerIndex = idxClicked
            -- fetch latest balance & logs
            fetchPlayerBalance(players[selectedPlayerIndex])
            fetchPlayerLogs(players[selectedPlayerIndex])
            message = "Selected player: " .. players[selectedPlayerIndex]
        end
        return
    end

    local player = players[selectedPlayerIndex]
    if not player then return end

    -- Adjust balance buttons (y = infoStartY+5 = 21 approx)
    local btnY = 21
    local bx = (screenWidth // 2) - 12
    local btns = {
        {label = "-100", delta = -100, x=bx, w=6},
        {label = "-1000", delta = -1000, x=bx+7, w=7},
        {label = "-10000", delta = -10000, x=bx+15, w=7},
        {label = "+100", delta = 100, x=bx+23, w=5},
        {label = "+1000", delta = 1000, x=bx+29, w=6},
        {label = "+10000", delta = 10000, x=bx+36, w=6},
    }

    if y == btnY then
        for _, b in ipairs(btns) do
            if x >= b.x and x < b.x + b.w then
                local newBal = adjustPlayerBalance(player, b.delta)
                if newBal then
                    message = "Balance updated: $" .. newBal
                else
                    message = "Failed to update balance."
                end
                return
            end
        end
        -- Reset button
        local resetX = bx + 43
        local resetW = 5
        if x >= resetX and x < resetX + resetW then
            if confirmReset then
                local newBal = resetPlayerBalance(player)
                if newBal == 0 then
                    message = "Balance reset to 0."
                else
                    message = "Failed to reset."
                end
                confirmReset = false
            else
                confirmReset = true
                message = "Tap Reset again to confirm!"
            end
            return
        end
    end
end

-- === Main loop ===

local function main()
    fetchPlayers()

    -- Wait for admin radar detection or manual login
    while true do
        ADMINS = isAdminNearby()
        if #ADMINS > 0 then
            loggedInAdmin = ADMINS[1]
            message = "Radar detected admin: " .. loggedInAdmin
            break
        else
            drawUI()
            centerText("No admin nearby. Touch 'Login' to login manually.", 17)
            monitor.setCursorPos(1,1)
            os.pullEvent("monitor_touch")
            handleLoginInput()
            if loggedInAdmin then break end
        end
        sleep(1)
    end

    drawUI()

    while true do
        drawUI()
        local event, side, x, y = os.pullEvent("monitor_touch")
        handleTouch(x, y)
    end
end

-- Run
main()
