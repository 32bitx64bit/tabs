-- Store hydration & live unread/mention/metadata synchronization.
local C = require("tabs.constants")
local Model = require("tabs.model")

local M = {}

local function safe_call(fn, ...)
  local ok, res = pcall(fn, ...)
  if not ok then return nil end
  return res
end

function M.resolve_guild_name(guild_id)
  local gid = C.normalize_guild_id(guild_id)
  if not gid then return nil end
  if gid == C.DM_GUILD_ALIAS then
    return "Direct Messages"
  end
  local g = safe_call(store.guild, gid)
  if type(g) == "table" and type(g.name) == "string" and g.name ~= "" then
    return g.name
  end
  return nil
end

function M.spec_from_channel_obj(ch, fallback_guild_name)
  if type(ch) ~= "table" then return nil end
  local cid = ch.id or ch.channel_id
  if not cid or cid == "" or cid == "0" then return nil end
  local gid = C.normalize_guild_id(ch.guild_id)
  local kind = ch.kind or (gid == C.DM_GUILD_ALIAS and "dm" or "text")
  if kind == "category" then return nil end
  local label = (type(ch.display_name) == "string" and ch.display_name ~= "") and ch.display_name
    or (type(ch.name) == "string" and ch.name ~= "") and ch.name
    or (kind == "dm" and "Direct Message" or "Channel")
  local gname = fallback_guild_name or M.resolve_guild_name(gid)
  return {
    kind = kind,
    guild_id = gid,
    channel_id = tostring(cid),
    parent_id = (ch.parent_id and ch.parent_id ~= "" and ch.parent_id ~= "0") and tostring(ch.parent_id) or nil,
    label = label,
    guild_name = gname,
    unread_count = tonumber(ch.unread_count) or 0,
    mention_count = tonumber(ch.mention_count) or 0,
    muted = ch.muted == true,
  }
end

function M.spec_from_channel_id(channel_id, hints)
  hints = hints or {}
  if channel_id and channel_id ~= "" and channel_id ~= "0" then
    local ch = safe_call(store.channel, tostring(channel_id))
    if type(ch) == "table" then
      if ch.kind == "category" then return nil end
      local spec = M.spec_from_channel_obj(ch)
      if spec then
        if not spec.parent_id and hints.parent_id and hints.parent_id ~= "" then
          spec.parent_id = tostring(hints.parent_id)
          if spec.kind == "text" then spec.kind = "thread" end
        end
        return spec
      end
    end
  end

  -- Fallback when opening an uncached/inline thread or channel not yet hydrated in store.
  local cid = (channel_id and channel_id ~= "" and channel_id ~= "0") and tostring(channel_id) or nil
  if not cid then return nil end
  local gid = C.normalize_guild_id(hints.guild_id)
  local pid = (hints.parent_id and hints.parent_id ~= "" and hints.parent_id ~= "0") and tostring(hints.parent_id) or nil
  local kind = hints.kind or (pid and "thread" or (gid == C.DM_GUILD_ALIAS and "dm" or "text"))
  local label = (type(hints.name) == "string" and hints.name ~= "") and hints.name
    or (type(hints.label) == "string" and hints.label ~= "") and hints.label
    or (kind == "thread" and "Thread" or "Channel")
  return {
    kind = kind,
    guild_id = gid,
    channel_id = cid,
    parent_id = pid,
    label = label,
    guild_name = M.resolve_guild_name(gid),
    unread_count = 0,
    mention_count = 0,
    muted = false,
  }
end

function M.spec_for_view(view)
  if view == "friends" or view == "dm_home" then
    return {
      kind = "friends",
      guild_id = C.DM_GUILD_ALIAS,
      channel_id = nil,
      parent_id = nil,
      label = "Friends",
      guild_name = "Direct Messages",
      unread_count = 0,
      mention_count = 0,
      muted = false,
    }
  elseif view == "requests" then
    return {
      kind = "requests",
      guild_id = C.DM_GUILD_ALIAS,
      channel_id = nil,
      parent_id = nil,
      label = "Message Requests",
      guild_name = "Direct Messages",
      unread_count = 0,
      mention_count = 0,
      muted = false,
    }
  end
  return nil
end

