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
RIG = os.path.join(os.path.dirname(os.path.abspath(__file__)), "menu-rig.sh")  # hearth gets DISPLAY
WORKER = os.environ.get("MENU_PROBE_WORKER", "")
RIGDIR = os.path.join(os.environ["XDG_RUNTIME_DIR"], "menu-rig-survey" + WORKER)
# The rig's homes, the apps' folders and temp files: on disk (menu-rig.sh's
# MENU_RIG_DISK default). /run/user is a small RAM tmpfs the live session
# needs; Flatpak apps' data filled it.
DISKDIR = os.path.join("/var/tmp", "menu-rig-" + os.environ.get("USER", "ben"), "menu-rig-survey" + WORKER)
# Probed apps' own folders (home, XDG dirs, temp), outside /var/tmp: WebKit's
# sandbox mounts them and then can't make its /var/tmp symlink ("destination
# exists": Evolution never started). Sandboxed AppImages keep DISKDIR (their
# sandbox hides your home).
# Short (/tmp is on disk here): a Flatpak'd Chromium puts its SingletonSocket
# in HOME/.var/app/ID/cache/scoped_dir.../ and dies past the 108-byte socket
# limit (Tidal HiFi, Unity Hub, Cherry Studio under ~/.cache/...).
APPROOT = f"/tmp/mr{WORKER or 0}"


def rmtree(path):
    """Delete, read-only folders too (Flatpak payloads): rmtree's
    ignore_errors otherwise leaves them, gigabytes at a time. Only inside
    the survey's own folders: anything else is refused."""
    real = os.path.realpath(path)
    user = os.environ.get("USER", "ben")
    roots = (f"/var/tmp/menu-rig-{user}/", os.path.expanduser("~/.cache/hearth-menu-survey/"))
    short_tmp = re.fullmatch(r"/tmp/menu-rig-\d+-\d+|/tmp/mr\d+/apps/\d+(/.*)?", real.rstrip("/"))
    if not (short_tmp or real.startswith(roots)) or real.rstrip("/") in {r.rstrip("/") for r in roots}:
        print(f"menu-probe: refusing to delete {path}", file=sys.stderr, flush=True)
        return
    for dp, dn, fn in os.walk(path):
        for d in dn:
            try:
                os.chmod(os.path.join(dp, d), 0o700)
            except OSError:
                pass
    shutil.rmtree(path, ignore_errors=True)
ENV = dict(os.environ, MENU_RIG_DIR=RIGDIR)
# The session's Qt Quick style (hearth-qt-style's org.hearth.desktop,
# 2026-11-25) isn't on probed apps' QML paths (Flatpaks, nixpkgs apps with
# their own Qt): they'd fail to start over it, which says nothing about
# their menus.
ENV.pop("QT_QUICK_CONTROLS_STYLE", None)
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


def x11_app_pid(pid):
    """For a window through xwayland-satellite (pid = the satellite), the X
    client's own pid: _NET_WM_PID of the active X window."""
    try:
        if "xwayland-sat" not in open(f"/proc/{pid}/comm").read():
            return pid
    except OSError:
        return pid
    xp = tool("xprop", "xorg.xprop")
    disp = arbor_display()
    if not xp or not disp:
        return pid
    r = rig("run", "env", f"DISPLAY={disp}", f"{xp}/bin/xprop", "-root", "_NET_ACTIVE_WINDOW")
    m = re.search(r"(0x[0-9a-f]+)", r.stdout)
    if not m:
        return pid
    r = rig("run", "env", f"DISPLAY={disp}", f"{xp}/bin/xprop", "-id", m.group(1), "_NET_WM_PID")
    m = re.search(r"= (\d+)", r.stdout)
    return int(m.group(1)) if m else pid


def inspect(win):
    """What the app exposes (atspi-inspect.py), shortcuts window, MPRIS."""
    pid = (win or {}).get("pid") or 0
    if not pid:
        return {}
    pid = x11_app_pid(pid)
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
    "GTK_MODULES": "appmenu-gtk-module:gail:atk-bridge",
    "GTK_PATH": "/run/current-system/sw/lib/gtk-3.0",
    "QT_QPA_PLATFORM": "wayland;xcb",
    "ELECTRON_OZONE_PLATFORM_HINT": "auto",
    "NO_AT_BRIDGE": "0",
    "GTK_A11Y": "atspi",
    "QT_LINUX_ACCESSIBILITY_ALWAYS_ON": "1",
    "ELM_ATSPI_MODE": "1",
    "ACCESSIBILITY_ENABLED": "1",
    # No sound server in the rig: games that refuse to start without an
    # audio device (Quadrapassel's OpenAL) get dummy ones.
    "ALSOFT_DRIVERS": "null",
    "SDL_AUDIODRIVER": "dummy",
    # Icon themes and other shared data, as in a session (GTK aborts on a
    # missing icon otherwise). Read-only system paths.
    "XDG_DATA_DIRS": "/run/current-system/sw/share:/etc/profiles/per-user/" + os.environ.get("USER", "ben") + "/share",
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


HEAVY = re.compile(r"(^|-)(gcc|clang|llvm|rustc|cargo|ghc|go|openjdk|jdk|qtbase|qtwebengine|webkitgtk|chromium|"
                   r"electron-unwrapped|linux|boost|opencv|opencascade|ffmpeg|gtk[34]?|python3)-\d", re.I)


def unfree_build_ok(attr):
    """Whether an unfree package is cheap to build here: Hydra builds no
    unfree package, but most are a vendor binary repackaged (fetch, unpack,
    patchelf, wrap: Steam, Discord, Chrome, VS Code), minutes of work. A dry
    run lists what would be built; a few derivations and nothing heavy (a
    compiler, a toolkit, a browser engine) is cheap. Anything else (bambu-
    studio once compiled from source at -j24 and filled RAM) is not."""
    r = subprocess.run(["nix", "build", "--dry-run", "--impure", "--inputs-from", "/etc/nixos", f"nixpkgs#{attr}"],
                       capture_output=True, text=True, timeout=300, env=dict(ENV, NIXPKGS_ALLOW_UNFREE="1"))
    if r.returncode:
        return False, (r.stderr.strip().splitlines() or [""])[-1]
    drvs, building = [], False
    for l in r.stderr.splitlines():
        if "will be built" in l:
            building = True
            continue
        if "will be fetched" in l:
            building = False
            continue
        if building and l.strip().endswith(".drv"):
            drvs.append(os.path.basename(l.strip())[33:-4])
    heavy = [d for d in drvs if HEAVY.search(d)]
    # The package itself compiled from source (bambu-studio: two
    # derivations, one a C++ build of hours): its build tools say so.
    e = subprocess.run(["nix", "eval", "--json", "--impure", "--inputs-from", "/etc/nixos",
                        f"nixpkgs#{attr}.nativeBuildInputs", "--apply",
                        "map (p: p.pname or p.name or \"\")"],
                       capture_output=True, text=True, timeout=300, env=dict(ENV, NIXPKGS_ALLOW_UNFREE="1"))
    try:
        tools = json.loads(e.stdout or "[]")
    except ValueError:
        tools = []
    compiles = [t for t in tools if re.match(r"(cmake|meson|ninja|cargo|rustc|go|qmake|scons|gradle|maven|"
                                             r"autoreconf|cargo-.*-hook|yarn-config-hook|npm-config-hook)", t or "")]
    why = f"{len(drvs)} to build" + (f", heavy: {heavy[:3]}" if heavy else "") + (f", compiles: {compiles[:3]}" if compiles else "")
    return len(drvs) <= 12 and not heavy and not (compiles and drvs), why


