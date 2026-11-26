"""Every AI model on this computer, and who holds the graphics memory.

Used by helpers/hearth-ai (the AI hub behind the menu bar's AI icon):

- inventory(): installed models from every place they live (Ollama,
  Magnitude, llama.cpp model folders, the Hugging Face cache, LM Studio,
  ComfyUI, Piper, Whisper), each sorted into a category (language, speech to
  text, text to speech, image, video, ...).
- gpu_clients(): per process graphics memory (VRAM and GTT spill), GPU time,
  the systemd user unit it runs in, and which model files it has open, so a
  Python app running Whisper shows up as "Whisper large-v3" and not "python3".
- services(): systemd user units that run one model each
  (inkling-2-mini.service and the like), found by what they run.
- Memory manager (Arbiter): remembers when each loaded model last used the
  GPU and how long it takes to load; unloads idle models (a model that takes
  long to load stays longer) and, when the card fills up, evicts the models
  that are idle longest and cheapest to load again.
- catalog(): models that can be installed: Magnitude's recommendations,
  hearth's picks per category, and a Hugging Face search by category.
"""

import glob
import json
import os
import re
import shutil
import struct
import subprocess
import time
import urllib.parse
import urllib.request

HOME = os.path.expanduser("~")
STATE_HOME = os.environ.get("XDG_STATE_HOME") or os.path.join(HOME, ".local", "state")
CACHE_HOME = os.environ.get("XDG_CACHE_HOME") or os.path.join(HOME, ".cache")
CONFIG_HOME = os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config")
STATE_FILE = os.path.join(STATE_HOME, "hearth", "ai-models.json")
CATALOG_CACHE = os.path.join(CACHE_HOME, "hearth", "ai-catalog.json")
MAGNITUDE = os.environ.get("HEARTH_MAGNITUDE_BIN") or os.path.join(HOME, ".magnitude", "bin", "magnitude")

CATEGORIES = [
    ("llm", "Language"),
    ("embedding", "Embeddings"),
    ("stt", "Speech to text"),
    ("tts", "Text to speech"),
    ("image", "Image generation"),
    ("video", "Video generation"),
    ("audio", "Audio & music"),
    ("vision", "Vision"),
    ("other", "Other"),
]
CATEGORY_LABEL = dict(CATEGORIES)


def human_bytes(n):
    n = float(n or 0)
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024 or unit == "TB":
            return ("%.0f %s" if unit in ("B", "KB") else "%.1f %s") % (n, unit)
        n /= 1024


def _read(path, default=""):
    try:
        with open(path, errors="replace") as f:
            return f.read()
    except OSError:
        return default


def _json(path, default=None):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


# --- categories --------------------------------------------------------------

PIPELINE = {
    "text-generation": "llm", "text2text-generation": "llm", "image-text-to-text": "llm",
    "conversational": "llm", "any-to-any": "llm", "visual-question-answering": "llm",
    "feature-extraction": "embedding", "sentence-similarity": "embedding", "text-ranking": "embedding",
    "automatic-speech-recognition": "stt",
    "text-to-speech": "tts",
    "text-to-audio": "audio", "audio-to-audio": "audio", "audio-classification": "audio",
    "voice-activity-detection": "audio",
    "text-to-image": "image", "image-to-image": "image", "unconditional-image-generation": "image",
    "text-to-video": "video", "image-to-video": "video", "video-to-video": "video",
    "image-segmentation": "vision", "image-classification": "vision", "object-detection": "vision",
    "zero-shot-image-classification": "vision", "depth-estimation": "vision",
    "image-feature-extraction": "vision", "mask-generation": "vision", "image-to-text": "vision",
}

# Name patterns, checked in order (most models in caches carry no pipeline tag).
NAME_RULES = [
    ("stt", r"whisper|parakeet|canary|wav2vec|\basr\b|-stt\b|moonshine|sensevoice"),
    ("tts", r"tts|kokoro|piper|chatterbox|voice|bark|xtts|\bf5\b|maya1|s2-pro|orpheus|snac|styletts|melo|dia-"),
    ("video", r"wan2|wan-ai|\bwan\b|hunyuan.?video|ltx|cogvideo|mochi|-video|video-|t2v|i2v|skyreels"),
    ("audio", r"musicgen|stable-audio|ace-step|audioldm|riffusion|ecapa|spkrec|accent-id|demucs|audiogen|yue"),
    ("image", r"sdxl|stable-diffusion|\bsd3|flux|z-image|ip-adapter|controlnet|imaje|qwen-image|hidream|"
              r"pixart|kolors|lumina|\bvae\b|-vae|lora|playground"),
    ("embedding", r"embed|\bbge\b|bge-|\be5-|gte-|nomic|minilm|siglip|\bclip\b|colbert|rerank"),
    ("vision", r"birefnet|\bsam\b|sam2|segment|depth|yolo|detr|florence|rmbg|grounding"),
]

