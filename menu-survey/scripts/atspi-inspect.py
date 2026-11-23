#!/usr/bin/env python3
"""What an app exposes that a global menu could be built from, for the gap
triage (run by menu-probe.py inside the rig, with hearth's Python, which has
gi/Atspi). Prints one JSON object.

Usage: atspi-inspect.py PID [WINDOW_TITLE]

  atspi      found (bool), toolkit, nodes (count, capped), roles (counts of
             the interesting ones), menubars, menus, menu_items,
             menu_buttons: [{role, name, popup}] (buttons that open a menu:
             HAS_POPUP, or named like a ☰ / "Menu" / "More options")
  flatpak    the app id if the process runs in a Flatpak sandbox
"""
import json
import os
import re
import sys

import gi

gi.require_version("Atspi", "2.0")
from gi.repository import Atspi  # noqa: E402

MENU_NAME = re.compile(r"(^|\b)(menu|main menu|application menu|more options|more|options|hamburger|"
                       r"open menu|primary menu|☰|⋮|…)(\b|$)", re.I)
CAP = 4000


def ancestors(pid):
    seen = []
    try:
        while pid > 1 and len(seen) < 32:
            seen.append(pid)
            with open(f"/proc/{pid}/stat") as f:
                pid = int(f.read().rsplit(")", 1)[1].split()[1])
    except (OSError, ValueError, IndexError):
        pass
    return seen


def flatpak_proxies(pid):
    """xdg-dbus-proxy pids serving pid's Flatpak sandbox (see hearth-appmenu)."""
    try:
        with open(f"/proc/{pid}/mountinfo") as f:
            names = {os.path.basename(l.split()[3]) for l in f if "/.dbus-proxy/" in l.split()[3]}
    except OSError:
        return set()
    inodes = set()
    with open("/proc/net/unix") as f:
        next(f, None)
        for l in f:
            p = l.split()
            if len(p) >= 8 and os.path.basename(p[7]) in names:
                inodes.add(p[6])
    found = set()
    for p in os.listdir("/proc"):
        if not p.isdigit():
            continue
        try:
            if open(f"/proc/{p}/comm").read().strip() != "xdg-dbus-proxy":
                continue
            for fd in os.listdir(f"/proc/{p}/fd"):
                link = os.readlink(f"/proc/{p}/fd/{fd}")
                if link.startswith("socket:[") and link[8:-1] in inodes:
                    found.add(int(p))
                    break
        except OSError:
            continue
    return found


def main():
    pid = int(sys.argv[1])
    title = sys.argv[2] if len(sys.argv) > 2 else ""
    res = {"atspi": {"found": False}}
    try:
        with open(f"/proc/{pid}/root/.flatpak-info") as f:
            res["flatpak"] = next((l.split("=", 1)[1].strip() for l in f if l.startswith("name=")), "")
    except OSError:
        pass
    Atspi.init()
    mine = set(ancestors(pid)) | flatpak_proxies(pid)
    desk = Atspi.get_desktop(0)
    app = None
    for i in range(desk.get_child_count()):
        a = desk.get_child_at_index(i)
        try:
            if a and a.get_process_id() in mine:
                app = a
                break
        except Exception:
            continue
    if app is None:
        print(json.dumps(res))
        return
    a = res["atspi"]
    a.update(found=True, toolkit=app.get_toolkit_name() or "", name=app.get_name() or "", nodes=0,
             roles={}, menubars=0, menus=0, menu_items=0, menu_buttons=[])
    interesting = {"menu bar", "menu", "menu item", "check menu item", "radio menu item", "push button",
                   "button", "push button menu", "toggle button", "tool bar", "frame", "document web",
                   "popup menu", "page tab list"}
    stack = [app]
    while stack and a["nodes"] < CAP:
        o = stack.pop()
        a["nodes"] += 1
        try:
            role = o.get_role_name() or ""
            n = o.get_child_count()
        except Exception:
            continue
        if role in interesting:
            a["roles"][role] = a["roles"].get(role, 0) + 1
        if role in ("label", "static", "text", "paragraph", "alert", "dialog", "heading") and len(a.setdefault("texts", [])) < 12:
            try:
                txt = (o.get_name() or "").strip()
                if not txt and role in ("text", "paragraph", "static", "label"):
                    ti = o.get_text_iface()
                    txt = (ti.get_text(0, min(ti.get_character_count(), 300)) if ti else "").strip()
                if txt:
                    a["texts"].append(txt[:200])
            except Exception:
                pass
        if role == "menu bar":
            a["menubars"] += 1
        elif role == "menu":
            a["menus"] += 1
        elif "menu item" in role:
            a["menu_items"] += 1
        elif role in ("push button", "button", "toggle button", "menu button", "push button menu"):
            try:
                name = o.get_name() or ""
                popup = o.get_state_set().contains(Atspi.StateType.HAS_POPUP)
            except Exception:
                name, popup = "", False
            if (popup or role == "push button menu" or MENU_NAME.search(name)) and len(a["menu_buttons"]) < 12:
                a["menu_buttons"].append({"role": role, "name": name[:60], "popup": popup})
        for i in range(min(n, 400)):
            try:
                c = o.get_child_at_index(i)
            except Exception:
                c = None
            if c is not None:
                stack.append(c)
    print(json.dumps(res))


if __name__ == "__main__":
    main()
