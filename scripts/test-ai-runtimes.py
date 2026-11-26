#!/usr/bin/env python3
"""Checks helpers/hearth_ai_runtimes + hearth-ai's Runtime provider against
small stand-ins for each runtime's API (no runtime or model needed, nothing
touches the GPU):

    python3 scripts/test-ai-runtimes.py

Each stand-in runs as a process whose command line names its runtime (so
discovery recognises it the way it would the real one), answers that
runtime's model list / loaded / load / unload calls, and records what it
was asked. The test then finds them all, reads their state, loads and
unloads through the provider, and checks each call reached the right
endpoint. A one-model server's Stop ends its process.
"""
import json
import os
import signal
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
HELPERS = os.path.join(os.path.dirname(HERE), "helpers")
sys.path.insert(0, HELPERS)

MOCK = r'''
import json, sys
from http.server import BaseHTTPRequestHandler, HTTPServer
flavor, port, log = sys.argv[1], int(sys.argv[2]), sys.argv[3]
models = ["alpha-7b-Q4_K_M", "beta-embed"]
loaded = {"alpha-7b-Q4_K_M"}
def note(*a):
    with open(log, "a") as f:
        f.write(json.dumps(a) + "\n")
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, obj, code=200):
        b = json.dumps(obj).encode()
        self.send_response(code); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        p = self.path.split("?")[0]
        api = {"lemonade": "/api/v1", "docker": "/engines/v1"}.get(flavor, "/v1")
        if p == api + "/models":
            ms = models[:1] if flavor in ("vllm", "koboldcpp") else models
            return self.send({"object": "list", "data": [{"id": m, "object": "model"} for m in ms]})
        if flavor == "lmstudio" and p == "/api/v0/models":
            return self.send({"data": [{"id": m, "type": "embeddings" if "embed" in m else "llm",
                                        "state": "loaded" if m in loaded else "not-loaded",
                                        "quantization": "Q4_K_M", "max_context_length": 32768} for m in models]})
        if flavor == "textgen" and p == "/v1/internal/model/info":
            return self.send({"model_name": next(iter(loaded), "None")})
        if flavor == "textgen" and p == "/v1/internal/model/list":
            return self.send({"model_names": models})
        if flavor == "tabby" and p == "/v1/model":
            return self.send({"id": next(iter(loaded), "")})
        if flavor == "tabby" and p == "/v1/model/list":
            return self.send({"data": [{"id": m} for m in models]})
        if flavor == "localai" and p == "/system":
            return self.send({"loaded_models": [{"id": m} for m in loaded]})
        if flavor == "lemonade" and p == "/api/v1/health":
            return self.send({"status": "ok", "model_loaded": next(iter(loaded), None)})
        self.send({"error": "no"}, 404)
    def do_POST(self):
        n = int(self.headers.get("Content-Length") or 0)
        body = json.loads(self.rfile.read(n) or b"{}")
        note("POST", self.path, body, self.headers.get("x-admin-key", ""))
        if "unload" in self.path or "shutdown" in self.path:
            loaded.clear()
        if self.path.endswith("/load"):
            loaded.add(body.get("model_name") or body.get("model"))
        if self.path.endswith("/chat/completions"):
            loaded.add(body.get("model"))
            return self.send({"choices": [{"message": {"role": "assistant", "content": "hi"}}]})
        self.send({"ok": True})
HTTPServer(("127.0.0.1", port), H).serve_forever()
'''

# flavor, the runtime it stands in for (its name goes on the command line), port
CASES = [
    ("lmstudio", "lmstudio", 18231),
    ("textgen", "text-generation-webui", 18232),
    ("tabby", "tabbyapi", 18233),
    ("localai", "local-ai", 18234),
    ("lemonade", "lemonade", 18235),
    ("vllm", "vllm", 18236),
    ("koboldcpp", "koboldcpp", 18237),
    ("generic", "some-new-server", 18238),
]


