-- Offline Lua 5.5 verification suite for Tabs! (mirrors C-Cord's sandbox.c, manifest.c, and plugin_panels.c).
-- Run with: lua5.5 tests/run_tests.lua

local passed = 0
local failed = 0

local function assert_eq(actual, expected, msg)
  if actual ~= expected then
    error((msg or "assert_eq failed") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual), 2)
  end
end

local function assert_true(cond, msg)
  if not cond then
    error(msg or "assert_true failed", 2)
  end
end

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
    io.write("[PASS] " .. name .. "\n")
  else
    failed = failed + 1
    io.write("[FAIL] " .. name .. "\n  " .. tostring(err) .. "\n")
  end
end

-- Exact allowlists from C-Cord src/theme/theme.h and src/ui/plugin_panels.c
local VALID_THEME_TOKENS = {
  bg_primary = true, bg_secondary = true, bg_tertiary = true, bg_floating = true, bg_input = true,
  bg_user_panel = true, bg_message_hover = true, bg_item_hover = true, bg_item_selected = true,
  bg_guild_idle = true, divider = true, border_subtle = true, scrollbar_thumb = true, scrollbar_track = true,
  text_normal = true, text_muted = true, text_header = true, text_secondary = true, text_link = true,
  text_on_brand = true, text_placeholder = true, text_interactive_hover = true, text_interactive_active = true,
  brand = true, brand_hover = true, status_online = true, status_idle = true, status_dnd = true,
  status_offline = true, danger = true, mention_bg = true, selection = true, caret = true, pill = true,
  overlay = true, avatar_0 = true, avatar_1 = true, avatar_2 = true, avatar_3 = true, avatar_4 = true,
  avatar_5 = true,
  -- aliases in plugin_panels.c
  text_primary = true, bg_hover = true, bg_selected = true, border = true,
  online = true, idle = true, dnd = true, offline = true,
}

local VALID_ICONS = {
  hash = true, speaker = true, voice = true, gear = true, settings = true,
  chevron_up = true, chevron_down = true, chevron_left = true, chevron_right = true,
  close = true, x = true, members = true, friends = true, mic = true, mic_muted = true,
  headphones = true, headphones_deafened = true, camera = true, screen = true,
  disconnect = true, search = true, pin = true, reply = true, edit = true,
  attachment = true, file = true, forum = true, user = true, profile = true,
  inbox = true, folder = true, plus = true, add = true, compass = true,
  discover = true, at = true, dm = true,
}

local VALID_PERMS = {
  ["events.navigation"] = true, ["ui.contextMenu"] = true, ["clipboard.write"] = true,
  ["storage"] = true, ["commands"] = true,
  ["events.messages"] = true, ["events.presence"] = true, ["events.voice"] = true,
  ["events.channels"] = true, ["store.read"] = true, ["messages.send"] = true,
  ["messages.manage"] = true, ["messages.hook"] = true, ["presence.write"] = true,
  ["navigation.write"] = true, ["voice.control"] = true, ["ui.panel"] = true,
  ["ui.composer"] = true, ["clipboard.read"] = true, ["gateway.raw"] = true,
  ["fs.read"] = true, ["fs.write"] = true, ["fs.watch"] = true, ["network.http"] = true,
  ["system.notify"] = true, ["system.open"] = true, ["system.info"] = true, ["system.exec"] = true,
}

-- Minimal deterministic JSON encoder for mock json.encode
local function json_escape(s)
  return '"' .. s:gsub('[\\"\b\f\n\r\t]', {
    ['\\'] = '\\\\', ['"'] = '\\"', ['\b'] = '\\b', ['\f'] = '\\f',
    ['\n'] = '\\n', ['\r'] = '\\r', ['\t'] = '\\t',
  }) .. '"'
end

