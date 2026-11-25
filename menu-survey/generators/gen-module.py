#!/usr/bin/env python3
"""Generate a menu module (menus/*.yaml, hearth-menu-module/1) from an app's
source, for apps whose toolkit exports no menus and has no accessibility
tree. Step 4 of MODULES.md's generator ladder: toolkit menu tables in
source, one parser per toolkit, so every app on that toolkit is covered.

Parsers (each returns [(title, [item | None])], item = (label, keys)):
  tk     Tcl/Tk: `set m [menu PATH]`, `X add cascade -label L -menu $m`,
         `$m add command -label L -accelerator A` (xmaxima, Scid)
  tkinter  Python Tkinter: add_cascade(label=, menu=), add_command(label=,
         accelerator=) (Thonny)
  xaml   Avalonia/WPF: <Menu><MenuItem Header="_File" InputGesture="Ctrl+O"/>
         (Ryubing, PixiEditor, SourceGit)
  winforms  *.Designer.cs: .Text, .ShortcutKeys, DropDownItems.AddRange (KeePass, CKAN)
  c-keytable  C default key tables with an action-description table
         (Terminology's ADD_KB + keyin.c)
  fltk   FLUID .fl files (Submenu/MenuItem with `shortcut 0x...`) and C++
         Fl_Menu_Item tables ({"&Open", FL_CTRL+'o', ...}) (ZynAddSubFX)

Only items with a keyboard shortcut become menu items: a module acts by
sending keys. Menus with none are left out.

Usage:
  gen-module.py --nixpkgs ATTR [--id ID] [--app-id A,B] > menus/ID.yaml
  gen-module.py --src DIR --id ID ...
The source comes from nixpkgs (`nix build nixpkgs#ATTR.src`), unpacked
under /var/tmp/menu-gen-src and only read (untrusted: nothing in it runs).
"""
import argparse
import datetime
import os
import re
import subprocess
import sys
import tarfile
import zipfile

WORK = "/var/tmp/menu-gen-src"
MOD = {"ctrl": "Ctrl", "control": "Ctrl", "ctl": "Ctrl", "alt": "Alt", "meta": "Alt", "option": "Alt",
       "shift": "Shift", "super": "Super", "cmd": "Ctrl", "command": "Ctrl", "mod1": "Alt"}


def norm_keys(s):
    """'Alt+b', 'Control-x', 'Ctrl+Shift+S', '<Control-s>' -> 'Alt+B' etc."""
    s = s.strip().strip("{}\"'").replace("Key-", "")
    if "><" in s or s.count("<") > 1:  # a key sequence (Netgen's <l><g>): not one chord
        return ""
    s = s.strip("<>")
    if not s:
        return ""
    parts = [p for p in re.split(r"[+-]", s) if p]
    if len(parts) > 1 and s[-1] in "+-":
        parts.append(s[-1])
    mods, key = [], parts[-1]
    for p in parts[:-1]:
        m = MOD.get(p.lower())
        if not m:
            return ""
        if m not in mods:
            mods.append(m)
    key = key.upper() if len(key) == 1 else key[:1].upper() + key[1:]
    order = [m for m in ("Ctrl", "Alt", "Shift", "Super") if m in mods]
    return "+".join(order + [key])


# ---------------------------------------------------------------- Tk

TK_MC = re.compile(r"\bmc\s+(?:\"([^\"]*)\"|\{([^}]*)\}|([^\s\]]+))")
TK_LIT = re.compile(r"(?:\"([^\"]*)\"|\{([^}]*)\}|(\S+))")
TK_ACCEL = re.compile(r"-accel(?:erator)?\s+(?:\{([^}]*)\}|\"([^\"]*)\"|(\S+))")


def tk_label(cmd):
    """-label's text: the message catalog's key wherever it's wrapped
    ([mc "File"], [set label [M [mc "Batch File"]]]), else the literal."""
    i = cmd.find("-label")
    if i < 0:
        return ""
    rest = cmd[i + 6:].lstrip()
    if rest.startswith("["):
        m = TK_MC.search(rest[:200])
        return next((g for g in m.groups() if g), "").strip() if m else ""
    m = TK_LIT.match(rest)
    return next((g for g in m.groups() if g), "").strip() if m else ""


