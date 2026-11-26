"""The local AI runtimes hearth knows how to talk to, and finding them.

helpers/hearth-ai lists Ollama, llama.cpp and Magnitude itself. Everything
else that serves models on this computer is found here, by what listens on
a local port:

- a known runtime (RUNTIMES below: LM Studio, vLLM, SGLang, KoboldCpp,
  text-generation-webui, TabbyAPI, LocalAI, llamafile, Lemonade, Jan,
  GPT4All, Docker Model Runner, ComfyUI), recognised by its process (and,
  for one in a container or run as another user, by its usual port and
  how its API answers), gets its own model list, load and unload;
- any other server answering the OpenAI-style GET /v1/models is listed as
  well ("OpenAI-compatible server"), so a runtime that doesn't exist yet
  still shows up.

Never probed: ports systemd holds for on-demand units (probing
inkling-2-mini-proxy.socket would start a 20 GB model), and ports the
caller already covers (Ollama, hearth's llama.cpp, Magnitude, model units).

Each runtime is data, not code: a new one is an entry in RUNTIMES (how to
recognise it, where its API is, how it loads and unloads, where its models
live).
"""
import glob
import json
import os
import re
import socket
import subprocess
import time
import urllib.request

HOME = os.path.expanduser("~")
UA = {"User-Agent": "hearth-ai", "Accept": "application/json"}

# id, label, process pattern (argv / exe / cwd, lower case), usual ports,
# api: OpenAI base path, multi: serves several models (load/unload per
# model) or one, flavor: its own load/unload/list API (see Runtime below),
# app: a desktop app that manages its models itself (hearth doesn't stop
# or unload them), dirs: where its models live, fingerprint: a GET that
# only this runtime answers (for one found by port alone).
RUNTIMES = [
    {"id": "lmstudio", "label": "LM Studio", "pattern": r"lm[ -]?studio|/\.lmstudio/|\bllmster\b|(^|/)lms(\s|$)",
     "ports": [1234], "api": "/v1", "multi": True, "flavor": "lmstudio",
     "dirs": ["~/.lmstudio/models", "~/.cache/lm-studio/models"], "fingerprint": "/api/v0/models"},
    {"id": "vllm", "label": "vLLM", "pattern": r"\bvllm\b", "ports": [8000], "api": "/v1", "multi": False,
     "fingerprint": "/version"},
    {"id": "sglang", "label": "SGLang", "pattern": r"\bsglang\b", "ports": [30000], "api": "/v1", "multi": False,
     "fingerprint": "/get_model_info"},
    {"id": "koboldcpp", "label": "KoboldCpp", "pattern": r"koboldcpp", "ports": [5001], "api": "/v1",
     "multi": False, "fingerprint": "/api/extra/version"},
    {"id": "textgen", "label": "text-generation-webui", "pattern": r"text-generation-webui|oobabooga|textgen",
     "ports": [5000], "api": "/v1", "multi": True, "flavor": "textgen",
     "dirs": ["~/text-generation-webui/user_data/models", "~/text-generation-webui/models",
              "~/src/text-generation-webui/user_data/models", "~/src/text-generation-webui/models"],
     "cwdDirs": ["user_data/models", "models"], "fingerprint": "/v1/internal/model/info"},
    {"id": "tabbyapi", "label": "TabbyAPI", "pattern": r"tabbyapi", "ports": [5000], "api": "/v1", "multi": True,
     "flavor": "tabby", "dirs": ["~/tabbyAPI/models", "~/src/tabbyAPI/models"], "cwdDirs": ["models"],
     "fingerprint": "/v1/model/list"},
    {"id": "localai", "label": "LocalAI", "pattern": r"local-ai|localai", "ports": [8080], "api": "/v1",
     "multi": True, "flavor": "localai", "cwdDirs": ["models"], "argDirs": ["--models-path"],
     "envDirs": ["LOCALAI_MODELS_PATH", "MODELS_PATH"], "fingerprint": "/system"},
    {"id": "llamafile", "label": "llamafile", "pattern": r"llamafile", "ports": [8080], "api": "/v1",
     "multi": False},
    {"id": "lemonade", "label": "Lemonade", "pattern": r"lemonade", "ports": [8000], "api": "/api/v1",
     "multi": True, "flavor": "lemonade", "fingerprint": "/api/v1/health"},
    {"id": "jan", "label": "Jan", "pattern": r"(^|/)jan(\s|$)|/jan/|\.jan\b", "ports": [1337], "api": "/v1",
     "multi": True, "app": True,
     "dirs": ["~/.local/share/Jan/data/llamacpp/models", "~/.local/share/Jan/data/models", "~/jan/models"]},
    {"id": "gpt4all", "label": "GPT4All", "pattern": r"gpt4all|nomic\.ai", "ports": [4891], "api": "/v1",
     "multi": True, "app": True, "dirs": ["~/.local/share/nomic.ai/GPT4All"]},
    {"id": "docker", "label": "Docker Model Runner", "pattern": r"model-runner|docker-model",
     "ports": [12434], "api": "/engines/v1", "multi": True, "flavor": "docker",
     "fingerprint": "/engines/v1/models"},
    {"id": "comfyui", "label": "ComfyUI", "pattern": r"comfyui|comfy", "ports": [8188], "api": "",
     "multi": False, "flavor": "comfyui", "fingerprint": "/system_stats"},
]
BY_ID = {r["id"]: r for r in RUNTIMES}
GENERIC = {"id": "openai", "label": "OpenAI-compatible server", "pattern": "", "ports": [], "api": "/v1",
           "multi": True}


