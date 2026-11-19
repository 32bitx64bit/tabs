-- Bidirectional navigation coordinator and loop-prevention reconciliation engine.
local C = require("tabs.constants")
local Model = require("tabs.model")
local Sync = require("tabs.store_sync")

local M = {}

function M.new(state, on_change)
  local self = {
    state = state,
    on_change = on_change or function() end,
    recent_targets = {}, -- target_key -> expires_at_ms (suppresses stale in-flight echoes during rapid switching)
  }

  local function emit_change(persist_flag)
    self.on_change(persist_flag ~= false)
  end

  local function set_pending_nav(tab)
    local exp = time.now_ms() + C.NAV_RECONCILE_TTL_MS
    self.recent_targets[tab.target_key] = exp
    self.state.pending_nav = {
      tab_id = tab.id,
      target_key = tab.target_key,
      kind = tab.kind,
      guild_id = tab.guild_id,
      channel_id = tab.channel_id,
      expires_at = exp,
    }
  end

  local function is_recent_target(key)
    local exp = self.recent_targets[key]
    if not exp then return false end
    if time.now_ms() > exp then
      self.recent_targets[key] = nil
      return false
    end
    return true
  end

  local function pending_active()
    local p = self.state.pending_nav
    if not p then return nil end
    if time.now_ms() > p.expires_at then
      self.state.pending_nav = nil
      return nil
    end
    return p
  end

  -- Drive C-Cord's viewport to match the given tab.
  function self.dispatch_navigation(tab)
    if not tab then return end
    set_pending_nav(tab)
    if tab.kind == "friends" then
      navigation.select_view("friends")
    elseif tab.kind == "requests" then
      navigation.select_view("requests")
    elseif tab.kind == "guild" and not tab.channel_id then
      if tab.guild_id then
        navigation.select_guild(tab.guild_id)
      end
    elseif tab.channel_id then
      local opts = {}
      if tab.guild_id then opts.guild_id = tab.guild_id end
      if tab.parent_id then opts.parent_id = tab.parent_id end
      if tab.kind == "thread" and tab.label then opts.name = tab.label end
      navigation.select_channel(tab.channel_id, opts)
    elseif tab.guild_id then
      navigation.select_guild(tab.guild_id)
    end
  end

  function self.activate_tab(tab_id, opts)
    opts = opts or {}
    local tab = Model.find_tab(self.state, tab_id)
    if not tab then return false end

    self.state.active_id = tab.id
    self.state._bg_anchor_id = nil
    self.state._bg_offset = 0
    tab.unread_count = 0
    tab.mention_count = 0
    Model.ensure_visible(self.state, tab.id)

    if not opts.keep_ctx then
      self.state.ctx_mode = nil
      self.state.ctx_tab_id = nil
    end

    if opts.navigate ~= false then
      self.dispatch_navigation(tab)
    end
    emit_change(true)
    return true
  end

  -- Open a target spec in a new tab (or focus existing tab when dedupe is enabled).
  function self.open_target_in_tab(spec, opts)
    opts = opts or {}
    if not spec then return nil end
    local key = Model.target_key(spec)
    local should_focus = opts.focus
    if should_focus == nil then should_focus = true end

    if self.state.settings.dedupe_tabs and not opts.allow_duplicate then
      local existing = Model.find_by_target(self.state, key)
      if existing then
        if should_focus then
          self.activate_tab(existing.id)
        else
          Model.ensure_visible(self.state, existing.id)
          emit_change(false)
        end
        return existing
      end
    end

    local tab = Model.open_tab(self.state, spec, {
      activate = should_focus,
      after_active = opts.after_active ~= false,
      pinned = opts.pinned == true,
    })

    if should_focus then
      tab.unread_count = 0
      tab.mention_count = 0
      self.state.ctx_mode = nil
      self.state.ctx_tab_id = nil
      if opts.navigate ~= false then
        self.dispatch_navigation(tab)
      end
    end
    emit_change(true)
    return tab
  end

  -- Click "+" or /tabs new: duplicate current view into a new active tab and optionally open Quick Switcher.
  function self.open_new_tab(open_switcher)
    local cur = Model.active_tab(self.state)
    local base_spec = cur or Sync.spec_from_selected() or Sync.spec_for_view("friends")
    local tab = Model.open_tab(self.state, base_spec, {
      activate = true,
      after_active = true,
      pinned = false,
    })
    tab.unread_count = 0
    tab.mention_count = 0
    self.state.ctx_mode = nil
    self.state.ctx_tab_id = nil
    emit_change(true)

    local want_qs = open_switcher
    if want_qs == nil then
      want_qs = self.state.settings.new_tab_opens_switcher
    end
    if want_qs then
      navigation.open_quick_switcher()
    end
    return tab
  end

  function self.close_tab(tab_id, opts)
    local ok, reason, next_active, was_active = Model.close_tab(self.state, tab_id, opts)
    if not ok then
      if reason == "pinned" then
        ui.toast.show("Unpin tab before closing (double-click to unpin)", "info")
      elseif reason == "last_tab" then
        ui.toast.show("At least one tab must stay open", "info")
      end
      return false
    end
    if was_active and next_active then
      next_active.unread_count = 0
      next_active.mention_count = 0
      self.dispatch_navigation(next_active)
    end
    emit_change(true)
    return true
  end

  function self.reopen_closed()
    local tab = Model.reopen_closed(self.state)
    if not tab then
      ui.toast.show("No recently closed tabs", "info")
      return nil
    end
    Sync.refresh_tab(tab, true)
    self.state.ctx_mode = nil
    self.state.ctx_tab_id = nil
    self.dispatch_navigation(tab)
    emit_change(true)
    return tab
  end

  function self.step_history(tab_id, delta)
    local tab = Model.find_tab(self.state, tab_id or self.state.active_id)
    if not tab then return false end
    local updated = Model.step_history(tab, delta)
    if not updated then return false end
    Sync.refresh_tab(updated, tab.id == self.state.active_id)
    if tab.id == self.state.active_id then
      self.dispatch_navigation(updated)
    end
    emit_change(true)
    return true
  end

  function self.cycle_active(delta)
    local target = Model.cycle_active(self.state, delta)
    if not target then return false end
    self.activate_tab(target.id)
    return true
  end

  -- Apply a user-initiated navigation destination (channel.select or view.select).
  local function apply_user_navigation(spec)
    if not spec then return end
    local key = Model.target_key(spec)
    local p = pending_active()

    if p then
      if key == p.target_key or (p.kind == "guild" and p.guild_id and spec.guild_id == p.guild_id) then
        -- Expected confirmation of our own tab switch.
        self.state.pending_nav = nil
        local ptab = Model.find_tab(self.state, p.tab_id)
        if ptab then
          Model.navigate_tab_in_place(ptab, spec, p.kind == "guild")
          ptab.unread_count = 0
          ptab.mention_count = 0
          emit_change(true)
        end
        return
      end
      -- Intermediate DM channel event emitted while switching to Friends/Requests view: ignore.
      if (p.kind == "friends" or p.kind == "requests") and spec.guild_id == C.DM_GUILD_ALIAS and spec.channel_id then
        return
      end
      -- Stale echo from an earlier rapid tab click while a newer tab switch is still in flight: ignore.
      if is_recent_target(key) then
        return
      end
      -- Different destination: user explicitly navigated elsewhere quickly.
      self.state.pending_nav = nil
    end

    -- Dismiss transient context shelf when user navigates in C-Cord.
    self.state.ctx_mode = nil
    self.state.ctx_tab_id = nil

    if #self.state.tabs == 0 then
      local t = Model.open_tab(self.state, spec, { activate = true })
      t.unread_count = 0
      t.mention_count = 0
      emit_change(true)
      return
    end

    local active = Model.active_tab(self.state)
    if active and active.is_placeholder then
      active.is_placeholder = nil
      active.history = {}
      active.history_idx = 0
      Model.navigate_tab_in_place(active, spec, true)
      active.unread_count = 0
      active.mention_count = 0
      emit_change(true)
      return
    end
    if active and active.target_key == key then
      Model.navigate_tab_in_place(active, spec, false)
      active.unread_count = 0
      active.mention_count = 0
      emit_change(false)
      return
    end

    -- Dedupe mode: jump to already-open tab if present.
    if self.state.settings.dedupe_tabs then
      local existing = Model.find_by_target(self.state, key)
      if existing then
        self.state.active_id = existing.id
        Model.navigate_tab_in_place(existing, spec, false)
        existing.unread_count = 0
        existing.mention_count = 0
        Model.ensure_visible(self.state, existing.id)
        emit_change(true)
        return
      end
    end

    -- Pinned tab protection: never silently overwrite a pinned tab when user clicks another channel.
    if active and active.pinned and self.state.settings.protect_pinned then
      local existing = Model.find_by_target(self.state, key)
      if existing then
        self.state.active_id = existing.id
        existing.unread_count = 0
        existing.mention_count = 0
        Model.ensure_visible(self.state, existing.id)
        emit_change(true)
        return
      end
      local nt = Model.open_tab(self.state, spec, { activate = true, after_active = true, pinned = false })
      nt.unread_count = 0
      nt.mention_count = 0
      emit_change(true)
      return
    end

    if active then
      Model.navigate_tab_in_place(active, spec, true)
      active.unread_count = 0
      active.mention_count = 0
      emit_change(true)
    end
  end

  function self.on_channel_select(ev)
    if type(ev) ~= "table" or not ev.channel_id then return end
    local spec = Sync.spec_from_channel_obj(ev) or Sync.spec_from_channel_id(ev.channel_id, ev)
    if spec then
      spec.unread_count = 0
      spec.mention_count = 0
      apply_user_navigation(spec)
    end
  end

  function self.on_view_select(ev)
    if type(ev) ~= "table" then return end
    if ev.view == "friends" or ev.view == "requests" then
      apply_user_navigation(Sync.spec_for_view(ev.view))
    end
    -- "discovery" temporarily hides plugin panels natively in C-Cord; keep active tab untouched.
    -- "channel" / "thread" / "guild" are accompanied by channel.select / guild.select.
  end

  function self.on_guild_select(ev)
    if type(ev) ~= "table" then return end
    local p = pending_active()
    if p then
      -- Suppress intermediate guild.select while a programmatic tab switch is settling.
      return
    end
    -- Usually followed immediately by channel.select; no mutation needed unless DM has no channel.
  end

  function self.on_aux_open(ev)
    local spec = Sync.spec_from_aux_open(ev)
    if not spec then return end
    local focus = self.state.settings.aux_open_focus == true
    local tab = self.open_target_in_tab(spec, { focus = focus, after_active = true })
    if tab and not focus then
      ui.toast.show("Opened tab: " .. tab.label, "info")
    end
  end

  function self.on_channel_delete(ev)
    if type(ev) ~= "table" or not ev.channel_id then return end
    local matches = Model.find_by_channel(self.state, ev.channel_id)
    if #matches == 0 then return end
    local removed_any = false
    local need_nav = false
    for _, tab in ipairs(matches) do
      if #self.state.tabs > 1 then
        local ok, _, _, was_active = Model.close_tab(self.state, tab.id, {
          force_pinned = true,
          record_closed = false,
        })
        if ok then
          removed_any = true
          if was_active then need_nav = true end
        end
      end
    end
    if removed_any then
      if need_nav then
        local cur = Model.active_tab(self.state)
        if cur then self.dispatch_navigation(cur) end
      end
      emit_change(true)
    end
  end

  -- Startup / guilds.loaded reconciliation: ensure at least one tab matches current client selection.
  function self.bootstrap_from_store(is_initial_boot)
    local hydrated = Sync.refresh_all(self.state)
    local sel_spec = Sync.spec_from_selected()

    if #self.state.tabs == 0 then
      local spec = sel_spec or Sync.spec_for_view("friends")
      local t = Model.open_tab(self.state, spec, { activate = true })
      if not sel_spec then
        t.is_placeholder = true
      end
      t.unread_count = 0
      t.mention_count = 0
      emit_change(sel_spec ~= nil)
      return
    end

    if sel_spec then
      local sel_key = Model.target_key(sel_spec)
      local active = Model.active_tab(self.state)
      if active and active.is_placeholder then
        active.is_placeholder = nil
        active.history = {}
        active.history_idx = 0
        Model.navigate_tab_in_place(active, sel_spec, true)
        active.unread_count = 0
        active.mention_count = 0
        emit_change(true)
        return
      end
      if active and active.target_key == sel_key then
        Model.navigate_tab_in_place(active, sel_spec, false)
        active.unread_count = 0
        active.mention_count = 0
        emit_change(hydrated)
        return
      end
      -- If user restored saved tabs and the startup channel already exists among them, focus it;
      -- otherwise on first boot navigate to saved active tab (or align with current view if hot-reloaded).
      local match = Model.find_by_target(self.state, sel_key)
      if match then
        self.state.active_id = match.id
        match.unread_count = 0
        match.mention_count = 0
        Model.ensure_visible(self.state, match.id)
        emit_change(true)
        return
      end
      if is_initial_boot and active then
        -- Keep saved tabs intact and sync C-Cord to the saved active tab if it still exists in store,
        -- or adopt current selection if saved active tab is unavailable.
        local active_valid = (active.kind == "friends" or active.kind == "requests")
        if not active_valid and active.channel_id then
          local ok, ch = pcall(store.channel, active.channel_id)
          active_valid = ok and type(ch) == "table"
        end
        if active_valid then
          self.dispatch_navigation(active)
          emit_change(hydrated)
          return
        end
      end
      -- Fallback: open current client selection as an active tab without discarding saved tabs.
      local t = Model.open_tab(self.state, sel_spec, { activate = true })
      t.unread_count = 0
      t.mention_count = 0
      emit_change(true)
      return
    end

    if hydrated then
      emit_change(false)
    end
  end

  return self
end

return M
