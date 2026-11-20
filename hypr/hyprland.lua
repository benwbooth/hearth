-- Ben's Hyprland config (Hyprland 0.55, Lua). Installed as
-- ~/.config/hypr/hyprland.lua by /etc/nixos; the shell is hearth.
-- Keybinds follow the Plasma shortcuts this replaces wherever Hyprland has
-- an equivalent.

local hearth_ipc = "hearth-ipc call "

------------------
---- MONITORS ----
------------------

hl.monitor({
    output   = "DP-1",
    mode     = "5120x2160@165.06",
    position = "0x0",
    -- 4/3, not 1.3: Hyprland needs a whole-pixel logical size (in 1/120
    -- steps), so 1.3 silently became 1.333 for windows while the cursor
    -- stayed clamped to 1.3, leaving the right and bottom edges unreachable.
    -- The nearest valid scales on 5120x2160 are 1.25 and 4/3.
    scale    = 4/3,
    -- No HDR: Hyprland's HDR mode maps SDR content to 80 nits, so
    -- everything looked faded and brown.
})
-- Anything else plugged in: sensible defaults.
hl.monitor({ output = "", mode = "preferred", position = "auto", scale = "auto" })

-----------------------
---- ENVIRONMENT ------
-----------------------

hl.env("XCURSOR_THEME", "breeze_cursors")
hl.env("XCURSOR_SIZE", "24")
hl.env("HYPRCURSOR_SIZE", "24")
-- Keep Qt apps on Breeze + KDE dialogs (plasma-integration works outside Plasma).
hl.env("QT_QPA_PLATFORMTHEME", "kde")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")

---------------------
---- LOOK & FEEL ----
---------------------

hl.config({
    general = {
        gaps_in  = 0,
        gaps_out = 0,
        border_size = 1,
        col = {
            active_border   = "rgba(3daee9ff)",
            inactive_border = "rgba(31363bff)",
        },
        resize_on_border = true,
        extend_border_grab_area = 12,
        hover_icon_on_border = true,
    },
    decoration = {
        rounding = 6,
        shadow = { enabled = true, range = 12, render_power = 3, color = "rgba(00000066)" },
        blur = { enabled = true, size = 4, passes = 2 },
    },
    animations = { enabled = true },
    dwindle = { preserve_split = true },
    master = { new_status = "slave", orientation = "center", slave_count_for_center_master = 2, mfact = 0.5 },
    misc = {
        disable_hyprland_logo = true,
        disable_splash_rendering = true,
        force_default_wallpaper = 0,
        focus_on_activate = true,
        middle_click_paste = true,
    },
    -- X11 apps draw at native pixels and scale themselves (Xft.dpi=128 is
    -- already set for Plasma), instead of being bitmap-scaled blurry.
    xwayland = { force_zero_scaling = true },
    ecosystem = { no_update_news = true, no_donation_nag = true },
    binds = { workspace_back_and_forth = false, allow_workspace_cycles = true },
    cursor = { zoom_rigid = false },
})

hl.curve("easeOutQuint", { type = "bezier", points = { {0.23, 1}, {0.32, 1} } })
hl.animation({ leaf = "global",     enabled = true, speed = 6,   bezier = "default" })
hl.animation({ leaf = "windows",    enabled = true, speed = 4,   bezier = "easeOutQuint", style = "popin 90%" })
hl.animation({ leaf = "workspaces", enabled = true, speed = 3.5, bezier = "easeOutQuint", style = "slide" })
hl.animation({ leaf = "fade",       enabled = true, speed = 3,   bezier = "easeOutQuint" })

---------------
---- INPUT ----
---------------

hl.config({
    input = {
        kb_layout = "us",
        follow_mouse = 1,
        sensitivity = 0,
        accel_profile = "flat",
        touchpad = { natural_scroll = true },
    },
})

-------------------
---- AUTOSTART ----
-------------------