def _read(path):
    try:
        with open(path, errors="replace") as f:
            return f.read()
    except OSError:
        return ""


def get(url, timeout=0.6, headers=None):
    req = urllib.request.Request(url, headers=dict(UA, **(headers or {})))
    with urllib.request.urlopen(req, timeout=timeout) as r:
        body = r.read()
    try:
        return json.loads(body.decode() or "null")
    except ValueError:
        return None


def post(url, body=None, timeout=60, headers=None):
    data = json.dumps(body if body is not None else {}).encode()
    req = urllib.request.Request(url, data=data, method="POST",
                                 headers=dict(UA, **{"Content-Type": "application/json"}, **(headers or {})))
    with urllib.request.urlopen(req, timeout=timeout) as r:
        body = r.read()
    try:
        return json.loads(body.decode() or "null")
    except ValueError:
        return None


# --- listening sockets ---------------------------------------------------------------

def _listening():
    """{port: inode} for TCP sockets listening on loopback or every address."""
    out = {}
    for f, v6 in (("/proc/net/tcp", False), ("/proc/net/tcp6", True)):
        for line in _read(f).splitlines()[1:]:
            p = line.split()
            if len(p) < 10 or p[3] != "0A":
                continue
            addr, port = p[1].split(":")
            port = int(port, 16)
            if v6:
                ok = addr in ("0" * 32, "0" * 31 + "1", "0000000000000000FFFF00000100007F",
                              "0000000000000000FFFF000000000000")
            else:
                ok = addr in ("00000000", "0100007F")
            if ok:
                out.setdefault(port, p[9])
    return out


def _inode_pids():
    """socket inode -> pid, for this user's processes (others' fds aren't readable)."""
    out = {}
    for fd in glob.glob("/proc/[0-9]*/fd/*"):
        try:
            t = os.readlink(fd)
        except OSError:
            continue
        if t.startswith("socket:["):
            out.setdefault(t[8:-1], int(fd.split("/")[2]))
    return out


def _proc(pid):
    """{argv, exe, cwd, comm, ppid, start} of a process ({} when gone)."""
    if not pid:
        return {}
    argv = [a for a in _read("/proc/%d/cmdline" % pid).split("\0") if a]
    if not argv and not os.path.exists("/proc/%d" % pid):
        return {}
    try:
        exe = os.readlink("/proc/%d/exe" % pid)
    except OSError:
        exe = ""
    try:
        cwd = os.readlink("/proc/%d/cwd" % pid)
    except OSError:
        cwd = ""
    stat = _read("/proc/%d/stat" % pid)
    rest = stat[stat.rfind(")") + 2:].split() if ")" in stat else []
    return {"pid": pid, "argv": argv, "exe": exe, "cwd": cwd, "comm": _read("/proc/%d/comm" % pid).strip(),
            "ppid": int(rest[1]) if len(rest) > 1 else 0, "start": rest[19] if len(rest) > 19 else ""}


def _identify(info):
    """The runtime a process belongs to, from it or its two nearest parents
    (LM Studio's server is a child of the app; Jan's too)."""
    p, hops = info, 0
    while p and hops < 3:
        text = " ".join(p.get("argv", [])[:6] + [p.get("exe", ""), p.get("cwd", ""), p.get("comm", "")]).lower()
        for r in RUNTIMES:
            if re.search(r["pattern"], text):
                return r
        p = _proc(p.get("ppid", 0)) if p.get("ppid", 0) > 1 else {}
        hops += 1
    return None


def children(pid):
    """pid and its descendants (a runtime's model workers: LocalAI backends,
    vLLM's engine core, LM Studio's model processes)."""
    kids = {}
    for st in glob.glob("/proc/[0-9]*/stat"):
        s = _read(st)
        if ")" not in s:
            continue
        rest = s[s.rfind(")") + 2:].split()
        if len(rest) > 1:
            kids.setdefault(int(rest[1]), []).append(int(st.split("/")[2]))
    out, todo = [], [pid]
    while todo and len(out) < 256:
        p = todo.pop()
        out.append(p)
        todo += kids.get(p, [])
    return out


# --- discovery -------------------------------------------------------------------------

_probe = {}        # (port, pid, start) -> (when, result or None)
_owners = [None, {}]   # [listening inodes, inode -> pid]


def _models(base, timeout=0.6):
    r = get(base + "/models", timeout=timeout)
    if isinstance(r, dict) and isinstance(r.get("data"), list):
        return r["data"]
    if isinstance(r, dict) and isinstance(r.get("models"), list):   # Lemonade's older shape
        return r["models"]
    return None


