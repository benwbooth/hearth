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
import shlex
import signal
import subprocess
import sys
import time

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
RIG = os.path.expanduser("~/.config/Claude/side-session-notes/local_3249e068-f6b4-44ca-966b-72365fe5da97/menu-rig.sh")
RIGDIR = os.path.join(os.environ["XDG_RUNTIME_DIR"], "menu-rig-survey")
ENV = dict(os.environ, MENU_RIG_DIR=RIGDIR)
OUT = os.path.join(ROOT, "data", "probe.jsonl")
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
}
TOOLS = {}


def sh(args, timeout=60, **kw):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=timeout, env=ENV, **kw)
    except subprocess.TimeoutExpired:
        return subprocess.CompletedProcess(args, 124, "", "timeout")


def rig(*args, timeout=30):
    return sh([RIG, *args], timeout=timeout)


def nix_build(attr, timeout=900):
    r = sh(["nix", "build", "--no-link", "--print-out-paths", "--inputs-from", "/etc/nixos",
            "--option", "max-jobs", "0", f"nixpkgs#{attr}"], timeout=timeout)
    outs = [l for l in r.stdout.split() if l.startswith("/nix/store/")]
    return outs, (r.stderr.strip().splitlines() or [""])[-1]


def tool(name, attr=None):
    if name not in TOOLS:
        outs, _ = nix_build(attr or name)
        TOOLS[name] = outs[0] if outs else ""
    return TOOLS[name]


def rig_up():
    if os.path.exists(os.path.join(RIGDIR, "hearth.pid")):
        r = rig("run", "arbor", "msg", "-j", "windows")
        if r.returncode == 0:
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


def cleanup():
    if SCOPE["unit"]:
        sh(["systemctl", "--user", "kill", "-s", "KILL", SCOPE["unit"]], timeout=20)
        SCOPE["unit"] = ""
    core = set(open(os.path.join(RIGDIR, "core.pids")).read().split())
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
    m = (dump or {}).get("menu") or {}
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
    env = dict(SESSION_ENV, **extra_env)
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
        menus, dump, t1, refocused = [], {}, time.time(), False
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
        cur = dict(window=dict(title=w.get("title"), app_id=w.get("app_id"), app_menu=w.get("app_menu"),
                               gtk_menu=w.get("gtk_menu")),
                   route=route, request=req,
                   menus=[f"{l}:{n}" for l, n in menus], n_items=count_items(dump.get("menu") or {}),
                   result="menus" if any(n for _, n in menus) else "fallback", n_windows=len(cands))
        if best is None or cur["n_items"] > best["n_items"]:
            best = cur
        if cur["result"] == "menus":
            break
    if best["result"] != "menus" and not escaped:
        # A start screen / welcome dialog in front: Escape once, look again.
        wt = tool("wtype")
        if wt:
            rig("run", f"{wt}/bin/wtype", "-k", "Escape")
            time.sleep(2)
            if [w for w in windows() if w["id"] not in before and w.get("app_id") != "org.quickshell"]:
                again = attempt_windows(attr, before, win, wait_menu, escaped=True)
                if again and again["n_items"] > best["n_items"]:
                    again["after_escape"] = True
                    best = again
    return best


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
    core = set(open(os.path.join(RIGDIR, "core.pids")).read().split())
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


def probe(attr):
    outs, err = nix_build(attr)
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
        if disp and tk not in ("gtk4", "gtk4-adwaita"):
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
    rows[-1]["shot"] = shot(attr)
    cleanup()
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--from", dest="start", type=int, default=1)
    ap.add_argument("--count", type=int, default=50)
    ap.add_argument("--attrs")
    ap.add_argument("--keep-rig", action="store_true")
    a = ap.parse_args()
    done = set()
    if os.path.exists(OUT):
        done = {json.loads(l)["attr"] for l in open(OUT)}
    if a.attrs:
        todo = a.attrs.split(",")
    else:
        todo = []
        with open(os.path.join(ROOT, "data", "apps.tsv")) as f:
            hdr = f.readline().rstrip("\n").split("\t")
            for line in f:
                r = dict(zip(hdr, line.rstrip("\n").split("\t")))
                if r["include"] != "1" or r["source"] != "nixpkgs" or int(r["rank"]) < a.start:
                    continue
                todo.append(r["attr"])
        todo = [t for t in todo if t not in done][:a.count]
    rig_up()
    with open(OUT, "a") as f:
        for attr in todo:
            t = time.time()
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
