#!/usr/bin/env python3
"""A test tray icon (StatusNotifierItem) with a dbusmenu that has every kind
of row hearth's tray menu draws: named icons (Breeze's white/black media
glyphs), a pixmap icon (a white glyph, as Qt apps send), check and radio
items, a disabled item, separators, a submenu, and a row whose label
changes every two seconds (live updates while the menu is open).

Run it on a test shell's bus, never the real session's (its icon would
show in the real menu bar):
    DBUS_SESSION_BUS_ADDRESS=... scripts/test-tray-sni.py
Then `scripts/test-session.sh ipc NAME call tray menu hearth-test-sni`.
Needs python3 with dbus-python and gi (hearth's runtime PATH has both).
"""
import os
import struct
import zlib

import dbus
import dbus.service
from dbus.mainloop.glib import DBusGMainLoop
from gi.repository import GLib

DBusGMainLoop(set_as_default=True)
bus = dbus.SessionBus()
NAME = f"org.kde.StatusNotifierItem-{os.getpid()}-1"
MENU = "com.canonical.dbusmenu"


def png(size, pixel):
    """A size x size RGBA PNG; pixel(x, y) -> (r, g, b, a)."""
    raw = b"".join(b"\0" + b"".join(bytes(pixel(x, y)) for x in range(size)) for y in range(size))

    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xFFFFFFFF)

    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", size, size, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b""))


# A white eye-slash-like glyph: a ring with a bar, like an app's "Hide" pixmap.
def glyph(x, y, n=32):
    cx = cy = (n - 1) / 2
    d = ((x - cx) ** 2 + (y - cy) ** 2) ** 0.5
    on = 9 <= d <= 12.5 or (abs(x - y) <= 1.5 and 4 <= x <= n - 5)
    return (255, 255, 255, 255 if on else 0)


WHITE_PNG = png(32, glyph)
# A colourful pixmap stays as it is.
COLOUR_PNG = png(32, lambda x, y: (230, 80, 40, 255) if ((x - 15.5) ** 2 + (y - 15.5) ** 2) < 150 else (0, 0, 0, 0))

state = {"tick": 0, "check": True, "radio": 1, "rev": 1}


def items():
    s = state
    return [
        (1, {"label": "Hide Test App", "icon-data": dbus.ByteArray(WHITE_PNG)}, []),
        (2, {"label": "Show Now Playing Notification", "icon-name": "dialog-information"}, []),
        (3, {"type": "separator"}, []),
        (4, {"label": "Play", "icon-name": "media-playback-start"}, []),
        (5, {"label": "Stop", "icon-name": "media-playback-stop"}, []),
        (6, {"label": "Previous", "icon-name": "media-skip-backward"}, []),
        (7, {"label": "Next", "icon-name": "media-skip-forward"}, []),
        (8, {"type": "separator"}, []),
        (9, {"label": "Shuffle", "toggle-type": "checkmark", "toggle-state": int(s["check"])}, []),
        (10, {"label": "Repeat", "children-display": "submenu"}, [
            (11, {"label": "Off", "toggle-type": "radio", "toggle-state": int(s["radio"] == 0)}, []),
            (12, {"label": "One", "toggle-type": "radio", "toggle-state": int(s["radio"] == 1)}, []),
            (13, {"label": "All", "toggle-type": "radio", "toggle-state": int(s["radio"] == 2)}, []),
            (14, {"type": "separator"}, []),
            (15, {"label": "Colour pixmap", "icon-data": dbus.ByteArray(COLOUR_PNG)}, []),
        ]),
        (16, {"label": f"Live: tick {s['tick']}"}, []),
        (17, {"label": "Disabled item", "enabled": False, "icon-name": "edit-delete"}, []),
        (18, {"type": "separator"}, []),
        (19, {"label": "About Test App…", "icon-name": "help-about"}, []),
        (20, {"label": "Quit Test App", "icon-name": "application-exit"}, []),
    ]


def node(i, props, kids, depth):
    p = dbus.Dictionary(props, signature="sv")
    if kids:
        p["children-display"] = "submenu"
    ch = [node(*k, depth - 1) for k in kids] if depth != 0 else []
    return dbus.Struct((dbus.Int32(i), p, dbus.Array(ch, signature="v")), signature=None)


def find(i, lst=None):
    for k in (items() if lst is None else lst):
        if k[0] == i:
            return k
        f = find(i, k[2])
        if f:
            return f
    return None


