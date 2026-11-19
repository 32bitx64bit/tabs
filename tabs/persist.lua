-- Debounced persistent storage for Tabs! state and settings.
local C = require("tabs.constants")
local Model = require("tabs.model")

local M = {}

function M.new(state)
  local self = {
    state = state,
    timer_id = nil,
    dirty = false,
  }

  function self.load()
    local ok, saved = pcall(storage.get, C.STORAGE_KEY)
    if not ok then
      log.warn("Failed reading saved tab state: " .. tostring(saved))
      return nil
    end
    if type(saved) ~= "table" then
      return nil
    end
    return saved
  end

  function self.flush()
    if self.timer_id then
      time.cancel(self.timer_id)
      self.timer_id = nil
    end
    if not self.dirty then return end
    self.dirty = false
    local payload = Model.serialize(self.state)
    local ok, err = pcall(storage.set, C.STORAGE_KEY, payload)
    if not ok then
      log.warn("Failed saving tab state: " .. tostring(err))
    end
  end

  function self.schedule()
    self.dirty = true
    if self.timer_id then
      time.cancel(self.timer_id)
      self.timer_id = nil
    end
    self.timer_id = time.after(C.PERSIST_DEBOUNCE_MS, function()
      self.timer_id = nil
      self.flush()
    end)
  end

  return self
end

return M