GGUF_ARCH = {"clip": "vision", "whisper": "stt", "bert": "embedding", "nomic-bert": "embedding",
             "jina-bert-v2": "embedding", "t5encoder": "embedding", "wavtokenizer-dec": "tts",
             "outetts": "tts"}


def classify(name, tag="", arch="", default="other"):
    if tag in PIPELINE:
        return PIPELINE[tag]
    low = name.lower()
    for cat, pat in NAME_RULES:
        if re.search(pat, low):
            return cat
    if arch in GGUF_ARCH:
        return GGUF_ARCH[arch]
    if arch and re.search(r"ForCausalLM|ForConditionalGeneration|LMHead", arch):
        return "llm"
    return default


# --- GGUF metadata -------------------------------------------------------------

_GGUF_SIZES = {0: 1, 1: 1, 2: 2, 3: 2, 4: 4, 5: 4, 6: 4, 7: 1, 10: 8, 11: 8, 12: 8}


def gguf_meta(path, want=("general.architecture", "general.name", "general.size_label")):
    """The first scalar metadata keys of a GGUF (stops at the tokenizer's
    big arrays). {} if it isn't one."""
    out = {}
    try:
        with open(path, "rb") as f:
            if f.read(4) != b"GGUF":
                return out
            ver = struct.unpack("<I", f.read(4))[0]
            if ver < 2:
                return out
            _tensors, kvs = struct.unpack("<QQ", f.read(16))

            def rstr():
                n = struct.unpack("<Q", f.read(8))[0]
                if n > 1 << 16:
                    raise ValueError("long string")
                return f.read(n).decode("utf-8", "replace")

            for _ in range(min(kvs, 64)):
                key = rstr()
                t = struct.unpack("<I", f.read(4))[0]
                if t == 8:
                    val = rstr()
                elif t == 9:  # array: skip numeric ones, stop at string arrays
                    et, n = struct.unpack("<IQ", f.read(12))
                    if et not in _GGUF_SIZES:
                        break
                    f.seek(_GGUF_SIZES[et] * n, 1)
                    continue
                elif t in _GGUF_SIZES:
                    raw = f.read(_GGUF_SIZES[t])
                    fmt = {0: "<B", 1: "<b", 2: "<H", 3: "<h", 4: "<I", 5: "<i", 6: "<f", 7: "<?",
                           10: "<Q", 11: "<q", 12: "<d"}[t]
                    val = struct.unpack(fmt, raw)[0]
                else:
                    break
                if key in want or key.endswith(".context_length"):
                    out[key] = val
                if key.startswith("tokenizer."):
                    break
    except (OSError, ValueError, struct.error):
        pass
    return out


_SKIP_GGUF = re.compile(r"mmproj|dspark|dflash|draft|-mtp\b|imatrix|\.vocab", re.I)
_PART = re.compile(r"-(\d{5})-of-(\d{5})$")


def _rotational(path):
    """True when the path lives on a spinning disk (loads are slow)."""
    try:
        st = os.stat(path)
        major, minor = os.major(st.st_dev), os.minor(st.st_dev)
        dev = os.path.realpath("/sys/dev/block/%d:%d" % (major, minor))
        for d in (dev, os.path.dirname(dev)):
            r = _read(os.path.join(d, "queue", "rotational")).strip()
            if r:
                return r == "1"
    except OSError:
        pass
    return False


def load_speed(path):
    """Bytes per second a cold load reads at, for load-time estimates."""
    return 160e6 if path and _rotational(path) else 1.6e9


_gguf_cache = {}


def scan_gguf(dirs, source):
    out = []
    for d in dirs:
        d = os.path.expanduser(d)
        if not os.path.isdir(d):
            continue
        groups = {}
        for f in glob.glob(os.path.join(d, "**", "*.gguf"), recursive=True):
            base = os.path.basename(f)
            stem = os.path.splitext(base)[0]
            if _SKIP_GGUF.search(stem):
                continue
            m = _PART.search(stem)
            key = (os.path.dirname(f), _PART.sub("", stem))
            g = groups.setdefault(key, {"files": [], "size": 0})
            try:
                g["size"] += os.path.getsize(f)
            except OSError:
                pass
            if not m or m.group(1) == "00001":
                g["first"] = f
            g["files"].append(f)
        for (folder, stem), g in groups.items():
            first = g.get("first") or g["files"][0]
            try:
                mt = os.path.getmtime(first)
            except OSError:
                mt = 0
            meta = _gguf_cache.get((first, mt))
            if meta is None:
                meta = _gguf_cache[(first, mt)] = gguf_meta(first)
            arch = meta.get("general.architecture", "")
            ctx = next((v for k, v in meta.items() if k.endswith(".context_length")), 0)
            quant = ""
            qm = re.search(r"(UD-)?(IQ\d_\w+|Q\d_\w+|Q\d+|F16|BF16|F32|NVFP4|MXFP4|FP8|PQ\d_\d|PTQ\d_\d)$", stem, re.I)
            if qm:
                quant = qm.group(0)
            out.append({
                "key": "file:" + first, "name": stem, "family": os.path.basename(folder),
                "category": classify(stem + " " + os.path.basename(folder), arch=arch, default="llm"),
                "source": source, "path": first, "folder": folder, "size": g["size"],
                "sizeText": human_bytes(g["size"]), "arch": arch, "context": ctx, "quant": quant,
                "params": meta.get("general.size_label", ""), "deletable": True,
                "deletePaths": sorted(g["files"]), "runners": [],
            })
    return out


