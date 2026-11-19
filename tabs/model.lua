-- Pure tab state model: CRUD, pinning, ordering, dedupe, history, closed stack, and settings.
local C = require("tabs.constants")

local M = {}

local function copy_entry(src)
  if type(src) ~= "table" then return nil end
  return {
    kind = src.kind or "text",
    guild_id = C.normalize_guild_id(src.guild_id),
    channel_id = (src.channel_id and src.channel_id ~= "" and src.channel_id ~= "0") and tostring(src.channel_id) or nil,
    parent_id = (src.parent_id and src.parent_id ~= "" and src.parent_id ~= "0") and tostring(src.parent_id) or nil,
    label = (type(src.label) == "string" and src.label ~= "") and src.label or "Tab",
    guild_name = (type(src.guild_name) == "string" and src.guild_name ~= "") and src.guild_name or nil,
  }
end

function M.target_key(entry)
  if not entry then return "" end
  local kind = entry.kind or "text"
  if kind == "friends" then return "view:friends" end
  if kind == "requests" then return "view:requests" end
  if entry.channel_id and entry.channel_id ~= "" then
    if kind == "thread" or (entry.parent_id and entry.parent_id ~= "") then
      return "th:" .. tostring(entry.channel_id)
    end
    return "ch:" .. tostring(entry.channel_id)
  end
  if kind == "guild" and entry.guild_id then
    return "guild:" .. tostring(entry.guild_id)
  end
  return "view:" .. tostring(kind)
end

function M.clone_settings(src)
  local out = {}
  for k, v in pairs(C.DEFAULT_SETTINGS) do
    out[k] = v
  end
  if type(src) == "table" then
    if C.VALID_SLOTS[src.slot] then out.slot = src.slot end
    if src.density == "normal" or src.density == "compact" then out.density = src.density end
    if type(src.dedupe_tabs) == "boolean" then out.dedupe_tabs = src.dedupe_tabs end
    if type(src.protect_pinned) == "boolean" then out.protect_pinned = src.protect_pinned end
    if type(src.new_tab_opens_switcher) == "boolean" then out.new_tab_opens_switcher = src.new_tab_opens_switcher end
    if type(src.aux_open_focus) == "boolean" then out.aux_open_focus = src.aux_open_focus end
  end
  return out
end

