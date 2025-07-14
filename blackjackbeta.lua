-- Wavecrest Blackjack

-- === Peripheral Setup ===
local monitor = peripheral.wrap("monitor_777")
local bidMonitor = peripheral.wrap("monitor_779")
local actionMonitor = peripheral.wrap("monitor_778")
local radar = peripheral.wrap("radar_36") or error("Radar not found")
local modem = peripheral.wrap("top") or error("Modem not found on top")
rednet.open("top")

-- === Constants ===
local ACCOUNT_ID = 8166
local PROTOCOL = "casino"
local BLACKJACK_MULTIPLIER = 1.5
local BET_INCREMENTS = {500, 1000, 10000}
local MAX_BET = 25000
local MIN_BET = 500
local WIN_DELAY = 2
local MAX_DISTANCE = 8

-- === Game State ===
local currentPlayer = nil
local currentBet = MIN_BET
local inGamePhase = false

-- === Rednet Balance + Logging ===
local function getBalance(player)
  rednet.send(ACCOUNT_ID, { action = "get_balance", player = player }, PROTOCOL)
  local _, res = rednet.receive(PROTOCOL, 3)
  return res and res.balance or 0
end

local function logRemote(player, note, delta)
  rednet.send(ACCOUNT_ID, {
    action = "log",
    player = player,
    note = note,
    delta = delta
  }, PROTOCOL)
end

local function updateBalance(player, delta, reason)
  rednet.send(ACCOUNT_ID, {
    action = "transfer",
    player = player,
    delta = delta,
    note = reason
  }, PROTOCOL)
  logRemote(player, reason, delta)
  local _, res = rednet.receive(PROTOCOL, 3)
  return res and res.balance or getBalance(player)
end