def tk_menus(files):
    """The main menu bar from Tcl sources. Items: (label, accelerator, nav).
    nav reaches an item without an accelerator through Tk's mnemonics: Alt
    and the menu's underlined letter posts it (tk::TraverseToMenu), the
    entry's underlined letter invokes it (tk::TraverseWithinMenu). Only
    where the source sets -underline on both: counting arrow presses
    breaks on tearoffs and entries some platforms leave out."""
    entries, var = {}, {}
    for fn in files:
        try:
            text = open(fn, errors="replace").read()
        except OSError:
            continue
        text = re.sub(r"\\\n\s*", " ", text)
        var = {}
        for line in text.splitlines():
            line = line.strip()
            m = re.match(r"set\s+(\w+)\s+\[menu\s+(\S+)", line)
            if m:
                var[m.group(1)] = m.group(2)
                continue
            m = re.match(r"set\s+(\w+)\s+(\.[\w.]+)\s*$", line)
            if m:
                var[m.group(1)] = m.group(2)
            m = re.match(r"(\$\w+|\.[\w.$]+)\s+add\s+(cascade|command|checkbutton|radiobutton|separator)\b(.*)", line)
            if not m:
                continue
            who, kind, rest = m.groups()
            path = var.get(who[1:], who) if who.startswith("$") else who
            es = entries.setdefault(path, [])
            if kind == "separator":
                es.append(("sep",))
                continue
            label = tk_label(rest)
            ul = re.search(r"-underline\s+(\d+)", rest)
            ul = int(ul.group(1)) if ul else -1
            if kind == "cascade":
                sub = re.search(r"-menu\s+(?:\$(\w+)|\[menu\s+(\S+)|(\.[\w.]+))", rest)
                sp = (var.get(sub.group(1)) if sub.group(1) else (sub.group(2) or sub.group(3))) if sub else None
                es.append(("cascade", label, sp, ul))
                continue
            acc = TK_ACCEL.search(rest)
            keys = norm_keys(next((g for g in acc.groups() if g), "")) if acc else ""
            es.append(("item", label, keys, ul))
    subs = {e[2] for es in entries.values() for e in es if e[0] == "cascade"}
    roots = [p for p, es in entries.items() if p not in subs and sum(e[0] == "cascade" for e in es) >= 2]
    if not roots:
        return []
    root = max(roots, key=lambda p: sum(e[0] == "cascade" for e in entries[p]))
    out = []
    def letter(label, ul):
        c = label[ul] if 0 <= ul < len(label) else ""
        return c.upper() if c.isalnum() else ""

    for e in (x for x in entries[root] if x[0] == "cascade"):
        _, title, sp, mul = e
        ml = letter(title, mul)
        items, seen, used = [], set(), set()
        for x in entries.get(sp, []):
            if x[0] == "sep":
                items.append(None)
                continue
            if x[0] == "item" and x[1] and x[1] not in seen:
                seen.add(x[1])
                il = letter(x[1], x[3])
                # Tk invokes the first entry with that letter: a later one
                # sharing it can't be reached this way.
                nav = f"Escape Alt+{ml} {il.lower()}" if ml and il and il not in used else ""
                used.add(il)
                items.append((x[1], x[2], nav))
        if title:
            out.append((title, items))
    return out


