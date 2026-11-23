#!/usr/bin/env python3
"""Run apps one by one in a nested arbor + hearth on a PRIVATE session bus and
record which route (if any) gets their menus into hearth's menu bar.

Never touches the live display or bus: everything goes through menu-rig.sh
(private dbus-daemon, kwin --virtual, nested arbor, installed hearth) with
MENU_RIG_DIR=$XDG_RUNTIME_DIR/menu-rig-survey.

For each app (data/apps.tsv order, include=1, prebuilt nixpkgs only):
  1. nix build (substitute only: max-jobs 0, so nothing compiles)
  2. its first visible desktop entry's Exec, run inside the rig with the arbor
     session's environment (GTK_MODULES=appmenu-gtk-module, QT_QPA_PLATFORMTHEME=kde,
     QT_QPA_PLATFORM=wayland;xcb, ELECTRON_OZONE_PLATFORM_HINT=auto, a11y on)
  3. wait for its window, focus it, read arbor's app_menu/gtk_menu and hearth's
     `appmenu dump`; "menus" = the app's own top-level menus with items
  4. if no menus: retry with the general levers that apply to its toolkit
     (no app patches): electron+libdbusmenu, X11 (xwayland-satellite),
     --force-renderer-accessibility
  5. screenshot (grim) of the final attempt, kill the app's process group

Output: data/probe.jsonl (one line per attempt; resumable: done attrs skipped).

Usage: menu-probe.py [--from RANK] [--count N] [--attrs a,b,c] [--keep-rig]
"""
import argparse
import configparser
import glob
import json
import os
import re
import shlex
import shutil
import signal
import subprocess
import sys
import time

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
RIG = os.path.expanduser("~/.config/Claude/side-session-notes/local_3249e068-f6b4-44ca-966b-72365fe5da97/menu-rig.sh")
WORKER = os.environ.get("MENU_PROBE_WORKER", "")
RIGDIR = os.path.join(os.environ["XDG_RUNTIME_DIR"], "menu-rig-survey" + WORKER)
ENV = dict(os.environ, MENU_RIG_DIR=RIGDIR)
# MENU_PROBE_DEVLOOP=1: the rig runs devloop's latest arbor and hearth (the
# engine as it is now) instead of the installed ones.
HEARTH_PKG = ""
if os.environ.get("MENU_PROBE_DEVLOOP") == "1":
    _dl = os.path.expanduser("~/.local/state/devloop")
    HEARTH_PKG = os.path.dirname(os.path.dirname(os.path.realpath(f"{_dl}/hearth/bin/hearth")))
    ENV["HEARTH_PKG"] = HEARTH_PKG
    ENV["PATH"] = f"{_dl}/arbor/bin:" + ENV.get("PATH", "")


def hearth_python():
    """The Python hearth's helpers run with (dbus, gi, Atspi): from the
    hearth-shell wrapper's PATH."""
    pkg = HEARTH_PKG or os.path.dirname(os.path.dirname(os.path.realpath(
        subprocess.run(["sh", "-c", "command -v hearth-ipc"], capture_output=True, text=True).stdout.strip())))
    try:
        text = open(os.path.join(pkg, "libexec", "hearth-shell")).read()
        m = re.search(r"(/nix/store/[a-z0-9]{32}-python3-[^/:]*-env)/bin", text)
        if m:
            return m.group(1) + "/bin/python3"
    except OSError:
        pass
    return "python3"


def hearth_typelibs():
    """The Atspi typelib path hearth-atspi-menu uses (HEARTH_ATSPI_TYPELIB in
    the hearth-shell wrapper)."""
    pkg = HEARTH_PKG or os.path.dirname(os.path.dirname(os.path.realpath(
        subprocess.run(["sh", "-c", "command -v hearth-ipc"], capture_output=True, text=True).stdout.strip())))
    try:
        m = re.search(r"HEARTH_ATSPI_TYPELIB-'([^']+)'", open(os.path.join(pkg, "libexec", "hearth-shell")).read())
        return m.group(1) if m else ""
    except OSError:
        return ""


