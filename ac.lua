-- Full rewrite of Wavecrest Casino Account Computer

local depositChest = peripheral.wrap("minecraft:chest_389")
local withdrawalChest = peripheral.wrap("minecraft:chest_388")
local payoutChest = peripheral.wrap("minecraft:chest_390")
local monitor = peripheral.find("monitor")
local radar = peripheral.find("radar")
local logger = require("logger")

local API_URL = "https://a8410f940b59.ngrok-free.app/balance/"

local VALID_BOOKS = {
  ["01cf97"] = 500,
  ["e61758"] = 1000,
  ["1fafe1"] = 5000,
  ["6d281b"] = 10000,
  ["dd703d"] = 15000
}
local COIN_ORDER = {15000, 10000, 5000, 1000, 500}

-- Firebase functions
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

-- Draw text centered
local function drawCentered(text, y, color)
  local w, _ = monitor.getSize()
  local x = math.max(1, math.floor((w - #text) / 2))
  monitor.setCursorPos(x, y)
  if color then monitor.setTextColor(color) end
  monitor.write(text)
end

-- Return nearest player within 8 blocks
local function getNearestPlayerWithin8()
  if not radar then return nil end
  local nearest = nil
  local minDist = 8
  for _, player in ipairs(radar.getPlayers() or {}) do
    if player.x and player.y and player.z then
      local dist = math.sqrt(player.x^2 + player.y^2 + player.z^2)
      if dist <= minDist then
        nearest = player.name
        minDist = dist
      end
    end
  end
  return nearest
end

-- Give books from payout chest
local function giveBooks(amount)
  local prefixMap = {}
  for hash, val in pairs(VALID_BOOKS) do
    prefixMap[val] = hash
  end
  for _, denom in ipairs(COIN_ORDER) do
    while amount >= denom do
      for slot, item in pairs(payoutChest.list()) do
        if item.name == "minecraft:written_book" and item.nbtHash then
          local prefix = string.sub(item.nbtHash, 1, 6)
          if prefix == prefixMap[denom] then
            if payoutChest.pushItems(peripheral.getName(withdrawalChest), slot, 1) > 0 then
              amount = amount - denom
            end
            break
          end
        end
      end
      break
    end
  end
  return amount
end

-- UI State
local state = "main"
local selectedPlayer = nil
local balance = 0
local selection = { denom = 0, quantity = 0, amount = 0 }

while true do
  local prevPlayer = selectedPlayer
  selectedPlayer = getNearestPlayerWithin8()

  if selectedPlayer ~= prevPlayer then
    state = "main"
    selection = { denom = 0, quantity = 0, amount = 0 }
  end

  if selectedPlayer then
    balance = getBalance(selectedPlayer) or 0
    monitor.setBackgroundColor(colors.black)
    monitor.clear()
    monitor.setTextColor(colors.white)

    if state == "main" then
      drawCentered("Welcome to Wavecrest Casino!", 2)
      drawCentered("[Deposit]", 4, colors.green)
      drawCentered("[Withdraw]", 6, colors.cyan)
      local e, _, x, y = os.pullEventTimeout("monitor_touch", 0.5)
      if e == "monitor_touch" then
        if y == 4 then
          local total = 0
          for _, item in pairs(depositChest.list()) do
            if item.name == "minecraft:written_book" and item.nbtHash then
              local prefix = string.sub(item.nbtHash, 1, 6)
              local value = VALID_BOOKS[prefix]
              if value then
                total = total + (item.count * value)
              end
            end
          end
          if total > 0 then
            selection.amount = total
            state = "deposit_confirm"
          end
        elseif y == 6 then
          state = "denomination"
        end
      end

    elseif state == "deposit_confirm" then
      drawCentered("Deposit books detected!", 5)
      drawCentered("[ Confirm ]", 7, colors.green)
      drawCentered("[ Cancel ]", 9, colors.red)
      local e, _, _, y = os.pullEventTimeout("monitor_touch", 0.5)
      if e == "monitor_touch" then
        if y == 7 then
          for slot in pairs(depositChest.list()) do
            depositChest.pushItems(peripheral.getName(payoutChest), slot)
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
        end
      end

    elseif state == "denomination" then
      drawCentered("Select denomination", 3)
      local y = 5
      for _, v in ipairs(COIN_ORDER) do
        drawCentered("[ " .. v .. " ]", y)
        y = y + 2
      end
      local e, _, _, yClick = os.pullEventTimeout("monitor_touch", 0.5)
      if e == "monitor_touch" then
        local map = { [5] = 15000, [7] = 10000, [9] = 5000, [11] = 1000, [13] = 500 }
        local d = map[yClick]
        if d then
          selection.denom = d
          state = "quantity"
        end
      end

    elseif state == "quantity" then
      drawCentered("Selected: " .. selection.denom .. " coins", 3)
      drawCentered("Select quantity (1-10)", 5)
      for i = 1, 10 do
        monitor.setCursorPos(i * 3, 7)
        monitor.write("[" .. i .. "]")
      end
      local e, _, xClick, yClick = os.pullEventTimeout("monitor_touch", 0.5)
      if e == "monitor_touch" and yClick == 7 then
        for i = 1, 10 do
          if xClick >= i * 3 and xClick <= i * 3 + 2 then
            selection.quantity = i
            selection.amount = selection.denom * i
            state = "confirm"
            break
          end
        end
      end

    elseif state == "confirm" then
      drawCentered("Withdraw " .. selection.amount .. " coins?", 5)
      drawCentered("[ Confirm ]", 7, colors.green)
      drawCentered("[ Cancel ]", 9, colors.red)
      local e, _, _, y = os.pullEventTimeout("monitor_touch", 0.5)
      if e == "monitor_touch" then
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

  else
    monitor.setBackgroundColor(colors.black)
    monitor.clear()
    monitor.setTextColor(colors.yellow)
    drawCentered("Insert books or approach", 6, colors.yellow)
    sleep(0.5)
  end
  sleep(0.1)
end