# --- Hugging Face cache ---------------------------------------------------------

def hf_cache_dir():
    if os.environ.get("HF_HUB_CACHE"):
        return os.environ["HF_HUB_CACHE"]
    return os.path.join(os.environ.get("HF_HOME") or os.path.join(CACHE_HOME, "huggingface"), "hub")


_hf_cache = {}


def _front_matter(text):
    out = {}
    if not text.startswith("---"):
        return out
    for line in text.split("\n---", 1)[0].splitlines()[1:]:
        m = re.match(r"^(pipeline_tag|library_name):\s*(\S+)", line)
        if m:
            out[m.group(1)] = m.group(2).strip("'\"")
    return out


def scan_hf():
    hub = hf_cache_dir()
    out = []
    for d in sorted(glob.glob(os.path.join(hub, "models--*"))):
        repo = os.path.basename(d)[len("models--"):].replace("--", "/", 1)
        blobs = os.path.join(d, "blobs")
        try:
            mt = os.path.getmtime(blobs)
        except OSError:
            continue
        cached = _hf_cache.get(d)
        if cached and cached[0] == mt:
            out.append(cached[1])
            continue
        size = 0
        incomplete = False
        for e in os.scandir(blobs):
            if e.name.endswith(".incomplete"):
                incomplete = True
                continue
            try:
                size += e.stat().st_size
            except OSError:
                pass
        snaps = sorted(glob.glob(os.path.join(d, "snapshots", "*")), key=lambda p: -os.path.getmtime(p))
        snap = snaps[0] if snaps else ""
        fm = _front_matter(_read(os.path.join(snap, "README.md"))) if snap else {}
        arch = ""
        cfg = _json(os.path.join(snap, "config.json"), {}) if snap else {}
        if isinstance(cfg, dict):
            arch = ((cfg.get("architectures") or [""])[0]) or cfg.get("model_type", "") or ""
        idx = _json(os.path.join(snap, "model_index.json"), {}) if snap else {}
        tag = fm.get("pipeline_tag", "")
        if not tag and isinstance(idx, dict) and idx.get("_class_name"):
            tag = "text-to-video" if re.search(r"Video|Wan|LTX|Mochi", idx["_class_name"]) else "text-to-image"
        item = {
            "key": "hf:" + repo, "name": repo.split("/", 1)[-1], "family": repo.split("/", 1)[0],
            "repo": repo, "category": classify(repo, tag=tag, arch=arch, default="other"),
            "source": "Hugging Face cache", "path": d, "size": size, "sizeText": human_bytes(size),
            "arch": arch, "tag": tag, "library": fm.get("library_name", ""), "incomplete": incomplete,
            "deletable": True, "deletePaths": [d], "runners": [],
        }
        if size < 1 << 20 and not incomplete:
            continue  # only a README or config was fetched
        _hf_cache[d] = (mt, item)
        out.append(item)
    return out


# --- model folders in Hugging Face layout ------------------------------------------

def scan_weight_dirs(dirs, source):
    """Model folders as text-generation-webui, TabbyAPI, vLLM and LocalAI keep
    them: a directory with config.json and its weights (*.safetensors,
    *.bin, EXL2 shards), one model each, one level down from each dir."""
    out = []
    for root in dirs:
        for d in sorted(glob.glob(os.path.join(root, "*", "config.json")) +
                        glob.glob(os.path.join(root, "*", "*", "config.json"))):
            d = os.path.dirname(d)
            files = [f for f in glob.glob(os.path.join(d, "*"))
                     if re.search(r"\.(safetensors|bin|pt|pth)$", f) and os.path.isfile(f)]
            if not files:
                continue
            size = sum(os.path.getsize(f) for f in files)
            cfg = _json(os.path.join(d, "config.json"), {})
            arch = ""
            if isinstance(cfg, dict):
                arch = ((cfg.get("architectures") or [""])[0]) or cfg.get("model_type", "") or ""
            name = os.path.basename(d)
            out.append({"key": "file:" + d, "name": name, "family": "", "category": classify(name, arch=arch, default="llm"),
                        "source": source, "path": d, "size": size, "sizeText": human_bytes(size), "arch": arch,
                        "deletable": True, "deletePaths": [d], "runners": []})
    return out


# --- other model folders -----------------------------------------------------------

