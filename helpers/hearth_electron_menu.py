"""An Electron app's menu bar from its own code, for hearth-appmenu.

Electron exports its menu over dbusmenu only if it can dlopen libdbusmenu,
and its in-window menu bar is on AT-SPI only with accessibility forced on.
Neither may be injected (no app patching). But the menu itself is data in
the app: the `Menu.buildFromTemplate([...])` template in its JavaScript,
inside `resources/app.asar` (or an unpacked app directory). This reads it:

- the asar archive (header pickle + JSON index), or the app directory;
- every object literal with a `submenu: [...]` in the app's own scripts
  (not node_modules), with a small bracket- and string-aware scanner;
- labels: string literals, translation calls (`t("menu.file")`,
  ``n(`icu:mainMenuFile`)``) resolved through the app's English messages
  files, and Electron's standard role labels;
- items that can run without the app's code: an `accelerator`, or a `role`
  with Electron's default key (copy, paste, zoomIn, togglefullscreen...).
  Those are sent as keys through arbor send-keys; Electron's menu
  accelerators work while its menu bar is hidden too.

menus_for(path) -> [{"title": str, "items": [{"label", "keys"} | "separator"]}]
"""
import json
import os
import re
import struct

ROLE_KEYS = {
    "undo": ("Undo", "Ctrl+Z"), "redo": ("Redo", "Ctrl+Shift+Z"), "cut": ("Cut", "Ctrl+X"),
    "copy": ("Copy", "Ctrl+C"), "paste": ("Paste", "Ctrl+V"),
    "pasteandmatchstyle": ("Paste and Match Style", "Ctrl+Shift+V"), "delete": ("Delete", "Del"),
    "selectall": ("Select All", "Ctrl+A"), "reload": ("Reload", "Ctrl+R"),
    "forcereload": ("Force Reload", "Ctrl+Shift+R"), "toggledevtools": ("Toggle Developer Tools", "Ctrl+Shift+I"),
    "resetzoom": ("Actual Size", "Ctrl+0"), "zoomin": ("Zoom In", "Ctrl++"), "zoomout": ("Zoom Out", "Ctrl+-"),
    "togglefullscreen": ("Toggle Full Screen", "F11"), "minimize": ("Minimize", "Ctrl+M"),
    "close": ("Close Window", "Ctrl+W"), "quit": ("Quit", "Ctrl+Q"),
}
ROLE_MENUS = {
    "editmenu": ("Edit", ["undo", "redo", None, "cut", "copy", "paste", "pasteandmatchstyle", "delete", "selectall"]),
    "viewmenu": ("View", ["reload", "forcereload", "toggledevtools", None, "resetzoom", "zoomin", "zoomout", None,
                          "togglefullscreen"]),
    "windowmenu": ("Window", ["minimize", "close"]),
    "filemenu": ("File", ["close"]),
}
MAX_JS = 30 * 1024 * 1024


# ------------------------------------------------------------ app files

class AsarFiles:
    def __init__(self, path):
        self.f = open(path, "rb")
        hsize = struct.unpack("<I", self.f.read(8)[4:8])[0]
        h = self.f.read(hsize)
        slen = struct.unpack("<I", h[4:8])[0]
        self.index = json.loads(h[8:8 + slen])
        self.base = 8 + hsize
        self.files = {}
        self._walk(self.index, "")

    def _walk(self, node, path):
        for k, v in node.get("files", {}).items():
            p = f"{path}/{k}"
            if "files" in v:
                self._walk(v, p)
            elif "offset" in v and not v.get("unpacked"):
                self.files[p.lstrip("/")] = v

    def names(self):
        return self.files.keys()

    def size(self, name):
        return self.files[name].get("size", 0)

    def read(self, name):
        v = self.files[name]
        self.f.seek(self.base + int(v["offset"]))
        return self.f.read(v["size"]).decode("utf-8", "replace")


class DirFiles:
    def __init__(self, root):
        self.root, self._names = root, []
        for d, dirs, fs in os.walk(root):
            dirs[:] = [x for x in dirs if x != "node_modules" and not x.startswith(".")]
            for f in fs:
                self._names.append(os.path.relpath(os.path.join(d, f), root))
            if len(self._names) > 20000:
                break

    def names(self):
        return self._names

    def size(self, name):
        return os.path.getsize(os.path.join(self.root, name))

    def read(self, name):
        with open(os.path.join(self.root, name), errors="replace") as f:
            return f.read()


def open_app(path):
    if path.endswith(".asar") and os.path.isfile(path):
        return AsarFiles(path)
    if os.path.isdir(path) and os.path.exists(os.path.join(path, "package.json")):
        return DirFiles(path)
    return None


# ------------------------------------------------------------ translations

