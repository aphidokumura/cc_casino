-- Admin Computer (Rednet-based, Radar Login, Remote Access to PC 8166)

local monitor = peripheral.wrap("top")
local radar = peripheral.wrap("radar_37")
local modem = peripheral.wrap("bottom")
local account_computer_id = 8166

if not modem then error("No modem on bottom") end
rednet.open("bottom")

-- === Admins and State ===
local ALLOWED_ADMINS = {
  EmTheTurtle03 = true,
  RadoslawGuzior = true,
  HughJaynis1234 = true,
}

local adminDistanceThreshold = 6
local adminLoggedIn = false
local loggedInUser = nil

local currentPage = 1
local selectedPlayer = nil
local players = {}
local playerBalance = 0
local logs = {}

-- === Radar Login ===
local function detectAdmin()
  local nearby = radar.getPlayers()
  for _, p in ipairs(nearby) do
    if p.distance <= adminDistanceThreshold and ALLOWED_ADMINS[p.name] then
      return p.name
    end
  end
  return nil
end

-- === Rednet Communication ===
local function requestPlayers()
  rednet.send(account_computer_id, {action = "get_players"}, "casino")
  local id, response = rednet.receive("casino", 2)
  if type(response) == "table" and response.players then
    players = response.players
  end
end

local function requestBalance(name)
  rednet.send(account_computer_id, {action = "get_balance", player = name}, "casino")
  local id, response = rednet.receive("casino", 2)
  if response and response.balance then
    playerBalance = response.balance
  end
end

local function sendAdjustment(delta, note)
  rednet.send(account_computer_id, {
    action = "transfer",
    player = selectedPlayer,
    delta = delta,
    note = note
  }, "casino")
end

-- === UI Helpers ===
local function drawCentered(y, textLine)
  local w, _ = monitor.getSize()
  local x = math.floor((w - #textLine) / 2)
  monitor.setCursorPos(x, y)
  monitor.write(textLine)
end

local function drawMenu()
  monitor.setBackgroundColor(colors.black)
  monitor.setTextColor(colors.white)
  monitor.clear()

  if not adminLoggedIn then
    drawCentered(10, "No Admin in Range")
    return
  end

  drawCentered(1, "Admin Panel - Logged in as " .. loggedInUser)
  drawCentered(3, "Select Player (Page " .. currentPage .. ")")

  for i = 1, 5 do
    local index = (currentPage - 1) * 5 + i
    if players[index] then
      local label = (selectedPlayer == players[index]) and "> " .. players[index] .. " <" or players[index]
      drawCentered(4 + i, label)
    end
  end

  drawCentered(11, "[ < Page ]     [ Page > ]")

  if selectedPlayer then
    drawCentered(13, "Player: " .. selectedPlayer)
    drawCentered(14, "Balance: $" .. playerBalance)
    drawCentered(16, "[ -100 ]  [ +100 ]  [ -1000 ]  [ +1000 ]")
    drawCentered(17, "[ -10000 ]  [ +10000 ]")
    drawCentered(19, "[ RESET BALANCE ]")
  end
end

-- === Button Handling ===
local function handleTouch(x, y)
  if not adminLoggedIn then return end

  if y >= 5 and y <= 9 then
    local index = (currentPage - 1) * 5 + (y - 4)
    if players[index] then
      selectedPlayer = players[index]
      requestBalance(selectedPlayer)
    end
  elseif y == 11 then
    if x < 20 then
      currentPage = math.max(1, currentPage - 1)
    else
      local maxPage = math.ceil(#players / 5)
      currentPage = math.min(maxPage, currentPage + 1)
    end
  elseif y == 16 and selectedPlayer then
    if x >= 10 and x < 20 then sendAdjustment(-100, "Admin Adjust")
    elseif x >= 20 and x < 30 then sendAdjustment(100, "Admin Adjust")
    elseif x >= 30 and x < 40 then sendAdjustment(-1000, "Admin Adjust")
    elseif x >= 40 and x <= 50 then sendAdjustment(1000, "Admin Adjust") end
    requestBalance(selectedPlayer)
  elseif y == 17 and selectedPlayer then
    if x >= 15 and x < 30 then sendAdjustment(-10000, "Admin Adjust")
    elseif x >= 30 and x <= 45 then sendAdjustment(10000, "Admin Adjust") end
    requestBalance(selectedPlayer)
  elseif y == 19 and selectedPlayer then
    sendAdjustment(-playerBalance, "Admin Reset")
    requestBalance(selectedPlayer)
  end
end

-- === Main Loops ===
local function uiLoop()
  while true do
    drawMenu()
    sleep(0.2)
  end
end

local function radarLoop()
  while true do
    local name = detectAdmin()
    if name then
      adminLoggedIn = true
      loggedInUser = name
    else
      adminLoggedIn = false
      loggedInUser = nil
    end
    sleep(0.5)
  end
end

local function touchLoop()
  while true do
    local _, _, x, y = os.pullEvent("monitor_touch")
    handleTouch(x, y)
  end
end

local function refreshPlayersLoop()
  while true do
    if adminLoggedIn then
      requestPlayers()
    end
    sleep(5)
  end
end

parallel.waitForAny(
  uiLoop,
  radarLoop,
  touchLoop,
  refreshPlayersLoop
)