def tkinter_menus(files):
    """Python Tkinter: `m = tk.Menu(bar)`, `bar.add_cascade(label=_("File"),
    menu=m)`, `m.add_command(label="Open", accelerator="Ctrl+O")`."""
    titles, items, order = {}, {}, []
    s = r"(?:_|N_|gettext|tr)?\(?\s*[rbuf]?[\"']([^\"']*)[\"']\s*\)?"
    for fn in files:
        try:
            text = open(fn, errors="replace").read()
        except OSError:
            continue
        if "add_cascade" not in text and "add_command" not in text:
            continue
        text = re.sub(r"\(\s*\n\s*", "(", text)
        for m in re.finditer(r"([\w.\[\]'\"]+)\.(add_cascade|add_command|add_checkbutton|add_radiobutton|add_separator)\s*\(([^)]*(?:\([^)]*\)[^)]*)*)\)", text):
            who, kind, args = m.groups()
            key = (fn, who)
            lab = re.search(r"\blabel\s*=\s*" + s, args)
            label = lab.group(1).strip() if lab else ""
            if kind == "add_cascade":
                sub = re.search(r"\bmenu\s*=\s*([\w.\[\]'\"]+)", args)
                if sub and label:
                    sk = (fn, sub.group(1))
                    titles[sk] = label
                    if sk not in order:
                        order.append(sk)
                continue
            if kind == "add_separator":
                items.setdefault(key, []).append(None)
                continue
            acc = re.search(r"\baccelerator\s*=\s*" + s, args)
            keys = norm_keys(acc.group(1)) if acc else ""
            if label:
                items.setdefault(key, []).append((label.replace("&", ""), keys))
    return [(titles[k], items.get(k, [])) for k in order]


# ---------------------------------------------------------------- FLTK

FL_MASK = {0x10000: "Shift", 0x40000: "Ctrl", 0x80000: "Alt", 0x400000: "Super"}
FL_KEYS = {0xff08: "BackSpace", 0xff09: "Tab", 0xff0d: "Return", 0xff1b: "Escape", 0xffff: "Delete",
           0xff50: "Home", 0xff57: "End", 0xff55: "Page_Up", 0xff56: "Page_Down", 0xff63: "Insert",
           0xff51: "Left", 0xff52: "Up", 0xff53: "Right", 0xff54: "Down"}


def fl_keys(v):
    mods = [n for bit, n in FL_MASK.items() if v & bit]
    k = v & 0xffff
    if 0xffbd < k <= 0xffbd + 12:
        key = f"F{k - 0xffbd}"
    elif k in FL_KEYS:
        key = FL_KEYS[k]
    elif 32 < k < 127:
        key = chr(k).upper()
    else:
        return ""
    order = [m for m in ("Ctrl", "Alt", "Shift", "Super") if m in mods]
    return "+".join(order + [key])


def fl_expr(e):
    """FL_CTRL+'o', FL_COMMAND|FL_SHIFT+'s', FL_F+2, 0x4006f -> keys."""
    e = e.strip()
    if re.fullmatch(r"0x[0-9a-fA-F]+|\d+", e):
        return fl_keys(int(e, 0))
    v = 0
    for tok in re.split(r"\s*[+|]\s*", e):
        if tok in ("FL_CTRL", "FL_COMMAND", "FL_CONTROL"):
            v |= 0x40000
        elif tok == "FL_ALT":
            v |= 0x80000
        elif tok == "FL_SHIFT":
            v |= 0x10000
        elif tok == "FL_META":
            v |= 0x400000
        elif re.fullmatch(r"'(\\?.)'", tok):
            v |= ord(tok[1:-1][-1])
        elif re.fullmatch(r"FL_F", tok):
            v |= 0xffbd
        elif re.fullmatch(r"\d+", tok):
            v += int(tok)
        elif tok in ("FL_Delete", "FL_BackSpace", "FL_Escape", "FL_Enter", "FL_Home", "FL_End"):
            v |= {"FL_Delete": 0xffff, "FL_BackSpace": 0xff08, "FL_Escape": 0xff1b, "FL_Enter": 0xff0d,
                  "FL_Home": 0xff50, "FL_End": 0xff57}[tok]
        elif tok in ("0", ""):
            pass
        else:
            return ""
    return fl_keys(v) if v & 0xffff else ""


def fl_clean(label):
    return label.replace("&&", "\0").replace("&", "").replace("\0", "&").replace("@", "").strip()


