#!/usr/bin/env python3
"""Classify an app's UI toolkit statically, without running or downloading it.

Sources, all read remotely from cache.nixos.org:
  closure   `nix path-info -r --store https://cache.nixos.org OUT` (narinfo
            references): which toolkits/runtimes are in the runtime closure.
  files     `nix store ls -R --store https://cache.nixos.org OUT`: bundled
            Electron/CEF/Flutter/XUL layouts (app.asar, libcef.so, libxul.so,
            libflutter_linux_gtk.so, ...).
  binary    the first 4 MiB of the main program (the desktop file's Exec,
            following nixpkgs wrapper scripts to the real ELF). .dynstr sits
            near the start of an ELF, so DT_NEEDED libraries and imported
            symbols show there: libQt6Quick vs libQt6Widgets,
            gtk_application_set_menubar vs gtk_menu_bar_new, adw_*, ...
For packages not on the cache (unfree), `--drv` uses the derivation's inputs
instead (`nix derivation show`), which is weaker (no symbol scan).

Usage:
  classify.py STORE_PATH [DESKTOP_EXEC]       one app, JSON to stdout
  classify.py --apps data/apps.tsv --top N    batch -> data/classified.jsonl (resumable)
"""
import argparse
import concurrent.futures as cf
import json
import os
import re
import shlex
import subprocess
import sys

CACHE = "https://cache.nixos.org"
ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")

# Strings looked for in the binary's first 4 MiB.
SYMS = [
    "libQt6Widgets.so", "libQt6Quick.so", "libQt6Qml.so", "libQt5Widgets.so", "libQt5Quick.so",
    "libQt5Qml.so", "libKF6XmlGui.so", "libKF5XmlGui.so", "libKF6Kirigami", "libKirigami",
    "libgtk-3.so", "libgtk-4.so", "libgtk-x11-2.0.so", "libadwaita-1.so", "libgranite",
    "gtk_application_set_menubar", "gtk_menu_bar_new", "_ZN3Gtk11Application11set_menubar",
    "_ZN3Gtk7MenuBarC", "_ZN3Gtk10PopoverMenuBar", "gtk_menu_item_new", "gtk_widget_insert_action_group", "gtk_popover_menu_bar_new",
    "gtk_application_window_set_show_menubar", "gtk_menu_button_new", "adw_application_new",
    "gtk_header_bar_new", "adw_header_bar_new", "libwx_gtk3u", "libwx_baseu", "libtk8", "libtcl8",
    "libfltk", "libSDL2-2.0.so", "libSDL3.so", "libglfw.so", "libvulkan.so", "libGL.so", "libEGL.so",
    "libxkbcommon.so", "libwayland-client.so", "libX11.so", "libflutter_linux_gtk.so", "libcef.so",
    "libxul.so", "libjvm.so", "libQt6WebEngine", "libQt5WebEngine", "libwebkit2gtk", "libwebkitgtk-6",
    "libdbusmenu", "QMenuBar", "_ZN8QMenuBar", "libmono", "libSkiaSharp", "libHarfBuzzSharp",
    "libgdk_pixbuf", "libnotcurses", "libncurses", "libimgui", "libelementary", "libefl",
    "GTK_IS_MENU_BAR", "gtk_menu_shell_append", "libslint", "winit", "eframe", "egui", "iced",
    "gpui", "libghostty", "Electron", "libnode.so", "libcairo.so",
]