def comfy_roots():
    roots = [os.environ.get("COMFYUI_PATH", "")] + [os.path.join(HOME, p) for p in
                                                   ("ComfyUI", "src/ComfyUI", ".local/share/ComfyUI", "comfy/ComfyUI")]
    return [r for r in roots if r and os.path.isdir(os.path.join(r, "models"))]


def scan_misc():
    out = []

    def add(path, cat, source, name=None):
        try:
            size = os.path.getsize(path)
        except OSError:
            return
        out.append({"key": "file:" + path, "name": name or os.path.splitext(os.path.basename(path))[0],
                    "family": "", "category": cat, "source": source, "path": path, "size": size,
                    "sizeText": human_bytes(size), "deletable": True, "deletePaths": [path], "runners": []})

    for root in comfy_roots():
        for sub, cat in (("checkpoints", "image"), ("diffusion_models", "image"), ("unet", "image"),
                         ("loras", "image"), ("upscale_models", "image")):
            for f in glob.glob(os.path.join(root, "models", sub, "**", "*.*"), recursive=True):
                if f.endswith((".safetensors", ".ckpt", ".pt", ".pth", ".gguf", ".bin")):
                    n = os.path.basename(f)
                    add(f, "video" if classify(n) == "video" else cat, "ComfyUI")
    for f in glob.glob(os.path.join(CACHE_HOME, "whisper", "*.pt")):
        add(f, "stt", "Whisper")
    for d in (os.path.join(HOME, ".local", "share", "piper"), os.path.join(HOME, ".local", "share", "piper-voices"),
              os.path.join(CACHE_HOME, "piper")):
        for f in glob.glob(os.path.join(d, "**", "*.onnx"), recursive=True):
            if os.path.exists(f + ".json"):
                add(f, "tts", "Piper")
    for d in (os.path.join(HOME, ".local", "share", "whisper.cpp"), os.path.join(CACHE_HOME, "whisper.cpp")):
        for f in glob.glob(os.path.join(d, "**", "ggml-*.bin"), recursive=True):
            add(f, "stt", "whisper.cpp")
    return out


# --- GPU clients -------------------------------------------------------------------

_MODEL_PATH = re.compile(r"(/\S*?/models--[^/\s]+)|(/\S+\.(?:gguf|safetensors|onnx|ckpt|pth?|bin))\b")
KNOWN_APPS = [
    (r"ollama", "Ollama"), (r"llama-server", "llama.cpp"), (r"magnitude-inference", "Magnitude"),
    (r"whisperlive|whisper_live|whisper-typer", "Whisper Typer"), (r"whisper", "Whisper"),
    (r"piper", "Piper"), (r"quickshell", "hearth"), (r"\barbor\b", "arbor (compositor)"),
    (r"[Xx]wayland", "Xwayland"), (r"comfy", "ComfyUI"),
]


def _unit_of(pid):
    cg = _read("/proc/%s/cgroup" % pid)
    m = re.search(r"/([^/\n]+\.(?:service|scope))\s*$", cg, re.M)
    if not m:
        return ""
    return m.group(1) if "/user@" in cg else ""


def gpu_clients():
    """[{pid, pdev, vram, gtt, engineNs, name, comm, unit, models: [paths]}]
    for processes with an open DRM device (amdgpu fdinfo), each DRM client
    counted once. Processes of other users (Ollama runs as its own user)
    aren't readable and are missing."""
    per = {}
    for fdinfo in glob.glob("/proc/[0-9]*/fdinfo"):
        pid = fdinfo.split("/")[2]
        try:
            fds = os.listdir(fdinfo)
        except OSError:
            continue
        seen = set()
        for fd in fds:
            txt = _read(os.path.join(fdinfo, fd))
            if "drm-client-id" not in txt:
                continue
            cid = re.search(r"drm-client-id:\s*(\d+)", txt)
            pdev = re.search(r"drm-pdev:\s*(\S+)", txt)
            key = (cid.group(1) if cid else fd, pdev.group(1) if pdev else "")
            if key in seen:
                continue
            seen.add(key)
            e = per.setdefault((pid, key[1]), {"vram": 0, "gtt": 0, "engineNs": 0})
            for m in re.finditer(r"drm-memory-(vram|gtt):\s*(\d+)\s*KiB", txt):
                e[m.group(1)] += int(m.group(2)) * 1024
            for m in re.finditer(r"drm-engine-(gfx|compute):\s*(\d+)\s*ns", txt):
                e["engineNs"] += int(m.group(2))
    out = []
    for (pid, pdev), e in per.items():
        cmd = _read("/proc/%s/cmdline" % pid).replace("\0", " ").strip()
        comm = _read("/proc/%s/comm" % pid).strip()
        if not cmd and not comm:
            continue
        exe = os.path.basename(cmd.split(" ", 1)[0]) if cmd else comm
        label = re.sub(r"-wrapped$", "", exe.lstrip(".")) or comm
        for pat, name in KNOWN_APPS:
            if re.search(pat, cmd or comm):
                label = name
                break
        models = []
        if e["vram"] + e["gtt"] >= 256 << 20:
            models = process_models(pid)
        out.append({"pid": int(pid), "pci": pdev, "name": label, "comm": comm, "cmd": cmd[:300],
                    "vram": e["vram"], "gtt": e["gtt"], "engineNs": e["engineNs"],
                    "vramText": human_bytes(e["vram"]), "gttText": human_bytes(e["gtt"]) if e["gtt"] >= 64 << 20 else "",
                    "unit": _unit_of(pid), "models": models})
    out.sort(key=lambda p: -(p["vram"] + p["gtt"]))
    return out