function M.new_state(saved)
  local st = {
    tabs = {},
    active_id = nil,
    scroll_offset = 0,
    closed = {},
    settings = M.clone_settings(saved and saved.settings),
    -- Transient UI state (not persisted):
    ctx_mode = nil,       -- nil | "tab" | "settings"
    ctx_tab_id = nil,
    pending_nav = nil,
  }

  if type(saved) == "table" then
    if type(saved.tabs) == "table" then
      local seen_ids = {}
      for _, raw in ipairs(saved.tabs) do
        local tab = M.normalize_tab(raw)
        if tab and not seen_ids[tab.id] then
          seen_ids[tab.id] = true
          st.tabs[#st.tabs + 1] = tab
        end
      end
    end
    M.normalize_order(st)

    if type(saved.closed) == "table" then
      for i = 1, math.min(#saved.closed, C.MAX_CLOSED_STACK) do
        local item = copy_entry(saved.closed[i])
        if item then
          item.target_key = M.target_key(item)
          st.closed[#st.closed + 1] = item
        end
      end
    end

    if type(saved.active_id) == "string" and M.find_tab(st, saved.active_id) then
      st.active_id = saved.active_id
    elseif #st.tabs > 0 then
      st.active_id = st.tabs[1].id
    end
  end

  return st
end

function M.normalize_tab(raw)
  if type(raw) ~= "table" then return nil end
  local entry = copy_entry(raw)
  if not entry then return nil end
  local id = (type(raw.id) == "string" and raw.id:match("^[a-z0-9][a-z0-9_-]*$") and #raw.id <= 24)
    and raw.id or C.new_tab_id()
  local tab = {
    id = id,
    kind = entry.kind,
    guild_id = entry.guild_id,
    channel_id = entry.channel_id,
    parent_id = entry.parent_id,
    label = entry.label,
    guild_name = entry.guild_name,
    target_key = M.target_key(entry),
    pinned = raw.pinned == true,
    unread_count = tonumber(raw.unread_count) or 0,
    mention_count = tonumber(raw.mention_count) or 0,
    muted = raw.muted == true,
    history = { copy_entry(entry) },
    history_idx = 1,
  }
  return tab
end

-- Keep all pinned tabs contiguously on the left while preserving relative order in both zones.
function M.normalize_order(st)
  local pinned, unpinned = {}, {}
  for _, t in ipairs(st.tabs) do
    if t.pinned then
      pinned[#pinned + 1] = t
    else
      unpinned[#unpinned + 1] = t
    end
  end
  local merged = {}
  for _, t in ipairs(pinned) do merged[#merged + 1] = t end
  for _, t in ipairs(unpinned) do merged[#merged + 1] = t end
  st.tabs = merged
  M.clamp_scroll(st)
end

function M.count_pinned(st)
  local n = 0
  for _, t in ipairs(st.tabs) do
    if t.pinned then n = n + 1 end
  end
  return n
end

function M.count_unpinned(st)
  return #st.tabs - M.count_pinned(st)
end

function M.find_tab(st, id)
  if not id then return nil, nil end
  for i, t in ipairs(st.tabs) do
    if t.id == id then return t, i end
  end
  return nil, nil
end

function M.active_tab(st)
  local t, idx = M.find_tab(st, st.active_id)
  if t then return t, idx end
  if #st.tabs > 0 then
    st.active_id = st.tabs[1].id
    return st.tabs[1], 1
  end
  return nil, nil
end

function M.find_by_target(st, key)
  if not key or key == "" then return nil, nil end
  for i, t in ipairs(st.tabs) do
    if t.target_key == key then return t, i end
  end
  return nil, nil
end

function M.find_by_channel(st, channel_id)
  if not channel_id or channel_id == "" then return {} end
  local cid = tostring(channel_id)
  local matches = {}
  for _, t in ipairs(st.tabs) do
    if t.channel_id == cid then
      matches[#matches + 1] = t
    end
  end
  return matches
end

function M.clamp_scroll(st)
  local unpinned_count = M.count_unpinned(st)
  local max_off = math.max(0, unpinned_count - 1)
  if st.scroll_offset < 0 then
    st.scroll_offset = 0
  elseif st.scroll_offset > max_off then
    st.scroll_offset = max_off
  end
end

function M.ensure_visible(st, tab_id)
  local tab, idx = M.find_tab(st, tab_id)
  if not tab or tab.pinned then return end
  local pinned_n = M.count_pinned(st)
  local u_idx = idx - pinned_n -- 1-based index among unpinned tabs
  if u_idx < 1 then return end
  if u_idx - 1 < st.scroll_offset then
    st.scroll_offset = u_idx - 1
  elseif u_idx > st.scroll_offset + C.MAX_UNPINNED_RENDERED then
    st.scroll_offset = u_idx - C.MAX_UNPINNED_RENDERED
  end
  M.clamp_scroll(st)
end

function M.scroll_by(st, delta)
  local before = st.scroll_offset
  st.scroll_offset = st.scroll_offset + delta
  M.clamp_scroll(st)
  return st.scroll_offset ~= before
end

-- Create and insert a new tab.
-- opts: { activate = bool, pinned = bool, after_active = bool, index = number }
function M.open_tab(st, spec, opts)
  opts = opts or {}
  local tab = M.normalize_tab({
    kind = spec.kind,
    guild_id = spec.guild_id,
    channel_id = spec.channel_id,
    parent_id = spec.parent_id,
    label = spec.label,
    guild_name = spec.guild_name,
    pinned = opts.pinned == true,
    unread_count = spec.unread_count or 0,
    mention_count = spec.mention_count or 0,
    muted = spec.muted == true,
  })

  local pinned_n = M.count_pinned(st)
  local insert_at
  if tab.pinned then
    insert_at = pinned_n + 1
  elseif opts.index then
    insert_at = math.max(pinned_n + 1, math.min(#st.tabs + 1, opts.index))
  elseif opts.after_active then
    local _, aidx = M.active_tab(st)
    local base_idx = (aidx and aidx > pinned_n) and aidx or pinned_n
    if not opts.activate then
      -- Consecutive background opens from the same active tab preserve click order (like Chrome/Firefox).
      if st._bg_anchor_id == st.active_id then
        st._bg_offset = (st._bg_offset or 0) + 1
      else
        st._bg_anchor_id = st.active_id
        st._bg_offset = 1
      end
      insert_at = math.min(#st.tabs + 1, base_idx + st._bg_offset)
    else
      st._bg_anchor_id = nil
      st._bg_offset = 0
      insert_at = base_idx + 1
    end
  else
    insert_at = #st.tabs + 1
  end

  table.insert(st.tabs, insert_at, tab)
  if opts.activate or not st.active_id then
    st.active_id = tab.id
    st._bg_anchor_id = nil
    st._bg_offset = 0
    M.ensure_visible(st, tab.id)
  end
  return tab
end

-- Update an existing tab's destination in-place, recording history if target changed.
function M.navigate_tab_in_place(tab, spec, record_history)
  local entry = copy_entry(spec)
  if not entry then return false end
  local new_key = M.target_key(entry)
  local changed = (tab.target_key ~= new_key)

  tab.kind = entry.kind
  tab.guild_id = entry.guild_id
  tab.channel_id = entry.channel_id
  tab.parent_id = entry.parent_id
  tab.label = entry.label
  if entry.guild_name then
    tab.guild_name = entry.guild_name
  elseif entry.kind == "friends" or entry.kind == "requests" or entry.guild_id == C.DM_GUILD_ALIAS then
    tab.guild_name = "Direct Messages"
  end
  tab.target_key = new_key
  if spec.unread_count ~= nil then tab.unread_count = tonumber(spec.unread_count) or 0 end
  if spec.mention_count ~= nil then tab.mention_count = tonumber(spec.mention_count) or 0 end
  if spec.muted ~= nil then tab.muted = spec.muted == true end

  if record_history ~= false then
    tab.history = tab.history or {}
    tab.history_idx = tab.history_idx or 0
    if changed or #tab.history == 0 then
      -- Trim forward history when branching
      for i = #tab.history, tab.history_idx + 1, -1 do
        tab.history[i] = nil
      end
      tab.history[#tab.history + 1] = copy_entry(entry)
      if #tab.history > C.MAX_HISTORY_PER_TAB then
        table.remove(tab.history, 1)
      end
      tab.history_idx = #tab.history
    else
      -- Keep current history entry metadata fresh (e.g. updated channel label)
      tab.history[tab.history_idx] = copy_entry(entry)
    end
  end

  return changed
end

function M.can_go_back(tab)
  return tab ~= nil and type(tab.history) == "table" and (tab.history_idx or 1) > 1
end

function M.can_go_forward(tab)
  return tab ~= nil and type(tab.history) == "table" and (tab.history_idx or 1) < #tab.history
end

function M.step_history(tab, delta)
  if not tab or type(tab.history) ~= "table" then return nil end
  local next_idx = (tab.history_idx or 1) + delta
  if next_idx < 1 or next_idx > #tab.history then return nil end
  tab.history_idx = next_idx
  local entry = tab.history[next_idx]
  M.navigate_tab_in_place(tab, entry, false)
  return tab
end

local function push_closed(st, tab)
  local entry = copy_entry(tab)
  if not entry then return end
  entry.target_key = M.target_key(entry)
  table.insert(st.closed, 1, entry)
  while #st.closed > C.MAX_CLOSED_STACK do
    table.remove(st.closed)
  end
end

-- Close a tab by ID. Returns (ok, reason, new_active_tab_or_nil, switched_active).
function M.close_tab(st, id, opts)
  opts = opts or {}
  local tab, idx = M.find_tab(st, id)
  if not tab then return false, "not_found", nil, false end
  if tab.pinned and not opts.force_pinned then
    return false, "pinned", nil, false
  end
  if #st.tabs <= 1 and not opts.allow_last then
    return false, "last_tab", nil, false
  end

  local was_active = (st.active_id == tab.id)
  if opts.record_closed ~= false then
    push_closed(st, tab)
  end
  table.remove(st.tabs, idx)
  if st.ctx_tab_id == id then
    st.ctx_mode = nil
    st.ctx_tab_id = nil
  end

  local next_active = nil
  if was_active then
    if #st.tabs > 0 then
      local next_idx = math.min(idx, #st.tabs)
      next_active = st.tabs[next_idx]
      st.active_id = next_active.id
      M.ensure_visible(st, next_active.id)
    else
      st.active_id = nil
    end
  end
  M.clamp_scroll(st)
  return true, nil, next_active, was_active
end

function M.reopen_closed(st)
  if #st.closed == 0 then return nil end
  local entry = table.remove(st.closed, 1)
  return M.open_tab(st, entry, { activate = true, after_active = true })
end

function M.duplicate_tab(st, id, opts)
  opts = opts or {}
  local tab = M.find_tab(st, id)
  if not tab then return nil end
  return M.open_tab(st, tab, {
    activate = opts.activate ~= false,
    after_active = true,
    pinned = false,
  })
end

function M.toggle_pin(st, id)
  local tab, idx = M.find_tab(st, id)
  if not tab then return nil end
  table.remove(st.tabs, idx)
  tab.pinned = not tab.pinned
  local pinned_n = M.count_pinned(st)
  if tab.pinned then
    -- Append to end of pinned zone
    table.insert(st.tabs, pinned_n + 1, tab)
  else
    -- Place at start of unpinned zone so user never loses sight of it
    table.insert(st.tabs, pinned_n + 1, tab)
  end
  M.clamp_scroll(st)
  if st.active_id == tab.id then
    M.ensure_visible(st, tab.id)
  end
  return tab
end

function M.can_move(st, id, delta)
  local tab, idx = M.find_tab(st, id)
  if not tab then return false end
  local pinned_n = M.count_pinned(st)
  local lo = tab.pinned and 1 or (pinned_n + 1)
  local hi = tab.pinned and pinned_n or #st.tabs
  local dest = idx + delta
  return dest >= lo and dest <= hi
end

function M.move_tab(st, id, delta)
  if not M.can_move(st, id, delta) then return false end
  local tab, idx = M.find_tab(st, id)
  local dest = idx + delta
  st.tabs[idx], st.tabs[dest] = st.tabs[dest], st.tabs[idx]
  if st.active_id == tab.id then
    M.ensure_visible(st, tab.id)
  end
  return true
end

function M.cycle_active(st, delta)
  if #st.tabs <= 1 then return nil end
  local _, idx = M.active_tab(st)
  if not idx then return nil end
  local next_idx = ((idx - 1 + delta) % #st.tabs) + 1
  local target = st.tabs[next_idx]
  st.active_id = target.id
  M.ensure_visible(st, target.id)
  return target
end

function M.close_others(st, keep_id)
  local keep = M.find_tab(st, keep_id)
  if not keep then return 0, false end
  local closed_count = 0
  local active_closed = false
  for i = #st.tabs, 1, -1 do
    local t = st.tabs[i]
    if t.id ~= keep_id and not t.pinned then
      if st.active_id == t.id then active_closed = true end
      push_closed(st, t)
      table.remove(st.tabs, i)
      closed_count = closed_count + 1
    end
  end
  if active_closed then
    st.active_id = keep.id
    M.ensure_visible(st, keep.id)
  end
  M.clamp_scroll(st)
  return closed_count, active_closed
end

function M.close_to_right(st, anchor_id)
  local _, anchor_idx = M.find_tab(st, anchor_id)
  if not anchor_idx then return 0, false end
  local closed_count = 0
  local active_closed = false
  for i = #st.tabs, anchor_idx + 1, -1 do
    local t = st.tabs[i]
    if not t.pinned then
      if st.active_id == t.id then active_closed = true end
      push_closed(st, t)
      table.remove(st.tabs, i)
      closed_count = closed_count + 1
    end
  end
  if active_closed then
    st.active_id = anchor_id
    M.ensure_visible(st, anchor_id)
  end
  M.clamp_scroll(st)
  return closed_count, active_closed
end

function M.close_all_unpinned(st)
  local pinned_n = M.count_pinned(st)
  local closed_count = 0
  local active_closed = false
  for i = #st.tabs, 1, -1 do
    local t = st.tabs[i]
    if not t.pinned then
      -- Always keep at least one tab total when no pinned tabs exist
      if pinned_n == 0 and #st.tabs <= 1 then
        break
      end
      if st.active_id == t.id then active_closed = true end
      push_closed(st, t)
      table.remove(st.tabs, i)
      closed_count = closed_count + 1
    end
  end
  if active_closed and #st.tabs > 0 then
    st.active_id = st.tabs[#st.tabs].id
    M.ensure_visible(st, st.active_id)
  end
  M.clamp_scroll(st)
  return closed_count, active_closed
end

function M.serialize(st)
  local tabs_out = {}
  for _, t in ipairs(st.tabs) do
    tabs_out[#tabs_out + 1] = {
      id = t.id,
      kind = t.kind,
      guild_id = t.guild_id,
      channel_id = t.channel_id,
      parent_id = t.parent_id,
      label = t.label,
      guild_name = t.guild_name,
      pinned = t.pinned == true,
    }
  end
  local closed_out = {}
  for i = 1, math.min(#st.closed, C.MAX_CLOSED_STACK) do
    closed_out[#closed_out + 1] = copy_entry(st.closed[i])
  end
  return {
    schema = C.SCHEMA_VERSION,
    active_id = st.active_id,
    tabs = tabs_out,
    closed = closed_out,
    settings = M.clone_settings(st.settings),
  }
end

return M