def nix_build_unfree(attr, timeout=1200):
    """Build a cheap unfree package (unfree_build_ok): two jobs of four
    cores at most, 20 minutes at most."""
    args = ["nix", "build", "--print-out-paths", "--no-link", "--impure", "--inputs-from", "/etc/nixos",
            "--option", "max-jobs", "2", "--option", "cores", "4", f"nixpkgs#{attr}"]
    global ENV
    old = ENV
    ENV = dict(ENV, NIXPKGS_ALLOW_UNFREE="1")
    try:
        r = sh(args, timeout=timeout)
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
    # A hearth that didn't load (a QML error) reads no menus at all: every
    # app would be measured menu-less. Stop instead.
    try:
        if any("Failed to load configuration" in l for l in tail(os.path.join(RIGDIR, "hearth.log"), 400)):
            sys.exit("rig's hearth failed to load: see " + os.path.join(RIGDIR, "hearth.log"))
    except OSError:
        pass
    # at-spi2-core from hearth's own build (its typelib path), not the
    # system's: the system may not have it (Plasma's removal took it out of
    # /run/current-system, and every rig ran without an a11y bus).
    asp = next((p.rsplit("/lib/", 1)[0] for p in hearth_typelibs().split(":") if "-at-spi2-core-" in p), "")
    if not asp or not os.path.exists(f"{asp}/libexec/at-spi-bus-launcher"):
        sys.exit("no at-spi2-core found (hearth's HEARTH_ATSPI_TYPELIB)")
    subprocess.Popen(["setsid", RIG, "run", f"{asp}/libexec/at-spi-bus-launcher",
                      "--launch-immediately"], env=ENV, stdout=subprocess.DEVNULL,
                     stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL)
    time.sleep(2)
    # The a11y bus launcher's dbus-broker would activate the registry through
    # systemd, which a private bus can't do: start it ourselves.
    subprocess.Popen(["setsid", RIG, "run", f"{asp}/libexec/at-spi2-registryd"], env=ENV,
                     stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, stdin=subprocess.DEVNULL)
    time.sleep(1)
    r = rig("busctl", "set-property", "org.a11y.Bus", "/org/a11y/bus", "org.a11y.Status", "IsEnabled", "b", "true")
    if r.returncode:
        sys.exit("rig has no a11y bus: " + (r.stderr or r.stdout))
    if os.environ.get("MENU_PROBE_SCREENREADER"):
        # Experiment: the bus says a screen reader runs (Electron, Chromium
        # and EFL build their trees only then).
        rig("busctl", "set-property", "org.a11y.Bus", "/org/a11y/bus", "org.a11y.Status",
            "ScreenReaderEnabled", "b", "true")
    with open(os.path.join(RIGDIR, "core.pids"), "w") as f:
        f.write(" ".join(core_pids()))


def sync_modules():
    """The menu modules in the hearth checkout (menus/*.yaml), into the rig's
    ~/.config/hearth/menus, which hearth reads besides its own: modules
    written since devloop's last build are measured too (no build)."""
    src = os.path.join(ROOT, "..", "menus")
    dst = os.path.join(DISKDIR, "home", ".config", "hearth", "menus")
    os.makedirs(dst, exist_ok=True)
    for fn in glob.glob(os.path.join(src, "*.yaml")) + glob.glob(os.path.join(src, "*.json")):
        shutil.copy(fn, dst)


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


def app_procs(match):
    """Our uid's processes whose cwd or HOME/TMPDIR/XDG_RUNTIME_DIR satisfy
    match(path): the tested apps, wherever they ended up. `flatpak run` moves
    the app into its own app-flatpak-<id>-N.scope, out of our scope, so
    killing our scope alone leaks it."""
    found = []
    me = os.getuid()
    for p in os.listdir("/proc"):
        if not p.isdigit() or int(p) == os.getpid():
            continue
        try:
            if os.stat(f"/proc/{p}").st_uid != me:
                continue
            paths = []
            try:
                paths.append(os.readlink(f"/proc/{p}/cwd"))
            except OSError:
                pass
            try:
                for kv in open(f"/proc/{p}/environ", "rb").read().split(b"\0"):
                    k, _, v = kv.partition(b"=")
                    if k in (b"HOME", b"TMPDIR", b"XDG_RUNTIME_DIR"):
                        paths.append(v.decode(errors="replace"))
            except OSError:
                pass
            if any(match(x) for x in paths):
                found.append(int(p))
        except OSError:
            continue
    return found


def kill_procs(pids):
    """Stop each process's whole app scope when it is a Flatpak one (its
    bwrap/dbus-proxy helpers included), else SIGKILL the process."""
    scopes = set()
    for p in pids:
        try:
            cg = open(f"/proc/{p}/cgroup").read().strip().rsplit("/", 1)[-1]
        except OSError:
            continue
        if cg.startswith("app-flatpak-") and cg.endswith(".scope"):
            scopes.add(cg)
        else:
            try:
                os.kill(p, signal.SIGKILL)
            except OSError:
                pass
    for u in scopes:
        sh(["systemctl", "--user", "kill", "-s", "KILL", u], timeout=20)
        sh(["systemctl", "--user", "stop", u], timeout=20)
    return scopes


THROTTLED = set()


def throttle_flatpak_scopes():
    """The tested Flatpak's own app-flatpak-*.scope (Flatpak moves the app
    there, out of our scope) gets the same idle limits as our scopes; only
    scopes holding this worker's test app, never your real Flatpaks."""
    for p in own_app_procs():
        try:
            cg = open(f"/proc/{p}/cgroup").read().strip().rsplit("/", 1)[-1]
        except OSError:
            continue
        if cg.startswith("app-flatpak-") and cg.endswith(".scope") and cg not in THROTTLED:
            THROTTLED.add(cg)
            sh(["systemctl", "--user", "set-property", "--runtime", cg,
                "CPUWeight=idle", "IOWeight=1", "AllowedCPUs=0-7,12-19"], timeout=20)


def own_app_procs():
    mine = (os.path.join(DISKDIR, "apps") + "/", os.path.join(APPROOT, "apps") + "/")
    return app_procs(lambda x: x.startswith(mine))


def orphan_sweep():
    """Leftovers of any worker: processes still living in a deleted
    menu-rig-*/apps/N folder (a crashed or killed worker's apps)."""
    pat = re.compile(r"/menu-rig-[^/]*(/menu-rig-[^/]*)?/apps/\d+")

    def dead(x):
        m = pat.search(x)
        return bool(m) and (x.endswith(" (deleted)") or not os.path.isdir(x[:m.end()]))
    pids = app_procs(dead)
    if pids:
        scopes = kill_procs(pids)
        print(f"swept {len(pids)} leftover app processes ({len(scopes)} flatpak scopes)", file=sys.stderr, flush=True)


def cleanup():
    if SCOPE["unit"]:
        sh(["systemctl", "--user", "kill", "-s", "KILL", SCOPE["unit"]], timeout=20)
        SCOPE["unit"] = ""
    for _ in range(3):
        left = own_app_procs()
        if not left:
            break
        kill_procs(left)
        time.sleep(0.5)
    try:
        core = set(open(os.path.join(RIGDIR, "core.pids")).read().split())
    except OSError:
        return
    victims = [p for p in bus_pids() if p not in core]
    # What the rig's bus started for this app (Akonadi and its MariaDB,
    # Evolution's data server, portals): not always on the bus, never in a
    # scope of ours. Everything with this rig's bus in its environment.
    want = f"DBUS_SESSION_BUS_ADDRESS=unix:path={RIGDIR}/bus.sock".encode()
    me = os.getuid()
    # The rig itself stays: its core processes and all they started (arbor's
    # xwayland-satellite, the a11y bus), except what the session bus started.
    try:
        dbus_pid = open(os.path.join(RIGDIR, "dbus.pid")).read().strip()
    except OSError:
        dbus_pid = ""
    protected = set(core)
    for c in core:
        if c != dbus_pid:
            protected |= tree_pids(c)
    for name in ("arbor.pid", "hearth.pid"):
        try:
            protected |= tree_pids(open(os.path.join(RIGDIR, name)).read().strip())
        except OSError:
            pass
    for p in os.listdir("/proc"):
        if not p.isdigit() or p in protected or int(p) == os.getpid():
            continue
        try:
            if os.stat(f"/proc/{p}").st_uid != me:
                continue
            env = open(f"/proc/{p}/environ", "rb").read().split(b"\0")
        except OSError:
            continue
        if any(e == want or e.startswith(want + b",") for e in env):
            victims.append(p)
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
        rmtree(APPDIRS.pop())
    # Single-instance locks of killed apps (Chromium/Electron, Firefox).
    for pat in ("**/Singleton*", "**/lock", "**/.parentlock"):
        for fn in glob.glob(os.path.join(DISKDIR, "home", pat), recursive=True):
            try:
                os.unlink(fn)
            except OSError:
                pass