local function mock_json_encode(val)
  local t = type(val)
  if t == "nil" then return "null" end
  if t == "boolean" then return val and "true" or "false" end
  if t == "number" then return tostring(val) end
  if t == "string" then return json_escape(val) end
  if t == "table" then
    local n = #val
    if n > 0 then
      local parts = {}
      for i = 1, n do parts[i] = mock_json_encode(val[i]) end
      return "[" .. table.concat(parts, ",") .. "]"
    end
    local keys = {}
    for k in pairs(val) do
      if type(k) == "string" then keys[#keys + 1] = k end
    end
    table.sort(keys)
    local parts = {}
    for _, k in ipairs(keys) do
      parts[#parts + 1] = json_escape(k) .. ":" .. mock_json_encode(val[k])
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return nil, "unsupported type"
end

-- Build a strict C-Cord Lua 5.5 sandbox environment
local function create_harness(initial_storage, initial_store)
  local now = 1000000
  local uuid_seq = 0
  local timer_seq = 0
  local timers = {}
  local storage_data = {}
  if initial_storage then
    for k, v in pairs(initial_storage) do storage_data[k] = v end
  end

  local store_state = initial_store or {
    selected = { guild_id = "100", channel_id = "200", view = "channel", is_dm = false },
    guilds = {
      ["100"] = { id = "100", name = "Dev Server", is_dm = false, muted = false },
      ["101"] = { id = "101", name = "Design Hub", is_dm = false, muted = false },
      ["dm"]  = { id = "18446744073709551615", name = "Direct Messages", is_dm = true, muted = false },
    },
    channels = {
      ["200"] = { id = "200", guild_id = "100", name = "general", display_name = "general", kind = "text", unread_count = 0, mention_count = 0, muted = false },
      ["201"] = { id = "201", guild_id = "100", name = "dev", display_name = "dev", kind = "text", unread_count = 3, mention_count = 1, muted = false },
      ["202"] = { id = "202", guild_id = "100", name = "announcements", display_name = "announcements", kind = "text", unread_count = 5, mention_count = 0, muted = true },
      ["203"] = { id = "203", guild_id = "100", name = "help-forum", display_name = "help-forum", kind = "forum", unread_count = 0, mention_count = 0, muted = false },
      ["204"] = { id = "204", guild_id = "100", parent_id = "203", name = "Tab Bug", display_name = "Tab Bug", kind = "thread", unread_count = 1, mention_count = 0, muted = false },
      ["300"] = { id = "300", guild_id = "101", name = "showcase", display_name = "showcase", kind = "text", unread_count = 0, mention_count = 0, muted = false },
      ["400"] = { id = "400", guild_id = "18446744073709551615", name = "", display_name = "Alice", kind = "dm", unread_count = 0, mention_count = 2, muted = false, is_dm = true },
      ["401"] = { id = "401", guild_id = "18446744073709551615", name = "AFPAC gets CANCELLED PART 2", display_name = "AFPAC gets CANCELLED PART 2", kind = "group_dm", unread_count = 2, mention_count = 0, muted = false, is_dm = true },
      ["500"] = { id = "500", guild_id = "100", name = "Text Channels", display_name = "Text Channels", kind = "category", unread_count = 0, mention_count = 0, muted = false },
    },
  }

  local panels = {}
  local menus = {}
  local cmds = {}
  local handlers = {}
  local nav_calls = {}
  local toasts = {}
  local logs = {}
  local modules = {}

  local function ro(tbl)
    return setmetatable({}, {
      __index = tbl,
      __newindex = function() error("plugin API tables are read-only") end,
    })
  end

  local env
  local function sandbox_require(mod)
    if modules[mod] ~= nil then return modules[mod] end
    local path = mod:gsub("%.", "/") .. ".lua"
    local f, err = io.open(path, "rb")
    if not f then error("require: module '" .. mod .. "' not found (" .. tostring(err) .. ")") end
    local src = f:read("*a")
    f:close()
    local chunk, lerr = load(src, "=" .. path, "t", env)
    if not chunk then error(lerr) end
    local res = chunk()
    if res == nil then res = true end
    modules[mod] = res
    return res
  end

  local function resolve_gid(g)
    if g == "dm" or g == "18446744073709551615" or g == "1" then return "dm" end
    return tostring(g)
  end

  env = {
    -- Lua 5.5 safe base subset (matching sandbox.c open_all)
    assert = assert, error = error, ipairs = ipairs, next = next, pairs = pairs,
    pcall = pcall, rawequal = rawequal, rawget = rawget, rawlen = rawlen, rawset = rawset,
    select = select, setmetatable = setmetatable, getmetatable = getmetatable,
    tonumber = tonumber, tostring = tostring, type = type, xpcall = xpcall, _VERSION = _VERSION,
    table = table, math = math, utf8 = utf8, coroutine = coroutine,
    string = {
      byte = string.byte, char = string.char, find = string.find, format = string.format,
      gmatch = string.gmatch, gsub = string.gsub, len = string.len, lower = string.lower,
      match = string.match, pack = string.pack, packsize = string.packsize, rep = string.rep,
      reverse = string.reverse, sub = string.sub, unpack = string.unpack, upper = string.upper,
    },
    require = sandbox_require,
    plugin = ro({ id = "io.github.32bitx64bit.tabs", name = "Tabs!", version = "1.0.0", dir = "." }),
    log = ro({
      debug = function(m) logs[#logs + 1] = { level = "debug", msg = m } end,
      info  = function(m) logs[#logs + 1] = { level = "info",  msg = m } end,
      warn  = function(m) logs[#logs + 1] = { level = "warn",  msg = m } end,
      error = function(m) logs[#logs + 1] = { level = "error", msg = m } end,
    }),
    json = ro({ encode = mock_json_encode }),
    crypto = ro({
      uuid = function()
        uuid_seq = uuid_seq + 1
        return string.format("%08x-0000-4000-8000-000000000000", uuid_seq)
      end,
    }),
    time = ro({
      now_ms = function() return now end,
      after = function(ms, fn)
        timer_seq = timer_seq + 1
        timers[timer_seq] = { fire_at = now + ms, interval = 0, fn = fn, cancelled = false }
        return timer_seq
      end,
      every = function(ms, fn)
        timer_seq = timer_seq + 1
        timers[timer_seq] = { fire_at = now + ms, interval = ms, fn = fn, cancelled = false }
        return timer_seq
      end,
      cancel = function(id)
        if timers[id] then timers[id].cancelled = true; return true end
        return false
      end,
    }),
    storage = ro({
      get = function(k) return storage_data[k] end,
      set = function(k, v)
        assert_true(mock_json_encode(v) ~= nil, "storage value must be JSON serializable")
        storage_data[k] = v
      end,
      delete = function(k) storage_data[k] = nil end,
      clear = function() storage_data = {} end,
      keys = function()
        local out = {}
        for k in pairs(storage_data) do out[#out + 1] = k end
        return out
      end,
    }),
    events = ro({
      on = function(name, fn)
        handlers[name] = handlers[name] or {}
        handlers[name][#handlers[name] + 1] = fn
        return true
      end,
      off = function(name) handlers[name] = nil end,
    }),
    commands = ro({
      register = function(name, desc, fn)
        assert_true(name:match("^[a-z][a-z0-9_-]*$") ~= nil and #name <= 32, "invalid command name")
        assert_true(#desc >= 1 and #desc <= 100, "command description must be 1..100 bytes, got " .. #desc)
        assert_true(cmds[name] == nil, "duplicate command")
        cmds[name] = { desc = desc, fn = fn }
      end,
    }),
    ui = ro({
      toast = ro({
        show = function(text, lvl) toasts[#toasts + 1] = { text = text, level = lvl or "info" } end,
      }),
      contextMenu = ro({
        add = function(spec)
          assert_true(spec.id:match("^[a-z0-9][a-z0-9_-]*$") ~= nil and #spec.id <= 32, "invalid menu id")
          assert_true(#spec.label >= 1 and #spec.label <= 64, "invalid menu label")
          assert_true(menus[spec.id] == nil, "duplicate menu id")
          menus[spec.id] = spec
        end,
        remove = function(id) menus[id] = nil end,
      }),
      panel = ro({
        mount = function(spec)
          assert_true(spec.id:match("^[a-z0-9][a-z0-9_-]*$") ~= nil and #spec.id <= 32, "invalid panel id")
          assert_true(spec.height >= 12 and spec.height <= 240, "invalid panel height")
          assert_true(type(spec.root) == "table", "panel root must be table")
          panels[spec.id] = {
            id = spec.id, slot = spec.slot or "top", height = spec.height or 34,
            root = spec.root, on_event = spec.on_event, updates = 0,
          }
          return true
        end,
        update = function(id, patch)
          local p = assert(panels[id], "panel.update on unmounted panel: " .. tostring(id))
          if type(patch.type) == "string" and not patch.root then
            p.root = patch
          else
            if patch.slot then p.slot = patch.slot end
            if patch.height then
              assert_true(patch.height >= 12 and patch.height <= 240, "invalid panel height")
              p.height = patch.height
            end
            if patch.root then p.root = patch.root end
            if patch.on_event then p.on_event = patch.on_event end
          end
          p.updates = p.updates + 1
          return true
        end,
        unmount = function(id)
          panels[id] = nil
          return true
        end,
      }),
    }),
    store = ro({
      selected = function() return store_state.selected end,
      guild = function(id) return store_state.guilds[resolve_gid(id)] end,
      channel = function(id) return store_state.channels[tostring(id)] end,
      channels = function(gid)
        local key = resolve_gid(gid)
        local out = {}
        for _, ch in pairs(store_state.channels) do
          if resolve_gid(ch.guild_id) == key then out[#out + 1] = ch end
        end
        table.sort(out, function(a, b) return a.id < b.id end)
        return out
      end,
    }),
    navigation = ro({
      select_guild = function(gid) nav_calls[#nav_calls + 1] = { fn = "select_guild", guild_id = gid } end,
      select_channel = function(cid, opts) nav_calls[#nav_calls + 1] = { fn = "select_channel", channel_id = cid, opts = opts } end,
      select_view = function(view) nav_calls[#nav_calls + 1] = { fn = "select_view", view = view } end,
      action = function(act) nav_calls[#nav_calls + 1] = { fn = "action", action = act } end,
      open_quick_switcher = function() nav_calls[#nav_calls + 1] = { fn = "open_quick_switcher" } end,
    }),
  }

  local h = {
    env = env,
    panels = panels,
    menus = menus,
    cmds = cmds,
    nav_calls = nav_calls,
    toasts = toasts,
    logs = logs,
    storage_data = storage_data,
    store_state = store_state,
    require = sandbox_require,
  }

  function h.load_main()
    local f = assert(io.open("main.lua", "rb"))
    local src = f:read("*a")
    f:close()
    local chunk = assert(load(src, "=main.lua", "t", env))
    chunk()
  end

  function h.advance_ms(delta)
    now = now + delta
    local fired = true
    while fired do
      fired = false
      for id, t in pairs(timers) do
        if not t.cancelled and now >= t.fire_at then
          fired = true
          if t.interval > 0 then
            t.fire_at = now + t.interval
          else
            t.cancelled = true
          end
          t.fn()
        end
      end
    end
  end

  function h.emit(name, payload)
    local list = handlers[name]
    if not list then return end
    for _, fn in ipairs(list) do fn(payload) end
  end

  function h.panel_event(panel_id, ev)
    local p = assert(panels[panel_id], "panel not mounted: " .. tostring(panel_id))
    assert(p.on_event, "panel has no on_event")
    p.on_event(ev)
    h.advance_ms(1)
  end

  return h
end

-- Strict recursive validator matching src/ui/plugin_panels.c limits & theme compliance
local function validate_panel_tree(root, label)
  assert_true(type(root) == "table", label .. ": root must be a table")
  assert_true(type(root.id) == "string" and #root.id > 0, label .. ": root must carry an id for C-Cord wheel capture")

  local stats = { nodes = 0, hits = 0, max_depth = 0, max_children = 0 }

  local function check_color(field, val)
    if val == nil then return end
    assert_true(type(val) == "string", label .. ": color " .. field .. " must be string")
    assert_true(val:sub(1, 1) ~= "#", label .. ": HARDCODED HEX COLOR FORBIDDEN (" .. field .. "=" .. val .. ")")
    assert_true(VALID_THEME_TOKENS[val] == true, label .. ": unknown C-Cord theme token (" .. field .. "=" .. val .. ")")
  end

  local function walk(nd, depth)
    stats.nodes = stats.nodes + 1
    if depth > stats.max_depth then stats.max_depth = depth end
    assert_true(depth <= 24, label .. ": depth exceeded PANEL_MAX_DEPTH (24)")
    assert_true(stats.nodes <= 512, label .. ": node count exceeded PANEL_MAX_NODES (512)")

    if nd.id ~= nil then
      assert_true(type(nd.id) == "string" and #nd.id <= 64, label .. ": node id exceeds 64 bytes: " .. tostring(nd.id))
      if not nd.disabled then
        stats.hits = stats.hits + 1
        assert_true(stats.hits <= 256, label .. ": hit count exceeded PANEL_MAX_HITS (256)")
      end
    end
    if nd.tooltip ~= nil then
      assert_true(type(nd.tooltip) == "string" and #nd.tooltip <= 127, label .. ": tooltip exceeds 127 bytes (" .. #nd.tooltip .. ")")
    end

    check_color("bg", nd.bg)
    check_color("hover_bg", nd.hover_bg)
    check_color("border_color", nd.border_color)
    check_color("hover_border_color", nd.hover_border_color)
    check_color("color", nd.color)
    check_color("hover_color", nd.hover_color)

    if nd.type == "icon" then
      local ic = nd.name or nd.icon
      assert_true(VALID_ICONS[ic] == true, label .. ": unknown icon '" .. tostring(ic) .. "'")
    elseif nd.type == "button" and nd.icon then
      assert_true(VALID_ICONS[nd.icon] == true, label .. ": unknown button icon '" .. tostring(nd.icon) .. "'")
    end

    if nd.children ~= nil then
      assert_true(type(nd.children) == "table" and #nd.children > 0, label .. ": empty children table must be omitted")
      if #nd.children > stats.max_children then stats.max_children = #nd.children end
      assert_true(#nd.children <= 64, label .. ": children count exceeds 64 per box")
      for _, child in ipairs(nd.children) do
        walk(child, depth + 1)
      end
    end
  end

  walk(root, 0)
  return stats
end

-- ========================================================================= Tests

test("Manifest strictly complies with C-Cord src/plugins/manifest.c", function()
  local f = assert(io.open("plugin.json", "rb"))
  local raw = f:read("*a")
  f:close()
  assert_true(#raw > 0 and #raw <= 16384, "manifest size out of range")

  local id = raw:match('"id"%s*:%s*"([^"]+)"')
  local name = raw:match('"name"%s*:%s*"([^"]+)"')
  local version = raw:match('"version"%s*:%s*"([^"]+)"')
  local main_f = raw:match('"main"%s*:%s*"([^"]+)"')
  local desc = raw:match('"description"%s*:%s*"([^"]+)"')
  local schema = raw:match('"schema"%s*:%s*(%d+)')
  local api = raw:match('"api"%s*:%s*(%d+)')

  assert_eq(schema, "1", "schema must be 1")
  assert_eq(api, "1", "api must be 1")
  assert_true(id and id:match("^[a-z0-9][a-z0-9._-]*$") and #id <= 64 and not id:find("%.%."), "invalid id")
  assert_true(name and #name >= 1 and #name <= 64, "invalid name")
  assert_true(version and version:match("^%d+%.%d+%.%d+$"), "invalid semver version")
  assert_eq(main_f, "main.lua", "main entry")
  assert_true(desc and #desc <= 200, "description too long")

  local perms_block = assert(raw:match('"permissions"%s*:%s*%[(.-)%]'), "permissions array missing")
  local seen = {}
  for p in perms_block:gmatch('"([^"]+)"') do
    assert_true(VALID_PERMS[p], "unknown permission: " .. p)
    assert_true(not seen[p], "duplicate permission: " .. p)
    seen[p] = true
  end
  assert_true(seen["ui.panel"] and seen["navigation.write"] and seen["store.read"], "core perms missing")
end)

test("Cold boot mounts theme-native tabs-bar and hydrates active channel", function()
  local h = create_harness()
  h.load_main()

  local bar = assert(h.panels["tabs-bar"], "tabs-bar should mount immediately")
  assert_eq(bar.slot, "top", "default slot should be top")
  assert_eq(bar.height, 36, "default height should be 36")
  validate_panel_tree(bar.root, "initial-bar")

  assert_true(h.menus["tabs-open-channel"] ~= nil, "channel context menu registered")
  assert_true(h.menus["tabs-open-guild"] ~= nil, "guild context menu registered")
  assert_true(h.menus["tabs-open-nav"] ~= nil, "nav context menu registered")
  assert_true(h.cmds["tabs"] ~= nil, "/tabs command registered")
end)

test("Aux-open (middle-click) opens channels, threads, guilds, Friends/Requests in background tabs", function()
  local h = create_harness()
  h.load_main()

  -- Middle-click #dev, thread Tab Bug, guild Design Hub, Friends, and Requests
  h.emit("navigation.aux_open", { guild_id = "100", channel_id = "201", view = "channel", name = "dev" })
  h.emit("navigation.aux_open", { guild_id = "100", channel_id = "204", parent_id = "203", view = "thread", name = "Tab Bug" })
  h.emit("navigation.aux_open", { guild_id = "101", view = "guild" })
  h.emit("navigation.aux_open", { guild_id = "18446744073709551615", view = "friends" })
  h.emit("navigation.aux_open", { guild_id = "18446744073709551615", view = "requests" })
  h.advance_ms(10)

  -- None of the background aux_opens should have hijacked client navigation
  assert_eq(#h.nav_calls, 0, "background aux_open should not navigate away")
  validate_panel_tree(h.panels["tabs-bar"].root, "multi-aux-bar")

  -- Persist debounce fires after 300ms and saves all 6 tabs
  h.advance_ms(350)
  local saved = assert(h.storage_data["state_v1"], "state should persist")
  assert_eq(#saved.tabs, 6, "should have 6 open tabs")
end)

test("Navigation reconciliation suppresses intermediate guild.select without clobbering tabs", function()
  local h = create_harness()
  h.load_main()

  -- Open #showcase (guild 101) in background, then click it
  h.emit("navigation.aux_open", { guild_id = "101", channel_id = "300", view = "channel" })
  h.advance_ms(350)
  local tab_showcase = h.storage_data["state_v1"].tabs[2]
  assert_eq(tab_showcase.channel_id, "300")

  -- Click tab #showcase
  h.panel_event("tabs-bar", { type = "click", id = "t:" .. tab_showcase.id, button = 1, mods = {} })
  assert_eq(#h.nav_calls, 1)
  assert_eq(h.nav_calls[1].fn, "select_channel")
  assert_eq(h.nav_calls[1].channel_id, "300")

  -- Simulate C-Cord emitting guild.select(101) then channel.select(300)
  h.emit("guild.select", { guild_id = "101", name = "Design Hub", is_dm = false })
  h.emit("channel.select", { guild_id = "101", channel_id = "300", name = "showcase", display_name = "showcase", kind = "text" })
  h.advance_ms(350)

  local saved = h.storage_data["state_v1"]
  assert_eq(saved.active_id, tab_showcase.id, "active tab should stay #showcase")
  assert_eq(saved.tabs[1].channel_id, "200", "Tab 1 (#general) must not be clobbered")
  assert_eq(saved.tabs[2].channel_id, "300", "Tab 2 (#showcase) must remain intact")
end)

test("Pinned tab protection prevents sidebar navigation from overwriting a pinned tab", function()
  local h = create_harness()
  h.load_main()
  h.advance_ms(350)

  local tab1 = h.storage_data["state_v1"].tabs[1]
  -- Double-click Tab 1 to pin it
  h.panel_event("tabs-bar", { type = "double_click", id = "t:" .. tab1.id, button = 1, mods = {} })
  h.advance_ms(350)
  assert_eq(h.storage_data["state_v1"].tabs[1].pinned, true, "Tab 1 should be pinned")

  -- Verify pinned tab renders a pin icon (instead of #) alongside its full title
  local pinned_zone = h.panels["tabs-bar"].root.children[1]
  local pinned_tab_node = pinned_zone.children[1]
  assert_eq(pinned_tab_node.id, "t:" .. tab1.id)
  local saw_pin_icon, saw_full_title = false, false
  for _, child in ipairs(pinned_tab_node.children) do
    if child.type == "icon" then
      assert_eq(child.name, "pin", "pinned tab should show pin icon instead of channel icon")
      saw_pin_icon = true
    elseif child.type == "text" then
      assert_eq(child.text, "general", "pinned tab should display full title")
      assert_eq(child.ellipsis, false, "pinned tab title should not truncate")
      saw_full_title = true
    end
  end
  assert_true(saw_pin_icon and saw_full_title, "pinned tab must render both pin icon and full title")

  -- User clicks #dev in C-Cord's sidebar while pinned Tab 1 is active
  h.emit("channel.select", { guild_id = "100", channel_id = "201", name = "dev", display_name = "dev", kind = "text" })
  h.advance_ms(350)

  local saved = h.storage_data["state_v1"]
  assert_eq(#saved.tabs, 2, "should open a new unpinned tab instead of overwriting pinned tab")
  assert_eq(saved.tabs[1].channel_id, "200", "pinned tab remains #general")
  assert_eq(saved.tabs[1].pinned, true)
  assert_eq(saved.tabs[2].channel_id, "201", "new unpinned tab has #dev")
  assert_eq(saved.active_id, saved.tabs[2].id, "new unpinned tab becomes active")

  -- Middle-clicking pinned tab must NOT close it
  h.panel_event("tabs-bar", { type = "middle_click", id = "t:" .. tab1.id, button = 2, mods = {} })
  h.advance_ms(350)
  assert_eq(#h.storage_data["state_v1"].tabs, 2, "pinned tab cannot be accidentally middle-click closed")
end)

test("Right-click context shelf & settings shelf mount, act, switch slots live, and unmount cleanly", function()
  local h = create_harness()
  h.load_main()
  h.emit("navigation.aux_open", { guild_id = "100", channel_id = "201", view = "channel" })
  h.advance_ms(350)

  local tab2_id = h.storage_data["state_v1"].tabs[2].id
  -- Right-click tab 2 -> mounts tabs-ctx in Tab Context Mode
  h.panel_event("tabs-bar", { type = "right_click", id = "t:" .. tab2_id, button = 3, mods = {} })
  assert_true(h.panels["tabs-ctx"] ~= nil, "tabs-ctx should mount on tab right-click")
  validate_panel_tree(h.panels["tabs-ctx"].root, "tab-ctx-shelf")

  -- Duplicate tab 2 via context shelf -> auto-dismisses shelf
  h.panel_event("tabs-ctx", { type = "click", id = "ctx-dup", button = 1, mods = {} })
  assert_true(h.panels["tabs-ctx"] == nil, "tabs-ctx should unmount after duplicate")
  h.advance_ms(350)
  assert_eq(#h.storage_data["state_v1"].tabs, 3, "should now have 3 tabs")

  -- Click gear button -> mounts tabs-ctx in Settings Mode
  h.panel_event("tabs-bar", { type = "click", id = "act-menu", button = 1, mods = {} })
  assert_true(h.panels["tabs-ctx"] ~= nil, "settings shelf should mount")
  validate_panel_tree(h.panels["tabs-ctx"].root, "settings-shelf")

  -- Cycle slot top -> subheader -> bottom -> top, validating every slot's tree!
  h.panel_event("tabs-ctx", { type = "click", id = "set-slot", button = 1, mods = {} })
  assert_eq(h.panels["tabs-bar"].slot, "subheader")
  assert_eq(h.panels["tabs-ctx"].slot, "subheader")
  validate_panel_tree(h.panels["tabs-bar"].root, "subheader-bar")

  h.panel_event("tabs-ctx", { type = "click", id = "set-slot", button = 1, mods = {} })
  assert_eq(h.panels["tabs-bar"].slot, "bottom")
  assert_eq(h.panels["tabs-ctx"].slot, "bottom")
  validate_panel_tree(h.panels["tabs-bar"].root, "bottom-bar")
  validate_panel_tree(h.panels["tabs-ctx"].root, "bottom-ctx")

  -- Toggle compact mode
  h.panel_event("tabs-ctx", { type = "click", id = "set-density", button = 1, mods = {} })
  assert_eq(h.panels["tabs-bar"].height, 30, "compact height should be 30")
  validate_panel_tree(h.panels["tabs-bar"].root, "compact-bottom-bar")

  -- Dismiss shelf
  h.panel_event("tabs-ctx", { type = "click", id = "ctx-dismiss", button = 1, mods = {} })
  assert_true(h.panels["tabs-ctx"] == nil, "shelf should unmount on dismiss")
end)

test("Close, Reopen Closed, Back/Forward history, and channel.delete cleanup", function()
  local h = create_harness()
  h.load_main()
  -- Navigate within Tab 1: #general -> #dev -> Alice DM
  h.emit("channel.select", { guild_id = "100", channel_id = "201", name = "dev", display_name = "dev", kind = "text" })
  h.emit("channel.select", { guild_id = "18446744073709551615", channel_id = "400", name = "", display_name = "Alice", kind = "dm" })
  h.advance_ms(350)

  -- /tabs back -> returns to #dev
  h.cmds["tabs"].fn("back")
  assert_eq(h.nav_calls[#h.nav_calls].channel_id, "201", "history back should navigate to #dev")
  h.advance_ms(700)

  -- /tabs fwd -> returns to Alice DM
  h.cmds["tabs"].fn("fwd")
  assert_eq(h.nav_calls[#h.nav_calls].channel_id, "400", "history forward should navigate to Alice DM")
  h.advance_ms(700)

  -- Open #showcase, then close it, then reopen via right-click '+'
  h.emit("navigation.aux_open", { guild_id = "101", channel_id = "300", view = "channel" })
  h.advance_ms(350)
  local t2 = h.storage_data["state_v1"].tabs[2].id
  h.panel_event("tabs-bar", { type = "click", id = "x:" .. t2, button = 1, mods = {} })
  h.advance_ms(350)
  assert_eq(#h.storage_data["state_v1"].tabs, 1)
  assert_eq(#h.storage_data["state_v1"].closed, 1)

  h.panel_event("tabs-bar", { type = "right_click", id = "act-new", button = 3, mods = {} })
  h.advance_ms(350)
  assert_eq(#h.storage_data["state_v1"].tabs, 2, "reopen should restore closed tab")
  assert_eq(h.storage_data["state_v1"].tabs[2].channel_id, "300")

  -- Simulate channel deletion of #showcase -> tab auto-closes
  h.emit("channel.delete", { guild_id = "101", channel_id = "300" })
  h.advance_ms(350)
  assert_eq(#h.storage_data["state_v1"].tabs, 1, "deleted channel tab should close cleanly")
end)

test("Live message.create badge updates and app.quit immediate storage flush", function()
  local h = create_harness()
  h.load_main()
  h.emit("navigation.aux_open", { guild_id = "100", channel_id = "201", view = "channel" })
  h.advance_ms(10)

  -- Increase mentions in #dev and emit message.create
  h.store_state.channels["201"].mention_count = 7
  local updates_before = h.panels["tabs-bar"].updates
  h.emit("message.create", { channel_id = "201", guild_id = "100", author_id = "99", content = "ping" })
  h.advance_ms(10)
  assert_true(h.panels["tabs-bar"].updates > updates_before, "message.create on open background tab should trigger rerender")
  validate_panel_tree(h.panels["tabs-bar"].root, "badge-updated-bar")

  -- app.quit must flush pending dirty state immediately without waiting 300ms
  h.emit("navigation.aux_open", { guild_id = "100", channel_id = "202", view = "channel" })
  h.emit("app.quit", {})
  assert_eq(#h.storage_data["state_v1"].tabs, 3, "app.quit should immediately flush dirty state")
end)

test("Stress test: 50 tabs (15 pinned + 35 unpinned) stay strictly within C-Cord engine budgets and zero hex colors", function()
  local h = create_harness()
  local Model = h.require("tabs.model")
  local Renderer = h.require("tabs.renderer")
  local ContextBar = h.require("tabs.context_bar")

  local st = Model.new_state(nil)
  for i = 1, 50 do
    local long_name = "very-long-channel-name-with-unicode-日本語-🚀-" .. tostring(i)
    Model.open_tab(st, {
      kind = (i % 5 == 0) and "dm" or ((i % 4 == 0) and "thread" or "text"),
      guild_id = (i % 5 == 0) and "dm" or "100",
      channel_id = tostring(1000 + i),
      parent_id = (i % 4 == 0) and "203" or nil,
      label = long_name,
      guild_name = "Super Long Server Name That Tests Tooltip Truncation Safely",
      unread_count = (i % 3 == 0) and 4 or 0,
      mention_count = (i % 7 == 0) and 150 or 0,
      muted = (i % 6 == 0),
    }, { pinned = (i <= 15), activate = (i == 20) })
  end

  for _, slot in ipairs({ "top", "subheader", "bottom" }) do
    for _, density in ipairs({ "normal", "compact" }) do
      st.settings.slot = slot
      st.settings.density = density
      local bar_stats = validate_panel_tree(Renderer.build_tree(st), "stress-bar-" .. slot .. "-" .. density)
      assert_true(bar_stats.nodes <= 300, "node budget should retain generous headroom, got " .. bar_stats.nodes)
      assert_true(bar_stats.hits <= 100, "hit budget should retain generous headroom, got " .. bar_stats.hits)

      st.ctx_mode = "tab"
      st.ctx_tab_id = st.active_id
      validate_panel_tree(ContextBar.build_tree(st), "stress-ctx-tab-" .. slot)

      st.ctx_mode = "settings"
      validate_panel_tree(ContextBar.build_tree(st), "stress-ctx-set-" .. slot)
    end
  end
end)

test("Rapid tab clicking suppresses stale earlier channel.select echoes", function()
  local h = create_harness()
  h.load_main()
  h.emit("navigation.aux_open", { guild_id = "100", channel_id = "201", view = "channel" })
  h.emit("navigation.aux_open", { guild_id = "101", channel_id = "300", view = "channel" })
  h.advance_ms(350)
  local tabs = h.storage_data["state_v1"].tabs
  local tab_b, tab_c = tabs[2], tabs[3]

  -- Click Tab B then 20ms later click Tab C before Tab B's echo arrives
  h.panel_event("tabs-bar", { type = "click", id = "t:" .. tab_b.id, button = 1, mods = {} })
  h.advance_ms(20)
  h.panel_event("tabs-bar", { type = "click", id = "t:" .. tab_c.id, button = 1, mods = {} })

  -- Stale echo from Tab B arrives first, followed by Tab C's real confirmation
  h.emit("channel.select", { guild_id = "100", channel_id = "201", name = "dev", display_name = "dev", kind = "text" })
  h.emit("channel.select", { guild_id = "101", channel_id = "300", name = "showcase", display_name = "showcase", kind = "text" })
  h.advance_ms(350)

  local saved = h.storage_data["state_v1"]
  assert_eq(saved.active_id, tab_c.id, "Tab C must stay active")
  assert_eq(saved.tabs[2].channel_id, "201", "Tab B must remain #dev")
  assert_eq(saved.tabs[3].channel_id, "300", "Tab C must NOT be overwritten with #dev")
end)

test("Cold boot before Discord READY replaces placeholder cleanly on guilds.loaded", function()
  local empty_store = {
    selected = { guild_id = "0", channel_id = "0", view = "channel", is_dm = false },
    guilds = {},
    channels = {},
  }
  local h = create_harness(nil, empty_store)
  h.load_main()

  -- Now Discord finishes loading and selects #general
  h.store_state.guilds["100"] = { id = "100", name = "Dev Server", is_dm = false, muted = false }
  h.store_state.channels["200"] = { id = "200", guild_id = "100", name = "general", display_name = "general", kind = "text", unread_count = 0, mention_count = 0, muted = false }
  h.store_state.selected = { guild_id = "100", channel_id = "200", view = "channel", is_dm = false }

  h.emit("guilds.loaded", { value = 1 })
  h.advance_ms(350)
  local saved = h.storage_data["state_v1"]
  assert_eq(#saved.tabs, 1, "should replace placeholder without leaving a phantom Friends tab")
  assert_eq(saved.tabs[1].channel_id, "200")
end)

test("Category channel context menu is safely rejected and malformed UTF-8 tooltips never crash", function()
  local h = create_harness()
  h.load_main()
  h.advance_ms(350)

  -- Right-click "Open in New Tab" on category channel 500
  h.menus["tabs-open-channel"].action({ kind = "channel", guild_id = "100", channel_id = "500" })
  h.advance_ms(350)
  assert_eq(#h.storage_data["state_v1"].tabs, 1, "category should not open a tab")
  assert_true(#h.toasts >= 1, "should inform user with toast")

  -- Malformed UTF-8 truncation check
  local C = h.require("tabs.constants")
  local bad = string.rep("\255\254abc", 40)
  local clamped = C.clamp_utf8(bad, 120)
  assert_true(#clamped <= 120, "clamped string must fit within 120 bytes")
end)

io.write(string.format("\nSummary: %d passed, %d failed\n", passed, failed))
if failed > 0 then os.exit(1) end