def inspect(win):
    """What the app exposes (atspi-inspect.py), shortcuts window, MPRIS."""
    pid = (win or {}).get("pid") or 0
    if not pid:
        return {}
    r = rig("run", "env", f"GI_TYPELIB_PATH={hearth_typelibs()}", hearth_python(),
            os.path.join(ROOT, "scripts", "atspi-inspect.py"), str(pid), (win or {}).get("title") or "",
            timeout=40)
    try:
        info = json.loads(r.stdout.strip().splitlines()[-1])
    except Exception:
        info = {"error": (r.stderr or r.stdout)[-200:]}
    try:
        exe = os.path.realpath(f"/proc/{pid}/exe")
        files = subprocess.run(["gresource", "list", exe], capture_output=True, text=True, timeout=10).stdout
        info["shortcuts_window"] = bool(re.search(r"(shortcuts-dialog|help-overlay|shortcuts(-window)?)\.ui", files))
        info["exe"] = exe
    except Exception:
        pass
    b = rig("busctl", "--json=short", "list")
    try:
        names = json.loads(b.stdout)
        tree = tree_pids(pid)
        info["mpris"] = [n["name"] for n in names if n.get("name", "").startswith("org.mpris.MediaPlayer2.")
                         and str(n.get("pid")) in tree]
    except Exception:
        pass
    return info
OUT = os.path.join(ROOT, "data", f"probe{WORKER}.jsonl")
SHOTS = os.path.join(ROOT, "data", "shots")
SESSION_ENV = {
    "GTK_MODULES": "appmenu-gtk-module",
    "GTK_PATH": "/run/current-system/sw/lib/gtk-3.0",
    "QT_QPA_PLATFORM": "wayland;xcb",
    "ELECTRON_OZONE_PLATFORM_HINT": "auto",
    "NO_AT_BRIDGE": "0",
    "GTK_A11Y": "atspi",
    "QT_LINUX_ACCESSIBILITY_ALWAYS_ON": "1",
    "ACCESSIBILITY_ENABLED": "1",
    # No sound server in the rig: games that refuse to start without an
    # audio device (Quadrapassel's OpenAL) get dummy ones.
    "ALSOFT_DRIVERS": "null",
    "SDL_AUDIODRIVER": "dummy",
}
TOOLS = {}


def sh(args, timeout=60, **kw):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=timeout, env=ENV, **kw)
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(args, 124, "", "timeout")


def rig(*args, timeout=30):
    return sh([RIG, *args], timeout=timeout)


ROOTS = os.path.expanduser("~/.cache/hearth-menu-survey/roots")


def nix_build(attr, timeout=900, unfree=False, root=None):
    """Substitute only, always (max-jobs 0): never compile anything locally.
    A package that isn't in the binary cache fails here and is skipped
    (an unfree bambu-studio once built from source at -j24 and filled RAM)."""
    args = ["nix", "build", "--print-out-paths", "--inputs-from", "/etc/nixos",
            "--option", "max-jobs", "0", "--option", "builders", ""]
    args += ["--out-link", os.path.join(ROOTS, root)] if root else ["--no-link"]
    if unfree:
        args += ["--impure"]
    os.makedirs(ROOTS, exist_ok=True)
    global ENV
    old = ENV
    if unfree:
        ENV = dict(ENV, NIXPKGS_ALLOW_UNFREE="1")
    try:
        r = sh(args + [f"nixpkgs#{attr}"], timeout=timeout)
    finally:
        ENV = old
    outs = [l for l in r.stdout.split() if l.startswith("/nix/store/")]
    return outs, (r.stderr.strip().splitlines() or [""])[-1]


def tool(name, attr=None):
    if name not in TOOLS:
        outs, _ = nix_build(attr or name, root=name)  # rooted: per-app deletes keep it
        TOOLS[name] = outs[0] if outs else ""
    return TOOLS[name]


def rig_alive():
    try:
        pid = int(open(os.path.join(RIGDIR, "hearth.pid")).read())
        os.kill(pid, 0)
    except (OSError, ValueError):
        return False
    return rig("run", "arbor", "msg", "-j", "windows").returncode == 0