def process_models(pid):
    """Model files a process has mapped or open: Hugging Face cache repos
    (as "hf:<repo>") and model files by path."""
    found = set()
    hub = hf_cache_dir()
    for line in _read("/proc/%s/maps" % pid).splitlines():
        if "/" not in line:
            continue
        p = line.split(None, 5)[-1] if len(line.split(None, 5)) == 6 else ""
        _add_model_path(p, hub, found)
    try:
        for fd in os.listdir("/proc/%s/fd" % pid):
            try:
                _add_model_path(os.readlink("/proc/%s/fd/%s" % (pid, fd)), hub, found)
            except OSError:
                pass
    except OSError:
        pass
    # llama-server style --model/-m arguments
    argv = _read("/proc/%s/cmdline" % pid).split("\0")
    for i, a in enumerate(argv[:-1]):
        if a in ("--model", "-m") and argv[i + 1].endswith(".gguf"):
            found.add("file:" + argv[i + 1])
    return sorted(found)


def _add_model_path(p, hub, found):
    if not p or p.startswith("[") or " (deleted)" in p:
        return
    m = re.search(r"/models--([^/]+)", p)
    if m and p.startswith(hub):
        found.add("hf:" + m.group(1).replace("--", "/", 1))
        return
    if re.search(r"\.(gguf|safetensors|onnx|ckpt|pth?)$", p) and not re.search(r"/nix/store/|site-packages", p):
        found.add("file:" + p)


# --- systemd model services -----------------------------------------------------------

def _unit_dirs():
    return [os.path.join(CONFIG_HOME, "systemd", "user")]


def _systemctl(*args, timeout=5):
    try:
        r = subprocess.run(["systemctl", "--user"] + list(args), capture_output=True, text=True, timeout=timeout)
        return r.stdout
    except (OSError, subprocess.SubprocessError):
        return ""


_svc_cache = {"t": 0, "list": []}


def service_server_bin(svc):
    """The llama-server a model unit runs (its own llama.cpp build beside its
    run script, e.g. ~/.local/share/inkling-2-mini/llama.cpp/bin/llama-server)."""
    d = os.path.dirname(svc.get("script") or "")
    if not d:
        return ""
    for c in glob.glob(os.path.join(d, "*", "bin", "llama-server")) + glob.glob(os.path.join(d, "bin", "llama-server")):
        if os.access(c, os.X_OK):
            return c
    for tok in re.findall(r"(/[^\s\"']*/llama-server)\b", svc.get("body", "")):
        if os.access(tok, os.X_OK):
            return tok
    return ""


def pick_llama_server(path):
    """The llama-server to run a GGUF nothing else runs: the build of a model
    unit whose model sits in the same folder (a newer quant of the same
    model needs the same build), else one whose model has the same
    architecture, else the newest unit build or one on PATH. "" if none."""
    arch = gguf_meta(path).get("general.architecture", "")
    folder = os.path.dirname(os.path.realpath(path))
    same_dir, same_arch, any_bin = "", "", []
    for svc in services():
        b = service_server_bin(svc)
        if not b:
            continue
        any_bin.append(b)
        mp = service_model_path(svc)
        if mp and os.path.dirname(os.path.realpath(mp)) == folder:
            same_dir = same_dir or b
        elif arch and mp and gguf_meta(mp).get("general.architecture", "") == arch:
            same_arch = same_arch or b
    if same_dir or same_arch:
        return same_dir or same_arch
    if any_bin:
        return max(any_bin, key=lambda b: os.path.getmtime(os.path.realpath(b)))
    from shutil import which
    return which("llama-server") or ""


# Servers that run one model per process: a user unit running one of them
# is a model unit (Load starts it, Unload stops it). Multi-model runtimes
# in a unit (LocalAI, LM Studio...) are found by hearth_ai_runtimes instead.
ONE_MODEL_SERVERS = r"llama-server|\bvllm\b|\bsglang\b|koboldcpp|llamafile"


