-- Declarative Flexbox renderer for the primary "tabs-bar" panel (100% theme-token compliant).
local C = require("tabs.constants")
local Model = require("tabs.model")

local M = {}

local function prefix_for_kind(kind)
  if kind == "text" or kind == "channel" or kind == "forum" then return "#" end
  if kind == "dm" then return "@" end
  return ""
end

local function build_tooltip(tab)
  local prefix = prefix_for_kind(tab.kind)
  local base = prefix .. (tab.label or "Tab")
  if tab.guild_name and tab.guild_name ~= "" and tab.guild_name ~= tab.label then
    base = base .. " — " .. tab.guild_name
  end
  if tab.pinned then
    base = base .. " (Pinned)"
  end
  if tab.mention_count and tab.mention_count > 0 then
    base = base .. " [" .. tostring(tab.mention_count) .. " mentions]"
  elseif (not tab.muted) and tab.unread_count and tab.unread_count > 0 then
    base = base .. " (Unread)"
  end
  return C.clamp_utf8(base, C.MAX_TOOLTIP_BYTES)
end

local function mention_text(n)
  if n > 99 then return "99+" end
  return tostring(n)
end

local function make_mention_pill(count, hide_on_hover)
  local pill = {
    type = "box",
    bg = "danger",
    radius = 7,
    pad_left = 5,
    pad_right = 5,
    pad_top = 1,
    pad_bottom = 1,
    align = "center",
    justify = "center",
    children = {
      {
        type = "text",
        text = mention_text(count),
        color = "text_on_brand",
        size = 10,
        bold = true,
        ellipsis = false,
      },
    },
  }
  if hide_on_hover then
    pill.hide_on_hover = true
  end
  return pill
end

local function make_unread_dot(hide_on_hover)
  local dot = {
    type = "box",
    w = 6,
    h = 6,
    radius = 3,
    bg = "brand",
  }
  if hide_on_hover then
    dot.hide_on_hover = true
  end
  return dot
end