def rig_up():
    if os.path.exists(os.path.join(RIGDIR, "hearth.pid")):
        if rig_alive():
            if not os.path.exists(os.path.join(RIGDIR, "core.pids")):
                with open(os.path.join(RIGDIR, "core.pids"), "w") as f:
                    f.write(" ".join(core_pids()))
            return
        rig("stop")
    r = rig("start", timeout=120)
    if "rig up" not in r.stdout:
        sys.exit("rig failed: " + r.stdout + r.stderr)
    subprocess.Popen(["setsid", RIG, "run", "/run/current-system/sw/libexec/at-spi-bus-launcher",
                      "--launch-immediately"], env=ENV, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL)
    time.sleep(2)
    # The a11y bus launcher's dbus-broker would activate the registry through
    # systemd, which a private bus can't do: start it ourselves.
    asp = os.path.dirname(os.path.dirname(os.path.realpath("/run/current-system/sw/libexec/at-spi-bus-launcher")))
    subprocess.Popen(["setsid", RIG, "run", f"{asp}/libexec/at-spi2-registryd"], env=ENV,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL)
    time.sleep(1)
    rig("busctl", "set-property", "org.a11y.Bus", "/org/a11y/bus", "org.a11y.Status", "IsEnabled", "b", "true")
    with open(os.path.join(RIGDIR, "core.pids"), "w") as f:
        f.write(" ".join(core_pids()))


def arbor_display():
    try:
        for l in open(os.path.join(RIGDIR, "arbor.env")):
            if l.startswith("DISPLAY="):
                return l.strip().split("=", 1)[1]
    except OSError:
        pass
    return ""


def windows():
    r = rig("run", "arbor", "msg", "-j", "windows")
    try:
        return json.loads(r.stdout)
    except Exception:
        return []


def bus_pids():
    """Processes on this rig's private bus."""
    want = f"DBUS_SESSION_BUS_ADDRESS=unix:path={RIGDIR}/bus.sock".encode()
    res = []
    for p in os.listdir("/proc"):
        if not p.isdigit():
            continue
        try:
            if want in open(f"/proc/{p}/environ", "rb").read().split(b"\0"):
                res.append(p)
        except OSError:
            pass
    return res


def core_pids():
    """The rig itself (dbus, kwin, arbor, hearth and their helpers, at-spi)."""
    return [p for p in bus_pids()]


SCOPE = {"n": 0, "unit": ""}


APPDIRS = []


def cleanup():
    if SCOPE["unit"]:
        sh(["systemctl", "--user", "kill", "-s", "KILL", SCOPE["unit"]], timeout=20)
        SCOPE["unit"] = ""
    try:
        core = set(open(os.path.join(RIGDIR, "core.pids")).read().split())
    except OSError:
        return
    victims = [p for p in bus_pids() if p not in core]
    # Clients of the nested arbor are ours (its own windows aside).
    victims += [str(w["pid"]) for w in windows() if w.get("app_id") != "org.quickshell" and w.get("pid")]
    for p in set(victims):
        try:
            os.kill(int(p), signal.SIGKILL)
        except OSError:
            pass
    for _ in range(20):
        if not [w for w in windows() if w.get("app_id") != "org.quickshell"]:
            break
        time.sleep(0.25)
    while APPDIRS:
        shutil.rmtree(APPDIRS.pop(), ignore_errors=True)
    # Single-instance locks of killed apps (Chromium/Electron, Firefox).
    for pat in ("**/Singleton*", "**/lock", "**/.parentlock"):
        for fn in glob.glob(os.path.join(RIGDIR, "home", pat), recursive=True):
            try:
                os.unlink(fn)
            except OSError:
                pass


def desktop_exec(out):
    """First visible Application entry: (exec argv, desktop id)."""
    files = sorted(glob.glob(os.path.join(out, "share/applications/*.desktop")))
    best = None
    for fn in files:
        cp = configparser.RawConfigParser(strict=False, interpolation=None)
        try:
            cp.read(fn, encoding="utf-8")
            e = cp["Desktop Entry"]
        except Exception:
            continue
        if e.get("Type", "Application") != "Application" or e.get("NoDisplay", "").lower() == "true" \
                or e.get("Hidden", "").lower() == "true" or e.get("Terminal", "").lower() == "true":
            continue
        ex = e.get("Exec", "")
        try:
            argv = shlex.split(ex)
        except ValueError:
            argv = ex.split()
        argv = [a for a in argv if not (len(a) == 2 and a.startswith("%"))]
        if not argv:
            continue
        cand = (argv, os.path.basename(fn))
        # Prefer the entry named like the package.
        if best is None or os.path.basename(fn).split(".")[-2].lower() in out.lower():
            best = cand
            if os.path.basename(fn).split(".")[-2].lower() in out.lower():
                break
    if not best:
        return None, None
    argv, did = best
    while argv and argv[0] == "env":
        argv = argv[1:]
        while argv and "=" in argv[0]:
            argv = argv[1:]
    if argv and not argv[0].startswith("/"):
        for o in [out] + sorted(glob.glob(out.rsplit("-", 1)[0] + "*")):
            p = os.path.join(o, "bin", argv[0])
            if os.path.exists(p):
                argv[0] = p
                break
        else:
            p = os.path.join(out, "bin", argv[0])
            if not os.path.exists(p):
                hits = glob.glob(os.path.join(out, "bin", "*"))
                argv[0] = hits[0] if len(hits) == 1 else argv[0]
    return argv, did


