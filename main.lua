-- Tabs! — Native, theme-compliant browser-style tabs for C-Cord.
local C = require("tabs.constants")
local Model = require("tabs.model")
local Persist = require("tabs.persist")
local Sync = require("tabs.store_sync")
local Nav = require("tabs.nav")
local Renderer = require("tabs.renderer")
local ContextBar = require("tabs.context_bar")
local Commands = require("tabs.commands")

local saved = nil
do
  local ok, raw = pcall(storage.get, C.STORAGE_KEY)
  if ok and type(raw) == "table" then
    saved = raw
  end
end

local state = Model.new_state(saved)
local persist = Persist.new(state)

local renderer
local ctx_bar
local nav

local function notify_changed(should_persist)
  if renderer then renderer.schedule() end
  if ctx_bar then ctx_bar.sync() end
  if should_persist ~= false then
    persist.schedule()
  end
end

nav = Nav.new(state, notify_changed)

-- Shared UI actions invoked from bar events, contextual shelf buttons, and /tabs commands.
local actions = {}

function actions.toggle_pin(tab_id)
  local tab = Model.toggle_pin(state, tab_id)
  if not tab then return end
  notify_changed(true)
end

function actions.move_tab(tab_id, delta)
  if Model.move_tab(state, tab_id, delta) then
    notify_changed(true)
  end
end

function actions.duplicate_tab(tab_id)
  local dup = Model.duplicate_tab(state, tab_id, { activate = true })
  if dup then
    state.ctx_mode = nil
    state.ctx_tab_id = nil
    notify_changed(true)
  end
end

function actions.close_others(keep_id)
  local n, active_closed = Model.close_others(state, keep_id)
  state.ctx_mode = nil
  state.ctx_tab_id = nil
  if n > 0 then
    if active_closed then
      local cur = Model.active_tab(state)
      if cur then nav.dispatch_navigation(cur) end
    end
    notify_changed(true)
  else
    ui.toast.show("No other unpinned tabs to close", "info")
    notify_changed(false)
  end
end

function actions.close_to_right(anchor_id)
  local n, active_closed = Model.close_to_right(state, anchor_id)
  state.ctx_mode = nil
  state.ctx_tab_id = nil
  if n > 0 then
    if active_closed then
      local cur = Model.active_tab(state)
      if cur then nav.dispatch_navigation(cur) end
    end
    notify_changed(true)
  else
    ui.toast.show("No unpinned tabs to the right", "info")
    notify_changed(false)
  end
end

function actions.close_all_unpinned()
  local n, active_closed = Model.close_all_unpinned(state)
  state.ctx_mode = nil
  state.ctx_tab_id = nil
  if n > 0 then
    if active_closed then
      local cur = Model.active_tab(state)
      if cur then nav.dispatch_navigation(cur) end
    end
    notify_changed(true)
  else
    ui.toast.show("No unpinned tabs to close", "info")
    notify_changed(false)
  end
end

function actions.set_slot(slot)
  if not C.VALID_SLOTS[slot] then return end
  if state.settings.slot == slot then return end
  state.settings.slot = slot
  renderer.render_now()
  ctx_bar.sync()
  persist.schedule()
  ui.toast.show("Tab bar moved to: " .. slot, "info")
end

