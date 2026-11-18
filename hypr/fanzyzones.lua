-- fanzyzones.lua: FancyZones-style window zones for Hyprland 0.55 (Lua config).
--
-- A port of Ben's KWin script "fanzyzones" (~/src/fanzyzones-kde). Load it from
-- hyprland.lua:
--
--     local fz = dofile(os.getenv("HOME") .. "/src/hearth/hypr/fanzyzones.lua")
--     fz.setup()                                   -- layout, events, drag tracking
--     fz.bind_keys()                               -- the KWin script's shortcuts
--     hl.config({ general = { layout = "lua:fanzyzones" } })
--
-- What it does:
--   * Registers a tiled layout "lua:fanzyzones". Every tiled window on a
--     workspace using it lives in one zone of the layout picked for that
--     monitor. New windows go to the next empty zone (or the least-crowded
--     one), and several windows may share a zone (they overlap, as in
--     FancyZones).
--   * Drag snapping. Dragging a tiled window (SUPER+LMB or a client-side title
--     bar) shows the zone overlay (drawn by hearth's ZoneOverlay.qml) and drops
--     it into the zone under the cursor. Dragging a floating window while holding
--     the snap modifier (Shift, per zones.json) does the same and tiles it into
--     that zone; without the modifier it stays a free floating window.
--     On workspaces that use another layout, snapping instead moves and
--     resizes the (floating) window to the zone rectangle, like the KWin script.
--   * Keyboard snapping, layout switching and cycling (see M.default_keys).
--   * "Macsimize": maximizing / fullscreening a window moves it to its own new
--     workspace right after the current one; restoring moves it back.
--   * Dynamic workspaces: numbered workspaces stay contiguous (emptied ones in
--     the middle are closed up) and one empty workspace is kept at the end.
--
-- Config lives in ~/.config/hearth/zones.json (seeded from Ben's KWin settings
-- on first run) and is shared with hearth's tray picker (Zones.qml), which
-- rewrites it and then runs `hyprctl dispatch 'FanzyZones.cmd("reload")'`.
-- Runtime state (zone of each window, macsimized windows) is kept in
-- $XDG_RUNTIME_DIR/hearth-fanzyzones-<instance>.json so it survives
-- `hyprctl reload`, which recreates the Lua state.
--
-- The shell is told about drags through Hyprland's socket2 as `custom` events:
--   custom>>fanzyzones show <monitor> <layout-id> <x> <y> <w> <h>   (area relative to the monitor)
--   custom>>fanzyzones hover <zone, 1-based, 0 = none>
--   custom>>fanzyzones flash <monitor> <layout-id> <x> <y> <w> <h>  (layout switched; brief preview)
--   custom>>fanzyzones hide
--   custom>>fanzyzones config                                          (zones.json rewritten by Lua)

local M = {}

local HOME = os.getenv("HOME") or ""
local XDG_CONFIG = os.getenv("XDG_CONFIG_HOME") or (HOME .. "/.config")
local RUNTIME = os.getenv("XDG_RUNTIME_DIR") or "/tmp"
local INSTANCE = os.getenv("HYPRLAND_INSTANCE_SIGNATURE") or "default"

M.LAYOUT = "fanzyzones"            -- registered as "lua:fanzyzones"
M.opts = {
    config_path = XDG_CONFIG .. "/hearth/zones.json",
    state_path = RUNTIME .. "/hearth-fanzyzones-" .. INSTANCE .. ".json",
    tick_ms = 16,                  -- drag tracking poll interval
    drag_binds = true,             -- watch LMB and the snap modifier keys
}

---------------------------------------------------------------------------
-- JSON (Hyprland's Lua has no json library)
---------------------------------------------------------------------------

local json = {}
local ARRAY = { __name = "json.array" }
function json.array(t) return setmetatable(t or {}, ARRAY) end

local function skip(s, i)
    local _, e = s:find("^[ \t\r\n]*", i)
    return e + 1
end

local decode_value
local escapes = { ['"'] = '"', ["\\"] = "\\", ["/"] = "/", b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

local function decode_string(s, i)
    local out, j = {}, i + 1
    while true do
        local c = s:sub(j, j)
        if c == "" then error("unterminated string") end
        if c == '"' then return table.concat(out), j + 1 end
        if c == "\\" then
            local n = s:sub(j + 1, j + 1)
            if n == "u" then
                local cp = tonumber(s:sub(j + 2, j + 5), 16) or 63
                j = j + 6
                if cp >= 0xD800 and cp <= 0xDBFF and s:sub(j, j + 1) == "\\u" then
                    local lo = tonumber(s:sub(j + 2, j + 5), 16) or 0
                    cp = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
                    j = j + 6
                end
                out[#out + 1] = utf8.char(cp)
            else
                out[#out + 1] = escapes[n] or n
                j = j + 2
            end
        else
            local k = s:find('["\\]', j) or (#s + 1)
            out[#out + 1] = s:sub(j, k - 1)
            j = k
        end
    end
end

decode_value = function(s, i)
    i = skip(s, i)
    local c = s:sub(i, i)
    if c == "{" then
        local t = {}
        i = skip(s, i + 1)
        if s:sub(i, i) == "}" then return t, i + 1 end
        while true do
            local k
            k, i = decode_string(s, skip(s, i))
            i = skip(s, i)
            if s:sub(i, i) ~= ":" then error("expected ':' at " .. i) end
            t[k], i = decode_value(s, i + 1)
            i = skip(s, i)
            local d = s:sub(i, i)
            if d == "}" then return t, i + 1 end
            if d ~= "," then error("expected ',' or '}' at " .. i) end
            i = i + 1
        end
    elseif c == "[" then
        local t = json.array()
        i = skip(s, i + 1)
        if s:sub(i, i) == "]" then return t, i + 1 end
        while true do
            t[#t + 1], i = decode_value(s, i)
            i = skip(s, i)
            local d = s:sub(i, i)
            if d == "]" then return t, i + 1 end
            if d ~= "," then error("expected ',' or ']' at " .. i) end
            i = i + 1
        end
    elseif c == '"' then
        return decode_string(s, i)
    elseif s:sub(i, i + 3) == "true" then
        return true, i + 4
    elseif s:sub(i, i + 4) == "false" then
        return false, i + 5
    elseif s:sub(i, i + 3) == "null" then
        return nil, i + 4
    else
        local num = s:match("^-?%d+%.?%d*[eE]?[-+]?%d*", i)
        if not num or num == "" then error("unexpected '" .. c .. "' at " .. i) end
        return tonumber(num), i + #num
    end
end

function json.decode(s)
    local ok, v = pcall(decode_value, s, 1)
    if ok then return v end
    return nil, v
end

local function encode_string(s)
    return '"' .. s:gsub('[%c"\\]', function(c)
        local m = { ['"'] = '\\"', ["\\"] = "\\\\", ["\n"] = "\\n", ["\t"] = "\\t", ["\r"] = "\\r" }
        return m[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
end

local function is_array(t)
    if getmetatable(t) == ARRAY then return true end
    local n = #t
    if n == 0 then return false end
    for k in pairs(t) do
        if type(k) ~= "number" or k < 1 or k > n or math.type(k) ~= "integer" then return false end
    end
    return true
end

local function encode(v, indent)
    local tv = type(v)
    if tv == "nil" then return "null" end
    if tv == "boolean" then return tostring(v) end
    if tv == "number" then
        if v ~= v or v == math.huge or v == -math.huge then return "0" end
        if math.type(v) == "integer" then return tostring(v) end
        if v == math.floor(v) and math.abs(v) < 1e15 then return string.format("%.1f", v) end
        local short = string.format("%.15g", v)
        if tonumber(short) == v then return short end
        return string.format("%.17g", v)
    end
    if tv == "string" then return encode_string(v) end
    local pad = indent .. "  "
    if is_array(v) then
        if #v == 0 then return "[]" end
        local parts = {}
        for i = 1, #v do parts[i] = pad .. encode(v[i], pad) end
        return "[\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "]"
    end
    local keys = {}
    for k in pairs(v) do keys[#keys + 1] = tostring(k) end
    table.sort(keys)
    if #keys == 0 then return "{}" end
    local parts = {}
    for _, k in ipairs(keys) do parts[#parts + 1] = pad .. encode_string(k) .. ": " .. encode(v[k], pad) end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

function json.encode(v) return encode(v, "") end
M.json = json

local function read_file(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("a")
    f:close()
    return s
end

local function write_file(path, s)
    local dir = path:match("^(.*)/[^/]*$")
    if dir then os.execute("mkdir -p '" .. dir:gsub("'", "'\\''") .. "'") end
    local tmp = path .. ".tmp"
    local f = io.open(tmp, "w")
    if not f then return false end
    f:write(s)
    f:close()
    return os.rename(tmp, path)
end

---------------------------------------------------------------------------
-- Config (zones.json): same keys as the KWin script's settingsJson
---------------------------------------------------------------------------

local function zone(name, x, y, w, h) return { name = name, x = x, y = y, width = w, height = h } end
local third = 1 / 3

local function builtin_layouts()
    local grid = json.array()
    for r = 0, 2 do
        for c = 0, 2 do
            grid[#grid + 1] = zone("Zone " .. (r * 3 + c + 1), c * third, r * third, third, third)
        end
    end
    return json.array({
        { id = "builtin.two-panes", name = "Two Panes", is_built_in = true,
          zones = json.array({ zone("Left", 0, 0, 0.5, 1), zone("Right", 0.5, 0, 0.5, 1) }) },
        { id = "builtin.two-panes-wide", name = "Two Panes (Wide + Side)", is_built_in = true,
          zones = json.array({ zone("Main", 0, 0, 0.7, 1), zone("Side", 0.7, 0, 0.3, 1) }) },
        { id = "builtin.three-panes", name = "Three Panes", is_built_in = true,
          zones = json.array({ zone("Left", 0, 0, third, 1), zone("Center", third, 0, third, 1),
                               zone("Right", 2 * third, 0, third, 1) }) },
        { id = "builtin.three-panes-ultrawide", name = "Three Panes (Ultrawide)", is_built_in = true,
          zones = json.array({ zone("Left", 0, 0, 0.25, 1), zone("Center", 0.25, 0, 0.5, 1),
                               zone("Right", 0.75, 0, 0.25, 1) }) },
        { id = "builtin.quarters", name = "Quarters", is_built_in = true,
          zones = json.array({ zone("Top-Left", 0, 0, 0.5, 0.5), zone("Top-Right", 0.5, 0, 0.5, 0.5),
                               zone("Bottom-Left", 0, 0.5, 0.5, 0.5), zone("Bottom-Right", 0.5, 0.5, 0.5, 0.5) }) },
        { id = "builtin.priority-left", name = "Priority (Left Focus)", is_built_in = true,
          zones = json.array({ zone("Focus", 0, 0, 0.6, 1), zone("Top-Right", 0.6, 0, 0.4, 0.5),
                               zone("Bottom-Right", 0.6, 0.5, 0.4, 0.5) }) },
        { id = "builtin.grid-3x3", name = "Grid 3x3", is_built_in = true, zones = grid },
    })
end

-- Ben's settings from the KWin script (kwinrc [Script-fanzyzones_kde]).
function M.default_config()
    return {
        version = 1,
        snap_mode = "modifier",            -- "modifier" (hold modifiers while dragging) or "auto"
        modifiers = json.array({ "shift" }),
        default_layout = "builtin.three-panes-ultrawide",
        display_layouts = { ["DP-1"] = "builtin.three-panes-ultrawide" },
        layout_mru = json.array({ "builtin.three-panes-ultrawide", "builtin.two-panes",
                                  "builtin.three-panes", "builtin.quarters" }),
        gap = 0,
        outer_padding = 0,
        enable_zone_overlay = true,
        show_zone_numbers = true,
        highlight_color = { red = 0.18, green = 0.48, blue = 0.96 },
        overlay_opacity = 0.35,
        remember_window_geometries = true,
        keyboard_shortcuts_enabled = true,
        dynamic_workspaces = true,
        keep_empty_middle_desktops = false,
        macsimize_fullscreen = true,
        macsimize_maximized = true,
        macsimize_move_to_last_desktop = false,
        macsimize_exclusive_desktops = true,
        layouts = builtin_layouts(),
    }
end

local cfg = M.default_config()
local layouts_by_id = {}

local function index_layouts()
    layouts_by_id = {}
    local valid = json.array()
    for _, l in ipairs(cfg.layouts or {}) do
        if type(l) == "table" and type(l.id) == "string" and type(l.zones) == "table" and #l.zones > 0 then
            layouts_by_id[l.id] = l
            valid[#valid + 1] = l
        end
    end
    if #valid == 0 then valid = builtin_layouts() end
    cfg.layouts = valid
    for _, l in ipairs(valid) do layouts_by_id[l.id] = l end
end

function M.save_config(notify)
    write_file(M.opts.config_path, json.encode(cfg) .. "\n")
    if notify ~= false then M.emit("config") end
end

function M.load_config()
    local s = read_file(M.opts.config_path)
    local defaults = M.default_config()
    if not s then
        cfg = defaults
        index_layouts()
        M.save_config(false)
        return cfg
    end
    local parsed, err = json.decode(s)
    if type(parsed) ~= "table" then
        print("fanzyzones: bad " .. M.opts.config_path .. ": " .. tostring(err))
        parsed = {}
    end
    for k, v in pairs(defaults) do
        if parsed[k] == nil then parsed[k] = v end
    end
    if type(parsed.display_layouts) ~= "table" then parsed.display_layouts = {} end
    cfg = parsed
    index_layouts()
    return cfg
end

function M.config() return cfg end

local function layout_for_monitor(name)
    local id = (cfg.display_layouts or {})[name or ""] or cfg.default_layout
    return layouts_by_id[id] or cfg.layouts[1]
end
M.layout_for_monitor = layout_for_monitor

---------------------------------------------------------------------------
-- Geometry
---------------------------------------------------------------------------

local function zone_rect(z, area)
    local pad = math.max(0, cfg.outer_padding or 0)
    local gap = math.max(0, cfg.gap or 0)
    local ux, uy = area.x + pad, area.y + pad
    local uw, uh = math.max(1, area.w - pad * 2), math.max(1, area.h - pad * 2)
    return {
        x = math.floor(ux + uw * z.x + gap / 2 + 0.5),
        y = math.floor(uy + uh * z.y + gap / 2 + 0.5),
        w = math.max(1, math.floor(uw * z.width - gap + 0.5)),
        h = math.max(1, math.floor(uh * z.height - gap + 0.5)),
    }
end
M.zone_rect = zone_rect

local function zone_at(layout, area, x, y)
    for i, z in ipairs(layout.zones) do
        local r = zone_rect(z, area)
        if x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h then return i end
    end
    return 0
end

local function nearest_zone(layout, area, cx, cy)
    local best, bd = 1, math.huge
    for i, z in ipairs(layout.zones) do
        local r = zone_rect(z, area)
        local dx, dy = r.x + r.w / 2 - cx, r.y + r.h / 2 - cy
        local d = dx * dx + dy * dy
        if d < bd then best, bd = i, d end
    end
    return best
end

---------------------------------------------------------------------------
-- Runtime state
---------------------------------------------------------------------------

local S = {
    zones = {},   -- window address -> zone index (1-based), the window's home zone
    mac = {},     -- window address -> { orig = workspace id, ws = workspace id }
    trailing = nil, -- workspace id kept persistent as the trailing empty one
}
local known = {}  -- workspace id -> { [address] = true } tiled targets at the last recalc
local areas = {}  -- monitor name -> last work area seen by the layout (global coords)
local timers = {}
local save_timer

local function save_state()
    write_file(M.opts.state_path, json.encode({ zones = S.zones, mac = S.mac, trailing = S.trailing }))
end

local function schedule_save()
    if save_timer then
        save_timer:set_timeout(200)
        save_timer:set_enabled(true)
    else
        save_state()
    end
end

local function load_state()
    local s = read_file(M.opts.state_path)
    local t = s and json.decode(s)
    if type(t) == "table" then
        S.zones = type(t.zones) == "table" and t.zones or {}
        S.mac = type(t.mac) == "table" and t.mac or {}
        S.trailing = t.trailing
    end
end

-- Debug log: setup({ debug = true }) appends to $XDG_RUNTIME_DIR/hearth-fanzyzones.log
function M.log(...)
    if not M.opts.debug then return end
    local f = io.open(RUNTIME .. "/hearth-fanzyzones.log", "a")
    if not f then return end
    local parts = {}
    for i = 1, select("#", ...) do parts[#parts + 1] = tostring((select(i, ...))) end
    f:write(os.date("%H:%M:%S "), table.concat(parts, " "), "\n")
    f:close()
end

function M.emit(msg)
    M.log("emit", msg)
    pcall(hl.dispatch, hl.dsp.event("fanzyzones " .. msg))
end

local function win_sel(addr) return "address:" .. addr end

local function get_window(addr)
    if not addr then return nil end
    local ok, w = pcall(hl.get_window, win_sel(addr))
    if ok then return w end
    return nil
end

local function monitor_box(mon)
    local s = (mon.scale and mon.scale > 0) and mon.scale or 1
    return { x = mon.x, y = mon.y, w = math.floor(mon.width / s + 0.5), h = math.floor(mon.height / s + 0.5) }
end

-- Work area of a monitor: what the layout last saw, else the whole monitor.
local function area_for_monitor(mon)
    if not mon then return nil end
    return areas[mon.name] or monitor_box(mon)
end

local function uses_zones(ws)
    return ws and ws.tiled_layout == "lua:" .. M.LAYOUT
end

---------------------------------------------------------------------------
-- The layout
---------------------------------------------------------------------------

local drag -- forward: drag tracker state (below)
local end_drag

local function recalculate(ctx)
    local targets = ctx.targets
    M.log("recalc", #targets)
    if #targets == 0 then return end
    local first = targets[1].window
    local ws = first and first.workspace
    local mon = (ws and ws.monitor) or (first and first.monitor)
    local mon_name = mon and mon.name or ""
    local area = { x = ctx.area.x, y = ctx.area.y, w = ctx.area.w, h = ctx.area.h }
    if ws and not ws.special then areas[mon_name] = area end
    local layout = layout_for_monitor(mon_name)
    local n = #layout.zones
    local wsid = ws and ws.id or 0
    local prev = known[wsid] or {}
    local now = {}
    local changed = false

    -- A window coming back from a drag lands in the zone under the cursor.
    local cursor = hl.get_cursor_pos()
    for _, t in ipairs(targets) do
        local w = t.window
        local addr = w and w.address
        if addr and drag.active and drag.addr == addr and drag.following and cursor then
            local z = zone_at(layout, area, cursor.x, cursor.y)
            if z == 0 then z = nearest_zone(layout, area, cursor.x, cursor.y) end
            S.zones[addr] = z
            changed = true
            end_drag()
        end
    end

    -- Count windows per zone, then give homeless windows the emptiest zone.
    local count = {}
    for i = 1, n do count[i] = 0 end
    local homeless = {}
    for _, t in ipairs(targets) do
        local addr = t.window and t.window.address
        local z = addr and S.zones[addr]
        if z and z >= 1 then
            local eff = math.min(z, n)
            count[eff] = count[eff] + 1
        else
            homeless[#homeless + 1] = addr
        end
    end
    for _, addr in ipairs(homeless) do
        if addr then
            local best = 1
            for i = 1, n do
                if count[i] < count[best] then best = i end
            end
            S.zones[addr] = best
            count[best] = count[best] + 1
            changed = true
        end
    end

    for _, t in ipairs(targets) do
        local addr = t.window and t.window.address
        local z = math.min((addr and S.zones[addr]) or 1, n)
        t:place(zone_rect(layout.zones[z], area))
        if addr then now[addr] = true end
    end

    -- A zoned window that left the layout but is still mapped may be being
    -- dragged (Hyprland floats tiled windows while they're dragged): watch it.
    for addr in pairs(prev) do
        if not now[addr] then
            local w = get_window(addr)
            M.log("left layout", addr, w and w.mapped, w and w.floating, w and w.workspace and w.workspace.id, wsid)
            -- (The floating flag is set only after the window leaves the
            -- layout, so the tracker checks it on its first tick.)
            if w and w.mapped and w.workspace and w.workspace.id == wsid then
                M.track(addr, "tiled")
            end
        end
    end
    known[wsid] = now
    if changed then schedule_save() end
end

local function active_target(ctx)
    local aw = hl.get_active_window()
    if not aw then return nil end
    for _, t in ipairs(ctx.targets) do
        if t.window and t.window.address == aw.address then return t, aw end
    end
    return nil, aw
end

-- hl.dsp.layout("<msg>") on a fanzyzones workspace:
--   "zone N" | "next" | "prev" | "refresh" | "layout <id|next|prev|N>" | "reload"
local function layout_msg(ctx, msg)
    local cmd, arg = msg:match("^%s*(%S+)%s*(.-)%s*$")
    if not cmd then return true end
    if cmd == "zone" then
        local _, aw = active_target(ctx)
        local n = tonumber(arg)
        if aw and n then S.zones[aw.address] = math.floor(n); schedule_save() end
    elseif cmd == "next" or cmd == "prev" then
        local _, aw = active_target(ctx)
        if aw then M.cycle(cmd == "next" and 1 or -1, aw, true) end
    elseif cmd == "layout" then
        local mon = hl.get_active_monitor()
        if mon then M.set_layout(mon.name, arg, { no_refresh = true }) end
    elseif cmd == "reload" then
        M.load_config()
    end
    return true
end

-- Re-run the layout on every visible fanzyzones workspace.
function M.refresh()
    local focused = hl.get_active_monitor()
    local aws = hl.get_active_workspace()
    if uses_zones(aws) then pcall(hl.dispatch, hl.dsp.layout("refresh")) end
    -- Other monitors: briefly focus them so the layout message reaches them.
    for _, mon in ipairs(hl.get_monitors()) do
        if focused and mon.name ~= focused.name and uses_zones(mon.active_workspace) then
            pcall(hl.dispatch, hl.dsp.focus({ monitor = mon.name }))
            pcall(hl.dispatch, hl.dsp.layout("refresh"))
        end
    end
    if focused and hl.get_active_monitor() and hl.get_active_monitor().name ~= focused.name then
        pcall(hl.dispatch, hl.dsp.focus({ monitor = focused.name }))
    end
end

---------------------------------------------------------------------------
-- Snapping
---------------------------------------------------------------------------

-- Put window `w` into zone `z` of its monitor's layout.
function M.snap(w, z)
    if not w then return end
    local mon = w.monitor or hl.get_active_monitor()
    local layout = layout_for_monitor(mon and mon.name)
    z = math.max(1, math.min(math.floor(z), #layout.zones))
    local addr = w.address
    S.zones[addr] = z
    schedule_save()
    if uses_zones(w.workspace) then
        if w.floating then
            pcall(hl.dispatch, hl.dsp.window.float({ action = "disable", window = win_sel(addr) }))
        else
            M.refresh()
        end
    else
        -- Not a zones workspace: place the floating window on the zone, as KWin did.
        local area = area_for_monitor(mon)
        if not area then return end
        local r = zone_rect(layout.zones[z], area)
        if not w.floating then
            pcall(hl.dispatch, hl.dsp.window.float({ action = "enable", window = win_sel(addr) }))
        end
        pcall(hl.dispatch, hl.dsp.window.resize({ x = r.w, y = r.h, window = win_sel(addr) }))
        pcall(hl.dispatch, hl.dsp.window.move({ x = r.x, y = r.y, window = win_sel(addr) }))
    end
end

local function center_zone(w)
    local mon = w.monitor or hl.get_active_monitor()
    local area = area_for_monitor(mon)
    local layout = layout_for_monitor(mon and mon.name)
    return nearest_zone(layout, area, w.at.x + w.size.x / 2, w.at.y + w.size.y / 2), layout
end

function M.snap_zone(n)
    M.snap(hl.get_active_window(), n)
end

function M.cycle(delta, w, from_layout_msg)
    w = w or hl.get_active_window()
    if not w then return end
    local cur, layout = center_zone(w)
    if not w.floating and S.zones[w.address] then cur = math.min(S.zones[w.address], #layout.zones) end
    local n = #layout.zones
    local z = ((cur - 1 + delta) % n) + 1
    if from_layout_msg and not w.floating then
        S.zones[w.address] = z
        schedule_save()
    else
        M.snap(w, z)
    end
end

function M.snap_focused()
    local w = hl.get_active_window()
    if w then M.snap(w, (center_zone(w))) end
end

function M.snap_all()
    local ws = hl.get_active_workspace()
    if not ws then return end
    for _, w in ipairs(hl.get_workspace_windows(ws.id) or {}) do
        if w.floating and w.mapped and not w.pinned then M.snap(w, (center_zone(w))) end
    end
end

---------------------------------------------------------------------------
-- Layout selection
---------------------------------------------------------------------------

local function layout_index(id)
    for i, l in ipairs(cfg.layouts) do
        if l.id == id then return i end
    end
    return 1
end

local function flash(mon_name)
    if not cfg.enable_zone_overlay then return end
    local mon = hl.get_monitor(mon_name)
    if not mon then return end
    local area = area_for_monitor(mon)
    local layout = layout_for_monitor(mon_name)
    M.emit(string.format("flash %s %s %d %d %d %d", mon.name, layout.id,
        area.x - mon.x, area.y - mon.y, area.w, area.h))
end

-- which: layout id, 1-based index, "next" or "prev".
function M.set_layout(mon_name, which, opts)
    opts = opts or {}
    if not mon_name or mon_name == "" then
        local m = hl.get_active_monitor()
        mon_name = m and m.name
    end
    if not mon_name then return end
    local cur = layout_index(layout_for_monitor(mon_name).id)
    local idx
    if which == "next" then idx = cur % #cfg.layouts + 1
    elseif which == "prev" then idx = (cur - 2) % #cfg.layouts + 1
    elseif tonumber(which) then idx = math.floor(tonumber(which))
    else idx = layout_index(which) end
    local l = cfg.layouts[idx]
    if not l then return end
    cfg.display_layouts[mon_name] = l.id
    -- Most-recently-used order for the picker.
    local mru = json.array({ l.id })
    for _, id in ipairs(cfg.layout_mru or {}) do
        if id ~= l.id and layouts_by_id[id] then mru[#mru + 1] = id end
    end
    cfg.layout_mru = mru
    M.save_config()
    if not opts.no_refresh then M.refresh() end
    if not opts.quiet then flash(mon_name) end
end

function M.next_layout() M.set_layout(nil, "next") end
function M.prev_layout() M.set_layout(nil, "prev") end
function M.use_layout(i) M.set_layout(nil, i) end

---------------------------------------------------------------------------
-- Drag tracking and the overlay
--
-- Hyprland has no drag events, so a short-lived timer follows the cursor
-- while a drag may be happening: after a tiled zone window turns floating
-- (Hyprland floats tiled windows while they are dragged), after LMB goes down,
-- or while the snap modifier is held. A window whose position keeps a fixed
-- offset from the moving cursor is being dragged.
---------------------------------------------------------------------------

drag = { active = false }
local mods_down = {}   -- keysym name -> true while held
local tick_timer
local overlay_forced = false

local MOD_KEYS = {
    shift = { "Shift_L", "Shift_R" },
    control = { "Control_L", "Control_R" }, ctrl = { "Control_L", "Control_R" },
    alt = { "Alt_L", "Alt_R" },
    meta = { "Super_L", "Super_R" }, super = { "Super_L", "Super_R" },
}

local function modifiers_held()
    if cfg.snap_mode == "auto" then return true end
    local list = cfg.modifiers or {}
    if #list == 0 then return false end
    for _, m in ipairs(list) do
        local keys = MOD_KEYS[m] or {}
        local any = false
        for _, k in ipairs(keys) do if mods_down[k] then any = true end end
        if not any then return false end
    end
    return true
end

local function overlay_hide()
    if drag.shown then
        drag.shown = false
        drag.shown_mon = nil
        drag.hover = 0
        M.emit("hide")
    end
end

local function overlay_show(mon, layout, area, hover)
    if not cfg.enable_zone_overlay then return end
    if drag.shown_mon ~= mon.name or drag.shown_layout ~= layout.id then
        M.emit(string.format("show %s %s %d %d %d %d", mon.name, layout.id,
            area.x - mon.x, area.y - mon.y, area.w, area.h))
        drag.shown = true
        drag.shown_mon = mon.name
        drag.shown_layout = layout.id
        drag.hover = -1
    end
    if drag.hover ~= hover then
        drag.hover = hover
        M.emit("hover " .. hover)
    end
end

end_drag = function()
    M.log("end_drag", drag.addr, drag.reason, drag.following)
    overlay_hide()
    drag = { active = false }
    if tick_timer and not overlay_forced then tick_timer:set_enabled(false) end
end

-- Start (or keep) watching for a drag. reason: "tiled" | "button" | "modifier".
function M.track(addr, reason)
    if drag.active then
        if reason == "tiled" then drag.addr, drag.reason = addr, "tiled" end
        return
    end
    M.log("track", addr, reason)
    drag = { active = true, addr = addr, reason = reason, ticks = 0, hover = 0 }
    if tick_timer then tick_timer:set_enabled(true) end
end

local function drop_floating()
    -- A floating window was dropped: snap if the modifier is (still) held.
    local addr, z, armed = drag.addr, drag.hover, drag.armed
    end_drag()
    if armed and z and z > 0 then
        local w = get_window(addr)
        if w and w.floating then M.snap(w, z) end
    end
end

local function tick()
    if overlay_forced and not drag.active then return end
    if not drag.active then
        if tick_timer then tick_timer:set_enabled(false) end
        return
    end
    drag.ticks = drag.ticks + 1
    local c = hl.get_cursor_pos()
    if not c then return end
    local w = drag.addr and get_window(drag.addr) or nil
    if not drag.following and drag.reason ~= "tiled" then
        w = hl.get_active_window()
    end
    if not w or not w.mapped then
        end_drag()
        return
    end
    if not w.floating then
        -- Re-tiled: the layout already handled the drop (or it was never a drag).
        if drag.reason ~= "tiled" or drag.following or drag.ticks > 4 then end_drag() end
        return
    end
    local ox, oy = w.at.x - c.x, w.at.y - c.y
    if not drag.c0 or drag.addr ~= w.address then
        drag.addr, drag.c0, drag.ox, drag.oy = w.address, { x = c.x, y = c.y }, ox, oy
        return
    end
    local moved = math.abs(c.x - drag.c0.x) + math.abs(c.y - drag.c0.y) > 4
    local same = math.abs(ox - drag.ox) <= 2 and math.abs(oy - drag.oy) <= 2
    if not drag.following then
        if moved and same then
            drag.following = true
        else
            if not same or moved then
                -- The window jumped (e.g. Hyprland re-centring it under the
                -- cursor) or the cursor moved alone: start comparing afresh.
                drag.c0, drag.ox, drag.oy = { x = c.x, y = c.y }, ox, oy
            end
            if drag.reason == "modifier" then
                if not modifiers_held() then end_drag() end
            elseif drag.ticks > 60 then
                end_drag()
            end
            return
        end
    elseif not same then
        -- The window stopped following the cursor: it was dropped.
        if drag.reason ~= "tiled" then drop_floating() end
        return
    end
    drag.ox, drag.oy = ox, oy

    local mon = hl.get_monitor_at(c.x, c.y) or w.monitor
    if not mon then return end
    local layout = layout_for_monitor(mon.name)
    local area = area_for_monitor(mon)
    local hover = zone_at(layout, area, c.x, c.y)
    drag.armed = drag.reason == "tiled" or modifiers_held()
    if drag.armed then
        overlay_show(mon, layout, area, hover)
    else
        overlay_hide()
    end
end

-- Show/hide the overlay for the focused monitor without a drag (Ctrl+Alt+C).
function M.toggle_overlay()
    overlay_forced = not overlay_forced
    if overlay_forced then
        local mon = hl.get_active_monitor()
        if not mon then overlay_forced = false; return end
        drag.shown_mon = nil
        local c = hl.get_cursor_pos() or { x = 0, y = 0 }
        local layout, area = layout_for_monitor(mon.name), area_for_monitor(mon)
        overlay_show(mon, layout, area, zone_at(layout, area, c.x, c.y))
    else
        overlay_hide()
    end
end

local function on_button(pressed)
    if pressed then
        M.track(nil, "button")
    elseif drag.active and drag.following and drag.reason ~= "tiled" then
        drop_floating()
    end
end

local function on_modifier(key, pressed)
    mods_down[key] = pressed or nil
    if pressed and not drag.active and modifiers_held() then M.track(nil, "modifier") end
end

---------------------------------------------------------------------------
-- Macsimize and dynamic workspaces
---------------------------------------------------------------------------

local busy = false        -- true while we move windows around ourselves
local prune_timer

local function numbered_workspaces()
    local list = {}
    for _, ws in ipairs(hl.get_workspaces()) do
        if ws.id and ws.id >= 1 and not ws.special then list[#list + 1] = ws end
    end
    table.sort(list, function(a, b) return a.id < b.id end)
    return list
end

local function move_window(addr, wsid, follow)
    pcall(hl.dispatch, hl.dsp.window.move({ workspace = tostring(wsid), window = win_sel(addr), follow = follow or false }))
end

local function move_workspace_windows(from, to)
    for _, w in ipairs(hl.get_workspace_windows(tostring(from)) or {}) do
        move_window(w.address, to, false)
    end
end

local function remap_mac(fn)
    for _, rec in pairs(S.mac) do
        rec.ws = fn(rec.ws)
        rec.orig = fn(rec.orig)
    end
end

-- Make room at workspace `at` by moving every numbered workspace >= at up one.
local function shift_up(at)
    local list = numbered_workspaces()
    for i = #list, 1, -1 do
        local ws = list[i]
        if ws.id >= at and ws.windows > 0 then move_workspace_windows(ws.id, ws.id + 1) end
    end
    remap_mac(function(id) return (id and id >= at) and id + 1 or id end)
end

local function set_trailing(id)
    if S.trailing == id then return end
    if S.trailing then pcall(hl.workspace_rule, { workspace = tostring(S.trailing), persistent = false }) end
    S.trailing = id
    if id then pcall(hl.workspace_rule, { workspace = tostring(id), persistent = true }) end
    schedule_save()
end

-- Close up gaps between numbered workspaces and keep one empty one at the end.
function M.prune()
    if not cfg.dynamic_workspaces or busy then return end
    if #hl.get_monitors() > 1 then
        -- Workspace ids are global across monitors; renumbering would move
        -- windows between screens, so only keep the trailing workspace.
        local maxid = 0
        for _, ws in ipairs(numbered_workspaces()) do
            if ws.windows > 0 and ws.id > maxid then maxid = ws.id end
        end
        set_trailing(maxid + 1)
        return
    end
    busy = true
    local active = hl.get_active_workspace()
    local active_id = active and not active.special and active.id or nil
    local slots = {}
    for _, ws in ipairs(numbered_workspaces()) do
        if ws.windows > 0 or (ws.id == active_id) then
            slots[#slots + 1] = ws.id
        end
    end
    -- The trailing empty workspace counts only when it is the one being looked at.
    if not cfg.keep_empty_middle_desktops then
        local map = {}
        for i, id in ipairs(slots) do map[id] = i end
        local new_active = active_id and map[active_id]
        for i, id in ipairs(slots) do
            if id ~= i then move_workspace_windows(id, i) end
        end
        remap_mac(function(id) return (id and map[id]) or id end)
        if new_active and new_active ~= active_id then
            pcall(hl.dispatch, hl.dsp.focus({ workspace = tostring(new_active) }))
        end
    end
    local maxid = 0
    for _, ws in ipairs(numbered_workspaces()) do
        if ws.windows > 0 and ws.id > maxid then maxid = ws.id end
    end
    set_trailing(maxid + 1)
    busy = false
    schedule_save()
end

local function schedule_prune()
    if not cfg.dynamic_workspaces or busy then return end
    if prune_timer then
        prune_timer:set_timeout(150)
        prune_timer:set_enabled(true)
    end
end

local function others_on(wsid, addr)
    local n = 0
    for _, w in ipairs(hl.get_workspace_windows(tostring(wsid)) or {}) do
        if w.address ~= addr and w.mapped then n = n + 1 end
    end
    return n
end

function M.macsimize(w)
    if not w or S.mac[w.address] then return end
    local ws = w.workspace
    if not ws or ws.special or ws.id < 1 then return end
    local cur = ws.id
    if others_on(cur, w.address) == 0 then
        S.mac[w.address] = { orig = cur, ws = cur }  -- already alone; nothing to move
        schedule_save()
        return
    end
    busy = true
    local target
    if cfg.macsimize_move_to_last_desktop then
        target = 1
        for _, x in ipairs(numbered_workspaces()) do
            if x.windows > 0 and x.id >= target then target = x.id + 1 end
        end
    else
        target = cur + 1
        shift_up(target)
    end
    S.mac[w.address] = { orig = cur, ws = target }
    move_window(w.address, target, true)
    busy = false
    schedule_save()
    schedule_prune()
end

function M.restore(w, closing)
    local addr = type(w) == "string" and w or (w and w.address)
    local rec = addr and S.mac[addr]
    if not rec then return end
    S.mac[addr] = nil
    schedule_save()
    if rec.orig == rec.ws then return end
    local active = hl.get_active_workspace()
    if closing then
        if active and active.id == rec.ws then
            pcall(hl.dispatch, hl.dsp.focus({ workspace = tostring(rec.orig) }))
        end
    elseif type(w) ~= "string" and w.workspace and w.workspace.id == rec.ws then
        move_window(addr, rec.orig, true)
    end
    schedule_prune()
end

local function later(ms, fn)
    local t
    t = hl.timer(function() timers[t] = nil; fn() end, { timeout = ms, type = "oneshot" })
    timers[t] = true
end

-- Runs a beat after the event: moving a window from inside Hyprland's
-- fullscreen-change handler gets undone.
local function on_fullscreen(w)
    if not w then return end
    local addr = w.address
    later(30, function()
        w = get_window(addr)
        if w and w.mapped then M.fullscreen_changed(w) end
    end)
end

function M.fullscreen_changed(w)
    local fs = w.fullscreen or 0
    local maximized, full = (fs & 1) ~= 0, (fs & 2) ~= 0
    if (full and cfg.macsimize_fullscreen) or (maximized and cfg.macsimize_maximized) then
        M.macsimize(w)
    elseif fs == 0 then
        M.restore(w)
    end
end

local function mac_owner(wsid)
    for addr, rec in pairs(S.mac) do
        if rec.ws == wsid and rec.ws ~= rec.orig then return addr, rec end
    end
end

local function on_open(w)
    if not w then return end
    local ws = w.workspace
    if cfg.macsimize_exclusive_desktops and ws and not w.floating and (w.fullscreen or 0) == 0 then
        local owner, rec = mac_owner(ws.id)
        if owner and owner ~= w.address then move_window(w.address, rec.orig, true) end
    end
    -- Windows that map already maximized/fullscreen (no change event).
    local addr = w.address
    later(150, function()
        local ww = get_window(addr)
        if ww and (ww.fullscreen or 0) ~= 0 then M.fullscreen_changed(ww) end
    end)
    schedule_prune()
end

local function on_close(w)
    if not w then return end
    local addr = w.address
    if S.mac[addr] then M.restore(addr, true) end
    S.zones[addr] = nil
    if drag.active and drag.addr == addr then end_drag() end
    schedule_save()
    schedule_prune()
end

---------------------------------------------------------------------------
-- Setup, keys, shell commands
---------------------------------------------------------------------------

function M.setup(opts)
    for k, v in pairs(opts or {}) do M.opts[k] = v end
    M.load_config()
    load_state()

    hl.layout.register(M.LAYOUT, { recalculate = recalculate, layout_msg = layout_msg })

    save_timer = hl.timer(function() save_timer:set_enabled(false); save_state() end,
        { timeout = 200, type = "repeat" })
    save_timer:set_enabled(false)
    prune_timer = hl.timer(function() prune_timer:set_enabled(false); M.prune() end,
        { timeout = 150, type = "repeat" })
    prune_timer:set_enabled(false)
    tick_timer = hl.timer(tick, { timeout = M.opts.tick_ms, type = "repeat" })
    tick_timer:set_enabled(false)

    hl.on("window.fullscreen", on_fullscreen)
    hl.on("window.open", on_open)
    hl.on("window.close", on_close)
    hl.on("window.move_to_workspace", function() schedule_prune() end)
    hl.on("workspace.removed", function() schedule_prune() end)
    hl.on("workspace.active", function() schedule_prune() end)

    if M.opts.drag_binds then
        local o = { ignore_mods = true, non_consuming = true, transparent = true }
        local r = { ignore_mods = true, non_consuming = true, transparent = true, release = true }
        hl.bind("mouse:272", function() on_button(true) end, o)
        hl.bind("mouse:272", function() on_button(false) end, r)
        local seen = {}
        for _, keys in pairs(MOD_KEYS) do
            for _, k in ipairs(keys) do
                if not seen[k] then
                    seen[k] = true
                    hl.bind(k, function() on_modifier(k, true) end, o)
                    hl.bind(k, function() on_modifier(k, false) end, r)
                end
            end
        end
    end

    -- Recreate the trailing persistent workspace rule after a reload.
    if S.trailing then
        local id = S.trailing
        S.trailing = nil
        set_trailing(id)
    end
    _G.FanzyZones = M
    return M
end

-- The KWin script's shortcuts. Override with bind_keys({ ["SUPER + Z"] = "snap_focused", ... })
-- or pass false for a key to drop it.
M.default_keys = {
    ["CTRL + ALT + right"] = "next_zone",
    ["CTRL + ALT + left"] = "prev_zone",
    ["SUPER + SHIFT + Next"] = "next_layout",
    ["SUPER + SHIFT + Prior"] = "prev_layout",
    ["SUPER + SHIFT + space"] = "snap_focused",
    ["SUPER + space"] = "snap_all",
    ["CTRL + ALT + C"] = "toggle_overlay",
}
for i = 1, 9 do
    M.default_keys["SUPER + CTRL + " .. i] = "zone " .. i
    -- KWin used Meta+Shift+N for "use layout N"; Hyprland configs usually
    -- move windows to workspaces there, so it's opt-in: bind_keys({ layout_keys = true }).
end

local actions = {
    next_zone = function() M.cycle(1) end,
    prev_zone = function() M.cycle(-1) end,
    next_layout = M.next_layout,
    prev_layout = M.prev_layout,
    snap_focused = M.snap_focused,
    snap_all = M.snap_all,
    toggle_overlay = M.toggle_overlay,
}

local function action_fn(name)
    local z = name:match("^zone (%d+)$")
    if z then return function() M.snap_zone(tonumber(z)) end end
    local l = name:match("^layout (%d+)$")
    if l then return function() M.use_layout(tonumber(l)) end end
    return actions[name]
end

function M.bind_keys(overrides)
    overrides = overrides or {}
    local keys = {}
    for k, v in pairs(M.default_keys) do keys[k] = v end
    if overrides.layout_keys then
        for i = 1, 9 do keys["SUPER + SHIFT + " .. i] = "layout " .. i end
    end
    for k, v in pairs(overrides) do
        if k ~= "layout_keys" then keys[k] = v end
    end
    for combo, name in pairs(keys) do
        local fn = name and action_fn(name)
        if fn then
            hl.bind(combo, function()
                if cfg.keyboard_shortcuts_enabled ~= false then fn() end
            end, { description = "fanzyzones: " .. name })
        end
    end
end

-- Entry point for the shell: `hyprctl dispatch 'FanzyZones.cmd("set_layout", "DP-1", "builtin.quarters")'`.
-- Returns a function so hl.dispatch runs it.
--   reload                       re-read zones.json and re-run the layouts
--   set_layout <monitor> <id|N|next|prev>
--   snap <zone> [address]        snap a window (default: focused) into a zone
--   preview <monitor> <zone>     show the overlay with a zone highlighted (testing)
--   hide                         hide the overlay
--   dump                         write state to $XDG_RUNTIME_DIR/hearth-fanzyzones-debug.json
function M.cmd(name, a, b)
    return function()
        if name == "reload" then
            M.load_config()
            M.refresh()
        elseif name == "set_layout" then
            M.set_layout(a, b)
        elseif name == "snap" then
            local w = b and get_window(b) or hl.get_active_window()
            M.snap(w, tonumber(a) or 1)
        elseif name == "preview" then
            local mon = hl.get_monitor(a) or hl.get_active_monitor()
            if mon then
                drag.shown_mon = nil
                overlay_show(mon, layout_for_monitor(mon.name), area_for_monitor(mon), tonumber(b) or 0)
            end
        elseif name == "hide" then
            overlay_forced = false
            drag.shown = true
            overlay_hide()
        elseif name == "toggle_overlay" then
            M.toggle_overlay()
        elseif name == "dump" then
            local d = { zones = S.zones, mac = S.mac, trailing = S.trailing, areas = areas,
                        drag = { active = drag.active, addr = drag.addr, reason = drag.reason,
                                 following = drag.following, hover = drag.hover },
                        mods = mods_down, known = {} }
            for id, set in pairs(known) do d.known[tostring(id)] = set end
            write_file(RUNTIME .. "/hearth-fanzyzones-debug.json", json.encode(d))
        elseif actions[name] then
            actions[name]()
        end
    end
end

return M