def app_menus(dump):
    """Top-level menus with at least one item, from hearth's dump."""
    # The merged tree (the window's menus plus MPRIS / harvested shortcuts)
    # where hearth reports it.
    m = (dump or {}).get("tree") or (dump or {}).get("menu") or {}
    res = []
    for c in m.get("children") or []:
        if c.get("type") == "separator" or not c.get("visible", True):
            continue
        items = [x for x in c.get("children") or [] if x.get("type") != "separator"]
        res.append((c.get("label", ""), len(items)))
    return res


def count_items(node):
    return sum(1 + count_items(c) for c in node.get("children") or [] if c.get("type") != "separator")


def attempt(attr, argv, variant, extra_env, extra_args, wait_win=35, wait_menu=16):
    cleanup()
    before = {w["id"] for w in windows()}
    # The arbor session has X11 too (xwayland-satellite): VLC 3 and other
    # X11-only apps need DISPLAY even when they run "natively".
    env = dict(SESSION_ENV, DISPLAY=arbor_display())
    # Every attempt gets fresh home, runtime and temp dirs: a killed app's
    # single-instance lock or socket ("Strawberry is already running") must
    # not stop the next app, and no first-run state carries over.
    base = os.path.join(RIGDIR, "apps", str(SCOPE["n"] + 1))
    shutil.rmtree(base, ignore_errors=True)
    dirs = {"HOME": "home", "XDG_CONFIG_HOME": "home/.config", "XDG_CACHE_HOME": "home/.cache",
            "XDG_DATA_HOME": "home/.local/share", "XDG_STATE_HOME": "home/.local/state",
            "XDG_RUNTIME_DIR": "run", "TMPDIR": "tmp"}
    for k, d in dirs.items():
        os.makedirs(os.path.join(base, d), mode=0o700, exist_ok=True)
        env[k] = os.path.join(base, d)
    APPDIRS.append(base)
    env.update(extra_env)
    envargs = [f"{k}={v}" for k, v in env.items()]
    log = open(os.path.join(RIGDIR, "app.log"), "w")
    SCOPE["n"] += 1
    SCOPE["unit"] = f"menuprobe-{os.getpid()}-{SCOPE['n']}.scope"
    proc = subprocess.Popen(["systemd-run", "--user", "--scope", "--quiet", "--collect", "--unit", SCOPE["unit"],
                             "-p", "MemoryMax=8G", "setsid", RIG, "run", "env", *envargs, *argv, *extra_args], env=ENV,
                            stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL)
    t0 = time.time()
    win = None
    while time.time() - t0 < wait_win:
        ws = [w for w in windows() if w["id"] not in before and w.get("app_id") != "org.quickshell"]
        if ws:
            time.sleep(1.5)  # splash screens / the real main window
            ws = [w for w in windows() if w["id"] not in before and w.get("app_id") != "org.quickshell"]
            # The biggest-titled / last one is usually the main window.
            win = ws[-1] if ws else None
            break
        if proc.poll() is not None and time.time() - t0 > 8 and not bus_pids_beyond_core():
            break
        time.sleep(0.5)
    res = dict(attr=attr, variant=variant, argv=argv[:1] + extra_args, t_window=round(time.time() - t0, 1))
    if not win:
        res.update(result="no-window", log_tail=tail(os.path.join(RIGDIR, "app.log")))
        return res
    res.update(attempt_windows(attr, before, win, wait_menu))
    return res


