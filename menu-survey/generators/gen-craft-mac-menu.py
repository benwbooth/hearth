#!/usr/bin/env python3
"""gen-craft-mac-menu.py SRC [APP]: an ArtCraft app's macOS menu bar, read
from its source, as the menu hearth shows for it (menus/craft/APP.json).

For craft apps whose control server can't list their menu (gridcraft
0.19.1): their Mac menu is a static table, `fn tree()` in
apps/APP/src/native_menu.rs, of (label, id, accelerator) entries per
menu, "-" for a separator. The macOS-only code around it (native_menu.rs
`poll`) says how an id runs, and so does this file:

  "dialog:NAME[:ARG]"   control `ui.dialog {"name": NAME, ...}` (ARG as the
                         Mac menu passes it: saveCopy -> format, find ->
                         replace, backstage -> page, about -> tab)
  "url:https://..."     opens the page
  edit.cut/copy/paste/undo/redo   the key chord (the Mac menu sends those
                         to the focused field as keys, not commands)
  "view.theme"          the System/Light/Dark submenu (view.theme {mode})
  anything else         control `engine.execute {"command": ID}`

SRC is the app's source tree at the released tag (nix-craftapps' apps.json
names repo and tag). Regenerate when the app updates:

  git clone --depth 1 --branch v0.19.1 https://github.com/storytold/gridcraft /tmp/gc
  menu-survey/generators/gen-craft-mac-menu.py /tmp/gc gridcraft > menus/craft/gridcraft.json
"""
import json, os, re, subprocess, sys

KEYS = {"edit.undo": "Ctrl+Z", "edit.redo": "Ctrl+Shift+Z", "edit.cut": "Ctrl+X",
        "edit.copy": "Ctrl+C", "edit.paste": "Ctrl+V"}
DIALOG_ARG = {"saveCopy": "format", "find": "replace", "backstage": "page", "about": "tab"}


def accel(a):
    """muda's "CMD+SHIFT+S" as hearth shows it ("Ctrl+Shift+S"): CMD is
    Ctrl off the Mac, and the Mac's own CTRL becomes Ctrl too (macOS
    shortcuts like Ctrl+Cmd+V have no second Ctrl elsewhere: dropped)."""
    if not a:
        return ""
    parts = [p.strip().upper() for p in a.split("+")]
    if "CMD" in parts and "CTRL" in parts:
        return ""  # a Mac-only chord
    names = {"CMD": "Ctrl", "CTRL": "Ctrl", "SHIFT": "Shift", "ALT": "Alt", "OPTION": "Alt"}
    out = []
    for p in parts:
        if p in names:
            out.append(names[p])
        elif p.startswith("KEY") and len(p) == 4:
            out.append(p[3])
        elif p.startswith("DIGIT") and len(p) == 6:
            out.append(p[5])
        else:
            out.append({"COMMA": ",", "PERIOD": ".", "MINUS": "-", "EQUAL": "=", "SLASH": "/",
                        "BACKSPACE": "Backspace", "DELETE": "Del", "ESCAPE": "Esc", "ENTER": "Return",
                        "SPACE": "Space"}.get(p, p.title() if len(p) > 1 else p))
    return "+".join(out)


def run_of(ident):
    if ident in KEYS:
        return {"keys": KEYS[ident]}
    if ident.startswith("url:"):
        return {"url": ident[4:]}
    if ident.startswith("dialog:"):
        name, _, arg = ident[7:].partition(":")
        params = {"name": "comment" if name == "note" else name}
        if name == "find" and arg == "replace":
            params["replace"] = True
        elif name == "note":
            params["threaded"] = False
        elif name == "comment":
            params["threaded"] = True
        elif arg and name in DIALOG_ARG:
            params[DIALOG_ARG[name]] = arg
        return {"method": "ui.dialog", "params": params}
    return {"method": "engine.execute", "params": {"command": ident}}


def parse_tree(text):
    """`fn tree()`'s vec![("Title", vec![("Label", "id", Some("ACC")|None), ...]), ...]."""
    body = text[text.index("fn tree()"):]
    end = body.index("\n}\n")
    body = body[:end]
    menus = []
    title_re = re.compile(r'\(\s*"([^"]+)",\s*vec!\[')
    entry_re = re.compile(r'\(\s*"((?:[^"\\]|\\.)*)",\s*"((?:[^"\\]|\\.)*)",\s*(None|Some\("([^"]*)"\))\s*\)')
    pos = 0
    while True:
        m = title_re.search(body, pos)
        if not m:
            break
        nxt = title_re.search(body, m.end())
        chunk = body[m.end(): nxt.start() if nxt else len(body)]
        items = []
        for e in entry_re.finditer(chunk):
            label, ident, acc = e.group(1), e.group(2), e.group(4)
            if label == "-":
                items.append({"separator": True})
            elif ident == "view.theme":
                items.append({"label": label, "items": [
                    {"label": t, "run": {"method": "engine.execute", "params": {"command": "view.theme", "params": {"mode": t.lower()}}}}
                    for t in ("System", "Light", "Dark")]})
            else:
                items.append({"label": label, "id": ident, "shortcut": accel(acc) or KEYS.get(ident, ""), "run": run_of(ident)})
        menus.append({"title": m.group(1), "items": items})
        pos = m.end()
    return menus


def main():
    src = sys.argv[1]
    app = sys.argv[2] if len(sys.argv) > 2 else os.path.basename(os.path.abspath(src))
    path = os.path.join(src, "apps", app, "src", "native_menu.rs")
    with open(path) as f:
        text = f.read()
    try:
        tag = subprocess.run(["git", "-C", src, "describe", "--tags"], capture_output=True, text=True).stdout.strip()
    except OSError:
        tag = ""
    menus = parse_tree(text)
    if not menus:
        sys.exit(f"{path}: no fn tree() table")
    json.dump({"app": app, "source": f"apps/{app}/src/native_menu.rs fn tree()", "version": tag,
               "generator": "menu-survey/generators/gen-craft-mac-menu.py", "menus": menus},
              sys.stdout, indent=1, ensure_ascii=False)
    sys.stdout.write("\n")


if __name__ == "__main__":
    main()