-- Resolve a server/guild click into its first readable text/forum channel if cached,
-- or a "guild" tab that resolves when activated.
function M.spec_for_guild(guild_id)
  local gid = C.normalize_guild_id(guild_id)
  if not gid then return nil end
  if gid == C.DM_GUILD_ALIAS then
    return M.spec_for_view("friends")
  end

  local gname = M.resolve_guild_name(gid)
  local channels = safe_call(store.channels, gid)
  if type(channels) == "table" then
    for _, ch in ipairs(channels) do
      if type(ch) == "table" and (ch.kind == "text" or ch.kind == "forum") then
        local spec = M.spec_from_channel_obj(ch, gname)
        if spec then return spec end
      end
    end
  end

  return {
    kind = "guild",
    guild_id = gid,
    channel_id = nil,
    parent_id = nil,
    label = gname or "Server",
    guild_name = gname,
    unread_count = 0,
    mention_count = 0,
    muted = false,
  }
end

function M.spec_from_selected()
  local sel = safe_call(store.selected)
  if type(sel) ~= "table" then return nil end
  if sel.view == "friends" or sel.view == "requests" then
    return M.spec_for_view(sel.view)
  end
  if sel.view == "discovery" then
    return nil
  end
  local cid = sel.channel_id
  if cid and cid ~= "" and cid ~= "0" then
    return M.spec_from_channel_id(cid, { guild_id = sel.guild_id })
  end
  local gid = C.normalize_guild_id(sel.guild_id)
  if gid == C.DM_GUILD_ALIAS then
    return M.spec_for_view("friends")
  elseif gid then
    return M.spec_for_guild(gid)
  end
  return nil
end

function M.spec_from_aux_open(ev)
  if type(ev) ~= "table" then return nil end
  local view = ev.view
  if view == "friends" or view == "requests" then
    return M.spec_for_view(view)
  end
  if view == "discovery" then
    return nil
  end
  if view == "guild" then
    return M.spec_for_guild(ev.guild_id)
  end
  if ev.channel_id and ev.channel_id ~= "" and ev.channel_id ~= "0" then
    local hints = {
      guild_id = ev.guild_id,
      parent_id = ev.parent_id,
      name = ev.name,
      kind = (view == "thread" or (ev.parent_id and ev.parent_id ~= "")) and "thread" or nil,
    }
    return M.spec_from_channel_id(ev.channel_id, hints)
  end
  if ev.guild_id then
    return M.spec_for_guild(ev.guild_id)
  end
  return nil
end

-- Refresh live metadata & unread/mention badges for a single tab. Returns true if anything changed.
function M.refresh_tab(tab, is_active)
  if not tab then return false end
  local changed = false

  if tab.channel_id then
    local ch = safe_call(store.channel, tab.channel_id)
    if type(ch) == "table" then
      local spec = M.spec_from_channel_obj(ch)
      if spec then
        local unread = is_active and 0 or spec.unread_count
        local mentions = is_active and 0 or spec.mention_count
        if tab.label ~= spec.label then tab.label = spec.label; changed = true end
        if tab.kind ~= spec.kind then tab.kind = spec.kind; changed = true end
        if spec.guild_id and tab.guild_id ~= spec.guild_id then tab.guild_id = spec.guild_id; changed = true end
        if spec.guild_name and tab.guild_name ~= spec.guild_name then tab.guild_name = spec.guild_name; changed = true end
        if spec.parent_id and tab.parent_id ~= spec.parent_id then tab.parent_id = spec.parent_id; changed = true end
        if tab.unread_count ~= unread then tab.unread_count = unread; changed = true end
        if tab.mention_count ~= mentions then tab.mention_count = mentions; changed = true end
        if tab.muted ~= spec.muted then tab.muted = spec.muted; changed = true end
        local new_key = Model.target_key(tab)
        if tab.target_key ~= new_key then tab.target_key = new_key; changed = true end
      end
    end
  elseif tab.kind == "guild" and tab.guild_id then
    local gname = M.resolve_guild_name(tab.guild_id)
    if gname and tab.label ~= gname then
      tab.label = gname
      tab.guild_name = gname
      changed = true
    end
  end

  return changed
end

-- Refresh all open tabs from store. Returns true if any tab changed visually.
function M.refresh_all(state)
  local changed = false
  for _, tab in ipairs(state.tabs) do
    local is_active = (tab.id == state.active_id)
    if M.refresh_tab(tab, is_active) then
      changed = true
    end
  end
  return changed
end

-- Refresh tabs bound to a specific channel ID (used on message.create / channel.upsert / notify.update).
function M.refresh_channel(state, channel_id)
  if not channel_id or channel_id == "" then return false end
  local matches = Model.find_by_channel(state, channel_id)
  if #matches == 0 then return false end
  local changed = false
  for _, tab in ipairs(matches) do
    local is_active = (tab.id == state.active_id)
    if M.refresh_tab(tab, is_active) then
      changed = true
    end
  end
  return changed
end

return M