# Closure store-path names -> markers (prefix match on the name after the hash).
CLOSURE = [
    ("electron", r"^electron(-unwrapped)?-\d"), ("qtbase6", r"^qtbase-6"), ("qtbase5", r"^qtbase-5"),
    ("qtdeclarative6", r"^qtdeclarative-6"), ("qtdeclarative5", r"^qtdeclarative-5"),
    ("qtwebengine", r"^qtwebengine-"), ("kxmlgui", r"^kxmlgui-"), ("kirigami", r"^kirigami-"),
    ("gtk4", r"^gtk4-\d"), ("gtk3", r"^gtk\+3-\d"), ("gtk2", r"^gtk\+-2"), ("libadwaita", r"^libadwaita-"),
    ("granite", r"^granite-"), ("wx", r"^wxwidgets-|^wxGTK"), ("tk", r"^tk-8|^tk-9"),
    ("fltk", r"^fltk-"), ("sdl2", r"^SDL2-2|^sdl2-compat"), ("sdl3", r"^sdl3-|^SDL3-"),
    ("glfw", r"^glfw-"), ("jdk", r"^(openjdk|zulu|jdk|jre|temurin|jetbrains-jdk|openjfx)"),
    ("openjfx", r"^openjfx"), ("python", r"^python3-3"), ("pygobject", r"^python3.*pygobject"),
    ("pyqt", r"^python3.*(pyqt|pyside)"), ("gjs", r"^gjs-"), ("wine", r"^wine(64|-wow|-staging|)-?\d|^wine-"),
    ("mono", r"^mono-"), ("dotnet", r"^dotnet-(runtime|sdk)"), ("webkitgtk", r"^webkitgtk-"),
    ("flutter", r"^flutter"), ("libdbusmenu", r"^libdbusmenu-"), ("appindicator", r"appindicator"),
    ("firefox", r"^firefox-unwrapped|^thunderbird-unwrapped|^librewolf-unwrapped"),
    ("chromium", r"^chromium-unwrapped|^ungoogled-chromium"), ("nodejs", r"^nodejs-"),
    ("libGL", r"^libGL|^libglvnd"), ("vulkan", r"^vulkan-loader"), ("efl", r"^efl-"),
    ("ncurses", r"^ncurses-"), ("godot", r"^godot"), ("love", r"^love-"),
    ("libxkbcommon", r"^libxkbcommon-"), ("wayland", r"^wayland-1"),
]

FILES = [
    ("asar", r"/resources/app\.asar$"), ("electron_files", r"/(resources\.pak|v8_context_snapshot\.bin|chrome_100_percent\.pak)$"),
    ("libcef", r"/libcef\.so$"), ("libxul", r"/libxul\.so$"), ("libflutter", r"/libflutter_linux_gtk\.so$"),
    ("qml", r"\.qml$"), ("ui_gtk", r"\.ui$"), ("blp", r"\.blp$"), ("jar", r"\.jar$"),
    ("pyfile", r"\.py$"), ("jsfile", r"/share/[^/]+/js/.*\.js$|\.src\.gresource$"), ("gresource", r"\.gresource$"),
    ("exe", r"\.exe$"), ("love", r"\.love$"), ("pck", r"\.pck$"), ("unity", r"UnityPlayer\.so$"),
    ("electron_ver", r"/electron/version$"),
]


def run(args, timeout=120, binary=False, limit=None):
    try:
        p = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        if limit:
            data = p.stdout.read(limit)
            p.kill()
            p.wait()
            return data
        data, _ = p.communicate(timeout=timeout)
        return data if binary else data.decode(errors="replace")
    except Exception:
        return b"" if binary else ""


def closure(out):
    names = []
    for l in run(["nix", "path-info", "-r", "--store", CACHE, out]).split():
        b = os.path.basename(l)
        names.append(b[33:] if len(b) > 33 else b)
    return names


LINKS = {}


def files(out):
    """Paths in the output ("./bin/foo"); symlink targets go to LINKS."""
    res = []
    for l in run(["nix", "store", "ls", "-lR", "--store", CACHE, out], timeout=300).splitlines():
        m = re.match(r"^\S+\s+\d+\s+(\./\S.*?)(?: -> (.*))?$", l)
        if not m:
            continue
        res.append(m.group(1))
        if m.group(2):
            tgt = m.group(2)
            if not tgt.startswith("/"):
                tgt = os.path.normpath(os.path.join(out, os.path.dirname(m.group(1)[2:]), tgt))
            LINKS[out + "/" + m.group(1)[2:]] = tgt
    return res


def cat(path, limit=None):
    return run(["nix", "store", "cat", "--store", CACHE, path], binary=True, limit=limit)


def resolve_exec(out, exec_line, flist):
    """Desktop Exec -> the real program in the store (following wrapper scripts)."""
    try:
        argv = shlex.split(exec_line or "")
    except ValueError:
        argv = (exec_line or "").split()
    argv = [a for a in argv if not a.startswith("%") and "=" not in a.split("/")[0]]
    while argv and argv[0] in ("env", "sh", "bash", "-c", "flatpak-spawn"):
        argv = argv[1:]
    prog = argv[0] if argv else ""
    if not prog:
        bins = [f for f in flist if re.match(r"\./bin/[^./][^/]*$", f)]
        if not bins:
            return None, []
        prog = os.path.basename(bins[0])
    if prog.startswith("/nix/store/"):
        path = prog
    else:
        name = os.path.basename(prog)
        cands = [f for f in flist if f.endswith("/bin/" + name)]
        if not cands:
            return None, argv
        path = out + cands[0].split(out.split("/")[-1], 1)[-1] if not cands[0].startswith("/") else cands[0]
        path = out + "/" + cands[0].lstrip("./") if not cands[0].startswith("/nix") else cands[0]
    return path, argv


