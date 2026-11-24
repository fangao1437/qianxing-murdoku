-- economy.lua —— 调查币与背包的本地持久化逻辑
local M = {}

M.VERSION = 1
M.CURRENCY_ID = "murdoku.investigation_coin"
M.CURRENCY_NAME = "调查币"
M.CURRENCY_IMAGE_SOURCE = "Currency"
M.CURRENCY_CONFIG_ID = "murdoku.investigation_coin"
M.SAVE_KEY = "murdoku/economy"
M.FIRST_CLEAR_REWARD = 10
M.TICKET_ID = "clue_verify_ticket"
M.TICKET_NAME = "线索核验券"
M.TICKET_PRICE = 6

local function number(v, fallback)
  v = tonumber(v)
  if v == nil then return fallback end
  return math.max(0, math.floor(v))
end

local function normalized(raw)
  local s = type(raw) == "table" and raw or {}
  local items = type(s.items) == "table" and s.items or {}
  local rewarded = type(s.rewarded) == "table" and s.rewarded or {}
  return {
    version = M.VERSION,
    currency_id = tostring(s.currency_id or M.CURRENCY_ID),
    currency_config_id = tostring(s.currency_config_id or M.CURRENCY_CONFIG_ID),
    currency = number(s.currency, 0),
    items = { [M.TICKET_ID] = number(items[M.TICKET_ID], 0) },
    rewarded = rewarded,
  }
end

function M.load(adapter)
  if adapter == nil or adapter.load == nil then return normalized(nil) end
  local ok, raw = pcall(function() return adapter:load(M.SAVE_KEY) end)
  return normalized(ok and raw or nil)
end

function M.save(adapter, state)
  if adapter == nil or adapter.save == nil then return false end
  local s = normalized(state)
  local ok = pcall(function() adapter:save(M.SAVE_KEY, s, { no_signal = true }) end)
  return ok
end

function M.settings()
  return {
    currency_id = M.CURRENCY_ID,
    currency_config_id = M.CURRENCY_CONFIG_ID,
    currency_name = M.CURRENCY_NAME,
    image_source = M.CURRENCY_IMAGE_SOURCE,
    first_clear_reward = M.FIRST_CLEAR_REWARD,
    ticket_id = M.TICKET_ID,
  }
end

function M.wallet(adapter)
  local s = M.load(adapter)
  return s.currency, s.items[M.TICKET_ID], s
end

function M.grant_first_clear(adapter, level_id)
  if level_id == nil then return false, 0 end
  local s = M.load(adapter)
  local key = tostring(level_id)
  if s.rewarded[key] then return false, 0 end
  s.rewarded[key] = true
  s.currency = s.currency + M.FIRST_CLEAR_REWARD
  M.save(adapter, s)
  return true, M.FIRST_CLEAR_REWARD
end

function M.buy(adapter, item_id)
  if tostring(item_id or M.TICKET_ID) ~= M.TICKET_ID then return false, "商品不存在" end
  local s = M.load(adapter)
  if s.currency < M.TICKET_PRICE then return false, "调查币不足" end
  s.currency = s.currency - M.TICKET_PRICE
  s.items[M.TICKET_ID] = s.items[M.TICKET_ID] + 1
  M.save(adapter, s)
  return true, "已购买 1 张线索核验券"
end

function M.consume(adapter, item_id)
  if tostring(item_id or M.TICKET_ID) ~= M.TICKET_ID then return false, "道具不存在" end
  local s = M.load(adapter)
  if s.items[M.TICKET_ID] <= 0 then return false, "背包里没有线索核验券" end
  s.items[M.TICKET_ID] = s.items[M.TICKET_ID] - 1
  M.save(adapter, s)
  return true, "已使用 1 张线索核验券"
end

return M