def translations(files):
    """English strings from the app's messages files: flat key -> text."""
    out = {}
    for n in files.names():
        low = n.lower()
        if "node_modules" in low or not low.endswith(".json") or files.size(n) > 8_000_000:
            continue
        base = os.path.basename(low)
        if not (re.search(r"(^|[/_.-])en([_-](us|gb))?([/_.-]|$)", low) or base in ("messages.json", "strings.json")):
            continue
        try:
            data = json.loads(files.read(n))
        except Exception:
            continue
        if isinstance(data, list):
            # Keys and strings in two arrays (Signal: _locales/keys.json and
            # _locales/en/values.json): pair them with a keys file above.
            d = os.path.dirname(n)
            keys = None
            while d and keys is None:
                d = os.path.dirname(d)
                k = os.path.join(d, "keys.json") if d else "keys.json"
                if k in files.names():
                    try:
                        keys = json.loads(files.read(k))
                    except Exception:
                        keys = []
            if isinstance(keys, list) and len(keys) == len(data):
                for k, v in zip(keys, data):
                    if isinstance(k, str) and isinstance(v, str):
                        out.setdefault(k, v)
            continue

        def flat(d, prefix=""):
            if isinstance(d, dict):
                for k, v in d.items():
                    key = f"{prefix}.{k}" if prefix else str(k)
                    if isinstance(v, str):
                        out.setdefault(key, v)
                        out.setdefault(str(k), v)
                    elif isinstance(v, dict) and isinstance(v.get("messageformat") or v.get("message"), str):
                        out.setdefault(key, v.get("messageformat") or v.get("message"))
                        out.setdefault(str(k), v.get("messageformat") or v.get("message"))
                    else:
                        flat(v, key)
        flat(data)
    return out


# ------------------------------------------------------------ the scanner

def _skip_string(t, i):
    q = t[i]
    i += 1
    while i < len(t):
        c = t[i]
        if c == "\\":
            i += 2
            continue
        if q == "`" and c == "$" and i + 1 < len(t) and t[i + 1] == "{":
            depth, i = 1, i + 2
            while i < len(t) and depth:
                if t[i] in "\"'`":
                    i = _skip_string(t, i)
                    continue
                depth += {"{": 1, "}": -1}.get(t[i], 0)
                i += 1
            continue
        if c == q:
            return i + 1
        i += 1
    return i


def _match(t, i):
    """Index after the bracket that closes t[i]."""
    pairs = {"{": "}", "[": "]", "(": ")"}
    stack = [pairs[t[i]]]
    i += 1
    while i < len(t) and stack:
        c = t[i]
        if c in "\"'`":
            i = _skip_string(t, i)
            continue
        if c in pairs:
            stack.append(pairs[c])
        elif c in ")]}":
            if c != stack[-1]:
                return i + 1
            stack.pop()
        i += 1
    return i


def _top_props(obj):
    """Top-level `key: value` pairs of an object literal's source."""
    props, i, n = {}, 1, len(obj) - 1
    while i < n:
        m = re.compile(r"\s*(?:,\s*)?([A-Za-z_$][\w$]*|\"[^\"]*\"|'[^']*')\s*:").match(obj, i)
        if not m:
            # Skip one value (spread, shorthand, method...) up to the next comma.
            while i < n and obj[i] != ",":
                if obj[i] in "\"'`":
                    i = _skip_string(obj, i)
                elif obj[i] in "{[(":
                    i = _match(obj, i)
                else:
                    i += 1
            i += 1
            continue
        key = m.group(1).strip("\"'")
        j = m.end()
        start = j
        while j < n and obj[j] != ",":
            if obj[j] in "\"'`":
                j = _skip_string(obj, j)
            elif obj[j] in "{[(":
                j = _match(obj, j)
            else:
                j += 1
        props[key] = obj[start:j].strip()
        i = j + 1
    return props


def _elements(arr):
    """Object literals directly in an array literal's source."""
    out, i, n = [], 1, len(arr) - 1
    while i < n:
        c = arr[i]
        if c == "{":
            j = _match(arr, i)
            out.append(arr[i:j])
            i = j
        elif c in "\"'`":
            i = _skip_string(arr, i)
        elif c in "[(":
            i = _match(arr, i)
        else:
            i += 1
    return out


def _literal(v):
    v = v.strip()
    m = re.fullmatch(r"([\"'`])((?:\\.|(?!\1).)*)\1", v, re.S)
    if m and "${" not in m.group(2):
        return m.group(2)
    return None


def _label(v, tr):
    """A label expression: literal, translation call, or None."""
    if not v:
        return None
    lit = _literal(v)
    if lit is not None:
        return lit
    m = re.search(r"[\w$.]+\(\s*([\"'`])([^\"'`]+)\1", v)
    if m:
        key = m.group(2)
        txt = tr.get(key) or tr.get(key.split(":")[-1]) or tr.get(key.split(".")[-1])
        if txt:
            return txt
    return None


def _clean(label):
    label = re.sub(r"&(?=\w)", "", label).replace("&&", "&")
    label = re.sub(r"\{[^}]*\}", "", label).strip()
    return label[:1].upper() + label[1:] if label else label