def follow(path, depth=0):
    """Return (elf_head_bytes, path, chain). Follows shell wrappers and symlinks."""
    hops = 0
    while path in LINKS and hops < 8:
        path, hops = LINKS[path], hops + 1
    head = cat(path, limit=4 << 20)
    if not head and depth < 5:
        # A symlink into another store path: ask that path's listing.
        m = re.match(r"(/nix/store/[^/]+)/(.*)", path)
        if m:
            for l in run(["nix", "store", "ls", "-l", "--store", CACHE, path]).splitlines():
                t = re.search(r" -> (.*)$", l)
                if t:
                    tgt = t.group(1)
                    if not tgt.startswith("/"):
                        tgt = os.path.normpath(os.path.join(os.path.dirname(path), tgt))
                    return follow(tgt, depth + 1)
    chain = [path]
    if depth > 5:
        return head, path, chain
    if head[:4] == b"\x7fELF":
        # makeBinaryWrapper: a small ELF that needs only libc and embeds the
        # real program's store path ("/nix/store/...-foo/bin/.foo-wrapped").
        libs = set(re.findall(rb"lib[A-Za-z0-9_+-]+\.so[.0-9]*", head))
        if len(head) < (1 << 20) and libs <= {b"libc.so.6"}:
            ts = re.findall(rb"makeCWrapper '([^']+)'", head) or \
                re.findall(rb"/nix/store/[a-z0-9]{32}-[^\x00\s\"']+/\.[^\x00\s\"'/]+-wrapped", head) or \
                re.findall(rb"/nix/store/[a-z0-9]{32}-[^\x00\s\"']+/(?:bin|libexec)/[^\x00\s\"']+", head)
            for t in ts:
                t = t.decode(errors="replace")
                if not re.search(r"/bin/(bash|sh|env)$|ld-linux|/glibc-", t):
                    h, p, c = follow(t, depth + 1)
                    return h, p, chain + c
        return head, path, chain
    text = head[:200000].decode(errors="replace")
    if head[:2] == b"#!":
        # nixpkgs wrappers: exec -a "$0" "/nix/store/...-foo/bin/.foo-wrapped" "$@"
        m = re.findall(r'exec\s+(?:-a\s+"?\S+"?\s+)?"?(/nix/store/[^"\s]+)"?', text)
        if not m:
            m = re.findall(r'(/nix/store/[^"\s\']+/(?:bin|libexec|lib)/[^"\s\']+)', text)
        # Prefer a target that is not an interpreter.
        for t in reversed(m):
            if not re.search(r"/bin/(bash|sh|env|python3?[\d.]*|gjs|node|java|perl|ruby|lua)$", t):
                h, p, c = follow(t, depth + 1)
                return h, p, chain + c
        interp = re.match(r"#!\s*(\S+)", text)
        return head, path, chain + ([interp.group(1)] if interp else [])
    return head, path, chain


def classify_store(out, exec_line=""):
    names = closure(out)
    flist = files(out)
    cm = {k for k, rx in CLOSURE for n in names if re.search(rx, n)}
    fm = {k for k, rx in FILES for f in flist if re.search(rx, f)}
    electron_ver = ""
    for n in names:
        m = re.match(r"^electron(?:-unwrapped)?-(\d+[\d.]*)", n)
        if m:
            electron_ver = m.group(1)
    prog, argv = resolve_exec(out, exec_line, flist)
    sm, chain = set(), []
    if prog:
        head, real, chain = follow(prog)
        for s in SYMS:
            if s.encode() in head:
                sm.add(s)
        if head[:4] != b"\x7fELF":
            text = head[:400000].decode(errors="replace")
            if re.search(r"electron", text, re.I):
                sm.add("script:electron")
            if re.search(r"\bjava\b|\.jar\b", text):
                sm.add("script:java")
            if "gjs" in text:
                sm.add("script:gjs")
            if re.search(r"python", text):
                sm.add("script:python")
            if re.search(r"\bwine", text):
                sm.add("script:wine")
        if b"Electron/" in head or b"electron::" in head:
            sm.add("Electron")
    toolkit, menu_hint = decide(cm, fm, sm)
    return dict(store=out, toolkit=toolkit, menu_hint=menu_hint, electron=electron_ver,
                closure=sorted(cm), files=sorted(fm), syms=sorted(sm), chain=chain[:4])


