-- Native C-Cord context menu entries and /tabs slash command suite.
local C = require("tabs.constants")
local Model = require("tabs.model")
local Sync = require("tabs.store_sync")

local M = {}

local function split_args(str)
  local parts = {}
  if type(str) ~= "string" then return parts end
  for token in str:gmatch("%S+") do
    parts[#parts + 1] = token:lower()
  end
  return parts
end

function M.register(state, nav, actions)
  -- Native right-click menus (Class 1 Safe API)
  ui.contextMenu.add({
    id = "tabs-open-channel",
    label = "Open in New Tab",
    target = "channel",
    action = function(ctx)
      if type(ctx) ~= "table" or not ctx.channel_id then return end
      local spec = Sync.spec_from_channel_id(ctx.channel_id, {
        guild_id = ctx.guild_id,
        parent_id = ctx.parent_id,
      })
      if not spec then
        ui.toast.show("Categories can't be opened as tabs", "info")
        return
      end
      nav.open_target_in_tab(spec, { focus = true, after_active = true })
    end,
  })

  ui.contextMenu.add({
    id = "tabs-open-guild",
    label = "Open Server in New Tab",
    target = "guild",
    action = function(ctx)
      if type(ctx) ~= "table" or not ctx.guild_id then return end
      local spec = Sync.spec_for_guild(ctx.guild_id)
      if spec then
        nav.open_target_in_tab(spec, { focus = true, after_active = true })
      end
    end,
  })

  ui.contextMenu.add({
    id = "tabs-open-nav",
    label = "Open in New Tab",
    target = "nav",
    action = function(ctx)
      if type(ctx) ~= "table" then return end
      local spec = Sync.spec_for_view(ctx.view or "friends")
      if spec then
        nav.open_target_in_tab(spec, { focus = true, after_active = true })
      end
    end,
  })

  -- Consolidated /tabs slash command (never sends text to channel; always returns nil).
  commands.register(
    "tabs",
    "Manage Tabs!: new, close, reopen, pin, dup, next, prev, back, fwd, slot, compact, dedupe",
    function(args)
      local parts = split_args(args)
      local cmd = parts[1]

      if not cmd or cmd == "help" then
        ui.toast.show(
          "/tabs: new | close | reopen | pin | dup | next | prev | left | right | back | fwd | slot <top|subheader|bottom> | compact | dedupe | settings",
          "info"
        )
        return nil
      end

      if cmd == "new" then
        nav.open_new_tab(true)
      elseif cmd == "dup" or cmd == "duplicate" then
        local active = Model.active_tab(state)
        if active then actions.duplicate_tab(active.id) end
      elseif cmd == "close" then
        local active = Model.active_tab(state)
        if active then nav.close_tab(active.id) end
      elseif cmd == "reopen" then
        nav.reopen_closed()
      elseif cmd == "pin" or cmd == "unpin" then
        local active = Model.active_tab(state)
        if active then actions.toggle_pin(active.id) end
      elseif cmd == "next" then
        nav.cycle_active(1)
      elseif cmd == "prev" or cmd == "previous" then
        nav.cycle_active(-1)
      elseif cmd == "left" then
        local active = Model.active_tab(state)
        if active then actions.move_tab(active.id, -1) end
      elseif cmd == "right" then
        local active = Model.active_tab(state)
        if active then actions.move_tab(active.id, 1) end
      elseif cmd == "back" then
        if not nav.step_history(nil, -1) then
          ui.toast.show("No earlier channel in this tab", "info")
        end
      elseif cmd == "fwd" or cmd == "forward" then
        if not nav.step_history(nil, 1) then
          ui.toast.show("No forward channel in this tab", "info")
        end
      elseif cmd == "close-others" then
        local active = Model.active_tab(state)
        if active then actions.close_others(active.id) end
      elseif cmd == "close-unpinned" then
        actions.close_all_unpinned()
      elseif cmd == "slot" then
        local target_slot = parts[2]
        if target_slot and C.VALID_SLOTS[target_slot] then
          actions.set_slot(target_slot)
        else
          actions.cycle_slot()
        end
      elseif cmd == "compact" or cmd == "density" then
        actions.toggle_density()
      elseif cmd == "dedupe" then
        actions.toggle_dedupe()
      elseif cmd == "settings" or cmd == "menu" then
        actions.toggle_settings_shelf()
      elseif cmd == "reset" then
        actions.reset_all()
      else
        ui.toast.show("Unknown /tabs subcommand: " .. cmd .. " (try /tabs help)", "warn")
      end
      return nil
    end
  )
end

return M