def _keys(accel):
    if not accel:
        return ""
    parts = []
    for p in accel.split("+"):
        low = p.lower()
        parts.append({"cmdorctrl": "Ctrl", "commandorcontrol": "Ctrl", "control": "Ctrl", "ctrl": "Ctrl",
                      "command": "Ctrl", "cmd": "Ctrl", "shift": "Shift", "alt": "Alt", "option": "Alt",
                      "super": "Meta", "meta": "Meta", "plus": "+", "space": "Space", "return": "Return",
                      "enter": "Return", "escape": "Esc", "esc": "Esc", "delete": "Del",
                      "backspace": "Backspace"}.get(low, p.upper() if len(p) == 1 else p))
    return "+".join(parts)


def _item(obj, tr, depth):
    props = _top_props(obj)
    typ = _literal(props.get("type", "")) or ""
    if typ == "separator":
        return "separator"
    role = (_literal(props.get("role", "")) or "").lower()
    label = _label(props.get("label"), tr)
    if "submenu" in props and props["submenu"].startswith("[") and depth < 3:
        items = [x for x in (_item(o, tr, depth + 1) for o in _elements(props["submenu"])) if x]
        if role in ROLE_MENUS and not items:
            title, roles = ROLE_MENUS[role]
            items = [{"label": ROLE_KEYS[r][0], "keys": ROLE_KEYS[r][1]} if r else "separator" for r in roles]
        if label or role in ROLE_MENUS:
            return {"label": _clean(label or ROLE_MENUS[role][0]), "items": items}
        return None
    if role in ROLE_MENUS:
        title, roles = ROLE_MENUS[role]
        return {"label": _clean(label or title),
                "items": [{"label": ROLE_KEYS[r][0], "keys": ROLE_KEYS[r][1]} if r else "separator"
                          for r in roles]}
    keys = _keys(_literal(props.get("accelerator", "")) or "")
    if not keys and role in ROLE_KEYS:
        keys = ROLE_KEYS[role][1]
    if not label and role in ROLE_KEYS:
        label = ROLE_KEYS[role][0]
    if not label or not keys:
        return None  # nothing to show, or nothing hearth could run
    return {"label": _clean(label), "keys": keys}


def _tidy(items):
    out = []
    for it in items:
        if it == "separator" and (not out or out[-1] == "separator"):
            continue
        out.append(it)
    while out and out[-1] == "separator":
        out.pop()
    return out


def menus_for(path):
    files = open_app(path)
    if files is None:
        return []
    tr = translations(files)
    best = []
    for n in files.names():
        if not n.endswith((".js", ".cjs", ".mjs")) or "node_modules" in n or files.size(n) > MAX_JS:
            continue
        try:
            t = files.read(n)
        except Exception:
            continue
        if "submenu" not in t or ("buildFromTemplate" not in t and "setApplicationMenu" not in t
                                  and "Menu" not in t):
            continue
        # Arrays of top-level menus: an array whose elements have submenus.
        for m in re.finditer(r"submenu\s*:\s*\[", t):
            # The enclosing array of this menu object = a candidate template.
            i, depth = m.start(), 0
            while i > 0:
                i -= 1
                c = t[i]
                if c in ")]}":
                    depth += 1
                elif c in "([{":
                    if depth == 0:
                        if c == "{":
                            # the menu object; its parent should be the array
                            j = i
                            d2 = 0
                            while j > 0:
                                j -= 1
                                if t[j] in ")]}":
                                    d2 += 1
                                elif t[j] in "([{":
                                    if d2 == 0:
                                        break
                                    d2 -= 1
                            if t[j] == "[":
                                arr = t[j:_match(t, j)]
                                menus = [x for x in (_item(o, tr, 0) for o in _elements(arr))
                                         if isinstance(x, dict) and "items" in x]
                                score = sum(len(x["items"]) for x in menus)
                                if len(menus) >= 2 and score > sum(len(x["items"]) for x in best):
                                    best = menus
                        break
                    depth -= 1
    out = []
    for menu in best:
        items = _tidy([it for it in menu["items"] if it == "separator" or "keys" in it
                       or ("items" in it and it["items"])])
        if items:
            out.append({"title": menu["label"], "items": items})
    return out


def app_path(pid):
    """The running app's asar or directory, from its command line or next
    to its executable (bundled Electron)."""
    try:
        args = open(f"/proc/{pid}/cmdline", "rb").read().decode(errors="replace").split("\0")
    except OSError:
        return ""
    for a in args[1:]:
        if a.endswith(".asar") and os.path.isfile(a):
            return a
        if a.startswith("/") and os.path.isdir(a) and os.path.exists(os.path.join(a, "package.json")):
            return a
    try:
        exe = os.path.realpath(f"/proc/{pid}/exe")
    except OSError:
        return ""
    for cand in (os.path.join(os.path.dirname(exe), "resources", "app.asar"),
                 os.path.join(os.path.dirname(exe), "resources", "app")):
        if os.path.exists(cand):
            return cand
    return ""


if __name__ == "__main__":
    import sys
    print(json.dumps(menus_for(sys.argv[1]), indent=1, ensure_ascii=False))