def settle(before, stable=4.0, limit=30.0):
    """The app's new windows, once the set has not changed for `stable` s."""
    t0, last, since = time.time(), None, time.time()
    while time.time() - t0 < limit:
        ws = [w for w in windows() if w["id"] not in before and w.get("app_id") != "org.quickshell"]
        sig = sorted((w["id"], w.get("title"), bool(w.get("app_menu") or w.get("gtk_menu"))) for w in ws)
        if sig != last:
            last, since = sig, time.time()
        elif time.time() - since >= stable:
            return ws
        time.sleep(0.5)
    return ws


def attempt_windows(attr, before, win, wait_menu, escaped=False):
    cands = settle(before) or [win]
    # Windows that export an address first, then the rest (newest first).
    cands.sort(key=lambda w: (not (w.get("app_menu") or w.get("gtk_menu")), -w["id"]))
    best = None
    for cw in cands[:4]:
        rig("run", "arbor", "msg", "action", "focus-window", "--id", str(cw["id"]))
        menus, dump, t1, refocused, dump_ok = [], {}, time.time(), False, False
        while time.time() - t1 < wait_menu:
            time.sleep(1.0)
            if not refocused and time.time() - t1 > wait_menu / 2 and not any(n for _, n in menus):
                # Make hearth resolve the window again (AT-SPI trees fill lazily).
                qs = [x["id"] for x in windows() if x.get("app_id") == "org.quickshell"]
                if qs:
                    rig("run", "arbor", "msg", "action", "focus-window", "--id", str(qs[0]))
                    time.sleep(0.7)
                rig("run", "arbor", "msg", "action", "focus-window", "--id", str(cw["id"]))
                refocused = True
            r = rig("dump", timeout=20)
            try:
                dump = json.loads(r.stdout)
                dump_ok = True
            except Exception:
                dump = {}
            menus = app_menus(dump)
            if any(n for _, n in menus) and time.time() - t1 > 2.5:
                break
        w = next((x for x in windows() if x["id"] == cw["id"]), cw)
        req = dump.get("request") or {}
        route = req.get("kind") or ("none" if not menus else "?")
        if route == "x11" and menus:
            route = infer_x11_route(w)
        cur = dict(window=dict(title=w.get("title"), app_id=w.get("app_id"), pid=w.get("pid"),
                               app_menu=w.get("app_menu"),
                               gtk_menu=w.get("gtk_menu")),
                   route=route, request=req,
                   menus=[f"{l}:{n}" for l, n in menus], n_items=count_items(dump.get("tree") or dump.get("menu") or {}),
                   result="menus" if any(n for _, n in menus) else ("fallback" if dump_ok else "dump-failed"),
                   n_windows=len(cands))
        if best is None or cur["n_items"] > best["n_items"]:
            best = cur
        if cur["result"] == "menus":
            break
    if best["result"] != "menus" and escaped == "esc":
        # Still nothing: a separate first-run window (Vesktop Setup, DBeaver's
        # Product Configuration, a welcome or what's-new window) that a user
        # would close once; close it if the app has another window.
        mine = [w for w in windows() if w["id"] not in before and w.get("app_id") != "org.quickshell"]
        first_run = re.compile(r"setup|welcome|configuration|wizard|first|what.?s new|getting started|"
                               r"license|tip of the day|update|news|account", re.I)
        extra = [w for w in mine if first_run.search(w.get("title") or "")]
        if extra and len(mine) > len(extra) - 0 and len(mine) >= 2:
            for w in extra:
                rig("run", "arbor", "msg", "action", "close-window", "--id", str(w["id"]))
            time.sleep(3)
            again = attempt_windows(attr, before | {w["id"] for w in extra}, win, wait_menu, escaped="closed")
            if again and again["n_items"] > best["n_items"]:
                again["closed_first_run"] = [w.get("title") for w in extra]
                best = again
    if best["result"] != "menus" and not escaped:
        # A start screen / welcome dialog in front: Escape once, look again.
        wt = tool("wtype")
        if wt:
            rig("run", f"{wt}/bin/wtype", "-k", "Escape")
            time.sleep(2)
            if [w for w in windows() if w["id"] not in before and w.get("app_id") != "org.quickshell"]:
                again = attempt_windows(attr, before, win, wait_menu, escaped="esc")
                if again and again["n_items"] > best["n_items"]:
                    again["after_escape"] = True
                    best = again
    return best


def full_menus(r):
    return r.get("result") == "menus" and len([m for m in r.get("menus", []) if not m.endswith(":0")]) >= 2


