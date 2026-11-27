#!/usr/bin/env python3
"""Checks the assistant's Turbine tools (helpers/hearth-ai, TurbineTools)
end to end without a model or a window:

    python3 scripts/test-ai-turbine.py      # turbine on PATH, or TURBINE_BIN=...

Turbine runs in a pseudo-terminal of its own with --automation on a socket
in a private runtime folder; a stand-in llama-server plays the model and
answers with a fixed list of tool calls ("open main.rs in Turbine and fix the
warning"); hearth-ai is driven on stdin with its own config, runtime folder
and the memory manager in dry-run. Checked: the turbine_* tools are offered
(and only while a Turbine runs and ai.turbine isn't "off"), the system prompt
mentions them, "ask" shows one approval card (kind "turbine") before the
first edit and none for looking, the edit lands in the file, and a denied
card stops the edits.
"""
import json
import os
import pty
import select
import shutil
import signal
import socket
import subprocess
import sys
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
HUB = os.path.join(os.path.dirname(HERE), "helpers", "hearth-ai")
TURBINE = os.environ.get("TURBINE_BIN") or shutil.which("turbine")
if not TURBINE:
    sys.exit("turbine isn't on PATH (TURBINE_BIN=path/to/turbine)")

fails = []


def check(ok, what):
    print(("ok   " if ok else "FAIL ") + what)
    if not ok:
        fails.append(what)


tmp = tempfile.mkdtemp(prefix="hearth-ai-turbine-")
run_dir = os.path.join(tmp, "run")
cfg_dir = os.path.join(tmp, "config", "hearth")
bin_dir = os.path.join(tmp, "bin")
for d in (run_dir, cfg_dir, bin_dir):
    os.makedirs(d, mode=0o700)
os.symlink(os.path.realpath(TURBINE), os.path.join(bin_dir, "turbine"))
src = os.path.join(tmp, "main.rs")
with open(src, "w") as f:
    f.write("fn main() {\n    let x = 5;\n    println!(\"hi\");\n}\n")

# --- the model: a fixed script of tool calls ------------------------------------

SCRIPT = [
    ("turbine_look", {}),
    ("turbine_open", {"path": src}),
    ("turbine_key", {"key": "Ctrl+Home"}),
    ("turbine_key", {"key": "Down"}),
    ("turbine_key", {"key": "End"}),
    ("turbine_key", {"key": "Home"}),
    ("turbine_key", {"key": "Ctrl+Right"}),
    ("turbine_type", {"text": "_"}),
    ("turbine_key", {"key": "Ctrl+S"}),
    ("turbine_read", {}),
]
requests = []


class Model(BaseHTTPRequestHandler):
    def log_message(self, *a):
        pass

    def send(self, obj):
        b = json.dumps(obj).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b)))
        self.end_headers()
        self.wfile.write(b)

    def do_GET(self):
        if self.path.startswith("/models"):
            self.send({"data": [{"id": "fake", "status": {"value": "loaded"}}]})
        else:
            self.send({})

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length") or 0)) or b"{}")
        if not self.path.endswith("/chat/completions"):
            return self.send({"error": "no"})
        if body.get("max_tokens") == 1:       # warm-up / prime
            return self.send({"choices": [{"message": {"content": ""}}]})
        requests.append(body)
        msgs = body["messages"]
        results = [m for m in msgs if m.get("role") == "tool"]
        n = len(results)
        stop = results and "didn't allow" in results[-1]["content"]
        if n >= len(SCRIPT) or stop:
            msg = {"content": "Finished. Last: " + (results[-1]["content"] if results else "")}
        else:
            name, args = SCRIPT[n]
            msg = {"content": "", "tool_calls": [{"id": "c%d" % n, "type": "function",
                                                  "function": {"name": name, "arguments": json.dumps(args)}}]}
        self.send({"choices": [{"message": msg}]})


srv = HTTPServer(("127.0.0.1", 0), Model)
threading.Thread(target=srv.serve_forever, daemon=True).start()
model_url = "http://127.0.0.1:%d" % srv.server_port


def write_settings(turbine):
    with open(os.path.join(cfg_dir, "settings.json"), "w") as f:
        json.dump({"ai": {
            "turbine": turbine, "computerUse": "off", "runCommands": "off",
            "fastAssistant": {"enabled": False}, "autoUnload": False, "evictOnPressure": False,
            "assistant": {"provider": "llamacpp", "model": "fake"},
            "api": {"enabled": False},
            "providers": {"ollama": {"enabled": False}, "magnitude": {"enabled": False},
                          "services": {"enabled": False},
                          "llamacpp": {"enabled": True, "url": model_url, "modelsDir": os.path.join(tmp, "models")}},
        }}, f)


# --- Turbine in a pty --------------------------------------------------------------

sock = os.path.join(run_dir, "turbine-test.sock")
tpid, tfd = pty.fork()
if tpid == 0:
    os.environ["TERM"] = "xterm-256color"
    os.environ["XDG_RUNTIME_DIR"] = run_dir
    os.chdir(tmp)
    os.execv(TURBINE, [TURBINE, "--automation", sock, "--speed", "0"])
import fcntl  # noqa: E402
import struct  # noqa: E402
import termios  # noqa: E402
fcntl.ioctl(tfd, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 100, 0, 0))
os.kill(tpid, signal.SIGWINCH)


