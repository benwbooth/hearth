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
    s = s.strip().strip("{}\"'<>").replace("Key-", "")
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


def fluid_menus(files):
    """FLUID: `Submenu {} {label {&File} ...} { MenuItem {} {label {&Open...} ... shortcut 0x4006f} }`."""
    out = []
    for fn in files:
        try:
            text = open(fn, errors="replace").read()
        except OSError:
            continue
        # Walk Submenu/MenuItem blocks in order; a Submenu's items follow
        # until the next Submenu at the same nesting (good enough for menu
        # bars, which nest one level).
        for m in re.finditer(r"\b(Submenu|MenuItem)\s+\S*\s*\{([^{}]*(?:\{[^{}]*\}[^{}]*)*)\}", text):
            kind, body = m.groups()
            lab = re.search(r"label\s+(?:\{([^}]*)\}|\"([^\"]*)\"|(\S+))", body)
            label = fl_clean(next((g for g in lab.groups() if g), "")) if lab else ""
            if kind == "Submenu":
                if label:
                    out.append((label, []))
                continue
            if not out or not label:
                continue
            sc = re.search(r"shortcut\s+(0x[0-9a-fA-F]+|\d+)", body)
            out[-1][1].append((label, fl_keys(int(sc.group(1), 0)) if sc else ""))
            if re.search(r"\bdivider\b", body):
                out[-1][1].append(None)
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


# ---------------------------------------------------------------- driver

PARSERS = [
    ("tk", (".tcl", ".tk"), tk_menus),
    ("tkinter", (".py",), tkinter_menus),
    ("fltk-fluid", (".fl",), fluid_menus),
    ("fltk-cxx", (".cxx", ".cpp", ".cc", ".h", ".H"), flcxx_menus),
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


def best(root):
    """The parser with the most shortcut items."""
    res = []
    for name, exts, fn in PARSERS:
        files = list(sources(root, exts))
        usable = lambda i: i and (i[1] or (len(i) > 2 and i[2]))
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
            elif i[1] or (len(i) > 2 and i[2]):
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
                    out.append(f"      - {{ label: {yaml_str(label)}, shortcut: {i[1]}, do: {{ keys: {i[1]} }} }}")
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
    mid = a.id or a.nixpkgs or origin
    app_ids = [x for x in a.app_id.split(",") if x] or [mid]
    print(f"{parser}: {n} items in {len(menus)} menus", file=sys.stderr)
    sys.stdout.write(emit(mid, app_ids, a.nixpkgs, parser, origin, menus))


if __name__ == "__main__":
    main()