def late_check(rows):
    """Slow starters (Inkscape after its start screen, darktable's splash,
    Java workbenches): once more, the app's newest window as it is now. A
    full menu bar there counts for the session attempt."""
    if any(full_menus(r) for r in rows):
        return
    sess = next((r for r in rows if r.get("variant") == "session"), None)
    pid = ((sess or {}).get("window") or {}).get("pid")
    if not sess or not pid:
        return
    time.sleep(3)
    tree = tree_pids(pid)
    try:
        ppid = open(f"/proc/{pid}/stat").read().rsplit(")", 1)[1].split()[1]
        tree |= tree_pids(ppid)
    except OSError:
        pass
    mine = [w for w in windows() if str(w.get("pid")) in tree and w.get("app_id") != "org.quickshell"]
    if not mine:
        return
    w = max(mine, key=lambda x: x["id"])
    rig("run", "arbor", "msg", "action", "focus-window", "--id", str(w["id"]))
    time.sleep(5)
    try:
        dump = json.loads(rig("dump", timeout=20).stdout)
    except Exception:
        return
    menus = app_menus(dump)
    if len([n for _, n in menus if n]) >= 2:
        sess.update(result="menus", menus=[f"{l}:{n}" for l, n in menus], late=True,
                    n_items=count_items(dump.get("tree") or dump.get("menu") or {}),
                    route=(dump.get("request") or {}).get("kind") or "?",
                    window=dict(sess.get("window") or {}, title=w.get("title"), late_window=w["id"]))


def tree_pids(pid):
    """pid and its descendants."""
    kids = {}
    for p in os.listdir("/proc"):
        if p.isdigit():
            try:
                pp = open(f"/proc/{p}/stat").read().rsplit(")", 1)[1].split()[1]
                kids.setdefault(pp, []).append(p)
            except OSError:
                pass
    res, todo = set(), [str(pid)]
    while todo:
        x = todo.pop()
        if x not in res:
            res.add(x)
            todo += kids.get(x, [])
    return res


def infer_x11_route(w):
    """hearth's "x11" watch covers three routes: an X11 window (satellite),
    an Electron registration from a Wayland window's process, or AT-SPI."""
    pid = w.get("pid") or 0
    try:
        comm = open(f"/proc/{pid}/comm").read()
    except OSError:
        comm = ""
    if "xwayland-sat" in comm:
        return "x11"
    r = rig("busctl", "call", "com.canonical.AppMenu.Registrar", "/com/canonical/AppMenu/Registrar",
            "com.canonical.AppMenu.Registrar", "GetMenus", "--json=short")
    try:
        regs = json.loads(r.stdout)["data"][0]
    except Exception:
        regs = []
    tree = tree_pids(pid)
    try:
        ppid = open(f"/proc/{pid}/stat").read().rsplit(")", 1)[1].split()[1]
        tree |= tree_pids(ppid) if ppid not in ("1", "0") else set()
    except OSError:
        pass
    for _, sender, path in regs:
        q = rig("busctl", "call", "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus",
                "GetConnectionUnixProcessID", "s", sender)
        spid = q.stdout.split()[-1] if q.stdout else ""
        if spid in tree:
            g = rig("busctl", "call", sender, path, "com.canonical.dbusmenu", "GetLayout", "iias", "0", "1", "0")
            if g.returncode == 0:
                return "registrar"
    return "atspi"


def bus_pids_beyond_core():
    try:
        core = set(open(os.path.join(RIGDIR, "core.pids")).read().split())
    except OSError:
        core = set()
    return [p for p in bus_pids() if p not in core]


def tail(fn, n=6):
    try:
        return open(fn, errors="replace").read().strip().splitlines()[-n:]
    except OSError:
        return []


def shot(attr):
    grim = tool("grim")
    if not grim:
        return ""
    os.makedirs(SHOTS, exist_ok=True)
    fn = os.path.join(SHOTS, attr.replace("/", "_") + ".png")
    rig("run", f"{grim}/bin/grim", "-s", "0.5", fn, timeout=20)
    return os.path.relpath(fn, ROOT) if os.path.exists(fn) else ""


def toolkit_of(attr):
    try:
        for l in open(os.path.join(ROOT, "data", "classified.jsonl")):
            j = json.loads(l)
            if j["attr"] == attr:
                return j.get("toolkit", "")
    except OSError:
        pass
    return ""


FLATPAK_DIR = os.path.expanduser("~/.cache/hearth-menu-survey/flatpak")