hl.on("hyprland.start", function()
    -- 4/3 for X11 apps: with force_zero_scaling they draw at native pixels
    -- and scale themselves from Xft.dpi (Plasma loads this at login; nothing
    -- does under Hyprland). 128 = 96 x 4/3; the X cursor is scaled to match.
    hl.exec_cmd("printf 'Xft.dpi: 128\\nXcursor.size: 32\\nXcursor.theme: breeze_cursors\\n' | xrdb -merge")
    hl.exec_cmd("uwsm app -- hearth")
    -- Launcher daemon (also keeps the clipboard history).
    hl.exec_cmd("uwsm app -- vicinae server")
    -- hypridle runs as its own systemd user unit (services.hypridle).
    -- KWallet: SDDM's PAM module holds the login password until this hands
    -- it to kwalletd (Plasma's startup does the same).
    hl.exec_cmd("/run/current-system/sw/libexec/pam_kwallet_init")
    -- Wallpaper: hyprpaper draws it, hearth fetches Bing's image of the day.
    hl.exec_cmd("uwsm app -- hyprpaper")
    -- Night light on a schedule (~/.config/hypr/hyprsunset.conf); hearth's
    -- brightness popup overrides it live.
    hl.exec_cmd("uwsm app -- hyprsunset")
    -- Password prompts for admin actions: KDE's own polkit agent.
    hl.exec_cmd("systemctl --user start plasma-polkit-agent.service")
    -- KDE Connect's tray icon (in Plasma it was a panel widget).
    hl.exec_cmd("uwsm app -- kdeconnect-indicator")
end)

----------------------------
---- LAYOUTS ---------------
----------------------------

-- FanzyZones (zones, macsimize, dynamic workspaces); fanzyzones.lua is
-- installed next to this file. Its keys: Ctrl+Alt+Left/Right next/prev
-- zone, Super+Ctrl+1..9 snap to zone, Super+Shift+PgUp/PgDn layouts,
-- Super+Space snap all floating, Super+Shift+Space snap focused,
-- Ctrl+Alt+C overlay; Shift while dragging snaps into a zone.
local fz = require("fanzyzones")
fz.setup()
fz.bind_keys()
hl.config({ general = { layout = "lua:fanzyzones" } })

-- Title bars with minimize/maximize/close (hyprbars; the plugin path comes
-- from $HEARTH_HYPRBARS, set once per login by uwsm). Double-click maximizes.
require("titlebars").setup()

-- Super+Alt+Space cycles the tiling algorithm: zones and Hyprland's own.
local layouts = { "lua:fanzyzones", "dwindle", "master", "scrolling" }
local function cycle_layout()
    local cur = hl.get_config("general.layout")
    local nxt = layouts[1]
    for i, l in ipairs(layouts) do
        if l == cur then nxt = layouts[(i % #layouts) + 1] end
    end
    hl.config({ general = { layout = nxt } })
    hl.notification.create({ text = "Layout: " .. nxt, timeout = 1200 })
end

-- Zoom (KDE's Meta+= / Meta+- / Meta+0).
local function zoom(step)
    local z = hl.get_config("cursor.zoom_factor") or 1
    z = step == 0 and 1 or math.max(1, math.min(10, z * step))
    hl.config({ cursor = { zoom_factor = z } })
end

---------------------
---- KEYBINDINGS ----
---------------------

local M = "SUPER"

-- Launcher (Vicinae): tap Super (Plasma's "Meta"), Alt+F1 or Alt+Space.
hl.bind(M .. " + SUPER_L", hl.dsp.exec_cmd("vicinae toggle"), { release = true })
hl.bind("ALT + F1", hl.dsp.exec_cmd("vicinae toggle"))
hl.bind("ALT + SPACE", hl.dsp.exec_cmd("vicinae toggle"))
-- Super+1..9: activate task manager entry N (as in Plasma).
for i = 1, 9 do
    hl.bind(M .. " + " .. i, hl.dsp.exec_cmd(hearth_ipc .. "tasks activate " .. i))
end

-- Windows
hl.bind("ALT + F4", hl.dsp.window.close())
hl.bind(M .. " + CTRL + Escape", hl.dsp.window.kill())
hl.bind(M .. " + Page_Up", hl.dsp.window.fullscreen({ mode = "maximized" }))
hl.bind(M .. " + F", hl.dsp.window.fullscreen())
hl.bind(M .. " + Page_Down", hl.dsp.window.move({ workspace = "special:minimized", follow = false }))
hl.bind(M .. " + SHIFT + Page_Down", hl.dsp.workspace.toggle_special("minimized"))
hl.bind(M .. " + V", hl.dsp.exec_cmd("vicinae cmd launch clipboard:history"))
hl.bind(M .. " + T", hl.dsp.window.float({ action = "toggle" }))
hl.bind(M .. " + ALT + SPACE", cycle_layout)
hl.bind(M .. " + J", hl.dsp.layout("togglesplit"))

-- Quick tile (KDE Meta+arrows) = move the window that way in the layout.
hl.bind(M .. " + left",  hl.dsp.window.move({ direction = "left" }))
hl.bind(M .. " + right", hl.dsp.window.move({ direction = "right" }))
hl.bind(M .. " + up",    hl.dsp.window.move({ direction = "up" }))
hl.bind(M .. " + down",  hl.dsp.window.move({ direction = "down" }))
-- Switch window (KDE Meta+Alt+arrows) = move focus.
hl.bind(M .. " + ALT + left",  hl.dsp.focus({ direction = "left" }))
hl.bind(M .. " + ALT + right", hl.dsp.focus({ direction = "right" }))
hl.bind(M .. " + ALT + up",    hl.dsp.focus({ direction = "up" }))
hl.bind(M .. " + ALT + down",  hl.dsp.focus({ direction = "down" }))

-- Alt/Super+Tab walk through windows.
-- hearth's task switcher (shell/popups/Switcher.qml), KWin-style: live
-- thumbnails in recently-used order; releasing the modifier picks. The
-- release binds must be transparent: Hyprland shadows a modifier's release
-- bind once another key (Tab) was pressed with it.
local switching = false
local function switcher(cmd)
    return function()
        switching = true
        hl.dispatch(hl.dsp.event("hearth-switcher " .. cmd))
    end
end
local function switcher_commit()
    if not switching then return end
    switching = false
    hl.dispatch(hl.dsp.event("hearth-switcher commit"))
end
for _, mod in ipairs({ "ALT", M }) do
    hl.bind(mod .. " + Tab",           switcher("next"))
    hl.bind(mod .. " + SHIFT + Tab",   switcher("prev"))
    hl.bind(mod .. " + grave",         switcher("nextApp"))   -- current application only
    hl.bind(mod .. " + SHIFT + grave", switcher("prevApp"))
end
for _, key in ipairs({ "ALT_L", "ALT_R", "SUPER_L", "SUPER_R" }) do
    hl.bind(key, switcher_commit, { release = true, ignore_mods = true, transparent = true })
end

-- Overview (KDE Meta+W) and Grid View (Meta+G): shell/popups/Overview.qml.
hl.bind(M .. " + W", hl.dsp.event("hearth-overview toggle"))
hl.bind(M .. " + G", hl.dsp.event("hearth-overview toggle"))

-- Workspaces (KDE: Ctrl+F1..F4, Meta+Ctrl+arrows; with Shift moves the window).
for i = 1, 9 do
    hl.bind("CTRL + F" .. i, hl.dsp.focus({ workspace = i }))
    hl.bind(M .. " + CTRL + SHIFT + " .. i, hl.dsp.window.move({ workspace = i }))
end
hl.bind(M .. " + CTRL + left",  hl.dsp.focus({ workspace = "e-1" }))
hl.bind(M .. " + CTRL + right", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(M .. " + CTRL + SHIFT + left",  hl.dsp.window.move({ workspace = "e-1" }))
hl.bind(M .. " + CTRL + SHIFT + right", hl.dsp.window.move({ workspace = "r+1" }))
hl.bind(M .. " + mouse_down", hl.dsp.focus({ workspace = "e+1" }))
hl.bind(M .. " + mouse_up",   hl.dsp.focus({ workspace = "e-1" }))
hl.bind(M .. " + D", hl.dsp.exec_cmd(hearth_ipc .. "desktop toggle"))

-- Mouse: Super+drag moves, Super+right-drag resizes.
hl.bind(M .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
hl.bind(M .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

-- Zoom
hl.bind(M .. " + equal", function() zoom(1.25) end, { repeating = true })
hl.bind(M .. " + minus", function() zoom(0.8) end, { repeating = true })
hl.bind(M .. " + 0",     function() zoom(0) end)

-- Session
hl.bind(M .. " + L", hl.dsp.exec_cmd(hearth_ipc .. "session lock"))
hl.bind("CTRL + ALT + Delete", hl.dsp.exec_cmd(hearth_ipc .. "session open"))
hl.bind("XF86PowerOff", hl.dsp.exec_cmd(hearth_ipc .. "session open"))

-- Ben's own tools (were KDE custom shortcuts).
hl.bind(M .. " + H", hl.dsp.exec_cmd("dsnote-tts.sh"))
hl.bind(M .. " + C", hl.dsp.exec_cmd("ultrawide-crop"))

-- Speech Note's own shortcuts (Plasma's KGlobalAccel held them; here they
-- call its --action interface).
local speechnote = {
    C = "cancel", P = "pause-resume-reading", L = "start-listening",
    K = "start-listening-active-window", J = "start-listening-clipboard",
    slash = "start-listening-translate", period = "start-listening-translate-active-window",
    comma = "start-listening-translate-clipboard", R = "start-reading",
    E = "start-reading-clipboard", S = "stop-listening",
    B = "switch-to-next-stt-model", M = "switch-to-next-tts-model",
    V = "switch-to-prev-stt-model", N = "switch-to-prev-tts-model",
}
for key, action in pairs(speechnote) do
    hl.bind("CTRL + ALT + SHIFT + " .. key,
        hl.dsp.exec_cmd("flatpak run net.mkiol.SpeechNote --action " .. action))
end
hl.bind("Pause",     hl.dsp.exec_cmd("whisper-toggle"))

-- Screenshots
hl.bind("Print",              hl.dsp.exec_cmd("spectacle"))
hl.bind(M .. " + SHIFT + S",  hl.dsp.exec_cmd("spectacle -r"))

-- Media and volume keys (work on the lock screen too).
local lr = { locked = true, repeating = true }
hl.bind("XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 5%+"), lr)
hl.bind("XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), lr)
hl.bind("SHIFT + XF86AudioRaiseVolume", hl.dsp.exec_cmd("wpctl set-volume -l 1 @DEFAULT_AUDIO_SINK@ 1%+"), lr)
hl.bind("SHIFT + XF86AudioLowerVolume", hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 1%-"), lr)
hl.bind("XF86AudioMute",    hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"), { locked = true })
hl.bind("XF86AudioMicMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
hl.bind(M .. " + XF86AudioMute", hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SOURCE@ toggle"), { locked = true })
hl.bind("XF86MonBrightnessUp",   hl.dsp.exec_cmd(hearth_ipc .. "brightness up"), lr)
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd(hearth_ipc .. "brightness down"), lr)
hl.bind("XF86AudioPlay",  hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioPause", hl.dsp.exec_cmd("playerctl play-pause"), { locked = true })
hl.bind("XF86AudioNext",  hl.dsp.exec_cmd("playerctl next"), { locked = true })
hl.bind("XF86AudioPrev",  hl.dsp.exec_cmd("playerctl previous"), { locked = true })
hl.bind("XF86AudioStop",  hl.dsp.exec_cmd("playerctl stop"), { locked = true })

--------------------------------
---- WINDOW RULES --------------
--------------------------------

hl.window_rule({
    name  = "fix-xwayland-drags",
    match = { class = "^$", title = "^$", xwayland = true, float = true, fullscreen = false, pin = false },
    no_focus = true,
})
hl.window_rule({
    name  = "kde-dialogs-float",
    match = { class = "^(org.kde.polkit-kde-authentication-agent-1|org.kde.kdialog|pavucontrol|org.pulseaudio.pavucontrol|blueman-manager)$" },
    float = true,
})