def fluid_blocks(text, i=0):
    """FLUID's `Kind name {attrs} {children}` blocks from position i, nested:
    [(kind, attrs, children)]. Stops at the closing brace of the caller."""
    out = []
    n = len(text)

    def brace(j):  # j at "{": index after its matching "}"
        d = 0
        while j < n:
            c = text[j]
            if c == "\\":
                j += 2
                continue
            if c == "{":
                d += 1
            elif c == "}":
                d -= 1
                if d == 0:
                    return j + 1
            j += 1
        return n

    ws = re.compile(r"\s*")
    word = re.compile(r"[^\s{}]+")
    while i < n:
        i = ws.match(text, i).end()
        if i >= n:
            break
        if text[i] == "}":
            return out, i + 1
        m = word.match(text, i)
        if not m:  # a stray "{": skip its group
            i = brace(i)
            continue
        kind, i = m.group(0), ws.match(text, m.end()).end()
        # name: a braced group ({} when empty, decl {int x;}) or a word
        if i < n and text[i] == "{":
            i = brace(i)
        else:
            m = word.match(text, i)
            i = m.end() if m else i
        i = ws.match(text, i).end()
        attrs, kids = "", []
        if i < n and text[i] == "{":
            a1 = brace(i)
            attrs, i = text[i + 1:a1 - 1], a1
            j = ws.match(text, i).end()
            if j < n and text[j] == "{":
                kids, i = fluid_blocks(text, j + 1)
        out.append((kind, attrs, kids))
    return out, n


def fluid_menus(files):
    """FLUID: the Menu_Bar's Submenus as menus, their MenuItems (nested
    submenus flattened as "Sub › Item") with `shortcut 0x...`."""
    out = []

    def label_of(attrs):
        lab = re.search(r"label\s+(?:\{([^}]*)\}|\"([^\"]*)\"|(\S+))", attrs)
        return fl_clean(next((g for g in lab.groups() if g), "")) if lab else ""

    def items_of(kids, prefix=""):
        res = []
        for kind, attrs, sub in kids:
            label = label_of(attrs)
            if kind == "Submenu":
                res += items_of(sub, f"{prefix}{label} › " if label else prefix)
            elif kind == "MenuItem" and label:
                sc = re.search(r"shortcut\s+(0x[0-9a-fA-F]+|\d+)", attrs)
                res.append((prefix + label, fl_keys(int(sc.group(1), 0)) if sc else ""))
                if re.search(r"\bdivider\b", attrs):
                    res.append(None)
        return res

    def walk(blocks):
        for kind, attrs, kids in blocks:
            if kind in ("Fl_Menu_Bar", "Fl_Sys_Menu_Bar"):
                for k2, a2, sub in kids:
                    if k2 == "Submenu" and label_of(a2):
                        out.append((label_of(a2), items_of(sub)))
            else:
                walk(kids)

    for fn in files:
        try:
            text = open(fn, errors="replace").read()
        except OSError:
            continue
        walk(fluid_blocks(text)[0])
    return out


def flcxx_menus(files):
    """C++ Fl_Menu_Item tables: {"&File", 0, 0, 0, FL_SUBMENU}, {"&Open", FL_CTRL+'o', cb}, {0}."""
    out = []
    for fn in files:
        try:
            text = open(fn, errors="replace").read()
        except OSError:
            continue
        for tab in re.finditer(r"Fl_Menu_Item\s+\w+\s*\[\s*\]\s*=\s*\{(.*?)\};", text, re.S):
            depth = 0
            body = re.sub(r"\b(?:_|N_|gettext|tr|_t)\s*\(\s*(\"(?:[^\"\\]|\\.)*\")\s*\)", r"\1", tab.group(1))
            body = re.sub(r"\(\s*(?:const\s+)?char\s*\*\s*\)", "", body)
            for it in re.finditer(r"\{\s*(?:\"((?:[^\"\\]|\\.)*)\"|0|NULL|nullptr)\s*(?:,([^{}]*))?\}", body):
                label, rest = it.group(1), it.group(2) or ""
                if label is None:
                    depth = max(0, depth - 1)
                    continue
                args = [a.strip() for a in rest.split(",")]
                flags = args[3] if len(args) > 3 else ""
                if "FL_SUBMENU" in flags:
                    depth += 1
                    if depth == 1:
                        out.append((fl_clean(label), []))
                    continue
                if out and depth >= 1:
                    out[-1][1].append((fl_clean(label), fl_expr(args[0]) if args else ""))
                    if "FL_MENU_DIVIDER" in flags:
                        out[-1][1].append(None)
    return out