local function make_pinned_tab(tab, is_active, is_bottom, compact, tab_h)
  local has_mentions = (not is_active) and (tab.mention_count or 0) > 0
  local has_unread = (not is_active) and (not tab.muted) and (tab.unread_count or 0) > 0
  local fg_color = is_active and "text_header"
    or ((has_mentions or has_unread) and "text_normal" or (tab.muted and "text_placeholder" or "text_muted"))
  local hover_fg = is_active and "text_header" or "text_interactive_hover"

  local children = {}
  if is_active then
    children[#children + 1] = {
      type = "box",
      w = 3,
      h = compact and 12 or 14,
      radius = 2,
      bg = "brand",
    }
  end
  children[#children + 1] = {
    type = "icon",
    name = "pin",
    size = compact and 12 or 13,
    color = is_active and "brand" or fg_color,
    hover_color = is_active and "brand" or hover_fg,
  }
  children[#children + 1] = {
    type = "text",
    text = tab.label or "Tab",
    color = fg_color,
    hover_color = hover_fg,
    size = compact and 12 or "small",
    bold = is_active or has_mentions or has_unread,
    ellipsis = false,
  }
  if has_mentions then
    children[#children + 1] = make_mention_pill(tab.mention_count, false)
  elseif has_unread then
    children[#children + 1] = make_unread_dot(false)
  end

  local node = {
    type = "row",
    id = "t:" .. tab.id,
    tooltip = build_tooltip(tab),
    cursor = "pointer",
    h = tab_h,
    pad_left = is_active and 7 or 9,
    pad_right = 9,
    gap = 6,
    align = "center",
    children = children,
  }

  if is_active then
    node.bg = "bg_primary"
    node.border_color = "border_subtle"
    node.border_w = 1
    node.border_sides = is_bottom and "all" or "no_bottom"
    node.radius = 6
  else
    node.hover_bg = "bg_item_hover"
    node.radius = is_bottom and 6 or 5
    if not is_bottom then
      node.border_color = "border_subtle"
      node.hover_border_color = "border_subtle"
      node.border_w = 1
      node.border_sides = "bottom"
    end
  end
  return node
end

local function make_unpinned_tab(tab, is_active, is_bottom, compact, tab_h, can_close)
  local has_mentions = (not is_active) and (tab.mention_count or 0) > 0
  local has_unread = (not is_active) and (not tab.muted) and (tab.unread_count or 0) > 0
  local fg_color = is_active and "text_header"
    or ((has_mentions or has_unread) and "text_normal" or (tab.muted and "text_placeholder" or "text_muted"))
  local hover_fg = is_active and "text_header" or "text_interactive_hover"

  local children = {}
  if is_active then
    children[#children + 1] = {
      type = "box",
      w = 3,
      h = compact and 12 or 14,
      radius = 2,
      bg = "brand",
    }
  end
  children[#children + 1] = {
    type = "icon",
    name = C.icon_for_kind(tab.kind),
    size = compact and 12 or 13,
    color = fg_color,
    hover_color = hover_fg,
  }
  children[#children + 1] = {
    type = "text",
    text = tab.label or "Tab",
    color = fg_color,
    hover_color = hover_fg,
    size = compact and 12 or "small",
    bold = is_active or has_mentions or has_unread,
    ellipsis = true,
    flex = 1,
    min_w = 20,
  }

  if has_mentions then
    children[#children + 1] = make_mention_pill(tab.mention_count, can_close)
  elseif has_unread then
    children[#children + 1] = make_unread_dot(can_close)
  end

  if can_close then
    local close_btn = {
      type = "button",
      id = "x:" .. tab.id,
      icon = "close",
      icon_size = 10,
      variant = "ghost",
      size = "xs",
      w = 18,
      h = 18,
      tooltip = "Close tab",
    }
    if not is_active then
      close_btn.show_on_hover = true
    end
    children[#children + 1] = close_btn
  end

  local node = {
    type = "row",
    id = "t:" .. tab.id,
    tooltip = build_tooltip(tab),
    cursor = "pointer",
    flex = 1,
    min_w = compact and 88 or 104,
    max_w = 204,
    h = tab_h,
    pad_left = is_active and 7 or 9,
    pad_right = 6,
    gap = 6,
    align = "center",
    clip = true,
    children = children,
  }

  if is_active then
    node.bg = "bg_primary"
    node.border_color = "border_subtle"
    node.border_w = 1
    node.border_sides = is_bottom and "all" or "no_bottom"
    node.radius = 6
  else
    node.hover_bg = "bg_item_hover"
    node.radius = is_bottom and 6 or 5
    if not is_bottom then
      node.border_color = "border_subtle"
      node.hover_border_color = "border_subtle"
      node.border_w = 1
      node.border_sides = "bottom"
    end
  end
  return node
end

function M.bar_height(settings)
  return C.BAR_HEIGHT[settings.density] or C.BAR_HEIGHT.normal
end

-- Build pure declarative widget tree for "tabs-bar" (unit-testable without IPC).
function M.build_tree(state)
  local settings = state.settings
  local compact = (settings.density == "compact")
  local is_bottom = (settings.slot == "bottom")
  local bar_h = M.bar_height(settings)
  local tab_h = is_bottom and (bar_h - 6) or (bar_h - 4)
  local can_close = (#state.tabs > 1)

  local pinned, unpinned = {}, {}
  for _, tab in ipairs(state.tabs) do
    if tab.pinned then
      pinned[#pinned + 1] = tab
    else
      unpinned[#unpinned + 1] = tab
    end
  end

  local root_children = {}

  -- 1. Pinned Zone (anchored on the left)
  if #pinned > 0 then
    local pinned_children = {}
    local p_limit = math.min(#pinned, C.MAX_PINNED_RENDERED)
    local prev_p_active = false
    for i = 1, p_limit do
      local tab = pinned[i]
      local is_active = (tab.id == state.active_id)
      if i > 1 and (not is_active) and (not prev_p_active) then
        pinned_children[#pinned_children + 1] = {
          type = "divider",
          orientation = "vertical",
          inset = 8,
          thickness = 1,
          color = "divider",
        }
      end
      pinned_children[#pinned_children + 1] = make_pinned_tab(tab, is_active, is_bottom, compact, tab_h)
      prev_p_active = is_active
    end
    root_children[#root_children + 1] = {
      type = "row",
      gap = 2,
      pad_top = is_bottom and 0 or 2,
      pad_bottom = 0,
      pad_left = 2,
      pad_right = 2,
      align = is_bottom and "center" or "end",
      children = pinned_children,
    }
    if #unpinned > 0 then
      root_children[#root_children + 1] = {
        type = "divider",
        orientation = "vertical",
        inset = 7,
        thickness = 1,
        color = "divider",
      }
    end
  end

  -- 2. Scroll-left chevron (when horizontally scrolled)
  local scroll_off = math.max(0, math.min(state.scroll_offset or 0, math.max(0, #unpinned - 1)))
  if scroll_off > 0 then
    root_children[#root_children + 1] = {
      type = "row",
      align = "center",
      pad_bottom = is_bottom and 0 or 2,
      children = {
        {
          type = "button",
          id = "scroll-l",
          icon = "chevron_left",
          icon_size = 12,
          variant = "ghost",
          size = "xs",
          w = 20,
          h = compact and 20 or 22,
          tooltip = "Scroll tabs left (" .. tostring(scroll_off) .. " hidden)",
        },
      },
    }
  end

  -- 3. Scrollable Unpinned Tab Strip
  local strip_children = {}
  local win_start = scroll_off + 1
  local win_end = math.min(#unpinned, scroll_off + C.MAX_UNPINNED_RENDERED)
  local prev_was_active = false
  for i = win_start, win_end do
    local tab = unpinned[i]
    local is_active = (tab.id == state.active_id)
    if i > win_start and (not is_active) and (not prev_was_active) then
      strip_children[#strip_children + 1] = {
        type = "divider",
        orientation = "vertical",
        inset = 8,
        thickness = 1,
        color = "divider",
      }
    end
    strip_children[#strip_children + 1] = make_unpinned_tab(tab, is_active, is_bottom, compact, tab_h, can_close)
    prev_was_active = is_active
  end

  local strip_node = {
    type = "row",
    flex = 1,
    clip = true,
    gap = 2,
    pad_top = is_bottom and 0 or 2,
    pad_bottom = 0,
    pad_left = 2,
    pad_right = 2,
    align = is_bottom and "center" or "end",
  }
  if #strip_children > 0 then
    strip_node.children = strip_children
  end
  root_children[#root_children + 1] = strip_node

  -- 4. Right Utility Cluster (Scroll Right, New Tab, Settings)
  local util_children = {}
  local hidden_right = #unpinned - win_end
  local can_scroll_right = (#unpinned > 1) and (scroll_off < #unpinned - 1) and (scroll_off > 0 or #unpinned >= 5)
  if can_scroll_right then
    local r_tip = hidden_right > 0
      and ("Scroll tabs right (" .. tostring(hidden_right) .. " more)")
      or "Scroll tabs right"
    util_children[#util_children + 1] = {
      type = "button",
      id = "scroll-r",
      icon = "chevron_right",
      icon_size = 12,
      variant = "ghost",
      size = "xs",
      w = 20,
      h = compact and 20 or 22,
      tooltip = r_tip,
    }
  end

  util_children[#util_children + 1] = {
    type = "divider",
    orientation = "vertical",
    inset = 5,
    thickness = 1,
    color = "divider",
  }

  util_children[#util_children + 1] = {
    type = "button",
    id = "act-new",
    icon = "plus",
    icon_size = 13,
    variant = "ghost",
    size = "sm",
    w = 24,
    h = compact and 22 or 24,
    tooltip = "New Tab (Shift: duplicate, Right-click: reopen closed)",
  }

  util_children[#util_children + 1] = {
    type = "button",
    id = "act-menu",
    icon = "gear",
    icon_size = 13,
    variant = "ghost",
    size = "sm",
    w = 24,
    h = compact and 22 or 24,
    selected = (state.ctx_mode == "settings"),
    tooltip = "Tab Bar Settings & Actions",
  }

  root_children[#root_children + 1] = {
    type = "row",
    align = "center",
    gap = 3,
    pad_bottom = is_bottom and 0 or 2,
    children = util_children,
  }

  -- Root carries id = "tabs-root" so C-Cord dispatches wheel/click events anywhere on the bar.
  return {
    type = "row",
    id = "tabs-root",
    cursor = "default",
    bg = "bg_tertiary",
    border_color = "border_subtle",
    border_w = 1,
    border_sides = is_bottom and "top" or "bottom",
    pad_left = 6,
    pad_right = 6,
    pad_top = is_bottom and 3 or 2,
    pad_bottom = is_bottom and 3 or 0,
    gap = 4,
    align = is_bottom and "center" or "stretch",
    children = root_children,
  }
end

function M.new(state, on_event)
  local self = {
    state = state,
    on_event = on_event,
    mounted = false,
    last_slot = nil,
    last_height = nil,
    last_fingerprint = nil,
    dirty = false,
    timer_id = nil,
  }

  function self.render_now()
    if self.timer_id then
      time.cancel(self.timer_id)
      self.timer_id = nil
    end
    self.dirty = false

    local slot = self.state.settings.slot
    local height = M.bar_height(self.state.settings)
    local root = M.build_tree(self.state)
    local encoded = json.encode({ slot = slot, height = height, root = root })

    if self.mounted and encoded and encoded == self.last_fingerprint then
      return false
    end

    if not self.mounted then
      ui.panel.mount({
        id = C.PANEL_BAR_ID,
        slot = slot,
        height = height,
        root = root,
        on_event = self.on_event,
      })
      self.mounted = true
    else
      local patch = { root = root }
      if slot ~= self.last_slot then patch.slot = slot end
      if height ~= self.last_height then patch.height = height end
      ui.panel.update(C.PANEL_BAR_ID, patch)
    end

    self.last_slot = slot
    self.last_height = height
    self.last_fingerprint = encoded
    return true
  end

  function self.schedule()
    self.dirty = true
    if self.timer_id then return end
    self.timer_id = time.after(C.RENDER_COALESCE_MS, function()
      self.timer_id = nil
      if self.dirty then
        self.render_now()
      end
    end)
  end

  function self.unmount()
    if self.timer_id then
      time.cancel(self.timer_id)
      self.timer_id = nil
    end
    if self.mounted then
      pcall(ui.panel.unmount, C.PANEL_BAR_ID)
      self.mounted = false
      self.last_fingerprint = nil
    end
  end

  return self
end

return M