def desktop_exec(out):
    """First visible Application entry: (exec argv, desktop id)."""
    files = sorted(glob.glob(os.path.join(out, "share/applications/*.desktop")))
    best = None
    pname = re.sub(r"-(\d[^-]*|wrapped|bin|unwrapped)$", "", re.sub(r"-(\d[^-]*|wrapped|bin|unwrapped)$", "",
                   os.path.basename(out).split("-", 1)[-1])).lower()
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
        # Desktop-entry string escapes come first (\\$SHELL is \$SHELL to
        # the Exec quoting, then $SHELL: scrcpy's line ran "$SHELL" literally).
        ex = re.sub(r"\\([\\snrt])", lambda m: {"s": " ", "n": "\n", "r": "\r", "t": "\t"}.get(m[1], m[1]), e.get("Exec", ""))
        ex = ex.replace("\\$", "$").replace("\\`", "`")  # shlex keeps these inside "..."
        try:
            argv = shlex.split(ex)
        except ValueError:
            argv = ex.split()
        # Field codes as a launcher fills them with no files: %c is the
        # Name (khangman's -qwindowtitle "%c" lost its value and quit),
        # %k the entry's path, the rest go.
        argv = [{"%c": e.get("Name", ""), "%k": fn}.get(a, a) for a in argv]
        argv = [a for a in argv if not (len(a) == 2 and a.startswith("%"))]
        if not argv:
            continue
        stem = os.path.basename(fn)[:-len(".desktop")].split(".")[-1].lower()
        # Prefer the entry named like the package, then the plain launcher
        # (LibreOffice's startcenter "libreoffice %U" over "--base", whose
        # first window is a wizard dialog without menus).
        score = (stem == pname or stem.endswith("-" + pname), not any(a.startswith("-") for a in argv[1:]))
        if best is None or score > best[0]:
            best = (score, argv, os.path.basename(fn))
    if not best:
        return None, None
    _, argv, did = best
    while argv and argv[0] == "env":
        argv = argv[1:]
        while argv and "=" in argv[0]:
            argv = argv[1:]
    # "gapplication launch ID" (DBus-activatable GNOME apps): the app's own
    # binary, no arguments (it took "launch ID" as files to open and quit).
    if argv[:2] == ["gapplication", "launch"]:
        hits = sorted(glob.glob(os.path.join(out, "bin", "*")))
        names = [pname] + ([argv[2].rsplit(".", 1)[-1].lower()] if len(argv) > 2 else [])
        named = [h for h in hits if os.path.basename(h).lower() in names]
        return (named or hits)[:1], did
    # A shell line (Mixxx: sh -c "pasuspender -- mixxx || mixxx") stays a
    # shell line; the app's own name inside it resolves on PATH below.
    if argv and argv[0] in ("sh", "bash", "/bin/sh", "/bin/bash") and "-c" in argv[1:2]:
        bindir = os.path.join(out, "bin")
        argv = ["/bin/sh", "-c", f'PATH="{bindir}:$PATH"; ' + argv[2]] if len(argv) > 2 else argv
        return argv, did
    # The program by its name in the package's bin/ (an Exec of
    # /usr/bin/cropgui is the package's cropgui too), its other outputs
    # next; never another package's (ace-of-penguins got its desktop item's
    # derivation, "...-canfield.desktop/bin"). A name it doesn't have
    # (unetbootin_asroot): its own binary named like it, or its only one.
    if argv and not (argv[0].startswith("/nix/store/") and os.path.exists(argv[0])):
        name = os.path.basename(argv[0])
        outs = [out] + [o for o in sorted(glob.glob(out.rsplit("-", 1)[0] + "-*"))
                        if o != out and not o.endswith((".desktop", ".drv"))]
        hit = next((os.path.join(o, "bin", name) for o in outs if os.path.exists(os.path.join(o, "bin", name))), None)
        if not hit:
            bins = sorted(glob.glob(os.path.join(out, "bin", "*")))
            stem = name.split("_")[0].split("-")[0].lower()
            named = [b for b in bins if os.path.basename(b).lower() in (pname, stem)]
            hit = (named or (bins if len(bins) == 1 else [None]))[0]
        if hit:
            argv[0] = hit
    return argv, did


def app_menus(dump):
    if "menus" in (dump or {}) and isinstance(dump["menus"], list):  # appmenu summary
        return [(m.get("label", ""), m.get("items", 0)) for m in dump["menus"]]
    return _app_menus_tree(dump)


def read_menus(dump):
    """One-item menus that were read (a ☰ holding only About), not the
    reader's unread "…" placeholder: hearth's summary says unread=false."""
    return [m.get("label", "") for m in (dump or {}).get("menus") or []
            if isinstance(m, dict) and m.get("items") == 1 and m.get("unread") is False]


def _app_menus_tree(dump):
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


# Never started on the rig's bus, whichever app ships them: the keyring,
# the a11y bus (the rig runs its own), systemd, accounts.
SERVICE_DENY = re.compile(r"^(org\.a11y\.|org\.freedesktop\.(secrets|systemd1|machine1|import1|portable1|login1)|"
                          r"org\.kde\.kwalletd|org\.freedesktop\.impl\.portal\.(desktop\.(oo7|kde)|Secret)|"
                          r"org\.gnome\.keyring|org\.gnome\.OnlineAccounts|io\.github\.benwbooth\.)")
APP_SERVICES = []


def app_services(argv):
    """Link the D-Bus services of the app's closure into the rig's service
    folder (evolution-data-server for GNOME Contacts, gnome-terminal-server
    for GNOME Terminal), so its bus starts them as a session would; the
    previous app's are removed."""
    sdir = os.path.join(RIGDIR, "services")
    while APP_SERVICES:
        try:
            os.unlink(APP_SERVICES.pop())
        except OSError:
            pass
    prog = next((a for a in argv if a.startswith("/nix/store/")), "")
    if not prog or not os.path.isdir(sdir):
        return
    root = "/".join(os.path.realpath(prog).split("/")[:4])
    try:
        closure = subprocess.run(["nix-store", "-qR", root], capture_output=True, text=True, timeout=60).stdout.split()
    except Exception:
        return
    for p in closure:
        for f in glob.glob(os.path.join(p, "share/dbus-1/services/*.service")):
            name = os.path.basename(f)[:-len(".service")]
            dst = os.path.join(sdir, os.path.basename(f))
            if SERVICE_DENY.search(name) or os.path.exists(dst):
                continue
            try:
                os.symlink(f, dst)
                APP_SERVICES.append(dst)
            except OSError:
                pass
    if APP_SERVICES:
        rig("busctl", "call", "org.freedesktop.DBus", "/org/freedesktop/DBus", "org.freedesktop.DBus", "ReloadConfig")