# ---------------------------------------------------------------- .NET

def xaml_menus(files):
    """Avalonia/WPF XAML: <Menu> trees of <MenuItem Header="_File"
    InputGesture="Ctrl+O"/> (or HotKey=). Bound or resource headers
    ({Binding ...}, {DynamicResource ...}) can't be read and are left out,
    unless a resource file gives the text (resolve_keys)."""
    import xml.etree.ElementTree as ET
    out = []

    def local(tag):
        return tag.rsplit("}", 1)[-1]

    def header(el):
        h = el.get("Header") or ""
        m = re.match(r"\{(?:x:Static\s+\S*?\.|DynamicResource\s+|StaticResource\s+|i18n:Translate\s+)(\w+)\}", h)
        if m:
            return m.group(1)  # a resource key: resolve_keys may find its text
        if h.startswith("{"):
            # <MenuItem.Header><TextBlock Text="..."/></MenuItem.Header>
            return ""
        if not h:
            for c in el:
                if local(c.tag) == "MenuItem.Header":
                    t = next((x.get("Text") for x in c.iter() if x.get("Text")), "")
                    return "" if t.startswith("{") else t
        return h.strip()  # "_File": the access key stays until mnemonics()

    def items_of(el, prefix=""):
        res = []
        for c in el:
            t = local(c.tag)
            if t == "Separator":
                res.append(None)
            elif t == "MenuItem":
                h = header(c)
                subs = [x for x in c if local(x.tag) in ("MenuItem", "Separator")]
                if subs:
                    res += items_of(c, f"{prefix}{h} › " if h else prefix)
                elif h:
                    g = c.get("InputGesture") or c.get("HotKey") or c.get("Gesture") or ""
                    res.append((prefix + h, norm_keys(g) if not g.startswith("{") else ""))
        return res

    for fn in files:
        try:
            root = ET.parse(fn).getroot()
        except (ET.ParseError, OSError):
            continue
        for menu in root.iter():
            if local(menu.tag) != "Menu":
                continue
            for top in menu:
                if local(top.tag) == "MenuItem" and header(top):
                    out.append((header(top), items_of(top)))
    return out


WF_KEY = {"Control": "Ctrl", "Alt": "Alt", "Shift": "Shift"}


