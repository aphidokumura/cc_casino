-- Double Up (Radar polling every 5s, initial detection ≤16 blocks)
local logger = dofile("logger.lua")

local API_URL = "https://a8410f940b59.ngrok-free.app/balance/"

-- Peripheral Setup
local mainSide = "monitor_736"
local bidSide  = "monitor_737"
local actSide  = "monitor_735"

local main = peripheral.wrap(mainSide)
local bid  = peripheral.wrap(bidSide)
local act  = peripheral.wrap(actSide)

local speaker = peripheral.find("speaker") or peripheral.find("jukebox")
local radar = peripheral.find("playerDetector") or peripheral.find("radar")

-- Constants
local RISK_CHANCE = 45
local betOptions = {100, 200, 300, 400, 500}
local MAX_INITIAL_DISTANCE = 16 -- initial detection range to start game
local MAX_DISTANCE = 10         -- max distance to keep locked during game
local SCAN_INTERVAL = 5         -- seconds between radar scans

-- Centered write helper
local function center(mon, y, txt, color)
  local w, h = mon.getSize()
  if y > h then return end
  mon.setCursorPos(math.max(1, math.floor(w / 2 - #txt / 2)), y)
  mon.setTextColor(color or colors.white)
  mon.write(txt:sub(1, w))
end

-- Firebase Balance Helpers
local function getBal(name)
  local r = http.get(API_URL .. name)
  if not r then return 0 end
  local d = textutils.unserializeJSON(r.readAll()) r.close()
  return d and d.coins or 0
end

local function setBal(name, new)
  local body = textutils.serializeJSON({coins = new})
  http.post(API_URL .. name, body, {["Content-Type"]="application/json"})
end

local function update(name, change, new, action)
  setBal(name, new)
  logger.logTransaction(name, action, change, new)
end

-- Radar: get closest player within initial distance limit
local function getClosestPlayer()
  if not radar then return nil end
  local players = radar.getPlayers()
  if not players or #players == 0 then return nil end

  local closest = nil
  for i = 1, #players do
    local p = players[i]
    if p.distance <= MAX_INITIAL_DISTANCE then
      if not closest or p.distance < closest.distance then
        closest = p
      end
    end
  end
  return closest and closest.name or nil, closest and closest.distance or nil
end

-- Monitor UIs
local function showBettingUI(player, balance, bet)
  bid.setBackgroundColor(colors.black)
  bid.setTextColor(colors.white)
  bid.clear()
  center(bid, 1, player)
  center(bid, 2, "Balance: " .. balance)
  center(bid, 3, "Bet: " .. bet)
  center(bid, 4, "< Lower  Raise >")
end

local function showActionUI()
  act.setBackgroundColor(colors.black)
  act.setTextColor(colors.white)
  act.clear()
  center(act, 2, "[Enter] Confirm")
  center(act, 3, "[X] Cancel")
end

-- Betting Flow with preset bets
local function getBet(player, balance)
  local index = 1
  local bet = betOptions[index]

  while true do
    showBettingUI(player, balance, bet)
    showActionUI()

    local _, side, x, y = os.pullEvent("monitor_touch")

    if side == bidSide and y == 4 then
      if x <= 5 then
        index = math.max(1, index - 1)
      elseif x >= 14 then
        index = math.min(#betOptions, index + 1)
      end
      bet = betOptions[index]
    end

    if side == actSide then
      if y == 2 then -- Confirm
        if bet > balance then
          main.clear()
          center(main, 2, "Insufficient funds", colors.red)
          sleep(2)
        else
          return bet
        end
      elseif y == 3 then -- Cancel
        main.clear()
        center(main, 2, "Bet Cancelled", colors.red)
        sleep(2)
        return nil
      end
    end
  end
end

-- Double or Cash Prompt
local function doubleOrCash(player, winnings)
  act.setBackgroundColor(colors.black)
  act.setTextColor(colors.white)
  act.clear()
  center(act, 2, "Winnings: " .. winnings)
  center(act, 3, "< Double | Cash >")

  while true do
    local _, side, x, y = os.pullEvent("monitor_touch")
    if side == actSide and y == 3 then
      if x < 9 then return "double" else return "cash" end
    end
  end
end

-- Coin Flip Logic
local function flip()
  return math.random(100) <= RISK_CHANCE
end

-- Play sound note helper
local function playNote(index, success)
  if not speaker then return end
  local noteName = success and "note.pling" or "note.bass"
  local pitch = success and (0.5 + index * 0.15) or 0.4
  speaker.playSound("minecraft:block." .. noteName, 1.0, pitch)
end

-- Draw squares with pulsing current stage
local function drawProgress(stage, loss, pulseOn)
  main.clear()
  center(main, 4, "Double Up!", colors.white)
  for i = 0, 5 do
    local x = 12 + i * 5
    main.setCursorPos(x, 10)

    if i < stage then
      main.setBackgroundColor(colors.green)
    elseif i == stage then
      if loss then
        main.setBackgroundColor(colors.red)
      else
        main.setBackgroundColor(pulseOn and colors.white or colors.gray)
      end
    else
      main.setBackgroundColor(colors.gray)
    end

    main.write("   ")
  end
  main.setBackgroundColor(colors.black)
end

-- MAIN GAME LOOP
while true do
  main.setBackgroundColor(colors.black)
  main.setTextColor(colors.white)
  main.clear()
  center(main, 2, "Double Up")
  center(main, 4, "Waiting for player within 16 blocks...")

  local lockedPlayer = nil
  local lockedDistance = nil

  -- Scan radar every 5 seconds for a player within 16 blocks
  repeat
    lockedPlayer, lockedDistance = getClosestPlayer()
    if not lockedPlayer then sleep(SCAN_INTERVAL) end
  until lockedPlayer

  main.clear()
  center(main, 2, "Player: " .. lockedPlayer)
  sleep(1)

  local bal = getBal(lockedPlayer)
  local bet = getBet(lockedPlayer, bal)

  if not bet then
    -- Cancelled, restart loop
  else
    local winnings = bet
    local newBal = bal - bet
    update(lockedPlayer, -bet, newBal, "double-up bet")

    local currentStage = 0
    local gameOver = false

    while currentStage < 6 and not gameOver do
      -- Check if player is still near, else unlock but continue game
      local _, distNow = getClosestPlayer()
      if not distNow or distNow > MAX_DISTANCE then
        center(main, 15, "Player left. Continuing...", colors.yellow)
        sleep(2)
      end

      currentStage = currentStage + 1

      -- Animate with pulsing sound
      drawProgress(currentStage - 1, false, false)
      sleep(0.5)

      for j = 1, 8 do
        drawProgress(currentStage, false, j % 2 == 1)
        playNote(currentStage, true)
        sleep(0.5)
      end

      if flip() then
        winnings = winnings * 2
        drawProgress(currentStage, false, false)
        center(main, 13, "WIN! Winnings: " .. winnings, colors.green)
        if speaker then speaker.playSound("minecraft:block.note_block.chime") end
        sleep(1)

        if currentStage == 6 then
          newBal = newBal + winnings
          update(lockedPlayer, winnings, newBal, "double-up jackpot")
          center(main, 15, "JACKPOT! " .. winnings .. " coins!", colors.lime)
          sleep(3)
          break
        end

        local choice = doubleOrCash(lockedPlayer, winnings)
        if choice == "cash" then
          newBal = newBal + winnings
          update(lockedPlayer, winnings, newBal, "double-up cash out")
          main.clear()
          center(main, 2, "You won " .. winnings .. " coins!", colors.green)
          sleep(3)
          gameOver = true
        end
      else
        drawProgress(currentStage, true, false)
        center(main, 13, "You Lose!", colors.red)
        playNote(currentStage, false)
        update(lockedPlayer, 0, newBal, "double-up loss")
        if speaker then speaker.playSound("minecraft:block.note_block.bass") end
        sleep(3)
        break
      end
    end
  end
  -- After game ends, loop restarts and radar scans again every 5 seconds
end