def attempt(attr, argv, variant, extra_env, extra_args, wait_win=50, wait_menu=16):
    cleanup()
    sync_modules()
    app_services(argv)
    before = {w["id"] for w in windows()}
    # The arbor session has X11 too (xwayland-satellite): VLC 3 and other
    # X11-only apps need DISPLAY even when they run "natively".
    env = dict(SESSION_ENV, DISPLAY=arbor_display())
    # GTK modules as the session finds them: GTK 2's folder before GTK 3's
    # (each GTK loads appmenu-gtk-module from its own), from the hearth
    # under test.
    hp = HEARTH_PKG or "/run/current-system/sw"
    env["GTK_PATH"] = f"{hp}/lib/gtk-2.0:{hp}/lib/gtk-3.0:/run/current-system/sw/lib/gtk-2.0:/run/current-system/sw/lib/gtk-3.0"
    # Java's accessibility bridge, as arbor/config.kdl loads it into every
    # JVM (from the hearth under test). Not for Flatpaks: the session blanks
    # it there (they can't see the jar), and the survey's own Flatpak
    # installation has no such override.
    jaw = os.path.join(HEARTH_PKG or "/run/current-system/sw", "lib/java-atk-wrapper/java-atk-wrapper.jar")
    if os.path.exists(jaw) and "flatpak" not in " ".join(argv[:4]):
        env["JAVA_TOOL_OPTIONS"] = ("-Xbootclasspath/a:" + jaw
                                    + " -Djavax.accessibility.assistive_technologies=org.GNOME.Accessibility.AtkWrapper")
    # Every attempt gets fresh home, runtime and temp dirs: a killed app's
    # single-instance lock or socket ("Strawberry is already running") must
    # not stop the next app, and no first-run state carries over.
    base = os.path.join(DISKDIR if argv[0] == "bwrap" else APPROOT, "apps", str(SCOPE["n"] + 1))
    rmtree(base)
    dirs = {"HOME": "home", "XDG_CONFIG_HOME": "home/.config", "XDG_CACHE_HOME": "home/.cache",
            "XDG_DATA_HOME": "home/.local/share", "XDG_STATE_HOME": "home/.local/state",
            "XDG_RUNTIME_DIR": "run", "TMPDIR": "tmp"}
    for k, d in dirs.items():
        os.makedirs(os.path.join(base, d), mode=0o700, exist_ok=True)
        env[k] = os.path.join(base, d)
    if argv[0] != "bwrap":
        # A short TMPDIR: Chromium puts its SingletonSocket there and dies
        # when the path passes the 108-byte socket limit (ChatGPT, Brave,
        # Spotify under ~/.cache/... never opened a window).
        tmp = f"/tmp/menu-rig-{WORKER or 0}-{SCOPE['n'] + 1}"
        rmtree(tmp)
        os.makedirs(tmp, mode=0o700, exist_ok=True)
        env["TMPDIR"] = tmp
        APPDIRS.append(tmp)
    # The rig's PipeWire (menu-rig.sh): a PulseAudio server and JACK through
    # PipeWire's libjack, for apps that won't start without sound.
    rig_run = os.path.join(RIGDIR, "run")
    if os.path.exists(os.path.join(rig_run, "pipewire-0")):
        env["PIPEWIRE_RUNTIME_DIR"] = rig_run
        env["PULSE_SERVER"] = "unix:" + os.path.join(rig_run, "pulse", "native")
        pwjack = tool("pipewire-jack", "pipewire.jack")
        if pwjack and not any(x in " ".join(argv[:6]) for x in ("flatpak", "appimage-run", "bwrap")):
            env["LD_LIBRARY_PATH"] = os.path.join(pwjack, "lib")
    if any("appimage-run" in a for a in argv):
        # appimage-run extracts to $XDG_CACHE_HOME/appimage-run/<hash>; under
        # $TMPDIR/.mount_* it passes Tauri's AppImage check (its executable
        # must start with "$TMPDIR/.mount_", where the FUSE runtime mounts),
        # which otherwise panics on APPIMAGE/APPDIR. Harmless for the rest.
        env["XDG_CACHE_HOME"] = os.path.join(env["TMPDIR"], ".mount_cache")
        os.makedirs(env["XDG_CACHE_HOME"], exist_ok=True)
    if "flatpak" in " ".join(argv[:4]):
        # The Flatpak portal (bus-activated, the rig's runtime dir) reads each
        # instance's bwrapinfo.json from its own XDG_RUNTIME_DIR/.flatpak:
        # an app in another runtime dir can't Spawn (every Chromium and
        # Electron Flatpak's sandbox). Cleanup still finds it by HOME/TMPDIR.
        env["XDG_RUNTIME_DIR"] = os.path.join(RIGDIR, "run")
    # A lived-in home: the XDG user folders (gdm-settings and Varia crash on
    # a None Downloads folder) and a login shell (scrcpy runs $SHELL).
    home = env["HOME"]
    udirs = {"DESKTOP": "Desktop", "DOWNLOAD": "Downloads", "TEMPLATES": "Templates", "PUBLICSHARE": "Public",
             "DOCUMENTS": "Documents", "MUSIC": "Music", "PICTURES": "Pictures", "VIDEOS": "Videos"}
    for d in udirs.values():
        os.makedirs(os.path.join(home, d), exist_ok=True)
    with open(os.path.join(home, ".config", "user-dirs.dirs"), "w") as f:
        f.writelines(f'XDG_{k}_DIR="$HOME/{d}"\n' for k, d in udirs.items())
    env.setdefault("SHELL", "/run/current-system/sw/bin/bash")
    APPDIRS.append(base)
    env.update(extra_env)
    envargs = [f"{k}={v}" for k, v in env.items()]
    # On disk (DISKDIR), never the /run/user tmpfs: an app that floods its
    # output once filled it (2026-11-25/26).
    os.makedirs(DISKDIR, exist_ok=True)
    log = open(os.path.join(DISKDIR, "app.log"), "w")
    if os.environ.get("MENU_PROBE_DEBUG"):
        log.write("probe argv: " + repr(envargs + list(argv) + list(extra_args)) + "\n")
        log.flush()
    SCOPE["n"] += 1
    SCOPE["unit"] = f"menuprobe-{os.getpid()}-{SCOPE['n']}.scope"
    proc = subprocess.Popen(["systemd-run", "--user", "--scope", "--quiet", "--collect", "--unit", SCOPE["unit"],
                             "-p", "Slice=menusurvey.slice",  # the survey's 8 GB in all (restart-workers.sh)
                             "-p", "MemoryMax=4G", "-p", "CPUWeight=idle", "-p", "IOWeight=1",
                             "-p", "AllowedCPUs=0-7,12-19", "prlimit", "--core=0", "--fsize=1073741824", "--", "setsid", RIG, "run", "env", *envargs, *argv, *extra_args], env=ENV,
                            stdout=log, stderr=subprocess.STDOUT, stdin=subprocess.DEVNULL,
                            cwd=env["HOME"])  # apps drop logs/configs in their cwd
    t0 = time.time()
    win = None
    while time.time() - t0 < wait_win:
        if "flatpak" in " ".join(argv[:6]):
            throttle_flatpak_scopes()
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
        res.update(result="no-window", log_tail=tail(os.path.join(DISKDIR, "app.log")))
        # A tray-only app (Flameshot, EasyEffects, KTeaTime): no window, its
        # menu is its tray icon's. Nothing for the menu bar to show.
        tray = tray_items(proc.pid)
        if tray:
            res.update(result="tray-only", tray=tray)
        return res
    if "flatpak" in " ".join(argv[:6]):
        throttle_flatpak_scopes()  # once more: it may have moved after the window showed
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
            r = rig("ipc", "call", "appmenu", "summary", timeout=20)
            if "summary" not in r.stdout and not r.stdout.strip().startswith("{"):
                r = rig("dump", timeout=20)  # a hearth without summary
            try:
                dump = json.loads(r.stdout)
                dump_ok = True
            except Exception:
                dump = {}
            menus = app_menus(dump)
            if any(n for _, n in menus) and time.time() - t1 > 2.5:
                break
        opened = open_placeholders(menus, dump, cw["id"])
        if opened:
            dump, menus = opened
        w = next((x for x in windows() if x["id"] == cw["id"]), cw)
        req = dump.get("request") or {}
        route = req.get("kind") or ("none" if not menus else "?")
        if route == "x11" and menus:
            route = infer_x11_route(w)
        cur = dict(window=dict(title=w.get("title"), app_id=w.get("app_id"), pid=w.get("pid"),
                               app_menu=w.get("app_menu"),
                               gtk_menu=w.get("gtk_menu")),
                   route=route, request=req,
                   menus=[f"{l}:{n}" for l, n in menus], n_items=(sum(n for _, n in menus) if "menus" in dump else count_items(dump.get("tree") or dump.get("menu") or {})),
                   read_menus=read_menus(dump),
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
    if not escaped and not full_menus(best):
        # What the app exposes, while it's surely still up (Escape and the
        # first-run close below can end it).
        best["inspect"] = inspect(dict(best.get("window") or {}, pid=(best.get("window") or {}).get("pid")))
    if not full_menus(best) and not escaped and (best.get("inspect") or {}).get("atspi", {}).get("found"):
        # A first-run wizard in front (PCSX2's Setup Wizard): press its
        # Finish/Skip/Next buttons over AT-SPI, as a user would once.
        pid = x11_app_pid((best.get("window") or {}).get("pid") or 0)
        if pid:
            r = rig("run", "env", f"GI_TYPELIB_PATH={hearth_typelibs()}", hearth_python(),
                    os.path.join(ROOT, "scripts", "atspi-firstrun.py"), str(pid),
                    (best.get("window") or {}).get("title") or "", timeout=60)
            try:
                pressed = json.loads(r.stdout.strip().splitlines()[-1]).get("pressed") or []
            except Exception:
                pressed = []
            if pressed:
                time.sleep(3)
                again = attempt_windows(attr, before, win, wait_menu, escaped="wizard")
                if again and again["n_items"] > best["n_items"]:
                    again["first_run_pressed"] = pressed
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


def tray_items(root_pid):
    """StatusNotifierItem names on the rig's bus owned by the app's processes
    (Flatpaks: their D-Bus proxy)."""
    b = rig("busctl", "--json=short", "list")
    try:
        names = json.loads(b.stdout)
    except Exception:
        return []
    tree = tree_pids(root_pid)
    pid_of_name = {n.get("name", ""): str(n.get("pid") or "") for n in names}
    # Items register with the watcher by service name, often their unique
    # one (Qt: ":1.32/StatusNotifierItem").
    r = rig("busctl", "--json=short", "get-property", "org.kde.StatusNotifierWatcher", "/StatusNotifierWatcher",
            "org.kde.StatusNotifierWatcher", "RegisteredStatusNotifierItems")
    try:
        items = json.loads(r.stdout).get("data") or []
    except Exception:
        items = []
    found = []
    for it in items:
        svc = it.split("/", 1)[0]
        if pid_of_name.get(svc, "") in tree:
            found.append(it)
    return found


def full_menus(r):
    return r.get("result") == "menus" and len([m for m in r.get("menus", []) if not m.endswith(":0")]) >= 2


def open_placeholders(menus, dump, win_id=None):
    """Menus hearth reads only when they open (the AT-SPI ☰, a Kirigami
    drawer) show one placeholder item until then. Open each in the menu bar,
    as the user would (hearth reads it unseen, arbor ProbeWindow), and
    measure what it then holds."""
    if (dump.get("request") or {}).get("kind") not in ("atspi", "x11") or not menus:
        return None
    thin = [l for l, n in menus if n <= 1 and l][:3]
    if not thin:
        return None
    for label in thin:
        rig("ipc", "call", "appmenu", "openMenu", label, timeout=20)
        t0 = time.time()
        # A first read can take several seconds (an unnamed GTK 4 ☰ is
        # searched for, opened unseen, read three levels deep).
        while time.time() - t0 < 15:
            time.sleep(1.0)
            try:
                d = json.loads(rig("ipc", "call", "appmenu", "summary", timeout=20).stdout)
            except Exception:
                continue
            m = app_menus(d)
            # Read: more items, more menus, or its one item no longer the
            # "…" placeholder (a ☰ holding only Close window).
            if dict(m).get(label, 0) > 1 or len(m) > len(menus) or label in read_menus(d):
                dump, menus = d, m
                break
        if win_id:  # the bar's menu closes when the app takes focus back
            rig("run", "arbor", "msg", "action", "focus-window", "--id", str(win_id))
            time.sleep(0.5)
    dump["opened"] = thin
    return dump, menus


def ocr_top(r):
    """A window where no menus were found: what screen reading saw at its
    top and a strip of it (scripts/ocr-top.py) to look at, so "no menus"
    can be told from "menus nothing reads" (a drawn bar, an icon button)."""
    if r.get("result") != "fallback" or not (r.get("window") or {}).get("title"):
        return
    wid = next((w["id"] for w in windows() if w.get("title") == r["window"]["title"]
                and w.get("app_id") != "org.quickshell"), None)
    helpers = os.path.join(HEARTH_PKG or "/run/current-system/sw", "share", "hearth", "helpers")
    tess = tool("tesseract")
    os.makedirs(os.path.join(SHOTS, "top"), exist_ok=True)
    if wid is None or not tess or not os.path.isdir(helpers):
        return
    res = rig("run", "env", f"XDG_RUNTIME_DIR={os.environ['XDG_RUNTIME_DIR']}", f"PATH={tess}/bin:{os.environ.get('PATH', '')}",
              sys.executable, "-I", os.path.join(ROOT, "scripts", "ocr-top.py"), str(wid), helpers,
              os.path.join(SHOTS, "top", r["attr"].replace("/", "_") + ".png"), timeout=60)
    try:
        r["ocr_top"] = json.loads(res.stdout.strip().splitlines()[-1])
    except (ValueError, IndexError, AttributeError):
        r["ocr_top"] = {"error": (getattr(res, "stderr", "") or "")[-200:]}


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
        dump = json.loads(rig("ipc", "call", "appmenu", "summary", timeout=20).stdout)
    except Exception:
        return
    menus = app_menus(dump)
    if len([n for _, n in menus if n]) >= 2:
        sess.update(result="menus", menus=[f"{l}:{n}" for l, n in menus], late=True,
                    n_items=(sum(n for _, n in menus) if "menus" in dump else count_items(dump.get("tree") or dump.get("menu") or {})),
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


def tail(fn, n=6, limit=64 * 1024):
    """The last n lines, from at most the last `limit` bytes: an app that
    floods its log (gigabytes) once made every probe hold it in memory."""
    try:
        with open(fn, "rb") as f:
            f.seek(0, os.SEEK_END)
            f.seek(max(0, f.tell() - limit))
            # Each line cut too: a terminal program draws its whole screen
            # on one line (klip: 6.6 GB).
            return [l[:400] for l in f.read().decode(errors="replace").strip().splitlines()[-n:]]
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


def flatpak_terminal_only(fid):
    """Every launcher of the app is Terminal=true (cmus...): no window and no
    menus, and run without a tty it spins at 100% CPU."""
    files = glob.glob(os.path.join(FLATPAK_DIR, "app", fid, "current", "active", "export", "share",
                                   "applications", "*.desktop"))
    seen = False
    for fn in files:
        cp = configparser.RawConfigParser(strict=False, interpolation=None)
        try:
            cp.read(fn, encoding="utf-8")
            e = cp["Desktop Entry"]
        except Exception:
            continue
        if e.get("Type", "Application") != "Application" or e.get("NoDisplay", "").lower() == "true":
            continue
        seen = True
        if e.get("Terminal", "").lower() != "true":
            return False
    return seen


def probe_flatpak(attr):
    fid = attr.split(":", 1)[1]
    os.makedirs(FLATPAK_DIR, exist_ok=True)
    flatpak("remote-add", "--if-not-exists", "flathub", "https://dl.flathub.org/repo/flathub.flatpakrepo")
    r = flatpak("install", "-y", "--noninteractive", "flathub", fid)
    if r.returncode and "already installed" not in (r.stderr + r.stdout):
        return [dict(attr=attr, variant="build", result="install-failed", error=(r.stderr or r.stdout)[-300:])]
    if flatpak_terminal_only(fid):
        flatpak("uninstall", "-y", "--noninteractive", fid)
        return [dict(attr=attr, variant="exec", result="terminal-only", flatpak=True)]
    meta = flatpak("info", "--show-metadata", fid).stdout
    talk = sorted(set(re.findall(r"(com\.canonical\.AppMenu\.Registrar|org\.kde\.StatusNotifierWatcher|org\.a11y\.Bus)", meta)))
    # No network: with the host's network namespace an app reaches any
    # abstract X11 socket, Ben's own display's too (LVNAuth's startup.sh
    # sets DISPLAY=:0.0 and opened on the real desktop, 2026-11-25).
    argv = ["env", f"FLATPAK_USER_DIR={FLATPAK_DIR}", "flatpak", "run", "--unshare=network", fid]
    # A Java app: run it as hearth.globalMenu.javaFlatpaks would (the bridge
    # folder read-only, JAVA_TOOL_OPTIONS and JDK_JAVA_OPTIONS), so the
    # survey says which Java Flatpaks work with that override.
    java_override = False
    jaw = os.path.realpath(os.path.join(HEARTH_PKG or "/run/current-system/sw", "lib/java-atk-wrapper"))
    if os.path.isdir(jaw) and (toolkit_of(attr) in ("java-swing", "javafx") or "openjdk" in meta.lower()):
        opts = (f"-Xbootclasspath/a:{jaw}/java-atk-wrapper.jar"
                " -Djavax.accessibility.assistive_technologies=org.GNOME.Accessibility.AtkWrapper")
        argv = argv[:-1] + [f"--filesystem={jaw}:ro", f"--env=JAVA_TOOL_OPTIONS={opts}",
                            f"--env=JDK_JAVA_OPTIONS={opts}", fid]
        java_override = True
    rows = []
    r0 = attempt(attr, argv, "session", {}, [])
    r0["java_override"] = java_override
    r0["hearth"] = HEARTH_PKG or "installed"
    if r0.get("result") != "no-window" and len([m for m in r0.get("menus", []) if not m.endswith(":0")]) < 2 \
            and not (r0.get("inspect") or {}).get("atspi", {}).get("found"):
        r0["inspect"] = r0.get("inspect") or inspect(r0.get("window"))
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


APPIMAGE_DIR = "/var/tmp/menu-rig-" + os.environ.get("USER", "ben") + "/appimages"  # on disk, never /run/user
APPIMAGES = {}


def appimage_url(how):
    """The x86_64 AppImage to download: a direct URL, or the newest GitHub
    release that has one."""
    if how.get("url"):
        return how["url"]
    repo = how.get("repo")
    if not repo:
        return ""
    r = subprocess.run(["gh", "api", f"repos/{repo}/releases?per_page=8"], capture_output=True, text=True, timeout=60)
    try:
        rels = json.loads(r.stdout)
    except ValueError:
        return ""
    bad = re.compile(r"(aarch64|arm64|armhf|armv7|i[3-6]86|\.zsync$)", re.I)
    for rel in rels if isinstance(rels, list) else []:
        assets = [a for a in rel.get("assets") or [] if a.get("name", "").lower().endswith(".appimage")
                  and not bad.search(a["name"])]
        assets.sort(key=lambda a: (not re.search(r"x86_64|amd64|x64", a["name"], re.I), a["name"]))
        if assets:
            return assets[0]["browser_download_url"]
    return ""


# MENU_PROBE_EXTRA_ENV="K=V K2=V2": added to every app's environment
# (experiments on one rig).
SESSION_ENV.update(dict(kv.split("=", 1) for kv in os.environ.get("MENU_PROBE_EXTRA_ENV", "").split() if "=" in kv))


def sandboxed(argv):
    """Run an untrusted program (a downloaded AppImage) in bubblewrap: your
    home and the real session's sockets hidden (/run/user, /tmp), only the
    rig's bus, display and a11y sockets passed in, no network (an abstract
    X11 socket would reach the real X server otherwise)."""
    env = {}
    for l in open(os.path.join(RIGDIR, "arbor.env")):
        k, _, v = l.rstrip("\n").partition("=")
        env[k] = v
    wl = os.path.join(os.environ["XDG_RUNTIME_DIR"], env.get("WAYLAND_DISPLAY", ""))
    xnum = env.get("DISPLAY", ":").lstrip(":").split(".")[0]
    home = os.path.expanduser("~")
    args = ["bwrap", "--dev-bind", "/", "/", "--tmpfs", home, "--tmpfs", os.environ["XDG_RUNTIME_DIR"],
            "--bind", RIGDIR, RIGDIR, "--tmpfs", "/tmp", "--unshare-net", "--die-with-parent"]  # IPC shared: X's MIT-SHM needs it (RustDesk)
    for sock in (wl, wl + ".lock"):
        if os.path.exists(sock):
            args += ["--bind", sock, sock]
    if xnum and os.path.exists(f"/tmp/.X11-unix/X{xnum}"):
        args += ["--bind", f"/tmp/.X11-unix/X{xnum}", f"/tmp/.X11-unix/X{xnum}"]
    # An FHS /bin/true: anylinux AppImages' fix-namespaces hook tests user
    # namespaces with "unshare -r /bin/true" and, where that fails (NixOS
    # has only /bin/sh), opens an xterm about Ubuntu's restriction instead
    # of the app.
    true = shutil.which("true")
    if true:
        args += ["--tmpfs", "/bin", "--ro-bind", os.path.realpath("/bin/sh"), "/bin/sh",
                 "--ro-bind", os.path.realpath(true), "/bin/true"]
    return args + ["--"] + argv


def appimage_terminal_only():
    """Whether the AppImage just run (appimage-run's newest extraction under
    the attempt homes) has a desktop file with Terminal=true."""
    import glob
    dirs = glob.glob(os.path.join(DISKDIR, "apps", "*", "home", ".cache", "appimage-run", "*"))
    if not dirs:
        return False
    newest = max(dirs, key=lambda d: os.path.getmtime(d) if os.path.exists(d) else 0)
    for f in glob.glob(os.path.join(newest, "*.desktop")):
        try:
            if re.search(r"^Terminal\s*=\s*true\s*$", open(f, errors="replace").read(), re.M | re.I):
                return True
        except OSError:
            pass
    return False


def appimage_fs(fn):
    """The AppImage's payload: "squashfs" (the classic type 2 runtime) or
    "dwarfs" (uruntime), by the magic right after the ELF runtime (its end:
    the section header table, as appimagetool and uruntime find it; both
    runtimes carry the other format's magic as a string inside)."""
    import struct
    try:
        with open(fn, "rb") as f:
            eh = f.read(64)
            if eh[:4] != b"\x7fELF" or eh[4] != 2:
                return ""
            shoff, = struct.unpack_from("<Q", eh, 0x28)
            shentsize, shnum = struct.unpack_from("<HH", eh, 0x3A)
            f.seek(shoff + shentsize * shnum)
            magic = f.read(6)
    except (OSError, struct.error):
        return ""
    return "dwarfs" if magic == b"DWARFS" else "squashfs" if magic[:4] == b"hsqs" else ""


def probe_appimage(attr):
    how = APPIMAGES.get(attr) or {}
    url = appimage_url(how)
    if not url:
        return [dict(attr=attr, variant="build", result="not-prebuilt", error="no x86_64 AppImage found")]
    os.makedirs(APPIMAGE_DIR, exist_ok=True)
    fn = os.path.join(APPIMAGE_DIR, re.sub(r"[^A-Za-z0-9_.+-]", "_", attr) + ".AppImage")
    r = subprocess.run(["curl", "-sfL", "--max-filesize", str(2 * 1024 ** 3), "-o", fn, url],
                       capture_output=True, text=True, timeout=1800)
    try:
        if r.returncode or not os.path.exists(fn):
            return [dict(attr=attr, variant="build", result="install-failed", error=f"download: {url} {r.stderr[-200:]}")]
        os.chmod(fn, 0o755)
        # The survey's appimage-run (appimage-run.nix: unstable's glibc and
        # the libraries AppImages expect from the host), else the system's.
        ar = os.path.expanduser("~/.cache/hearth-menu-survey/roots/appimage-run/bin/appimage-run")
        # Its store path: the sandbox hides your home, where the GC root is.
        if appimage_fs(fn) == "dwarfs":
            # uruntime (pkgforge's "anylinux" AppImages): a DwarFS image that
            # appimage-run can't open, but self-contained (sharun bundles its
            # own loader and libraries), so it runs as is, extracting itself
            # to $TMPDIR (no FUSE in the sandbox).
            # The "AI\x02" marker at offset 8 blanked in this copy: with it,
            # NixOS's AppImage binfmt hands any exec of the file to the
            # system's appimage-run (programs.appimage.binfmt).
            with open(fn, "r+b") as f:
                f.seek(8)
                if f.read(3) == b"AI\x02":
                    f.seek(8)
                    f.write(b"\0\0\0")
            argv = sandboxed(["env", "APPIMAGE_EXTRACT_AND_RUN=1", fn])
        else:
            argv = sandboxed([os.path.realpath(ar) if os.path.exists(ar) else "/run/current-system/sw/bin/appimage-run", fn])
        rows = [attempt(attr, argv, "session", {}, [])]
        r0 = rows[0]
        r0.update(hearth=HEARTH_PKG or "installed", appimage=url, sandboxed=True)
        if r0.get("result") != "no-window" and not (r0.get("inspect") or {}).get("atspi", {}).get("found"):
            r0["inspect"] = r0.get("inspect") or inspect(r0.get("window"))
        late_check(rows)
        if rows[-1].get("result") == "no-window" and appimage_terminal_only():
            # A terminal program (Neovim, Helix): its desktop file says
            # Terminal=true. Skipped, like terminal-only Flatpaks.
            rows[-1]["result"] = "terminal-only"
        rows[-1]["shot"] = shot(attr)
        cleanup()
        return rows
    finally:
        try:
            os.unlink(fn)
        except OSError:
            pass


def probe(attr):
    if attr.startswith("appimage:"):
        return probe_appimage(attr)
    if attr.startswith("installed:"):
        return probe_installed(attr)
    if attr.startswith("flathub:"):
        return probe_flatpak(attr)
    src = APPS.get(attr, {}).get("source", "nixpkgs")
    # Not in the binary cache (uncached free, and every unfree package): its
    # Flathub copy instead (a download, never a build), else skipped.
    if src == "nixpkgs-unfree":
        # Ben, 2026-11-26: measure unfree packages themselves when that's
        # no hours-long build; their Flathub copy otherwise.
        try:
            ok, why = unfree_build_ok(attr)
        except subprocess.TimeoutExpired:
            ok, why = False, "dry run timed out"
        if ok:
            outs, err = nix_build_unfree(attr)
            if outs:
                try:
                    rows = probe_store(attr, outs, err)
                    for r in rows:
                        r["unfree_built"] = why
                    return rows
                finally:
                    store_delete(outs)
    if src in ("nixpkgs-unfree", "nixpkgs-uncached"):
        fid = APPS[attr].get("flathub")
        if not fid:
            return [dict(attr=attr, variant="build", result="not-prebuilt")]
        rows = probe_flatpak("flathub:" + fid)
        for r in rows:
            r["attr"], r["via_flathub"] = attr, fid
        return rows
    outs, err = nix_build(attr, unfree=(src == "nixpkgs-unfree"), timeout=1800 if src == "nixpkgs-unfree" else 900)
    fid = APPS.get(attr, {}).get("flathub")
    if not outs and fid and re.search(r"max-jobs|will be built|does not provide|Did you mean|has been removed", err or ""):
        # Not in the binary cache (or gone from nixpkgs): its Flathub copy.
        rows = probe_flatpak("flathub:" + fid)
        for r in rows:
            r["attr"], r["via_flathub"] = attr, fid
        return rows
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
    return probe_argv(attr, argv, toolkit_of(attr), dict(store=out, desktop=did))


INSTALLED = {}


OPEN_LABEL = re.compile(r"^(open|open file|open\.\.\.|open…|open file\.\.\.|open file…|open project.*|open folder.*)$", re.I)


def find_open_item(node, path=()):
    """The path ("File/Open…") of the app's Open command in hearth's menu
    dump, File first."""
    best = None
    for c in (node or {}).get("children") or []:
        label = (c.get("label") or "").replace("_", "").strip()
        p = path + (c.get("label") or "",)
        if c.get("children"):
            hit = find_open_item(c, p)
            if hit and (best is None or p[0].lower() == "file"):
                best = hit
                if p[0].lower() == "file":
                    return best
        elif OPEN_LABEL.match(label) and c.get("enabled", True):
            return "/".join(p)
    return best


def file_dialog(row):
    """Whether the app's Open dialog is the portal's (Hearth's file dialog
    on the desktop) or one the app draws itself: run its Open command (its
    menu item through hearth, else Ctrl+O) and see whose window opens. Ben,
    2026-11-26: installed apps' file dialogs, alongside their menus."""
    w = row.get("window") or {}
    cur = [x for x in windows() if x.get("app_id") != "org.quickshell"]
    win = next((x for x in cur if x.get("pid") == w.get("pid") and x.get("title") == w.get("title")), None) \
        or next((x for x in cur if x.get("pid") == w.get("pid")), None) or (cur[-1] if cur else None)
    if not win:
        return {"result": "no-window"}
    mine = tree_pids(x11_app_pid(win.get("pid") or 0) or win.get("pid") or 0)
    before = {x["id"] for x in windows()}
    rig("run", "arbor", "msg", "action", "focus-window", "--id", str(win["id"]))
    time.sleep(1.0)
    via = "keys"
    try:
        dump = json.loads(rig("dump", timeout=20).stdout)
        path = find_open_item(dump.get("tree") or dump.get("menu") or {})
    except Exception:
        path = None
    if path:
        r = rig("ipc", "call", "appmenu", "click", path, timeout=20)
        via = "menu:" + path if "ok" in r.stdout else "keys"
    if via == "keys":
        rig("run", "arbor", "msg", "action", "send-keys", "--id", str(win["id"]), "--keys", "Ctrl+O")
    new = []
    for _ in range(16):
        time.sleep(0.5)
        new = [x for x in windows() if x["id"] not in before and x.get("app_id") != "org.quickshell"]
        if new:
            time.sleep(0.8)
            new = [x for x in windows() if x["id"] not in before and x.get("app_id") != "org.quickshell"]
            break
    res = {"via": via}
    if not new:
        res["result"] = "none"
    else:
        d = new[-1]
        own = str(x11_app_pid(d.get("pid") or 0) or d.get("pid")) in mine
        res.update(result="own" if own else "portal", title=d.get("title"), app_id=d.get("app_id"))
        for x in new:
            rig("run", "arbor", "msg", "action", "close-window", "--id", str(x["id"]))
    return res


def probe_installed(attr):
    """An app installed on this machine (data/installed_exec.tsv, from
    installed_apps.py): run from the installed copy. Nothing is downloaded,
    built, uninstalled or deleted."""
    argv = INSTALLED.get(attr)
    if not argv:
        return [dict(attr=attr, variant="exec", result="no-entry")]
    note = APPS.get(attr, {}).get("note", "")
    m = re.search(r"\(catalog: ([^)]+)\)", note)
    tk = toolkit_of(m.group(1)) if m else ""
    if argv[0] == "flatpak":
        # Ben's own installations (system and user); the fresh HOME would
        # otherwise hide the user one.
        fid = argv[1]
        rows = [attempt(attr, ["env", "FLATPAK_USER_DIR=" + os.path.expanduser("~/.local/share/flatpak"),
                               "flatpak", "run", "--unshare=network", *argv[2:], fid], "session", {}, [])]
        r = rows[0]
        r["hearth"] = HEARTH_PKG or "installed"
        if r.get("result") != "no-window" and not (r.get("inspect") or {}).get("atspi", {}).get("found"):
            r["inspect"] = r.get("inspect") or inspect(r.get("window"))
        r.update(toolkit=tk, flatpak=True, installed=True)
        late_check(rows)
        rows[-1]["shot"] = shot(attr)
        if rows[-1].get("result") not in ("no-window", "tray-only"):
            rows[-1]["file_dialog"] = file_dialog(rows[-1])
        cleanup()
        return rows
    rows = probe_argv(attr, argv, tk, dict(installed=True))
    return rows


def probe_argv(attr, argv, tk, extra):
    rows = []
    r = attempt(attr, argv, "session", {}, [])
    r["hearth"] = HEARTH_PKG or "installed"
    if r.get("result") != "no-window" and len([m for m in r.get("menus", []) if not m.endswith(":0")]) < 2 \
            and not (r.get("inspect") or {}).get("atspi", {}).get("found"):
        r["inspect"] = r.get("inspect") or inspect(r.get("window"))
    r.update(extra, toolkit=tk)
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
    ocr_top(rows[-1])
    rows[-1]["shot"] = shot(attr)
    if extra.get("installed") and rows[-1].get("result") not in ("no-window", "tray-only"):
        try:
            rows[-1]["file_dialog"] = file_dialog(rows[-1])
        except Exception as e:
            rows[-1]["file_dialog"] = {"result": "error", "error": str(e)[:200]}
    cleanup()
    return rows


LOCAL = os.path.join(ROOT, "data", "local")  # this machine's installed apps (gitignored)


def app_rows():
    for fn in (os.path.join(ROOT, "data", "apps.tsv"), os.path.join(LOCAL, "installed_apps.tsv"),
               os.path.join(ROOT, "data", "appimages_apps.tsv")):
        try:
            with open(fn) as f:
                hdr = f.readline().rstrip("\n").split("\t")
                for line in f:
                    yield dict(zip(hdr, line.rstrip("\n").split("\t")))
        except OSError:
            continue


SLICE = "menusurvey.slice"
SLICE_LIMITS = ["MemoryHigh=6G", "MemoryMax=8G", "CPUWeight=idle", "IOWeight=1"]


def ensure_slice():
    """The survey's slice and its limits, whoever starts a run: all of it
    (workers, rigs, probed apps, one-off runs) in 8 GB (Ben, 2026-11-26:
    11 workers once held 40 GB). Runtime properties: set on every start."""
    subprocess.run(["systemctl", "--user", "start", SLICE], capture_output=True, timeout=20)
    subprocess.run(["systemctl", "--user", "set-property", "--runtime", SLICE, *SLICE_LIMITS],
                   capture_output=True, timeout=20)


def row_line(r, limit=100_000):
    """One result row as a JSON line, never over `limit` bytes: bulky
    fields (logs, inspection dumps) are cut first."""
    line = json.dumps(r)
    if len(line) > limit:
        r = dict(r)
        for k in ("log_tail", "inspect", "error"):
            if k in r and len(json.dumps(r[k])) > limit // 10:
                r[k] = ["(cut: over the row size limit)"] if k == "log_tail" else "(cut: over the row size limit)"
        line = json.dumps(r)
        if len(line) > limit:
            line = json.dumps({k: r[k] for k in ("attr", "variant", "result") if k in r} | {"note": "row cut: over the size limit"})
    return line + "\n"


def result_attrs(fn, limit=1 << 20):
    """The attrs measured in a results file, read a line at a time; a line
    over `limit` bytes is skipped, never loaded whole."""
    attrs = set()
    try:
        with open(fn, "rb") as f:
            while True:
                l = f.readline(limit)
                if not l:
                    break
                if not l.endswith(b"\n"):
                    while l and not l.endswith(b"\n"):  # the rest of an over-long line
                        l = f.readline(limit)
                    continue
                try:
                    attrs.add(json.loads(l)["attr"])
                except (ValueError, KeyError):
                    pass
    except OSError:
        pass
    return attrs


def canary_opens():
    """Whether a plain X11 app (xterm, from the system) opens a window in
    the rig right now: the harness's own health check."""
    xterm = shutil.which("xterm") or "/run/current-system/sw/bin/xterm"
    if not os.path.exists(xterm):
        return False
    try:
        r = attempt("canary:xterm", [xterm], "canary", {}, [], wait_win=20, wait_menu=1)
        cleanup()
        return r.get("result") != "no-window"
    except Exception:
        return False


def own_rss_mb():
    try:
        for l in open("/proc/self/status"):
            if l.startswith("VmRSS:"):
                return int(l.split()[1]) // 1024
    except OSError:
        pass
    return 0


def main():
    ensure_slice()
    # Every run, the workers and one-off test runs alike, in its own scope
    # at idle CPU/IO weight off the desktop's reserved cores: the rig it
    # starts (arbor, hearth, the bus) inherits it.
    # (A worker already runs in its limited service: moving it out would
    # leave it running when the service stops.)
    in_worker = "hearth-menu-probe-" in open("/proc/self/cgroup").read()
    if os.environ.get("MENU_PROBE_LIMITED") != "1" and not in_worker:
        os.environ["MENU_PROBE_LIMITED"] = "1"
        os.execvp("systemd-run", ["systemd-run", "--user", "--scope", "--quiet", "--collect",
                                  "-p", f"Slice={SLICE}", "-p", "MemoryMax=4G", "-p", "CPUWeight=idle", "-p", "IOWeight=1", "-p", "AllowedCPUs=0-7,12-19",
                                  sys.executable, "-I", os.path.abspath(__file__), *sys.argv[1:]])
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
    for fn in glob.glob(os.path.join(ROOT, "data", "probe*.jsonl")) + glob.glob(os.path.join(LOCAL, "probe*.jsonl")):
        done |= result_attrs(fn)
    if a.attrs:
        todo = a.attrs.split(",")
    else:
        todo = []
        for r in app_rows():
                APPS[r["attr"]] = r
                # Prebuilt only: nixpkgs from the binary cache, Flathub. Unfree
                # nixpkgs packages are never in the cache: probe() measures
                # their Flathub copy (they were skipped outright before, so 123
                # unfree apps, Steam and Discord among them, went unmeasured).
                want = ("flathub",) if a.flathub else tuple(a.sources.split(","))
                if r["include"] != "1" or r["source"] not in want or int(r["rank"]) < a.start:
                    continue
                todo.append(r["attr"])
        todo = [t for t in todo if t not in done][:a.count][a.offset::a.stride]
    if a.attrs:
        for r in app_rows():
            APPS[r["attr"]] = r
    try:
        APPIMAGES.update(json.load(open(os.path.join(ROOT, "data", "appimages.json"))))
    except (OSError, ValueError):
        pass
    try:
        with open(os.path.join(LOCAL, "installed_exec.tsv")) as f:
            for line in f:
                k, _, v = line.rstrip("\n").partition("\t")
                INSTALLED[k] = json.loads(v)
    except OSError:
        pass
    print(f"{len(todo)} apps to probe", file=sys.stderr, flush=True)
    orphan_sweep()  # a previous run's apps (stopped or crashed worker)
    os.makedirs(LOCAL, exist_ok=True)
    streak = 0
    with open(OUT, "a") as pub, open(os.path.join(LOCAL, f"probe{WORKER}.jsonl"), "a") as loc:
        for attr in todo:
            # A probe that grew (a leak, a huge read) stops instead of
            # growing on: its service is restarted by restart-workers.sh
            # and skips what it measured.
            if own_rss_mb() > 1500:
                print(f"menu-probe: {own_rss_mb()} MB resident, stopping", flush=True)
                break
            f = loc if attr.startswith("installed:") else pub
            t = time.time()
            if not rig_alive():
                rig("stop")
                rig_up()
            try:
                rows = probe(attr)
            except Exception as e:
                rows = [dict(attr=attr, variant="error", result="error", error=repr(e))]
            finally:
                # Even after a timeout or error: nothing of this app may
                # outlive its folder (cleanup kills before it deletes).
                try:
                    cleanup()
                    orphan_sweep()
                except Exception as e:
                    print(f"cleanup failed: {e!r}", file=sys.stderr, flush=True)
            for r in rows:
                f.write(row_line(r))
            f.flush()
            last = rows[-1]
            # Ten apps in a row without a window: the harness is broken (an
            # app launch that always fails), not the apps. Stop, loudly.
            streak = streak + 1 if all(r.get("result") in ("no-window",) for r in rows) else 0
            if streak >= 10 and canary_opens():
                # A known-good app still opens a window: the harness works,
                # these apps just don't (a requeue of hard cases runs them
                # back to back). Carry on.
                streak = 0
            if streak >= 10:
                print("10 apps in a row opened no window: the harness looks broken; stopping. Last log: "
                      + " | ".join(rows[-1].get("log_tail") or []), file=sys.stderr, flush=True)
                sys.exit(3)
            print(f"{attr}: {last.get('result')} via {last.get('variant')} route={last.get('route','')} "
                  f"{last.get('menus', '')} ({time.time() - t:.0f}s)", file=sys.stderr, flush=True)
    if not a.keep_rig:
        rig("stop")


if __name__ == "__main__":
    main()