class Menu(dbus.service.Object):
    @dbus.service.method(MENU, in_signature="iias", out_signature="u(ia{sv}av)")
    def GetLayout(self, parent, depth, names):
        if parent == 0:
            root = (0, {"children-display": "submenu"}, items())
        else:
            root = find(parent) or (parent, {}, [])
        return dbus.UInt32(state["rev"]), node(*root, depth)

    @dbus.service.method(MENU, in_signature="aias", out_signature="a(ia{sv})")
    def GetGroupProperties(self, ids, names):
        out = []
        for i in ids:
            k = find(i)
            if k:
                out.append((dbus.Int32(i), dbus.Dictionary(k[1], signature="sv")))
        return out

    @dbus.service.method(MENU, in_signature="is", out_signature="v")
    def GetProperty(self, i, name):
        return (find(i) or (0, {}, []))[1].get(name, "")

    @dbus.service.method(MENU, in_signature="isvu")
    def Event(self, i, event, data, ts):
        if event != "clicked":
            return
        print("clicked", i, flush=True)
        if i == 9:
            state["check"] = not state["check"]
        elif i in (11, 12, 13):
            state["radio"] = i - 11
        elif i == 20:
            loop.quit()
        self.bump()

    @dbus.service.method(MENU, in_signature="a(isvu)", out_signature="ai")
    def EventGroup(self, events):
        for e in events:
            self.Event(*e)
        return []

    @dbus.service.method(MENU, in_signature="i", out_signature="b")
    def AboutToShow(self, i):
        return False

    @dbus.service.method(MENU, in_signature="ai", out_signature="aiai")
    def AboutToShowGroup(self, ids):
        return [], []

    @dbus.service.signal(MENU, signature="ui")
    def LayoutUpdated(self, rev, parent):
        pass

    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="ss", out_signature="v")
    def Get(self, iface, prop):
        return self.GetAll(iface)[prop]

    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(self, iface):
        return {"Version": dbus.UInt32(3), "TextDirection": "ltr", "Status": "normal",
                "IconThemePath": dbus.Array([], signature="s")}

    def bump(self):
        state["rev"] += 1
        self.LayoutUpdated(dbus.UInt32(state["rev"]), dbus.Int32(0))


class Item(dbus.service.Object):
    IFACE = "org.kde.StatusNotifierItem"
    PROPS = {"Category": "ApplicationStatus", "Id": "hearth-test-sni", "Title": "hearth test tray icon",
             "Status": "Active", "IconName": "media-playback-start", "ItemIsMenu": False,
             "Menu": dbus.ObjectPath("/MenuBar"), "WindowId": dbus.Int32(0)}

    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="ss", out_signature="v")
    def Get(self, iface, prop):
        if prop not in self.PROPS:
            raise dbus.exceptions.DBusException("no " + prop, name="org.freedesktop.DBus.Error.InvalidArgs")
        return self.PROPS[prop]

    @dbus.service.method(dbus.PROPERTIES_IFACE, in_signature="s", out_signature="a{sv}")
    def GetAll(self, iface):
        return self.PROPS

    @dbus.service.method(IFACE, in_signature="ii")
    def Activate(self, x, y):
        print("activate", flush=True)

    @dbus.service.method(IFACE, in_signature="ii")
    def SecondaryActivate(self, x, y):
        pass

    @dbus.service.method(IFACE, in_signature="ii")
    def ContextMenu(self, x, y):
        pass

    @dbus.service.method(IFACE, in_signature="is")
    def Scroll(self, d, o):
        pass


name = dbus.service.BusName(NAME, bus)
item = Item(bus, "/StatusNotifierItem")
menu = Menu(bus, "/MenuBar")


def tick():
    state["tick"] += 1
    menu.bump()
    return True


def register():
    try:
        bus.get_object("org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher").RegisterStatusNotifierItem(
            NAME, dbus_interface="org.kde.StatusNotifierWatcher")
        print("registered", NAME, flush=True)
        return False
    except dbus.DBusException:
        return True  # no watcher yet: try again


GLib.timeout_add(2000, tick)
# Again whenever a (restarted) shell takes the watcher name.
bus.watch_name_owner("org.kde.StatusNotifierWatcher", lambda owner: owner and GLib.timeout_add(300, register))
loop = GLib.MainLoop()
loop.run()