function actions.cycle_slot()
  local cur = state.settings.slot
  local next_slot = C.SLOT_ORDER[1]
  for i, s in ipairs(C.SLOT_ORDER) do
    if s == cur then
      next_slot = C.SLOT_ORDER[(i % #C.SLOT_ORDER) + 1]
      break
    end
  end
  actions.set_slot(next_slot)
end

function actions.toggle_density()
  state.settings.density = (state.settings.density == "compact") and "normal" or "compact"
  renderer.render_now()
  ctx_bar.sync()
  persist.schedule()
end

function actions.toggle_dedupe()
  state.settings.dedupe_tabs = not state.settings.dedupe_tabs
  notify_changed(true)
end

function actions.toggle_protect_pinned()
  state.settings.protect_pinned = not state.settings.protect_pinned
  notify_changed(true)
end

function actions.toggle_aux_focus()
  state.settings.aux_open_focus = not state.settings.aux_open_focus
  notify_changed(true)
end

function actions.toggle_settings_shelf()
  if state.ctx_mode == "settings" then
    state.ctx_mode = nil
    state.ctx_tab_id = nil
  else
    state.ctx_mode = "settings"
    state.ctx_tab_id = nil
  end
  notify_changed(false)
end

function actions.toggle_tab_shelf(tab_id)
  if state.ctx_mode == "tab" and state.ctx_tab_id == tab_id then
    state.ctx_mode = nil
    state.ctx_tab_id = nil
  else
    state.ctx_mode = "tab"
    state.ctx_tab_id = tab_id
  end
  notify_changed(false)
end

function actions.dismiss_shelf()
  if state.ctx_mode ~= nil then
    state.ctx_mode = nil
    state.ctx_tab_id = nil
    notify_changed(false)
  end
end

function actions.reset_all()
  state.tabs = {}
  state.closed = {}
  state.active_id = nil
  state.scroll_offset = 0
  state.ctx_mode = nil
  state.ctx_tab_id = nil
  state.settings = Model.clone_settings(nil)
  nav.bootstrap_from_store(false)
  notify_changed(true)
  ui.toast.show("Tabs! reset to defaults", "info")
end

-- Primary tab bar mouse event handler.
local function on_bar_event(ev)
  if type(ev) ~= "table" then return end
  local etype = ev.type
  local id = ev.id or ""
  local mods = ev.mods or {}

  if etype == "wheel" then
    local delta = (tonumber(ev.wheel) or 0)
    if delta == 0 then return end
    local step = (delta > 0) and -1 or 1
    if mods.shift then
      nav.cycle_active(step)
    elseif Model.scroll_by(state, step) then
      notify_changed(false)
    end
    return
  end

  if id == "act-new" then
    if etype == "right_click" then
      nav.reopen_closed()
    elseif etype == "click" then
      nav.open_new_tab(not mods.shift)
    end
    return
  end

  if id == "act-menu" then
    if etype == "click" or etype == "right_click" then
      actions.toggle_settings_shelf()
    end
    return
  end

  if id == "scroll-l" and etype == "click" then
    if Model.scroll_by(state, -1) then notify_changed(false) end
    return
  end

  if id == "scroll-r" and etype == "click" then
    if Model.scroll_by(state, 1) then notify_changed(false) end
    return
  end

  if id == "tabs-root" then
    if etype == "double_click" then
      nav.open_new_tab(true)
    elseif etype == "right_click" then
      actions.toggle_settings_shelf()
    elseif etype == "click" then
      actions.dismiss_shelf()
    end
    return
  end

  -- Close button hit ("x:<tab_id>")
  local close_id = id:match("^x:(.+)$")
  if close_id then
    if etype == "click" or etype == "middle_click" then
      nav.close_tab(close_id)
    end
    return
  end

  -- Tab hit ("t:<tab_id>")
  local tab_id = id:match("^t:(.+)$")
  if tab_id then
    if etype == "click" then
      if mods.shift then
        actions.toggle_pin(tab_id)
      else
        nav.activate_tab(tab_id)
      end
    elseif etype == "middle_click" then
      nav.close_tab(tab_id)
    elseif etype == "double_click" then
      actions.toggle_pin(tab_id)
    elseif etype == "right_click" then
      actions.toggle_tab_shelf(tab_id)
    end
  end
end

-- Contextual shelf mouse event handler.
local function on_ctx_event(ev)
  if type(ev) ~= "table" or ev.type ~= "click" then return end
  local id = ev.id or ""

  if id == "ctx-dismiss" then
    actions.dismiss_shelf()
    return
  end

  -- Tab context actions
  local target_id = state.ctx_tab_id
  if id == "ctx-pin" and target_id then
    actions.toggle_pin(target_id)
    actions.dismiss_shelf()
  elseif id == "ctx-left" and target_id then
    actions.move_tab(target_id, -1)
  elseif id == "ctx-right" and target_id then
    actions.move_tab(target_id, 1)
  elseif id == "ctx-back" and target_id then
    nav.step_history(target_id, -1)
  elseif id == "ctx-fwd" and target_id then
    nav.step_history(target_id, 1)
  elseif id == "ctx-dup" and target_id then
    actions.duplicate_tab(target_id)
  elseif id == "ctx-close-others" and target_id then
    actions.close_others(target_id)
  elseif id == "ctx-close-right" and target_id then
    actions.close_to_right(target_id)
  elseif id == "ctx-close" and target_id then
    nav.close_tab(target_id)
    actions.dismiss_shelf()
  -- Settings shelf actions
  elseif id == "set-reopen" then
    nav.reopen_closed()
  elseif id == "set-slot" then
    actions.cycle_slot()
  elseif id == "set-density" then
    actions.toggle_density()
  elseif id == "set-dedupe" then
    actions.toggle_dedupe()
  elseif id == "set-protect-pin" then
    actions.toggle_protect_pinned()
  elseif id == "set-aux-focus" then
    actions.toggle_aux_focus()
  elseif id == "set-close-unpinned" then
    actions.close_all_unpinned()
  end
end

renderer = Renderer.new(state, on_bar_event)
ctx_bar = ContextBar.new(state, on_ctx_event)

-- Register native context menu items and /tabs command.
Commands.register(state, nav, actions)

-- Wire Class 1 navigation & lifecycle events.
events.on("channel.select", function(ev)
  nav.on_channel_select(ev)
end)

events.on("view.select", function(ev)
  nav.on_view_select(ev)
end)

events.on("guild.select", function(ev)
  nav.on_guild_select(ev)
end)

events.on("navigation.aux_open", function(ev)
  nav.on_aux_open(ev)
end)

events.on("app.ready", function()
  nav.bootstrap_from_store(true)
  renderer.render_now()
end)

events.on("app.quit", function()
  persist.flush()
end)

-- Wire Class 2 channel & message events for live tab metadata and unread/mention badges.
events.on("guilds.loaded", function()
  nav.bootstrap_from_store(false)
end)

events.on("channel.upsert", function(ev)
  if type(ev) == "table" and ev.channel_id then
    if Sync.refresh_channel(state, ev.channel_id) then
      notify_changed(false)
    end
  end
end)

events.on("channel.delete", function(ev)
  nav.on_channel_delete(ev)
end)

events.on("notify.update", function(ev)
  if type(ev) == "table" and ev.channel_id then
    if Sync.refresh_channel(state, ev.channel_id) then
      notify_changed(false)
    end
  else
    if Sync.refresh_all(state) then
      notify_changed(false)
    end
  end
end)

events.on("message.create", function(ev)
  if type(ev) == "table" and ev.channel_id then
    -- Only inspect channel_id to update unread/mention counters on open background tabs.
    if Sync.refresh_channel(state, ev.channel_id) then
      notify_changed(false)
    end
  end
end)

-- Lightweight periodic reconciliation to clear badges after external read-state acks.
time.every(C.BADGE_SYNC_INTERVAL_MS, function()
  if Sync.refresh_all(state) then
    renderer.schedule()
  end
end)

-- Initial bootstrap & mount (handles both cold startup and hot reload).
nav.bootstrap_from_store(true)
renderer.render_now()
ctx_bar.sync()

log.info("Loaded " .. plugin.name .. " v" .. plugin.version .. " (" .. tostring(#state.tabs) .. " tab(s))")