def flatpak(*args, timeout=1800):
    """flatpak --user with a throwaway installation (never Ben's own)."""
    env = dict(ENV, FLATPAK_USER_DIR=FLATPAK_DIR)
    try:
        return subprocess.run(["flatpak", "--user", *args], capture_output=True, text=True, timeout=timeout, env=env)
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(args, 124, "", "timeout")


def probe_flatpak(attr):
    fid = attr.split(":", 1)[1]
    os.makedirs(FLATPAK_DIR, exist_ok=True)
    flatpak("remote-add", "--if-not-exists", "flathub", "https://dl.flathub.org/repo/flathub.flatpakrepo")
    r = flatpak("install", "-y", "--noninteractive", "flathub", fid)
    if r.returncode and "already installed" not in (r.stderr + r.stdout):
        return [dict(attr=attr, variant="build", result="install-failed", error=(r.stderr or r.stdout)[-300:])]
    meta = flatpak("info", "--show-metadata", fid).stdout
    talk = sorted(set(re.findall(r"(com\.canonical\.AppMenu\.Registrar|org\.kde\.StatusNotifierWatcher|org\.a11y\.Bus)", meta)))
    argv = ["env", f"FLATPAK_USER_DIR={FLATPAK_DIR}", "flatpak", "run", fid]
    rows = []
    r0 = attempt(attr, argv, "session", {}, [])
    r0["hearth"] = HEARTH_PKG or "installed"
    if r0.get("result") != "no-window" and len([m for m in r0.get("menus", []) if not m.endswith(":0")]) < 2:
        r0["inspect"] = inspect(r0.get("window"))
    r0.update(toolkit=toolkit_of(attr), flatpak_talk=talk, flatpak=True)
    rows.append(r0)
    if r0["result"] != "menus":
        # Same app with the registrar allowed through the sandbox's D-Bus proxy.
        argv2 = argv[:-1] + ["--talk-name=com.canonical.AppMenu.Registrar", "--env=LD_LIBRARY_PATH=", fid]
        r1 = attempt(attr, argv2, "flatpak+registrar", {}, [])
        r1.update(toolkit=toolkit_of(attr))
        rows.append(r1)
    late_check(rows)
    rows[-1]["shot"] = shot(attr)
    cleanup()
    return rows


APPS = {}


def store_delete(outs):
    """Free the disk again: the app's closure, minus anything still alive
    (the system, other roots, the tools above)."""
    if outs:
        sh(["nix", "store", "delete", "--recursive", "--skip-alive", *outs], timeout=900)


def probe(attr):
    if attr.startswith("flathub:"):
        return probe_flatpak(attr)
    src = APPS.get(attr, {}).get("source", "nixpkgs")
    # Not in the binary cache (uncached free, and every unfree package): its
    # Flathub copy instead (a download, never a build), else skipped.
    if src == "nixpkgs-unfree":
        return [dict(attr=attr, variant="build", result="not-prebuilt", error="unfree: never in the binary cache")]
    if src == "nixpkgs-uncached":
        fid = APPS[attr].get("flathub")
        if not fid:
            return [dict(attr=attr, variant="build", result="not-prebuilt")]
        rows = probe_flatpak("flathub:" + fid)
        for r in rows:
            r["attr"], r["via_flathub"] = attr, fid
        return rows
    outs, err = nix_build(attr, unfree=(src == "nixpkgs-unfree"), timeout=1800 if src == "nixpkgs-unfree" else 900)
    try:
        return probe_store(attr, outs, err)
    finally:
        store_delete(outs)