def discover(skip_ports=(), skip_pid=lambda pid: False):
    """[{runtime, port, pid, proc}] for model servers listening here.

    skip_ports: ports the caller covers itself. skip_pid(pid): processes it
    covers (llama-server instances, model units)."""
    listening = _listening()
    if not listening:
        return []
    # Every process's fds are read only when the listening sockets change.
    inodes = frozenset(listening.values())
    if _owners[0] != inodes:
        _owners[:] = [inodes, _inode_pids()]
    owners = _owners[1]
    found = []
    now = time.time()
    for port, inode in sorted(listening.items()):
        if port in skip_ports:
            continue
        pid = owners.get(inode, 0)
        info = _proc(pid) if pid else {}
        if info and info.get("comm") == "systemd":
            continue  # a socket-activated unit: connecting would start it
        if pid and skip_pid(pid):
            continue
        rt = _identify(info) if info else None
        if not pid:
            # Another user's or a container's port: only a runtime's usual
            # one, told apart by how its API answers.
            rts = [r for r in RUNTIMES if port in r["ports"]]
            if not rts:
                continue
        elif not rt:
            rts = [GENERIC]
        else:
            rts = [rt]
        key = (port, pid, info.get("start", ""))
        hit = _probe.get(key)
        ttl = 600 if (hit and hit[1] is None and rts == [GENERIC]) else 120 if (hit and hit[1] is None) else 0
        if hit and (hit[1] is not None or now - hit[0] < ttl):
            if hit[1] is not None:
                found.append(dict(hit[1], proc=info))
            continue
        result = None
        base = "http://127.0.0.1:%d" % port
        for r in rts:
            if not pid and len(rts) > 1 and r.get("fingerprint"):
                try:
                    if get(base + r["fingerprint"], timeout=0.5) is None:
                        continue
                except Exception:  # noqa: BLE001 (not HTTP, not JSON, refused: not a model server)
                    continue
            try:
                if r.get("flavor") == "comfyui":
                    ok = get(base + "/system_stats", timeout=0.6) is not None
                else:
                    ok = _models(base + r["api"]) is not None
            except Exception:  # noqa: BLE001 (not HTTP, not JSON, refused: not a model server)
                ok = False
            if ok:
                result = {"runtime": r["id"], "port": port, "pid": pid}
                break
        _probe[key] = (now, result)
        if result:
            found.append(dict(result, proc=info))
    for k in [k for k, v in _probe.items() if now - v[0] > 3600]:
        del _probe[k]
    return found


# --- model folders -----------------------------------------------------------------------

def model_dirs(found=()):
    """[(dir, label)] where each runtime keeps its models: its usual folders,
    and for a running one its working directory's models folder, a
    --models-path argument, or a MODELS_PATH-style variable."""
    out = []
    for r in RUNTIMES:
        for d in r.get("dirs", []):
            d = os.path.expanduser(d)
            if os.path.isdir(d):
                out.append((d, r["label"]))
    for f in found:
        r = BY_ID.get(f["runtime"])
        info = f.get("proc") or {}
        if not r or not info:
            continue
        for sub in r.get("cwdDirs", []):
            d = os.path.join(info.get("cwd", ""), sub)
            if info.get("cwd") and os.path.isdir(d):
                out.append((d, r["label"]))
        argv = info.get("argv", [])
        for a in r.get("argDirs", []):
            for i, x in enumerate(argv):
                v = argv[i + 1] if x == a and i + 1 < len(argv) else x[len(a) + 1:] if x.startswith(a + "=") else ""
                if v and os.path.isdir(v):
                    out.append((v, r["label"]))
        env = _read("/proc/%d/environ" % f["pid"]).split("\0") if f.get("pid") else []
        for e in env:
            k, _, v = e.partition("=")
            if k in r.get("envDirs", []) and os.path.isdir(v):
                out.append((v, r["label"]))
    seen, uniq = set(), []
    for d, label in out:
        d = os.path.realpath(d)
        if d not in seen:
            seen.add(d)
            uniq.append((d, label))
    return uniq


def lms_bin():
    for b in (os.path.join(HOME, ".lmstudio", "bin", "lms"), os.path.join(HOME, ".cache", "lm-studio", "bin", "lms")):
        if os.access(b, os.X_OK):
            return b
    from shutil import which
    return which("lms") or ""


def tabby_admin_key(cwd):
    """TabbyAPI's admin key (its api_tokens.yml), for load and unload."""
    m = re.search(r"^admin_key:\s*['\"]?([^'\"\s]+)", _read(os.path.join(cwd or "", "api_tokens.yml")), re.M)
    return m.group(1) if m else ""


def run(argv, timeout=600):
    r = subprocess.run(argv, capture_output=True, text=True, timeout=timeout, stdin=subprocess.DEVNULL)
    if r.returncode != 0:
        raise RuntimeError(((r.stderr or r.stdout or "failed").strip().splitlines() or ["failed"])[-1])
    return r.stdout


def port_open(port):
    s = socket.socket()
    s.settimeout(0.3)
    try:
        return s.connect_ex(("127.0.0.1", port)) == 0
    finally:
        s.close()