def decide(cm, fm, sm):
    """Toolkit class, plus a menu hint (what kind of menu the app likely has)."""
    has = lambda *ks: any(k in cm or k in fm or k in sm for k in ks)
    if has("firefox", "libxul", "libxul.so"):
        return "firefox-xul", "menubar-hidden"
    if has("chromium") or (has("electron_files") and not has("asar") and not has("electron") and has("libcef") is False and "chrome" in " ".join(sm).lower()):
        return "chromium", "dbusmenu"
    if has("electron", "asar", "script:electron", "Electron", "electron_ver"):
        return "electron", "menubar"
    main_tk = has("libQt6Widgets.so", "libQt5Widgets.so", "libgtk-3.so", "libgtk-4.so", "libQt6Quick.so",
                  "libQt5Quick.so", "libwx_gtk3u")
    if has("libcef.so") or (has("libcef") and not main_tk):
        return "cef", "custom"
    if has("electron_files") and not main_tk:
        return "chromium", "dbusmenu"
    if has("libflutter", "libflutter_linux_gtk.so", "flutter"):
        return "flutter", "custom"
    if has("wine", "exe", "script:wine"):
        return "wine", "custom"
    if has("jar", "libjvm.so", "script:java") or (has("jdk") and not main_tk and not has("qtbase6", "qtbase5", "gtk4")):
        return ("javafx" if has("openjfx") else "java-swing"), "menubar"
    if has("libQt6Quick.so", "libQt5Quick.so", "libKF6Kirigami", "libKirigami") and not has("libQt6Widgets.so", "libQt5Widgets.so", "QMenuBar", "_ZN8QMenuBar", "libKF6XmlGui.so", "libKF5XmlGui.so"):
        return ("qt6-quick" if has("libQt6Quick.so", "qtbase6") else "qt5-quick"), "custom"
    if has("libQt6Widgets.so", "libKF6XmlGui.so") or (has("qtbase6") and not has("qtbase5")):
        if has("libQt6Quick.so") and not has("QMenuBar", "_ZN8QMenuBar"):
            return "qt6-mixed", "unknown"
        return "qt6-widgets", "menubar"
    if has("libQt5Widgets.so", "libKF5XmlGui.so", "qtbase5", "pyqt"):
        return "qt5-widgets", "menubar"
    if has("libmono", "mono", "dotnet", "libSkiaSharp"):
        return "dotnet", "custom"
    if has("wx", "libwx_gtk3u", "libwx_baseu"):
        return "wx-gtk3", "menubar"
    if has("libgtk-4.so", "gtk4", "libadwaita"):
        if has("libadwaita-1.so", "libadwaita", "adw_application_new"):
            return "gtk4-adwaita", "gmenu-popover"
        if has("gtk_application_set_menubar", "gtk_popover_menu_bar_new", "_ZN3Gtk11Application11set_menubar"):
            return "gtk4", "gmenu-menubar"
        return "gtk4", "gmenu-popover"
    if has("libgtk-3.so", "gtk3"):
        if has("libgranite", "granite"):
            return "gtk3", "headerbar"
        if has("gtk_application_set_menubar", "_ZN3Gtk11Application11set_menubar"):
            return "gtk3", "gmenu-menubar"
        if has("gtk_menu_bar_new", "GTK_IS_MENU_BAR", "gtk_menu_shell_append", "_ZN3Gtk7MenuBarC"):
            return "gtk3", "menubar"
        if has("gtk_header_bar_new"):
            return "gtk3", "headerbar"
        return "gtk3", "unknown"
    if has("gtk2", "libgtk-x11-2.0.so"):
        return "gtk2", "menubar"
    if has("tk", "libtk8"):
        return "tk", "menubar"
    if has("fltk", "libfltk"):
        return "fltk", "menubar"
    if has("efl", "libelementary"):
        return "efl", "custom"
    if has("godot", "pck", "unity", "love"):
        return "game-engine", "none"
    if has("sdl2", "sdl3", "glfw", "libSDL2-2.0.so", "libSDL3.so", "libglfw.so"):
        return "sdl-glfw", "none"
    if has("libxkbcommon.so", "libwayland-client.so", "libvulkan.so", "libEGL.so", "libGL.so", "libX11.so"):
        return "custom-drawn", "none"
    if has("ncurses", "libncurses"):
        return "tui", "none"
    return "unknown", "unknown"