def probe_store(attr, outs, err):
    if not outs:
        return [dict(attr=attr, variant="build", result="not-prebuilt", error=err)]
    out = outs[0]
    for o in outs:
        if glob.glob(os.path.join(o, "share/applications/*.desktop")):
            out = o
            break
    argv, did = desktop_exec(out)
    if not argv:
        return [dict(attr=attr, variant="exec", result="no-entry", store=out)]
    tk = toolkit_of(attr)
    rows = []
    r = attempt(attr, argv, "session", {}, [])
    r["hearth"] = HEARTH_PKG or "installed"
    if r.get("result") != "no-window" and len([m for m in r.get("menus", []) if not m.endswith(":0")]) < 2:
        r["inspect"] = inspect(r.get("window"))
    r.update(store=out, desktop=did, toolkit=tk)
    rows.append(r)
    if r["result"] != "menus":
        levers = []
        is_chromish = tk in ("electron", "chromium", "cef") or "electron" in " ".join(argv).lower()
        if is_chromish:
            dbm = tool("libdbusmenu")
            levers.append(("electron+libdbusmenu", {"LD_LIBRARY_PATH": f"{dbm}/lib"}, []))
            levers.append(("chromium-a11y", {}, ["--force-renderer-accessibility"]))
        disp = arbor_display()
        # X11 only changes the outcome for toolkits whose X11 path differs
        # (Chromium/Electron RegisterWindow, Java, unknown); Qt and GTK export
        # the same menus on Wayland.
        if disp and (is_chromish or tk in ("java-swing", "javafx", "unknown", "", "wx-gtk3", "tk", "fltk")):
            x11 = {"DISPLAY": disp, "QT_QPA_PLATFORM": "xcb", "GDK_BACKEND": "x11",
                   "ELECTRON_OZONE_PLATFORM_HINT": "x11", "SDL_VIDEODRIVER": "x11"}
            if is_chromish:
                x11["LD_LIBRARY_PATH"] = f"{tool('libdbusmenu')}/lib"
            levers.append(("x11", x11, ["--ozone-platform=x11"] if is_chromish else []))
        for name, env, args in levers:
            rr = attempt(attr, argv, name, env, args)
            rr.update(toolkit=tk)
            rows.append(rr)
            if rr["result"] == "menus":
                break
    late_check(rows)
    rows[-1]["shot"] = shot(attr)
    cleanup()
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--from", dest="start", type=int, default=1)
    ap.add_argument("--count", type=int, default=50)
    ap.add_argument("--attrs")
    ap.add_argument("--keep-rig", action="store_true")
    ap.add_argument("--stride", type=int, default=1, help="take every Nth app (parallel workers)")
    ap.add_argument("--offset", type=int, default=0)
    ap.add_argument("--flathub", action="store_true", help="Flathub-only apps (throwaway flatpak installation)")
    ap.add_argument("--sources", default="nixpkgs", help="comma list: nixpkgs,nixpkgs-unfree,nixpkgs-uncached,flathub")
    a = ap.parse_args()
    done = set()
    for fn in glob.glob(os.path.join(ROOT, "data", "probe*.jsonl")):
        done |= {json.loads(l)["attr"] for l in open(fn)}
    if a.attrs:
        todo = a.attrs.split(",")
    else:
        todo = []
        with open(os.path.join(ROOT, "data", "apps.tsv")) as f:
            hdr = f.readline().rstrip("\n").split("\t")
            for line in f:
                r = dict(zip(hdr, line.rstrip("\n").split("\t")))
                APPS[r["attr"]] = r
                # Prebuilt only: nixpkgs from the binary cache, Flathub. Unfree
                # nixpkgs packages are never in the cache: not a source.
                want = ("flathub",) if a.flathub else tuple(x for x in a.sources.split(",") if x != "nixpkgs-unfree")
                if r["include"] != "1" or r["source"] not in want or int(r["rank"]) < a.start:
                    continue
                todo.append(r["attr"])
        todo = [t for t in todo if t not in done][:a.count][a.offset::a.stride]
    if a.attrs:
        with open(os.path.join(ROOT, "data", "apps.tsv")) as f:
            hdr = f.readline().rstrip("\n").split("\t")
            for line in f:
                r = dict(zip(hdr, line.rstrip("\n").split("\t")))
                APPS[r["attr"]] = r
    print(f"{len(todo)} apps to probe", file=sys.stderr, flush=True)
    with open(OUT, "a") as f:
        for attr in todo:
            t = time.time()
            if not rig_alive():
                rig("stop")
                rig_up()
            try:
                rows = probe(attr)
            except Exception as e:
                rows = [dict(attr=attr, variant="error", result="error", error=repr(e))]
            for r in rows:
                f.write(json.dumps(r) + "\n")
            f.flush()
            last = rows[-1]
            print(f"{attr}: {last.get('result')} via {last.get('variant')} route={last.get('route','')} "
                  f"{last.get('menus', '')} ({time.time() - t:.0f}s)", file=sys.stderr, flush=True)
    if not a.keep_rig:
        rig("stop")


if __name__ == "__main__":
    main()