def main():
    tmp = os.environ.get("TMPDIR", "/tmp")
    work = os.path.join(tmp, "hearth-rt-test-%d" % os.getpid())
    os.makedirs(work)
    mock = os.path.join(work, "mock.py")
    open(mock, "w").write(MOCK)
    # A tabby api_tokens.yml in the stand-in's working directory.
    tabby_cwd = os.path.join(work, "tabbyAPI")
    os.makedirs(tabby_cwd)
    open(os.path.join(tabby_cwd, "api_tokens.yml"), "w").write("admin_key: secret-admin\n")
    procs, logs = {}, {}
    for flavor, name, port in CASES:
        logs[flavor] = os.path.join(work, flavor + ".log")
        # The runtime's name in argv[0] and the script path, as a real one's would be.
        script = os.path.join(work, name + "-server.py")
        os.symlink(mock, script)
        procs[flavor] = subprocess.Popen([sys.executable, script, flavor, str(port), logs[flavor]],
                                         cwd=tabby_cwd if flavor == "tabby" else work)
    time.sleep(1.0)
    fails = []

    def check(cond, what):
        print(("ok   " if cond else "FAIL ") + what)
        if not cond:
            fails.append(what)

    try:
        import hearth_ai_runtimes as rt
        import importlib.machinery
        import importlib.util
        loader = importlib.machinery.SourceFileLoader("hearth_ai", os.path.join(HELPERS, "hearth-ai"))
        spec = importlib.util.spec_from_loader("hearth_ai", loader)
        ha = importlib.util.module_from_spec(spec)
        loader.exec_module(ha)

        ports = {port: (flavor, name) for flavor, name, port in CASES}
        found = [f for f in rt.discover() if f["port"] in ports]
        got = {f["port"]: f["runtime"] for f in found}
        want = {"lmstudio": "lmstudio", "textgen": "textgen", "tabby": "tabbyapi", "localai": "localai",
                "lemonade": "lemonade", "vllm": "vllm", "koboldcpp": "koboldcpp", "generic": "openai"}
        for flavor, name, port in CASES:
            check(got.get(port) == want[flavor], "%s found as %s (got %s)" % (name, want[flavor], got.get(port)))

        provs = {f["port"]: ha.Runtime(f) for f in found}
        for flavor, name, port in CASES:
            p = provs.get(port)
            if not p:
                continue
            st = p.state()
            inst = [m["name"] for m in st["installed"]]
            ld = [m["name"] for m in st["loaded"]]
            single = flavor in ("vllm", "koboldcpp")
            check(st["running"] and inst == (["alpha-7b-Q4_K_M"] if single else ["alpha-7b-Q4_K_M", "beta-embed"]),
                  "%s lists its models (%s)" % (name, inst))
            check(ld == ["alpha-7b-Q4_K_M"] or (flavor in ("generic",) and ld == []),
                  "%s shows what's loaded (%s)" % (name, ld))
            if single or flavor == "generic":
                check(st["external"], "%s (started by hand, no unload call) is external: never unloaded automatically" % name)
            if single:
                continue
            if flavor != "generic":
                p.unload("alpha-7b-Q4_K_M")
            p.load("beta-embed", 5)
            calls = [json.loads(line) for line in open(logs[flavor])] if os.path.exists(logs[flavor]) else []
            paths = [c[1] for c in calls]
            exp = {"lmstudio": ["/api/v1/models/unload", "/v1/chat/completions"],
                   "textgen": ["/v1/internal/model/unload", "/v1/internal/model/load"],
                   "tabby": ["/v1/model/unload", "/v1/model/load"],
                   "localai": ["/backend/shutdown", "/v1/chat/completions"],
                   "lemonade": ["/api/v1/unload", "/api/v1/load"],
                   "generic": ["/v1/chat/completions"]}[flavor]
            if flavor == "generic":
                # Unknown server, multi-model, no unload API: Unload stops it
                # only on request; here just loading is checked.
                pass
            check(paths[-len(exp):] == exp, "%s unload/load hit %s (got %s)" % (name, exp, paths))
            if flavor == "tabby":
                check(all(c[3] == "secret-admin" for c in calls), "tabbyapi sends its admin key")
            st = p.state()
            if flavor in ("textgen", "tabby", "lemonade", "lmstudio"):
                check("beta-embed" in [m["name"] for m in st["loaded"]], "%s reports the newly loaded model" % name)

        # The assistant talks to a runtime through its own API base
        # (Lemonade's is /api/v1).
        for port in (18231, 18235):
            p = provs.get(port)
            if p:
                text, calls, _ = p.chat("alpha-7b-Q4_K_M", [{"role": "user", "content": "hi"}], [], 5)
                check(text == "hi", "assistant chat through %s (%s)" % (p.label, p.chat_url()))

        # A one-model server's Stop ends it.
        p = provs.get(18236)
        if p:
            p.unload("alpha-7b-Q4_K_M")
            time.sleep(0.5)
            check(procs["vllm"].poll() is not None, "vllm stand-in stopped by Unload/Stop")

        # A socket-activated port (systemd's) is never probed: covered by
        # discover() skipping comm == "systemd"; and skip_ports works.
        f2 = [f for f in rt.discover(skip_ports={18231}) if f["port"] == 18231]
        check(f2 == [], "skip_ports leaves a covered port alone")
    finally:
        for pr in procs.values():
            if pr.poll() is None:
                pr.send_signal(signal.SIGTERM)
        for pr in procs.values():
            try:
                pr.wait(3)
            except subprocess.TimeoutExpired:
                pr.kill()
        subprocess.run(["rm", "-rf", work])
    print("\n%d failed" % len(fails) if fails else "\nall passed")
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main())