def services():
    """User units that each serve one model: a unit whose ExecStart runs
    llama-server (directly or from a run script) or calls itself an
    inference server. Units managed by hearth itself are left out."""
    now = time.time()
    if now - _svc_cache["t"] < 30:
        units = _svc_cache["list"]
    else:
        units = []
        for d in _unit_dirs():
            for f in sorted(glob.glob(os.path.join(d, "*.service"))):
                name = os.path.basename(f)
                # magnitude.service is the Magnitude provider, not one model.
                if name.startswith("hearth-") or name.endswith("-proxy.service") or name == "magnitude.service":
                    continue
                text = _read(f)
                desc = (re.search(r"^Description=(.*)$", text, re.M) or [None, ""])[1]
                execs = re.findall(r"^ExecStart=(.*)$", text, re.M)
                script = ""
                for ex in execs:
                    for tok in ex.split():
                        tok = tok.replace("%h", HOME)
                        if tok.startswith("/") and os.path.isfile(tok) and not tok.startswith("/nix/store") \
                                and not tok.startswith("/usr/bin/env"):
                            script = tok
                body = _read(script) if script and os.path.getsize(script) < 1 << 20 else ""
                if not (re.search(r"inference|model server|llm server", desc, re.I)
                        or re.search(ONE_MODEL_SERVERS, " ".join(execs) + body)):
                    continue
                envf = (re.search(r"^EnvironmentFile=-?(.*)$", text, re.M) or [None, ""])[1].replace("%h", HOME)
                units.append({"unit": name, "desc": desc, "script": script, "env": envf, "body": body,
                              "socket": _proxy_socket(name)})
        _svc_cache.update(t=now, list=units)
    return units


def _proxy_socket(unit):
    """inkling-2-mini.service is started on demand through
    inkling-2-mini-proxy.socket: report the socket."""
    base = unit[:-len(".service")]
    for d in _unit_dirs():
        for cand in (base + "-proxy.socket", base + ".socket"):
            if os.path.exists(os.path.join(d, cand)):
                return cand
    return ""


def service_model_path(svc):
    """The GGUF a model service loads, from its environment file and the
    run script's defaults (`model_dir="${X_MODEL_DIR:-/path}"`)."""
    env = {}
    for line in _read(svc["env"]).splitlines():
        m = re.match(r"^\s*([A-Z0-9_]+)=(.*)$", line)
        if m:
            env[m.group(1)] = m.group(2).strip().strip("'\"")
    body = svc["body"]
    vals = {}
    for m in re.finditer(r'^\s*(\w+)="\$\{(\w+):-([^}]*)\}"', body, re.M):
        vals[m.group(1)] = env.get(m.group(2), m.group(3))
    d = next((v for k, v in vals.items() if k.endswith("model_dir")), "")
    f = next((v for k, v in vals.items() if k.endswith("model_file")), "")
    if d and f:
        return os.path.join(os.path.expanduser(d), f)
    m = re.search(r'^\s*model_path="\$\{model_dir\}/([^"]+)"', body, re.M)
    if d and m:
        return os.path.join(os.path.expanduser(d), m.group(1))
    m = re.search(r"(?:--model|-m)\s+(\S+\.gguf)", body)
    return m.group(1) if m else ""


def unit_info(unit):
    out = {}
    txt = _systemctl("show", unit, "-p", "ActiveState", "-p", "MainPID", "-p", "ExecMainStartTimestampMonotonic",
                     "-p", "ActiveEnterTimestampMonotonic", "-p", "InactiveExitTimestampMonotonic", "-p", "UnitFileState")
    for line in txt.splitlines():
        k, _, v = line.partition("=")
        out[k] = v
    return out


# --- Magnitude ---------------------------------------------------------------------------

def magnitude_installed():
    return os.access(MAGNITUDE, os.X_OK)


def magnitude_running(timeout=1):
    try:
        # Magnitude answers Python's default User-Agent with 503.
        req = urllib.request.Request("http://127.0.0.1:10100/health", headers={"User-Agent": "hearth-ai"})
        with urllib.request.urlopen(req, timeout=timeout) as r:
            h = json.loads(r.read().decode() or "{}")
        return h
    except (OSError, ValueError):
        return None


def magnitude(*args, timeout=30):
    r = subprocess.run([MAGNITUDE] + list(args), capture_output=True, text=True, timeout=timeout,
                       stdin=subprocess.DEVNULL)
    if r.returncode != 0:
        raise RuntimeError((r.stderr or r.stdout or "magnitude failed").strip().splitlines()[-1])
    return r.stdout