def winforms_menus(files):
    """WinForms: the designer's `x.Text = "&File";` and
    `x.DropDownItems.AddRange(new ...[] {a, b})` (menu trees, per file),
    shortcuts from `x.ShortcutKeys = Keys.Control | Keys.O` or any call
    passing the item and its keys (KeePass's UIUtil.AssignShortcut(item,
    Keys.Control | Keys.N)). The largest menu strip wins."""
    text_of, keys_of, trees = {}, {}, []

    def keys(expr):
        parts = re.findall(r"Keys\.(\w+)", expr)
        mods = [WF_KEY[p] for p in parts if p in WF_KEY]
        ks = [p for p in parts if p not in WF_KEY and p != "None"]
        if not ks:
            return ""
        k = ks[-1]
        k = k[1:] if re.fullmatch(r"D\d", k) else k
        return "+".join([x for x in ("Ctrl", "Alt", "Shift") if x in mods] + [k])

    for fn in files:
        try:
            src = open(fn, errors="replace").read()
        except OSError:
            continue
        if "Keys." not in src and "ToolStripMenuItem" not in src:
            continue
        for m in re.finditer(r"(?:this\.)?(\w+)\.Text\s*=\s*\"((?:[^\"\\]|\\.)*)\"", src):
            text_of.setdefault(m.group(1), m.group(2))
        for m in re.finditer(r"(?:this\.)?(\w+)\.ShortcutKeys\s*=\s*([^;]+);", src):
            keys_of[m.group(1)] = keys(m.group(2))
        for m in re.finditer(r"\(\s*(?:this\.)?(m?_?\w*[Mm]enu\w*)\s*,\s*((?:\(?\s*Keys\.\w+\s*\)?\s*\|?\s*)+)\)", src):
            keys_of.setdefault(m.group(1), keys(m.group(2)))
        kids, strips = {}, []
        for m in re.finditer(r"(?:this\.)?(\w+)\.(DropDownItems|Items|MenuItems)\.AddRange\(\s*new[^{]*\{([^}]*)\}", src, re.S):
            kids[m.group(1)] = re.findall(r"(?:this\.)?(\w+)\s*[,\n}]", m.group(3) + ",")
            if m.group(2) == "Items" and re.search(r"menu", m.group(1), re.I):
                strips.append(m.group(1))
        if strips:
            trees.append((kids, strips))

    def clean(t):
        return t.replace("&&", "\0").replace("&", "").replace("\0", "&").strip()

    def items_of(kids, name, prefix="", depth=0):
        res = []
        for n in kids.get(name, []):
            t = clean(text_of.get(n, ""))
            if re.search(r"sep", n, re.I) or t == "-":
                res.append(None)
            elif kids.get(n) and depth < 3:
                res += items_of(kids, n, f"{prefix}{t} › " if t else prefix, depth + 1)
            elif t:
                res.append((prefix + t, keys_of.get(n, "")))
        return res

    best_out = []
    for kids, strips in trees:
        for st in strips:
            out = [(clean(text_of.get(top, "")), items_of(kids, top)) for top in kids.get(st, [])
                   if clean(text_of.get(top, "")) and kids.get(top)]
            if sum(len(i) for _, i in out) > sum(len(i) for _, i in best_out):
                best_out = out
    return best_out

# ---------------------------------------------------------------- C key tables

C_BIND = re.compile(r"\(\s*(?:\w+\s*,\s*)?\"([^\"]+)\"\s*,\s*([01])\s*,\s*([01])\s*,\s*([01])\s*,\s*([01])\s*,\s*\"(\w+)\"\s*\)")
C_DESC = re.compile(r"\{\s*\"(\w+)\"\s*,\s*(?:gettext_noop|N_|_)\s*\(\s*\"([^\"]+)\"\s*\)")
C_KEYS = {"Prior": "Page_Up", "Next": "Page_Down"}
C_GROUPS = [("Edit", ("copy", "paste", "select", "cut", "undo", "redo", "find", "search")),
            ("Shell", ("tab", "term", "split", "session", "pane", "new", "close")),
            ("View", ("win", "fullscreen", "font", "zoom", "scroll", "backlog", "size", "visible", "group"))]


def ckeytable_menus(files):
    """C default key tables: ("Key", ctrl, alt, shift, win, "action") calls
    or macros (Terminology's ADD_KB) with the actions' descriptions from a
    {"action", gettext_noop("Description"), cb} table. Menus by the action
    name's words (copy/paste: Edit, tab/term: Shell, win/font: View)."""
    binds, desc = {}, {}
    for fn in files:
        try:
            text = open(fn, errors="replace").read()
        except OSError:
            continue
        for m in C_BIND.finditer(text):
            key, c, a, sh, w, act = m.groups()
            mods = [n for n, v in (("Ctrl", c), ("Alt", a), ("Shift", sh), ("Super", w)) if v == "1"]
            k = C_KEYS.get(key, key)
            binds.setdefault(act, "+".join(mods + [k[:1].upper() + k[1:] if len(k) > 1 else k.upper()]))
        for m in C_DESC.finditer(text):
            desc.setdefault(m.group(1), m.group(2))
    if len(binds) < 5 or sum(1 for a in binds if a in desc) < 3:
        return []
    menus = {}
    for act, keys in binds.items():
        if act not in desc:
            continue
        title = next((t for t, words in C_GROUPS if any(w in act.lower().split("_") or act.lower().startswith(w)
                                                        for w in words)), "Actions")
        menus.setdefault(title, []).append((desc[act], keys))
    order = [t for t, _ in C_GROUPS] + ["Actions"]
    return [(t, menus[t]) for t in order if t in menus]


