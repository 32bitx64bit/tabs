-- On-demand contextual shelf ("tabs-ctx") for right-click tab actions and live settings.
local C = require("tabs.constants")
local Model = require("tabs.model")

local M = {}

local function slot_label(slot)
  if slot == "subheader" then return "Below Header" end
  if slot == "bottom" then return "Bottom" end
  return "Top"
end

local function build_tab_ctx_tree(state, tab)
  local can_left = Model.can_move(state, tab.id, -1)
  local can_right = Model.can_move(state, tab.id, 1)
  local can_back = Model.can_go_back(tab)
  local can_fwd = Model.can_go_forward(tab)
  local can_close = (not tab.pinned) and (#state.tabs > 1)

  local children = {
    {
      type = "icon",
      name = C.icon_for_kind(tab.kind),
      size = 12,
      color = "text_muted",
    },
    {
      type = "text",
      text = tab.label or "Tab",
      color = "text_header",
      size = 12,
      bold = true,
      ellipsis = true,
      max_w = 130,
    },
    { type = "divider", orientation = "vertical", inset = 6, color = "divider" },
    {
      type = "button",
      id = "ctx-pin",
      label = tab.pinned and "Unpin" or "Pin",
      icon = "pin",
      icon_size = 11,
      variant = tab.pinned and "primary" or "secondary",
      size = "xs",
      tooltip = tab.pinned and "Unpin tab" or "Pin tab to left zone",
    },
    {
      type = "button",
      id = "ctx-left",
      icon = "chevron_left",
      icon_size = 11,
      variant = "secondary",
      size = "xs",
      disabled = not can_left,
      tooltip = "Move tab left",
    },
    {
      type = "button",
      id = "ctx-right",
      icon = "chevron_right",
      icon_size = 11,
      variant = "secondary",
      size = "xs",
      disabled = not can_right,
      tooltip = "Move tab right",
    },
    { type = "divider", orientation = "vertical", inset = 6, color = "divider" },
    {
      type = "button",
      id = "ctx-back",
      label = "Back",
      variant = "ghost",
      size = "xs",
      disabled = not can_back,
      tooltip = "Previous channel in this tab's history",
    },
    {
      type = "button",
      id = "ctx-fwd",
      label = "Fwd",
      variant = "ghost",
      size = "xs",
      disabled = not can_fwd,
      tooltip = "Next channel in this tab's history",
    },
    { type = "divider", orientation = "vertical", inset = 6, color = "divider" },
    {
      type = "button",
      id = "ctx-dup",
      label = "Duplicate",
      variant = "secondary",
      size = "xs",
      tooltip = "Open a copy of this tab",
    },
    {
      type = "button",
      id = "ctx-close-others",
      label = "Close Others",
      variant = "ghost",
      size = "xs",
      tooltip = "Close all other unpinned tabs",
    },
    {
      type = "button",
      id = "ctx-close-right",
      label = "Close Right",
      variant = "ghost",
      size = "xs",
      tooltip = "Close unpinned tabs to the right",
    },
    {
      type = "button",
      id = "ctx-close",
      label = "Close",
      variant = can_close and "danger" or "ghost",
      size = "xs",
      disabled = not can_close,
      tooltip = tab.pinned and "Unpin before closing" or "Close this tab",
    },
    { type = "spacer" },
    {
      type = "button",
      id = "ctx-dismiss",
      icon = "close",
      icon_size = 11,
      variant = "ghost",
      size = "xs",
      tooltip = "Dismiss",
    },
  }

  local is_bottom = (state.settings.slot == "bottom")
  return {
    type = "row",
    id = "ctx-root",
    cursor = "default",
    bg = "bg_secondary",
    border_color = "border_subtle",
    border_w = 1,
    border_sides = is_bottom and "top" or "bottom",
    pad_left = 8,
    pad_right = 6,
    gap = 4,
    align = "center",
    clip = true,
    children = children,
  }
end

local function build_settings_tree(state)
  local s = state.settings
  local closed_n = #state.closed
  local reopen_lbl = closed_n > 0 and ("Reopen (" .. tostring(closed_n) .. ")") or "Reopen"

  local children = {
    {
      type = "icon",
      name = "gear",
      size = 12,
      color = "text_muted",
    },
    {
      type = "text",
      text = "Tabs!",
      color = "text_header",
      size = 12,
      bold = true,
      ellipsis = false,
    },
    { type = "divider", orientation = "vertical", inset = 6, color = "divider" },
    {
      type = "button",
      id = "set-reopen",
      label = reopen_lbl,
      variant = "secondary",
      size = "xs",
      disabled = (closed_n == 0),
      tooltip = "Reopen the most recently closed tab",
    },
    {
      type = "button",
      id = "set-slot",
      label = "Bar: " .. slot_label(s.slot),
      variant = "secondary",
      size = "xs",
      tooltip = "Cycle tab bar placement (Top / Below Header / Bottom)",
    },
    {
      type = "button",
      id = "set-density",
      label = (s.density == "compact") and "Compact" or "Normal",
      variant = "secondary",
      size = "xs",
      selected = (s.density == "compact"),
      tooltip = "Toggle normal vs compact tab bar height",
    },
    {
      type = "button",
      id = "set-dedupe",
      label = s.dedupe_tabs and "Dedupe: On" or "Dedupe: Off",
      variant = s.dedupe_tabs and "primary" or "secondary",
      size = "xs",
      tooltip = "Jump to an existing tab instead of opening duplicates",
    },
    {
      type = "button",
      id = "set-protect-pin",
      label = s.protect_pinned and "Pin Lock: On" or "Pin Lock: Off",
      variant = s.protect_pinned and "primary" or "secondary",
      size = "xs",
      tooltip = "Prevent sidebar clicks from overwriting a pinned tab",
    },
    {
      type = "button",
      id = "set-aux-focus",
      label = s.aux_open_focus and "Mid-Click: Focus" or "Mid-Click: Bg",
      variant = "secondary",
      size = "xs",
      tooltip = "Whether middle-click / Ctrl+click switches to the new tab immediately",
    },
    {
      type = "button",
      id = "set-close-unpinned",
      label = "Close Unpinned",
      variant = "ghost",
      size = "xs",
      tooltip = "Close all unpinned tabs",
    },
    { type = "spacer" },
    {
      type = "button",
      id = "ctx-dismiss",
      icon = "close",
      icon_size = 11,
      variant = "ghost",
      size = "xs",
      tooltip = "Dismiss",
    },
  }

  local is_bottom = (s.slot == "bottom")
  return {
    type = "row",
    id = "ctx-root",
    cursor = "default",
    bg = "bg_secondary",
    border_color = "border_subtle",
    border_w = 1,
    border_sides = is_bottom and "top" or "bottom",
    pad_left = 8,
    pad_right = 6,
    gap = 4,
    align = "center",
    clip = true,
    children = children,
  }
end

function M.build_tree(state)
  if state.ctx_mode == "tab" then
    local tab = Model.find_tab(state, state.ctx_tab_id)
    if not tab then return nil end
    return build_tab_ctx_tree(state, tab)
  elseif state.ctx_mode == "settings" then
    return build_settings_tree(state)
  end
  return nil
end

function M.new(state, on_event)
  local self = {
    state = state,
    on_event = on_event,
    mounted = false,
    last_slot = nil,
    last_fingerprint = nil,
  }

  function self.sync()
    local root = M.build_tree(self.state)
    if not root then
      if self.mounted then
        pcall(ui.panel.unmount, C.PANEL_CTX_ID)
        self.mounted = false
        self.last_slot = nil
        self.last_fingerprint = nil
      end
      return
    end

    local slot = self.state.settings.slot
    local encoded = json.encode({ slot = slot, root = root })
    if self.mounted and encoded and encoded == self.last_fingerprint then
      return
    end

    if not self.mounted then
      ui.panel.mount({
        id = C.PANEL_CTX_ID,
        slot = slot,
        height = C.CTX_BAR_HEIGHT,
        root = root,
        on_event = self.on_event,
      })
      self.mounted = true
    else
      local patch = { root = root }
      if slot ~= self.last_slot then patch.slot = slot end
      ui.panel.update(C.PANEL_CTX_ID, patch)
    end
    self.last_slot = slot
    self.last_fingerprint = encoded
  end

  function self.unmount()
    if self.mounted then
      pcall(ui.panel.unmount, C.PANEL_CTX_ID)
      self.mounted = false
      self.last_slot = nil
      self.last_fingerprint = nil
    end
  end

  return self
end

return M