def classify_drv(attr):
    """Unfree / uncached: derivation inputs only."""
    js = run(["nix", "derivation", "show", "--impure", "--inputs-from", "/etc/nixos", f"nixpkgs#{attr}"], timeout=180)
    try:
        d = json.loads(js)
    except Exception:
        return dict(attr=attr, toolkit="unknown", menu_hint="unknown", error="eval")
    drv = next(iter(d.values()))
    names = []
    for k in list(drv.get("inputDrvs", {}).keys()) + drv.get("inputSrcs", []):
        b = os.path.basename(k)
        names.append(b[33:].removesuffix(".drv") if len(b) > 33 else b)
    env = drv.get("env", {})
    names += [os.path.basename(s) for s in str(env.get("src", "")).split()]
    cm = {k for k, rx in CLOSURE for n in names if re.search(rx, n)}
    # Bundled Chromium-based binaries (discord, slack, obsidian...) link nss + libdrm + gtk3 + alsa.
    blob = " ".join(names).lower()
    if not cm & {"electron"} and all(x in blob for x in ("nss-", "alsa-lib", "libdrm")) and ("gtk+3" in blob or "gtk3" in blob):
        cm.add("electron_like")
    sm = set()
    if "electron_like" in cm:
        sm.add("Electron")  # cannot tell Electron from CEF/Chrome without the binary
    electron_ver = ""
    for n in names:
        m = re.match(r"^electron(?:-unwrapped)?-(\d+[\d.]*)", n)
        if m:
            electron_ver = m.group(1)
    toolkit, hint = decide(cm, set(), sm)
    return dict(attr=attr, toolkit=toolkit, menu_hint=hint, electron=electron_ver, closure=sorted(cm),
                via="drv")


def batch(apps_path, top, out_path, jobs):
    done = set()
    if os.path.exists(out_path):
        done = {json.loads(l)["attr"] for l in open(out_path)}
    rows = []
    with open(apps_path) as f:
        hdr = f.readline().rstrip("\n").split("\t")
        for line in f:
            r = dict(zip(hdr, line.rstrip("\n").split("\t")))
            if r.get("include", "1") == "0":
                continue
            rows.append(r)
    rows = [r for r in rows[:top] if r["attr"] not in done]
    entries = {}
    dpath = os.path.join(ROOT, "data", "desktop_entries.jsonl")
    if os.path.exists(dpath):
        for l in open(dpath):
            j = json.loads(l)
            entries.setdefault(os.path.basename(j["path"]), []).append(j)

    def one(r):
        try:
            if r["source"] == "flathub":
                return dict(attr=r["attr"], toolkit="flathub-pending", menu_hint="unknown")
            if not r["store"]:
                return classify_drv(r["attr"])
            ex = ""
            for d in r["desktops"].split(","):
                for j in entries.get(d, []):
                    if j["path"].startswith(r["store"]) and j.get("Exec"):
                        ex = j["Exec"]
                        break
                if ex:
                    break
            res = classify_store(r["store"], ex)
            res["attr"] = r["attr"]
            res["exec"] = ex
            return res
        except Exception as e:
            return dict(attr=r["attr"], toolkit="unknown", menu_hint="unknown", error=str(e))

    with open(out_path, "a") as f, cf.ThreadPoolExecutor(jobs) as ex:
        for i, res in enumerate(ex.map(one, rows)):
            f.write(json.dumps(res) + "\n")
            f.flush()
            if i % 25 == 0:
                print(i, res["attr"], res["toolkit"], file=sys.stderr)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("store", nargs="?")
    ap.add_argument("exec", nargs="?", default="")
    ap.add_argument("--apps")
    ap.add_argument("--top", type=int, default=600)
    ap.add_argument("--out", default=os.path.join(ROOT, "data", "classified.jsonl"))
    ap.add_argument("--jobs", type=int, default=12)
    ap.add_argument("--drv")
    a = ap.parse_args()
    if a.drv:
        print(json.dumps(classify_drv(a.drv), indent=1))
    elif a.apps:
        batch(a.apps, a.top, a.out, a.jobs)
    else:
        print(json.dumps(classify_store(a.store, a.exec), indent=1))


if __name__ == "__main__":
    main()