def magnitude_models():
    """(installed, loaded) from `magnitude models list --json`."""
    try:
        data = json.loads(magnitude("models", "list", "--json", timeout=15))
    except (RuntimeError, ValueError, OSError, subprocess.SubprocessError):
        return [], []
    inst, loaded = [], []
    for m in data.get("models", []):
        pres = m.get("presentation") or {}
        acq = m.get("acquisitionState") or {}
        serving = m.get("servingState") or {}
        meta = serving.get("metadata") or {}
        assess = serving.get("assessment") or {}
        resid = (acq.get("residencyState") or {}).get("_tag", "")
        size = m.get("storageBytes") or meta.get("storageBytes") or 0
        origin = (m.get("origin") or {})
        src = ((origin.get("source") or {}).get("_tag", "")) if origin.get("_tag") == "Found" else "Magnitude"
        fit = assess.get("_tag", "")
        note = ""
        if fit == "DoesNotFit":
            note = "Doesn't fit: needs %s more" % human_bytes(assess.get("deficitBytes"))
        served = ((assess.get("served") or {}).get("contextLength")) or 0
        item = {
            "id": m.get("modelId", ""), "name": pres.get("displayName") or m.get("modelId", ""),
            "quant": pres.get("variantLabel", ""), "size": size, "sizeText": human_bytes(size),
            "arch": meta.get("architecture", ""), "context": served or meta.get("maximumContextLength", 0),
            "maxContext": meta.get("maximumContextLength", 0), "fits": fit, "note": note,
            "found": src != "Magnitude", "residency": resid,
            "vision": bool((serving.get("capabilities") or {}).get("vision")),
        }
        inst.append(item)
        if resid in ("Loaded", "Loading", "Resident", "Active", "Serving"):
            loaded.append(item)
    return inst, loaded


# --- persistent model memory (load times, last use) ------------------------------------------

class Memory:
    def __init__(self):
        self.data = _json(STATE_FILE, {}) or {}
        self.data.setdefault("models", {})
        self.dirty = False
        self.saved = 0

    def get(self, key):
        return self.data["models"].setdefault(key, {})

    def note(self, key, **kw):
        m = self.get(key)
        for k, v in kw.items():
            if m.get(k) != v:
                m[k] = v
                self.dirty = True

    def save(self, force=False):
        if not self.dirty or (not force and time.time() - self.saved < 15):
            return
        try:
            os.makedirs(os.path.dirname(STATE_FILE), exist_ok=True)
            tmp = STATE_FILE + ".tmp"
            with open(tmp, "w") as f:
                json.dump(self.data, f)
            os.replace(tmp, STATE_FILE)
            self.dirty = False
            self.saved = time.time()
        except OSError:
            pass


# --- catalog ---------------------------------------------------------------------------------

# hearth's picks per category: well known models that run locally. Sizes
# are fetched (Ollama registry, Hugging Face API) when the list is shown.
PICKS = [
    # Language (Ollama)
    {"category": "llm", "provider": "ollama", "ref": "qwen3.5:4b", "desc": "Small, fast assistant with tools and vision"},
    {"category": "llm", "provider": "ollama", "ref": "qwen3.5:9b", "desc": "Stronger all-rounder, still quick"},
    {"category": "llm", "provider": "ollama", "ref": "gemma3:12b", "desc": "Google's open model, good writing"},
    {"category": "llm", "provider": "ollama", "ref": "llama3.2:3b", "desc": "Tiny and fast for simple tasks"},
    {"category": "llm", "provider": "ollama", "ref": "qwen2.5-coder:14b", "desc": "Code completion and edits"},
    # Embeddings
    {"category": "embedding", "provider": "ollama", "ref": "nomic-embed-text", "desc": "Text search embeddings"},
    {"category": "embedding", "provider": "ollama", "ref": "mxbai-embed-large", "desc": "Higher quality text embeddings"},
    {"category": "embedding", "provider": "hf", "ref": "BAAI/bge-m3", "desc": "Multilingual embeddings for search"},
    # Speech to text
    {"category": "stt", "provider": "hf", "ref": "Systran/faster-whisper-large-v3", "desc": "Whisper large-v3 for faster-whisper"},
    {"category": "stt", "provider": "hf", "ref": "mobiuslabsgmbh/faster-whisper-large-v3-turbo", "desc": "Whisper turbo: nearly as good, much faster"},
    {"category": "stt", "provider": "hf", "ref": "nvidia/parakeet-tdt-0.6b-v2", "desc": "Very fast English transcription"},
    # Text to speech
    {"category": "tts", "provider": "hf", "ref": "hexgrad/Kokoro-82M", "desc": "Tiny, natural voices"},
    {"category": "tts", "provider": "hf", "ref": "ResembleAI/chatterbox", "desc": "Expressive voices, voice cloning"},
    {"category": "tts", "provider": "hf", "ref": "Qwen/Qwen3-TTS-12Hz-1.7B-CustomVoice", "desc": "Multilingual voices"},
    {"category": "tts", "provider": "hf", "ref": "microsoft/VibeVoice-1.5B", "desc": "Long multi-speaker speech"},
    # Image
    {"category": "image", "provider": "hf", "ref": "Tongyi-MAI/Z-Image-Turbo", "desc": "Fast, high quality images"},
    {"category": "image", "provider": "hf", "ref": "black-forest-labs/FLUX.1-schnell", "desc": "FLUX in a few steps"},
    {"category": "image", "provider": "hf", "ref": "stabilityai/stable-diffusion-xl-base-1.0", "desc": "SDXL, huge ecosystem of add-ons"},
    # Video
    {"category": "video", "provider": "hf", "ref": "Wan-AI/Wan2.1-T2V-1.3B-Diffusers", "desc": "Small text-to-video model"},
    {"category": "video", "provider": "hf", "ref": "Lightricks/LTX-Video", "desc": "Fast video generation"},
    # Audio & music
    {"category": "audio", "provider": "hf", "ref": "facebook/musicgen-small", "desc": "Music from a description"},
    {"category": "audio", "provider": "hf", "ref": "stabilityai/stable-audio-open-1.0", "desc": "Sound effects and loops"},
    # Vision
    {"category": "vision", "provider": "hf", "ref": "ZhengPeng7/BiRefNet", "desc": "Background removal"},
    {"category": "vision", "provider": "hf", "ref": "facebook/sam2.1-hiera-large", "desc": "Segment anything in images"},
]