# ---------------------------------------------------------------- driver

PARSERS = [
    ("tk", (".tcl", ".tk"), tk_menus),
    ("tkinter", (".py",), tkinter_menus),
    ("fltk-fluid", (".fl",), fluid_menus),
    ("fltk-cxx", (".cxx", ".cpp", ".cc", ".h", ".H"), flcxx_menus),
    ("xaml", (".axaml", ".xaml"), xaml_menus),
    ("c-keytable", (".c",), ckeytable_menus),
    ("winforms", (".cs",), winforms_menus),
]


def fetch_nixpkgs_src(attr):
    p = subprocess.run(["nix", "build", "--no-link", "--print-out-paths", "--option", "max-jobs", "0",
                        f"nixpkgs#{attr}.src"], capture_output=True, text=True)
    src = (p.stdout.strip().splitlines() or [""])[-1]
    if not src:
        sys.exit(f"no source for {attr}: {p.stderr.strip()[-300:]}")
    if os.path.isdir(src):
        return src, os.path.basename(src)
    dest = os.path.join(WORK, os.path.basename(src))
    if not os.path.isdir(dest):
        os.makedirs(dest)
        if zipfile.is_zipfile(src):
            with zipfile.ZipFile(src) as z:
                for n in z.namelist():
                    if not n.startswith("/") and ".." not in n.split("/"):
                        z.extract(n, dest)
        else:
            with tarfile.open(src) as t:
                t.extractall(dest, filter="data")
    return dest, os.path.basename(src)


def sources(root, exts):
    for d, dirs, files in os.walk(root):
        dirs[:] = [x for x in dirs if not x.startswith(".") and x not in ("test", "tests", "examples", "doc")]
        for f in files:
            if f.endswith(exts):
                yield os.path.join(d, f)


KEYLIKE = re.compile(r"^[A-Z][a-z]+(?:[A-Z][A-Za-z0-9]*)+$")


def resolve_keys(menus, root):
    """Labels that are message-catalog keys ("FileExit", Scid's
    `menuText E FileExit "Exit" 1 ...`): the text after the key in the
    source's English catalog (a file named english/en/C), else anywhere."""
    keys = {l for t, its in menus for l in [t] + [i[0] for i in its if i] if KEYLIKE.match(l)}
    if not keys:
        return menus
    found = {}
    files = [f for f in sources(root, (".tcl", ".tk", ".py", ".txt", ".lang", ".msg", ".po", ".ini", ".json",
                                        ".resx", ".axaml", ".xaml"))]
    english = re.compile(r"(english|[/_.-]en([_.-]|$)|[/_.-]C\.)", re.I)
    for f in sorted(files, key=lambda f: 0 if english.search(f) else 1):
        if len(found) == len(keys):
            break
        try:
            text = open(f, errors="replace").read()
        except OSError:
            continue
        for k in keys - found.keys():
            e = re.escape(k)
            m = (re.search(r"\b" + e + r"\b\s+[\"{]([^\"}\n]+)[\"}]", text)            # Tcl: Key "Text"
                 or re.search(r"name=\"" + e + r"\"[^>]*>\s*<value>([^<]+)<", text)   # .resx
                 or re.search(r"\"" + e + r"\"\s*:\s*\"([^\"\n]+)\"", text)         # JSON
                 or re.search(r"x:Key=\"" + e + r"\"[^>]*>([^<]+)<", text))           # XAML string
            if m:
                found[k] = m.group(1).strip()
    fix = lambda l: found.get(l, l)
    return [(fix(t), [None if i is None else (fix(i[0]),) + tuple(i[1:]) for i in its]) for t, its in menus]


