-- Shared constants, theme tokens, limits, and normalization helpers for Tabs!.
local M = {}

M.SCHEMA_VERSION = 1
M.STORAGE_KEY = "state_v1"

M.PANEL_BAR_ID = "tabs-bar"
M.PANEL_CTX_ID = "tabs-ctx"

-- C-Cord's synthetic guild ID for Direct Messages (UINT64_MAX).
M.DM_GUILD_RAW = "18446744073709551615"
M.DM_GUILD_ALIAS = "dm"

-- Render budgets calibrated safely below C-Cord's plugin_panels.c hard caps
-- (PANEL_MAX_NODES = 512, PANEL_MAX_HITS = 256, 64 visible children per box).
M.MAX_PINNED_RENDERED = 12
M.MAX_UNPINNED_RENDERED = 18
M.MAX_CLOSED_STACK = 20
M.MAX_HISTORY_PER_TAB = 20
M.MAX_TOOLTIP_BYTES = 120

-- Timing (milliseconds)
M.NAV_RECONCILE_TTL_MS = 650
M.PERSIST_DEBOUNCE_MS = 300
M.BADGE_SYNC_INTERVAL_MS = 4000
M.RENDER_COALESCE_MS = 0

-- Panel dimensions
M.BAR_HEIGHT = {
  normal = 36,
  compact = 30,
}
M.CTX_BAR_HEIGHT = 30

M.VALID_SLOTS = {
  top = true,
  subheader = true,
  bottom = true,
}

M.SLOT_ORDER = { "top", "subheader", "bottom" }

M.DEFAULT_SETTINGS = {
  slot = "top",
  density = "normal",
  dedupe_tabs = false,
  protect_pinned = true,
  new_tab_opens_switcher = true,
  aux_open_focus = false,
}

-- Map normalized tab kinds to verified C-Cord procedural icons (src/ui/plugin_panels.c).
M.KIND_ICON = {
  text = "hash",
  channel = "hash",
  dm = "at",
  group_dm = "members",
  forum = "forum",
  thread = "reply",
  voice = "speaker",
  stage = "speaker",
  friends = "members",
  requests = "inbox",
  guild = "folder",
}

function M.normalize_guild_id(gid)
  if gid == nil or gid == "" or gid == "0" then
    return nil
  end
  local s = tostring(gid)
  if s == M.DM_GUILD_RAW or s == M.DM_GUILD_ALIAS or s == "1" then
    return M.DM_GUILD_ALIAS
  end
  return s
end

function M.is_dm_guild(gid)
  return M.normalize_guild_id(gid) == M.DM_GUILD_ALIAS
end

function M.icon_for_kind(kind)
  return M.KIND_ICON[kind] or "hash"
end

function M.trim(s)
  if type(s) ~= "string" then return "" end
  return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- UTF-8-safe byte truncation so C-Cord's 128-byte tooltip buffer never splits a multibyte glyph.
function M.clamp_utf8(s, max_bytes)
  if type(s) ~= "string" then return "" end
  max_bytes = max_bytes or M.MAX_TOOLTIP_BYTES
  if #s <= max_bytes then return s end
  local budget = max_bytes - 3
  if budget < 1 then return "..." end
  if not utf8.len(s) then
    return s:sub(1, budget) .. "..."
  end
  local cut = 0
  for pos in utf8.codes(s) do
    if pos - 1 > budget then
      break
    end
    cut = pos - 1
  end
  if cut <= 0 then
    cut = budget
  end
  return s:sub(1, cut) .. "..."
end

function M.new_tab_id()
  local raw = crypto.uuid():gsub("-", "")
  return "t_" .. raw:sub(1, 8)
end

return M