# Hugging Face pipeline tags searched for each category.
CATEGORY_TAGS = {
    "llm": ["text-generation", "image-text-to-text"], "embedding": ["feature-extraction", "sentence-similarity"],
    "stt": ["automatic-speech-recognition"], "tts": ["text-to-speech"], "image": ["text-to-image"],
    "video": ["text-to-video", "image-to-video"], "audio": ["text-to-audio"],
    "vision": ["image-segmentation", "object-detection", "depth-estimation"], "other": [],
}


def _http_json(url, timeout=10):
    req = urllib.request.Request(url, headers={"User-Agent": "hearth-ai", "Accept": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode() or "null")


def ollama_size(ref):
    name, _, tag = ref.partition(":")
    if "/" not in name:
        name = "library/" + name
    req = urllib.request.Request("https://registry.ollama.ai/v2/%s/manifests/%s" % (name, tag or "latest"),
                                 headers={"Accept": "application/vnd.docker.distribution.manifest.v2+json"})
    with urllib.request.urlopen(req, timeout=10) as r:
        man = json.loads(r.read().decode())
    return sum(l.get("size", 0) for l in man.get("layers", []))


def hf_info(repo):
    d = _http_json("https://huggingface.co/api/models/%s?blobs=true" % urllib.parse.quote(repo, safe="/"))
    size = sum((s.get("size") or 0) for s in d.get("siblings", []))
    return {"size": size, "gated": bool(d.get("gated")), "tag": d.get("pipeline_tag", ""),
            "downloads": d.get("downloads", 0), "likes": d.get("likes", 0)}


def catalog_sizes(refresh=False):
    """Sizes of the picks, cached a week."""
    cache = _json(CATALOG_CACHE, {}) or {}
    if not refresh and time.time() - cache.get("time", 0) < 7 * 86400 and cache.get("sizes"):
        return cache["sizes"]
    sizes = dict(cache.get("sizes") or {})
    for p in PICKS:
        k = p["provider"] + ":" + p["ref"]
        try:
            if p["provider"] == "ollama":
                sizes[k] = {"size": ollama_size(p["ref"])}
            else:
                sizes[k] = hf_info(p["ref"])
        except (OSError, ValueError, KeyError):
            pass
    try:
        os.makedirs(os.path.dirname(CATALOG_CACHE), exist_ok=True)
        with open(CATALOG_CACHE, "w") as f:
            json.dump({"time": time.time(), "sizes": sizes}, f)
    except OSError:
        pass
    return sizes


def hf_search(query, category, limit=25):
    tags = CATEGORY_TAGS.get(category) or [""]
    out, seen = [], set()
    for tag in tags:
        q = {"sort": "downloads", "direction": "-1", "limit": str(limit), "full": "false"}
        if query:
            q["search"] = query
        if tag:
            q["pipeline_tag"] = tag
        try:
            res = _http_json("https://huggingface.co/api/models?" + urllib.parse.urlencode(q))
        except (OSError, ValueError):
            continue
        for m in res or []:
            rid = m.get("id") or m.get("modelId")
            if not rid or rid in seen:
                continue
            seen.add(rid)
            out.append({"provider": "hf", "ref": rid, "name": rid.split("/", 1)[-1], "family": rid.split("/", 1)[0],
                        "category": classify(rid, tag=m.get("pipeline_tag", "") or tag, default=category or "other"),
                        "downloads": m.get("downloads", 0), "likes": m.get("likes", 0), "desc": "",
                        "gguf": "gguf" in (m.get("tags") or [])})
    out.sort(key=lambda m: -m["downloads"])
    return out[:limit]


def trash(paths):
    """Move to the trash (gio), never delete outright."""
    for p in paths:
        r = subprocess.run(["gio", "trash", p], capture_output=True, text=True, timeout=120)
        if r.returncode != 0:
            raise RuntimeError((r.stderr or "couldn't move to the trash").strip())