def mnemonics(menus):
    """XAML access keys ("_File", "_Open"): Alt and the menu's letter opens
    it, each level's letter goes down ("Sub › Item"). Items without a
    shortcut get that as their keys; underscores leave the labels."""
    def letter(seg):
        m = re.search(r"(?<!_)_([A-Za-z0-9])", seg)
        return m.group(1) if m else ""

    def clean(seg):
        return seg.replace("__", "\0").replace("_", "").replace("\0", "_")

    out = []
    for title, its in menus:
        ml = letter(title)
        new, used = [], {}
        for i in its:
            if i is None:
                new.append(None)
                continue
            segs = i[0].split(" › ")
            lets = [letter(x) for x in segs]
            nav = ""
            if ml and all(lets):
                path = " ".join(x.lower() for x in lets)
                if path not in used:  # the first entry with a letter wins
                    nav = f"Escape Alt+{ml.upper()} {path}"
                used[path] = True
            new.append((" › ".join(clean(x) for x in segs), i[1], nav))
        out.append((clean(title), new))
    return out


def best(root):
    """The parser with the most shortcut items."""
    res = []
    for name, exts, fn in PARSERS:
        files = list(sources(root, exts))
        usable = lambda i: i and (i[1] or (len(i) > 2 and i[2]) or (name == "xaml" and "_" in i[0]))
        menus = [(t, its) for t, its in fn(files) if any(usable(i) for i in its)]
        n = sum(1 for _, its in menus for i in its if usable(i))
        if n:
            res.append((n, name, menus, files))
    return max(res, key=lambda r: r[0]) if res else None


def yaml_str(s):
    return s if re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9 ._()/&'…-]*[A-Za-z0-9.)…]?", s) and ": " not in s \
        else '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def emit(mid, app_ids, attr, parser, origin, menus):
    out = [f"# Generated by menu-survey/generators/gen-module.py ({parser}) from {origin}.",
           "# Only items with a keyboard shortcut; regenerate rather than edit.",
           "schema: hearth-menu-module/1", f"id: {mid}", "version: 1", "app:", "  match:",
           f"    app_id: [{', '.join(yaml_str(a) for a in app_ids)}]"]
    if attr:
        out.append(f"    nixpkgs: [{attr}]")
    out += ["  locales: [en]", "provenance:",
            f"  generator: hearth-menu-gen 0.1 / {parser} ({origin}, {datetime.date.today()})",
            "menus:"]
    for title, its in menus:
        keep = []
        for i in its:
            if i is None:
                if keep and keep[-1] is not None:
                    keep.append(None)
            elif i[0].strip() and (i[1] or (len(i) > 2 and i[2])):
                keep.append(i)
        while keep and keep[-1] is None:
            keep.pop()
        if not keep:
            continue
        out += [f"  - title: {yaml_str(title)}", "    items:"]
        for i in keep:
            if i is None:
                out.append("      - separator")
            else:
                label = i[0].replace("...", "…")
                if i[1]:
                    k = yaml_str(i[1])
                    out.append(f"      - {{ label: {yaml_str(label)}, shortcut: {k}, do: {{ keys: {k} }} }}")
                else:  # through the app's own menu bar, from the keyboard
                    out.append(f"      - {{ label: {yaml_str(label)}, do: {{ keys: \"{i[2]}\" }} }}")
    return "\n".join(out) + "\n"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--nixpkgs")
    ap.add_argument("--src")
    ap.add_argument("--id")
    ap.add_argument("--app-id", default="")
    a = ap.parse_args()
    if a.nixpkgs:
        root, origin = fetch_nixpkgs_src(a.nixpkgs)
    elif a.src:
        root, origin = a.src, os.path.basename(os.path.abspath(a.src))
    else:
        ap.error("--nixpkgs or --src")
    found = best(root)
    if not found:
        sys.exit("no menu table with shortcuts found")
    n, parser, menus, _ = found
    menus = resolve_keys(menus, root)
    if parser == "xaml":
        menus = mnemonics(menus)
    mid = a.id or a.nixpkgs or origin
    app_ids = [x for x in a.app_id.split(",") if x] or [mid]
    print(f"{parser}: {n} items in {len(menus)} menus", file=sys.stderr)
    sys.stdout.write(emit(mid, app_ids, a.nixpkgs, parser, origin, menus))


if __name__ == "__main__":
    main()