def drain():
    while True:
        try:
            r, _, _ = select.select([tfd], [], [], 0.5)
            if r and not os.read(tfd, 65536):
                return
        except OSError:
            return


threading.Thread(target=drain, daemon=True).start()
for _ in range(100):
    if os.path.exists(sock):
        break
    time.sleep(0.1)
check(os.path.exists(sock), "Turbine opened its automation socket in a pty")

# --- hearth-ai on stdin ------------------------------------------------------------

env = dict(os.environ, XDG_CONFIG_HOME=os.path.dirname(cfg_dir), XDG_RUNTIME_DIR=run_dir,
           PATH=bin_dir + os.pathsep + os.environ.get("PATH", ""), HEARTH_AI_MANAGE_DRYRUN="1",
           HEARTH_AI_API="0", HEARTH_AI_DRYRUN="1")
env.pop("TURBINE_SOCKET", None)
hub = subprocess.Popen([sys.executable, HUB], stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                       stderr=open(os.path.join(tmp, "hub.log"), "w"), text=True, bufsize=1, env=env,
                       start_new_session=True)
events = []
cond = threading.Condition()


def reader():
    for line in hub.stdout:
        try:
            m = json.loads(line)
        except ValueError:
            continue
        if m.get("type") in ("approve", "reply", "step"):
            with cond:
                events.append(m)
                cond.notify_all()
            if m["type"] == "approve":
                answer = ANSWERS.get(m["id"], "allow")
                hub.stdin.write(json.dumps({"cmd": "toolResult", "id": m["id"], "call": m["call"],
                                            "result": answer}) + "\n")
                hub.stdin.flush()


ANSWERS = {}
threading.Thread(target=reader, daemon=True).start()


def ask(rid, text, answer="allow", timeout=120):
    ANSWERS[rid] = answer
    hub.stdin.write(json.dumps({"cmd": "ask", "id": rid, "feature": "assistant", "text": text}) + "\n")
    hub.stdin.flush()
    end = time.time() + timeout
    with cond:
        while time.time() < end:
            r = [e for e in events if e["id"] == rid and e["type"] == "reply"]
            if r:
                return r[0], [e for e in events if e["id"] == rid]
            cond.wait(1)
    return None, [e for e in events if e["id"] == rid]


def names(req):
    return {t["function"]["name"] for t in req.get("tools") or []}


try:
    # 1. ask: one card before the first edit, the edit lands.
    write_settings("ask")
    reply, evs = ask(1, "open main.rs in Turbine and fix the warning")
    check(reply is not None, "the request finished")
    req = requests[0] if requests else {}
    tn = {n for n in names(req) if n.startswith("turbine_")}
    check(tn == {"turbine_" + n for n in ("look", "menu", "click", "type", "key", "read", "wait", "open")},
          "all eight Turbine tools offered, namespaced: %s" % sorted(tn))
    check(not names(req) & {"look", "open", "click", "type"}, "no unprefixed Turbine names")
    check("turbine_look" in req.get("messages", [{}])[0].get("content", ""), "system prompt explains Turbine")
    cards = [e for e in evs if e["type"] == "approve"]
    check(len(cards) == 1 and cards[0]["kind"] == "turbine", "one approval card, kind turbine: %s" % cards)
    steps = [e["name"] for e in evs if e["type"] == "step"]
    check(cards and steps.index("turbine_open") == cards[0]["call"] - 1,
          "the card came at turbine_open, not at turbine_look")
    text = reply["text"] if reply else ""
    check("let _x = 5;" in text, "turbine_read shows the fix: %r" % text[-200:])
    with open(src) as f:
        check("let _x = 5;" in f.read(), "Ctrl+S saved the fix to main.rs")
    look = next((m["content"] for r in requests for m in r["messages"] if m.get("role") == "tool"), "")
    check("Widgets:" in look and "Screen:" in look, "turbine_look returns the widget tree and screen")

    # 2. deny: no edits.
    with open(src, "w") as f:
        f.write("fn main() {\n    let x = 5;\n}\n")
    n0 = len(requests)
    reply, evs = ask(2, "fix it again", answer="deny")
    tools_results = [m["content"] for m in requests[-1]["messages"] if m.get("role") == "tool"] if len(requests) > n0 else []
    check(reply is not None and any("didn't allow" in t for t in tools_results), "a denied card stops the edits")
    with open(src) as f:
        check("let x = 5;" in f.read(), "main.rs untouched after Deny")

    # 3. off: no Turbine tools.
    write_settings("off")
    n0 = len(requests)
    ask(3, "hello")
    check(len(requests) > n0 and not any(n.startswith("turbine_") for n in names(requests[n0])),
          "ai.turbine off: no Turbine tools")

    # 4. allow, then Turbine gone: no tools, no card.
    write_settings("allow")
    os.kill(tpid, signal.SIGTERM)
    os.waitpid(tpid, 0)
    n0 = len(requests)
    ask(4, "hello")
    check(len(requests) > n0 and not any(n.startswith("turbine_") for n in names(requests[n0])),
          "no Turbine running: no Turbine tools (stale socket file ignored)")
finally:
    hub.terminate()
    try:
        os.kill(tpid, signal.SIGKILL)
    except OSError:
        pass
    srv.shutdown()

print("hub log:", os.path.join(tmp, "hub.log"))
if fails:
    sys.exit("%d failed" % len(fails))
shutil.rmtree(tmp, ignore_errors=True)
print("all passed")