-- === UI Helpers ===
local function displayCenteredOn(mon, lines, textColor, bgColor)
  local w, h = mon.getSize()
  mon.setBackgroundColor(bgColor or colors.black)
  mon.clear()
  mon.setTextColor(textColor or colors.white)
  for i, line in ipairs(lines) do
    local x = math.floor((w - #line) / 2) + 1
    local y = math.floor(h / 2 - #lines / 2) + i
    mon.setCursorPos(x, y)
    mon.write(line)
  end
end

local function waitForTouch()
  while true do
    local event, side, x, y = os.pullEvent("monitor_touch")
    if side == peripheral.getName(bidMonitor) then
      local width = bidMonitor.getSize()
      if inGamePhase then
        return (x <= math.floor(width / 2)) and "stand" or "hit"
      else
        if y == 3 then return "add500"
        elseif y == 4 then return "add1000"
        elseif y == 5 then return "add10000"
        elseif y == 6 then return "sub500"
        elseif y == 7 then return "sub1000"
        elseif y == 8 then return "sub10000"
        elseif y == 10 then return "max" end
      end
    elseif side == peripheral.getName(actionMonitor) then
      local width = actionMonitor.getSize()
      return (x <= math.floor(width / 2)) and "exit" or "play"
    elseif side == peripheral.getName(monitor) then
      return "ack"
    end
  end
end

-- === Radar & Player Detection ===
local function getLoggedInPlayer()
  local players = radar.getPlayers()
  table.sort(players, function(a, b) return a.distance < b.distance end)
  for _, p in ipairs(players) do
    if p.distance <= MAX_DISTANCE then
      return p.name
    end
  end
  return nil
end

-- === Game Logic ===
local cards = { "2", "3", "4", "5", "6", "7", "8", "9", "10", "J", "Q", "K", "A" }

local function drawCard() return cards[math.random(#cards)] end

local function handValue(hand)
  local total, aces = 0, 0
  for _, c in ipairs(hand) do
    if c == "A" then
      total = total + 11
      aces = aces + 1
    elseif tonumber(c) then
      total = total + tonumber(c)
    else
      total = total + 10
    end
  end
  while total > 21 and aces > 0 do
    total = total - 10
    aces = aces - 1
  end
  return total
end

local function drawCardBox(mon, x, y, value)
  mon.setCursorPos(x, y)
  mon.write("+----+")
  mon.setCursorPos(x, y + 1)
  mon.write("|" .. value .. string.rep(" ", 4 - #value) .. "|")
  mon.setCursorPos(x, y + 2)
  mon.write("|    |")
  mon.setCursorPos(x, y + 3)
  mon.write("|    |")
  mon.setCursorPos(x, y + 4)
  mon.write("+----+")
end

local function drawFancyHand(mon, hand, title, startY)
  mon.setTextColor(colors.white)
  mon.setCursorPos(1, startY - 1)
  mon.write(title)
  for i, card in ipairs(hand) do
    local x = 2 + (i - 1) * 8
    drawCardBox(mon, x, startY, card)
  end
end

local function drawGame(playerHand, dealerHand, hideDealer)
  monitor.setBackgroundColor(colors.blue)
  monitor.clear()
  drawFancyHand(monitor, playerHand, "Your Hand:", 2)
  local shownDealer = hideDealer and {dealerHand[1], "?"} or dealerHand
  drawFancyHand(monitor, shownDealer, "Dealer:", 9)
end

local function didPlayerWin(playerVal, dealerVal)
  if playerVal > 21 then return false
  elseif dealerVal > 21 then return true
  elseif playerVal == dealerVal then return math.random() < 0.45
  else return playerVal > dealerVal end
end

local function drawBettingButtons(mode)
  local w, h = bidMonitor.getSize()
  bidMonitor.setBackgroundColor(colors.lime)
  bidMonitor.clear()

  if mode == "game" then
    local standText = "[ STAND ]"
    local hitText = "[ HIT ]"
    local standX = math.floor((w / 2 - #standText) / 2) + 1
    local hitX = math.floor(w / 2 + (w / 2 - #hitText) / 2) + 1

    bidMonitor.setCursorPos(standX, 3)
    bidMonitor.setBackgroundColor(colors.orange)
    bidMonitor.setTextColor(colors.black)
    bidMonitor.write(standText)

    bidMonitor.setCursorPos(hitX, 3)
    bidMonitor.write(hitText)
  else
    bidMonitor.setTextColor(colors.black)
    bidMonitor.setBackgroundColor(colors.orange)
    bidMonitor.setCursorPos(1, 3) bidMonitor.write("[ +500    ]")
    bidMonitor.setCursorPos(1, 4) bidMonitor.write("[ +1000   ]")
    bidMonitor.setCursorPos(1, 5) bidMonitor.write("[ +10000  ]")
    bidMonitor.setCursorPos(1, 6) bidMonitor.write("[ -500    ]")
    bidMonitor.setCursorPos(1, 7) bidMonitor.write("[ -1000   ]")
    bidMonitor.setCursorPos(1, 8) bidMonitor.write("[ -10000  ]")
    bidMonitor.setCursorPos(1, 10) bidMonitor.write("[ MAX BET ]")
  end
end

local function drawActionButtons()
  local w, h = actionMonitor.getSize()
  actionMonitor.setBackgroundColor(colors.orange)
  actionMonitor.clear()
  local midY = math.floor(h / 2)
  local exitText = "[ EXIT ]"
  local playText = "[ PLAY ]"
  local exitX = math.floor((w / 2 - #exitText) / 2) + 1
  local playX = math.floor(w / 2 + (w / 2 - #playText) / 2) + 1
  actionMonitor.setCursorPos(exitX, midY)
  actionMonitor.setBackgroundColor(colors.cyan)
  actionMonitor.setTextColor(colors.black)
  actionMonitor.write(exitText)
  actionMonitor.setCursorPos(playX, midY)
  actionMonitor.write(playText)
end

local function playBlackjack()
  inGamePhase = true
  local playerHand = { drawCard(), drawCard() }
  local dealerHand = { drawCard(), drawCard() }

  while true do
    drawGame(playerHand, dealerHand, true)
    drawBettingButtons("game")
    drawActionButtons()
    if handValue(playerHand) >= 21 then break end
    local action = waitForTouch()
    if action == "hit" then
      table.insert(playerHand, drawCard())
    else
      break
    end
  end

  while handValue(dealerHand) < 17 do
    table.insert(dealerHand, drawCard())
    drawGame(playerHand, dealerHand, false)
    sleep(0.75)
  end

  local playerVal = handValue(playerHand)
  local dealerVal = handValue(dealerHand)
  drawGame(playerHand, dealerHand, false)

  local balance = getBalance(currentPlayer)
  local resultText = ""
  if didPlayerWin(playerVal, dealerVal) then
    local winnings = math.ceil(currentBet * BLACKJACK_MULTIPLIER)
    updateBalance(currentPlayer, winnings, "blackjack win")
    resultText = "You Win! +" .. winnings .. " coins"
  elseif playerVal > 21 or dealerVal > playerVal then
    updateBalance(currentPlayer, -currentBet, "blackjack loss")
    resultText = "You Lose! -" .. currentBet .. " coins"
  else
    resultText = "Push! No change"
  end

  displayCenteredOn(monitor, { "Result:", resultText, "", "Tap screen to continue..." }, colors.white, colors.blue)
  while true do if waitForTouch() == "ack" then break end end
  inGamePhase = false
end

-- === Main Loop ===
while true do
  currentPlayer = nil
  currentBet = MIN_BET
  displayCenteredOn(monitor, { "Welcome to Blackjack", "Stand near the machine" }, colors.yellow, colors.blue)
  displayCenteredOn(bidMonitor, { "Waiting for player..." }, colors.black, colors.lime)
  displayCenteredOn(actionMonitor, { "Waiting for player..." }, colors.black, colors.orange)

  repeat
    currentPlayer = getLoggedInPlayer()
    sleep(0.5)
  until currentPlayer

  local balance = getBalance(currentPlayer)

  while true do
    local nearbyPlayers = radar.getPlayers()
    local stillHere = false
    for _, p in ipairs(nearbyPlayers) do
      if p.name == currentPlayer and p.distance <= MAX_DISTANCE then
        stillHere = true
        break
      end
    end
    if not stillHere then
      currentPlayer = nil
      break
    end

    displayCenteredOn(monitor, {
      "Player: " .. currentPlayer,
      "Balance: " .. balance .. " coins",
      "Bet: " .. currentBet .. " coins",
    }, colors.yellow, colors.blue)

    drawBettingButtons()
    drawActionButtons()

    local input = waitForTouch()
    if input == "add500" then currentBet = math.min(MAX_BET, currentBet + 500)
    elseif input == "add1000" then currentBet = math.min(MAX_BET, currentBet + 1000)
    elseif input == "add10000" then currentBet = math.min(MAX_BET, currentBet + 10000)
    elseif input == "sub500" then currentBet = math.max(MIN_BET, currentBet - 500)
    elseif input == "sub1000" then currentBet = math.max(MIN_BET, currentBet - 1000)
    elseif input == "sub10000" then currentBet = math.max(MIN_BET, currentBet - 10000)
    elseif input == "max" then currentBet = MAX_BET
    elseif input == "hit" or input == "play" then
      if balance < currentBet then
        displayCenteredOn(monitor, { "Insufficient balance!" }, colors.red, colors.black)
        sleep(2)
      else
        playBlackjack()
        balance = getBalance(currentPlayer)
      end
    elseif input == "stand" or input == "exit" then
      break
    end
  end
end
