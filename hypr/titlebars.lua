-- titlebars.lua: KDE/Breeze-style window title bars for Hyprland 0.55 (Lua
-- config), drawn by the hyprbars plugin (nixpkgs hyprlandPlugins.hyprbars).
--
--     local tb = require("titlebars")
--     tb.setup()                       -- plugin from $HEARTH_HYPRBARS
--     tb.setup({ plugin = "/nix/store/...-hyprbars-0.55.0/lib/libhyprbars.so" })
--
-- What you get (see docs/titlebars.md):
--   * a 28 px Breeze Dark bar on every window: #31363b / #fcfcfc focused,
--     #202326 / #a1a9b1 unfocused, Noto Sans title;
--   * buttons on the right: minimize (to special:minimized, as Super+PgDn),
--     maximize (fullscreen mode "maximized", as Super+PgUp, so fanzyzones'
--     macsimize sees it), close;
--   * drag the bar to move (tiled windows float under the cursor and the
--     fanzyzones overlay snaps them back into a zone), double-click to
--     maximize / restore;
--   * no bar on fullscreen windows or on apps that draw their own title bar
--     (client-side decorations; see M.csd_classes);
--   * with hearth's patched hyprbars (on_middle_click / on_right_click keys,
--     left button only for moving and buttons): middle-click lowers a
--     floating window, right-click asks the shell for the window menu
--     (socket2 `custom>>titlebars menu <address> <x> <y>`). Stock hyprbars
--     treats every mouse button like the left one.
--
-- Loading: hl.plugin.load() only queues the path; Hyprland loads the plugin
-- after the config has run and then re-runs the config. So on the first pass
-- hl.plugin.hyprbars (and the plugin's config keys) don't exist yet, and this
-- module only queues the load; the second pass configures everything.
--
-- The plugin runs button and double-click actions as shell commands, so they
-- go back into this Lua state via `hyprctl dispatch 'Titlebars.cmd("...")'`.

local M = {}

M.opts = {
    plugin = nil,                  -- path to libhyprbars.so; default $HEARTH_HYPRBARS
    hyprctl = nil,                 -- default: hyprctl next to the running Hyprland
    height = 28,
    font = "Noto Sans",
    font_size = 13,                -- px (10 pt at 96 dpi, Theme.fontSize)
    align = "center",              -- "center" | "left"
    active_bg = "rgb(31363b)",     -- Theme.bgRaised
    inactive_bg = "rgb(202326)",   -- Theme.bg
    active_fg = "rgb(fcfcfc)",     -- Theme.fg
    inactive_fg = "rgb(a1a9b1)",   -- Theme.fgDim
    button_size = 18,
    -- Icons are drawn by the plugin in "sans" at 62% of button_size. The icon
    -- colour is picked by the plugin: white on a dark button, black on a light
    -- one (its Lua API ignores fg_color).
    buttons = {                    -- right to left
        { name = "close",    icon = "✕", bg = "rgba(fcfcfcff)" },
        { name = "maximize", icon = "∧", bg = "rgba(31363b00)" },
        { name = "minimize", icon = "∨", bg = "rgba(31363b00)" },
    },
    csd_bars = false,              -- true: keep bars on M.csd_classes too
    middle_click = "lower",        -- action name or false (patched plugin only)
    right_click = "menu",
}

-- Apps that draw their own title bar whatever Hyprland asks for: GTK
-- headerbar / libadwaita apps, browsers with tabs in the title bar, Electron
-- apps with a custom frame (VS Code's default "window.titleBarStyle":
-- "custom"). Lua patterns over the whole class. Apps that honour
-- xdg-decoration (Qt/KDE, GTK4 without a headerbar such as pavucontrol,
-- Firefox with its "Title bar" option on) get a hyprbars bar instead.
M.csd_classes = {
    "org%.gnome%..*", "nautilus", "gnome%-.*",
    "firefox", "librewolf", "zen", "chromium", "chromium%-browser",
    "google%-chrome.*", "brave%-browser", "vivaldi.*",
    "code", "code%-url%-handler", "Code", "Slack", "obsidian", "discord", "vesktop",
    "dev%.zed%.Zed",
}

local function file_exists(p)
    local f = p and io.open(p, "r")
    if f then f:close(); return true end
    return false
end

local function resolve_plugin(p)
    p = p or os.getenv("HEARTH_HYPRBARS")
    if not p or p == "" then return nil end
    -- Accept the package dir as well as the .so.
    if not p:match("%.so$") then p = p .. "/lib/libhyprbars.so" end
    return p
end

-- hyprctl from the same Hyprland as the one running this config (the
-- session's PATH may not have it, e.g. in nested test sessions).
local function find_hyprctl()
    local ok, pipe = pcall(io.popen, "readlink -f /proc/$PPID/exe 2>/dev/null")
    if ok and pipe then
        local exe = pipe:read("*l")
        pipe:close()
        local dir = exe and exe:match("^(.*)/[^/]+$")
        if dir and file_exists(dir .. "/hyprctl") then return dir .. "/hyprctl" end
    end
    return "hyprctl"
end

local function action(name)
    return string.format("%s dispatch 'Titlebars.cmd(\"%s\")'", M.opts.hyprctl, name)
end

-- Lua patterns -> one regex for a window rule.
local function classes_regex(list)
    local parts = {}
    for _, p in ipairs(list) do
        parts[#parts + 1] = (p:gsub("%%%.", "\\."):gsub("%%%-", "-"))
    end
    return "^(" .. table.concat(parts, "|") .. ")$"
end

---------------------------------------------------------------------------
-- Actions (also usable from binds and the shell)
---------------------------------------------------------------------------

local actions = {}

function actions.minimize()
    hl.dispatch(hl.dsp.window.move({ workspace = "special:minimized", silent = true }))
end

-- Same dispatcher as Super+PgUp: fanzyzones' window.fullscreen handler does
-- the macsimize (own workspace) and the restore.
function actions.maximize()
    hl.dispatch(hl.dsp.window.fullscreen({ mode = "maximized" }))
end

function actions.close()
    hl.dispatch(hl.dsp.window.close())
end

-- KWin's middle-click "Lower": send a floating window behind the others.
function actions.lower()
    local w = hl.get_active_window()
    if w and w.floating then hl.dispatch(hl.dsp.window.alter_zorder({ mode = "bottom" })) end
end

-- KWin's right-click window menu: hearth draws it.
function actions.menu()
    local w, c = hl.get_active_window(), hl.get_cursor_pos()
    if not w then return end
    c = c or { x = 0, y = 0 }
    pcall(hl.dispatch, hl.dsp.event(string.format("titlebars menu %s %d %d", w.address, c.x, c.y)))
end

M.actions = actions

-- `hyprctl dispatch 'Titlebars.cmd("close")'`; returns a function so
-- hl.dispatch runs it.
function M.cmd(name)
    return function()
        local fn = actions[name]
        if fn then fn() end
    end
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------

function M.setup(opts)
    for k, v in pairs(opts or {}) do M.opts[k] = v end
    local o = M.opts
    _G.Titlebars = M

    local plugin = resolve_plugin(o.plugin)
    if not plugin then
        hl.notification.create({ text = "titlebars: no hyprbars plugin (set HEARTH_HYPRBARS)", timeout = 5000 })
        return M
    end
    hl.plugin.load(plugin)

    -- First config pass: the plugin isn't loaded yet (see the header).
    if not hl.plugin.hyprbars then return M end

    o.hyprctl = o.hyprctl or find_hyprctl()

    hl.config({
        plugin = {
            hyprbars = {
                enabled = true,
                bar_height = o.height,
                bar_color = o.active_bg,
                ["col.text"] = o.active_fg,
                bar_text_font = o.font,
                bar_text_size = o.font_size,
                bar_text_align = o.align,
                bar_title_enabled = true,
                bar_buttons_alignment = "right",
                bar_part_of_window = true,
                bar_precedence_over_border = true,
                bar_padding = 6,
                bar_button_padding = 6,
                bar_blur = false,
                icon_on_hover = false,
                on_double_click = action("maximize"),
            },
        },
    })
    -- Keys only the patched plugin has.
    if hl.get_config("plugin.hyprbars.on_right_click") ~= nil then
        hl.config({
            plugin = {
                hyprbars = {
                    on_middle_click = o.middle_click and action(o.middle_click) or "",
                    on_right_click = o.right_click and action(o.right_click) or "",
                },
            },
        })
    end

    for _, b in ipairs(o.buttons) do
        hl.plugin.hyprbars.add_button({
            bg_color = b.bg,
            fg_color = b.fg or o.active_fg,
            size = b.size or o.button_size,
            icon = b.icon,
            action = action(b.name),
        })
    end

    -- Unfocused windows: darker bar, dimmer title (dynamic rule, follows focus).
    hl.window_rule({
        name = "titlebars-inactive",
        match = { focus = false },
        ["hyprbars:bar_color"] = o.inactive_bg,
        ["hyprbars:title_color"] = o.inactive_fg,
    })
    -- Real fullscreen (internal state 2, or 3 = maximized + fullscreen): no
    -- bar. `fullscreen = true` would also match maximized windows, which keep
    -- their bar as in KDE.
    for _, state in ipairs({ 2, 3 }) do
        hl.window_rule({
            name = "titlebars-fullscreen-" .. state,
            match = { fullscreen_state_internal = state },
            ["hyprbars:no_bar"] = true,
        })
    end
    if not o.csd_bars and #M.csd_classes > 0 then
        hl.window_rule({
            name = "titlebars-csd",
            match = { class = classes_regex(M.csd_classes) },
            ["hyprbars:no_bar"] = true,
        })
    end
    return M
end

return M
