"""Menus no accessibility tree shows, read off the screen: a popup the
toolkit opens but never exposes (Qt Quick's Menu in its own popup window,
Qt 6.8 and later: Kirigami apps' ☰ in System Settings, Info Center,
Tokodon...). hearth-atspi-menu opens it with a real click, and this module:

- captures the window (arbor screenshot-window: the window's own surfaces,
  its popups included, in its surface coordinates; never the clipboard),
- reads the lines that are there with the popup open and not before it
  (tesseract, on a 3x upscale: small UI text reads badly at 1x),
- gives each its label, a shortcut when the line ends in one, and its
  centre in the window's logical coordinates, where a click-window later
  chooses it (after checking the same line is there again).

Pure Python apart from arbor and tesseract: PNG decoding and the upscale
are done here (the helper's Python has no imaging library).
"""

import os
import re
import struct
import subprocess
import tempfile
import zlib

SCALE = 3  # upscale before OCR
MOD_RE = re.compile(r"^(?:(?:Ctrl|Shift|Alt|Meta|Super)\+)+[^+\s]+$|^F(?:[1-9]|1[0-2])\+\S+$")
KEY_RE = re.compile(r"^(?:(?:Ctrl|Shift|Alt|Meta|Super)\+)+\S+$|^F(?:[1-9]|1[0-2])(?:\+\S+)?$|^(?:Del|Delete|Esc|Return|Enter|Backspace|Tab)$")


# ------------------------------------------------------------------ images

def read_png(path):
    """(width, height, grey rows as bytes): 8-bit RGB/RGBA/grey PNGs."""
    with open(path, "rb") as f:
        data = f.read()
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    pos, idat, w = 8, [], 0
    while pos < len(data):
        n, typ = struct.unpack(">I4s", data[pos:pos + 8])
        chunk = data[pos + 8:pos + 8 + n]
        if typ == b"IHDR":
            w, h, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", chunk)
            if depth != 8 or interlace or ctype not in (0, 2, 4, 6):
                raise ValueError("unsupported PNG")
        elif typ == b"IDAT":
            idat.append(chunk)
        elif typ == b"IEND":
            break
        pos += 12 + n
    bpp = {0: 1, 2: 3, 4: 2, 6: 4}[ctype]
    raw = zlib.decompress(b"".join(idat))
    stride = w * bpp
    rows, prev, i = [], bytearray(stride), 0
    for _ in range(h):
        ft = raw[i]
        line = bytearray(raw[i + 1:i + 1 + stride])
        i += 1 + stride
        if ft == 1:
            for x in range(bpp, stride):
                line[x] = (line[x] + line[x - bpp]) & 255
        elif ft == 2:
            for x in range(stride):
                line[x] = (line[x] + prev[x]) & 255
        elif ft == 3:
            for x in range(stride):
                left = line[x - bpp] if x >= bpp else 0
                line[x] = (line[x] + ((left + prev[x]) >> 1)) & 255
        elif ft == 4:
            for x in range(stride):
                a = line[x - bpp] if x >= bpp else 0
                b = prev[x]
                c = prev[x - bpp] if x >= bpp else 0
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                line[x] = (line[x] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        prev = line
        if bpp == 1:
            rows.append(bytes(line))
        elif bpp == 2:
            rows.append(bytes(line[0::2]))
        else:
            r, g, b = line[0::bpp], line[1::bpp], line[2::bpp]
            rows.append(bytes((77 * r[k] + 150 * g[k] + 29 * b[k]) >> 8 for k in range(w)))
    return w, h, rows


def write_grey_png(path, w, h, rows):
    def chunk(t, d):
        return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    body = b"".join(b"\0" + r for r in rows)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 0, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(body, 1)) + chunk(b"IEND", b""))


def upscaled(w, h, rows, box=None):
    """The rows (cropped to box=(x0, y0, x1, y1)) scaled SCALE times: by
    linear interpolation for a small area (pixel fonts, DOSBox-X's, read far
    better smoothed), by repeating pixels for a large one (faster)."""
    x0, y0, x1, y1 = box or (0, 0, w, h)
    W, H = x1 - x0, y1 - y0
    if W * H > 160_000:
        out = []
        for r in rows[y0:y1]:
            big = bytes(b for b in r[x0:x1] for _ in range(SCALE))
            out.extend([big] * SCALE)
        return W * SCALE, H * SCALE, out
    k = SCALE
    xs = [(x0 + min(X // k, W - 1), x0 + min(X // k + 1, W - 1), (X % k) / k) for X in range(W * k)]
    out = []
    for Y in range(H * k):
        y, ty = Y // k, (Y % k) / k
        a, b = rows[y0 + min(y, H - 1)], rows[y0 + min(y + 1, H - 1)]
        out.append(bytes(int((a[xa] * (1 - tx) + a[xb] * tx) * (1 - ty) + (b[xa] * (1 - tx) + b[xb] * tx) * ty)
                         for xa, xb, tx in xs))
    return W * k, H * k, out


# --------------------------------------------------------------------- OCR

def capture(window, path):
    try:
        r = subprocess.run(["arbor", "msg", "action", "screenshot-window", "--id", str(window),
                            "--clipboard", "false", "--shadow", "false", "--path", path],
                           capture_output=True, timeout=5)
    except (OSError, subprocess.TimeoutExpired):
        return False
    for _ in range(30):  # written by the compositor after it answers
        if os.path.exists(path) and os.path.getsize(path) > 0:
            return True
        import time
        time.sleep(0.05)
    return r.returncode == 0 and os.path.exists(path)


def ocr_rows(png, box=None):
    """Text rows in the image: [{text, words, x0, y0, x1, y1}] in the
    image's own pixels (box: a crop, coordinates stay the full image's)."""
    w, h, rows = read_png(png)
    bw, bh, big = upscaled(w, h, rows, box)
    ox, oy = (box[0], box[1]) if box else (0, 0)
    tmp = png + ".up.png"
    write_grey_png(tmp, bw, bh, big)
    try:
        r = subprocess.run(["tesseract", tmp, "-", "--psm", "11", "tsv"],
                           capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.TimeoutExpired):
        return []
    finally:
        try:
            os.unlink(tmp)
        except OSError:
            pass
    words = []
    for line in r.stdout.splitlines()[1:]:
        f = line.split("\t")
        if len(f) < 12 or not f[11].strip():
            continue
        try:
            conf = float(f[10])
            x, y, ww, hh = (int(v) / SCALE for v in f[6:10])
        except ValueError:
            continue
        if conf < 30:
            continue
        words.append({"t": f[11].strip(), "x0": ox + x, "y0": oy + y, "x1": ox + x + ww, "y1": oy + y + hh})
    # Rows: words whose vertical centres line up.
    words.sort(key=lambda d: ((d["y0"] + d["y1"]) / 2, d["x0"]))
    out = []
    for d in words:
        cy = (d["y0"] + d["y1"]) / 2
        for row in out:
            if abs(cy - (row["y0"] + row["y1"]) / 2) < max(4, (row["y1"] - row["y0"]) * 0.5):
                row["words"].append(d)
                row["x0"], row["x1"] = min(row["x0"], d["x0"]), max(row["x1"], d["x1"])
                row["y0"], row["y1"] = min(row["y0"], d["y0"]), max(row["y1"], d["y1"])
                break
        else:
            out.append({"words": [d], "x0": d["x0"], "y0": d["y0"], "x1": d["x1"], "y1": d["y1"]})
    for row in out:
        row["words"].sort(key=lambda d: d["x0"])
        row["text"] = " ".join(d["t"] for d in row["words"])
    return out


def norm(s):
    return re.sub(r"[^a-z0-9]", "", s.lower())


def same_text(label, row_text, at_least=0.75):
    """Whether a re-read line is the item read before: OCR of the same
    line differs by a letter or two between reads ('Conf iguration' and
    'Configuration'), so a close enough match counts."""
    import difflib
    a, b = norm(label), norm(row_text)
    if not a or not b:
        return False
    if a in b:
        return True
    best = max((difflib.SequenceMatcher(None, a, b[i:i + len(a)]).ratio()
                for i in range(0, max(1, len(b) - len(a) + 1))), default=0)
    return best >= at_least


def menu_rows(before, after):
    """The popup's rows: in `after` and not in `before`, in one column."""
    old = {norm(r["text"]) for r in before}
    new = [r for r in after if norm(r["text"]) and norm(r["text"]) not in old]
    if len(new) < 1:
        return []
    # One column: rows whose left edges sit together (the popup), not
    # stray text the popup uncovered or changed elsewhere.
    new.sort(key=lambda r: r["x0"])
    groups = []
    for r in new:
        for g in groups:
            if abs(r["x0"] - g[0]["x0"]) < 40:
                g.append(r)
                break
        else:
            groups.append([r])
    col = max(groups, key=len)
    col.sort(key=lambda r: r["y0"])
    return col


def text_column(rows):
    """Where the text column starts: the most common left edge of the first
    real word (3+ letters) of each row."""
    starts = []
    for r in rows:
        for d in r["words"]:
            if len(re.sub(r"[^A-Za-z]", "", d["t"])) >= 3:
                starts.append(round(d["x0"] / 4))
                break
    return max(set(starts), key=starts.count) * 4 if starts else None


def fix_key_token(t):
    """OCR's usual misreads in an F-key shortcut: 'F1Z2+R', 'F1Z+M',
    'Fi0' -> F12+R, F12+M, F10 (Z for 2, l/I/i/| for 1, a doubled digit);
    'Ctri+Z', 'Ctr1+0' -> Ctrl+Z, Ctrl+O (a key after a modifier: 0 for O)."""
    if "+" in t:
        head, _, key = t.rpartition("+")
        head = re.sub(r"\bCtr[il1I|]\b", "Ctrl", head)
        if len(key) == 1 and key == "0" and re.search(r"Ctrl|Alt|Shift", head):
            key = "O"  # Ctrl+0 is rare in a menu; Ctrl+O (Open) is everywhere
        t = head + "+" + key
    m = re.match(r"^F([0-9IlZzi|]{1,4})((?:\+\S+)?)$", t)
    if not m:
        return t
    digits = m.group(1).translate(str.maketrans("IlZzi|", "112211"))
    for n in (digits[:2], digits[:1]):
        if n.isdigit() and 1 <= int(n) <= 12:
            return "F" + n + m.group(2)
    return t


def fill_shortcuts(png, rows, right):
    """Shortcuts the first read missed (tesseract skips short "Ctrl+C"s
    beside long labels: Pixelorama's Edit menu): the shortcut column read
    again on its own, each key put on the line it lines up with."""
    def is_key(t):
        t = fix_key_token(t)
        return bool(KEY_RE.match(t) or MOD_RE.match(t))
    # Keys after a label (an item named "Delete" is a label, not a key).
    xs = [d["x0"] for r in rows for d in r["words"][1:] if is_key(d["t"])]
    if len(xs) < 2 or len(xs) == len(rows):
        return rows
    box = (max(0, int(min(xs)) - 4), max(0, int(min(r["y0"] for r in rows)) - 4),
           int(right), int(max(r["y1"] for r in rows)) + 4)
    if box[2] - box[0] < 12:
        return rows
    for c in ocr_rows(png, box):
        keys = [d for d in c["words"] if is_key(d["t"])]
        if not keys:
            continue
        cy = (c["y0"] + c["y1"]) / 2
        for r in rows:
            if r["y0"] - 3 <= cy <= r["y1"] + 3 and not any(is_key(d["t"]) for d in r["words"]):
                r["words"] = sorted(r["words"] + keys, key=lambda d: d["x0"])
                r["text"] = " ".join(d["t"] for d in r["words"])
                r["x1"] = max(r["x1"], max(d["x1"] for d in keys))
                break
    return rows


def items_of(rows):
    """[(label, shortcut, (cx, cy))] from the popup's rows: a leading icon
    read as a stray character dropped, a trailing key combination split
    off, a submenu arrow dropped."""
    if not rows:
        return []
    col = text_column(rows)
    res = []
    for r in rows:
        ws = [dict(d, t=fix_key_token(d["t"])) for d in r["words"]]
        if col is not None:
            ws = [d for d in ws if d["x1"] > col - 2]
        # A shortcut: the last word(s) after a wide gap, shaped like a key.
        sc = ""
        if len(ws) >= 2:
            gaps = [ws[k + 1]["x0"] - ws[k]["x1"] for k in range(len(ws) - 1)]
            k = max(range(len(gaps)), key=lambda i: gaps[i])
            space = sorted(gaps)[len(gaps) // 2] if len(gaps) > 1 else 4
            tail = "".join(d["t"] for d in ws[k + 1:])
            tail = re.sub(r"^F[lI|]", "F1", tail)
            if gaps[k] > max(12, 3 * space) and KEY_RE.match(tail):
                sc, ws = tail, ws[:k + 1]
            elif MOD_RE.match(ws[-1]["t"]) and len(ws) >= 2:
                # A key with modifiers is never part of a label: split it
                # off however narrow the gap (a narrow menu).
                sc, ws = ws[-1]["t"], ws[:-1]
        while ws and ws[-1]["t"] in (">", "›", "»", "▸", "▶", ")", "»>"):
            ws = ws[:-1]
        label = " ".join(d["t"] for d in ws).strip(" .")
        if r["text"].rstrip().endswith("..."):
            label += "…"
        if not label or len(norm(label)) < 2:
            continue
        x0 = ws[0]["x0"] if ws else r["x0"]
        res.append((label, sc, ((x0 + r["x1"]) / 2, (r["y0"] + r["y1"]) / 2)))
    return res


def _longest_run(flags):
    best, start = (0, -1, -1), None
    for i, f in enumerate(flags + [False]):
        if f and start is None:
            start = i
        elif not f and start is not None:
            if i - start > best[0]:
                best = (i - start, start, i)
            start = None
    return best[1], best[2]


def changed_box(a, b, pad=2, step=24):
    """Where a menu opened between two grey captures of the same size: the
    block in which nearly every pixel changed (by more than `step`). A
    redraw's scattered differences (DOSBox-X repaints its whole screen, a
    cursor blinks) don't make such a block. None if there's no clear one."""
    if not a or not b or a[0] != b[0] or a[1] != b[1]:
        return None
    w, h, ra = a
    _, _, rb = b
    cols = [0] * w
    rows = [0] * h
    for y in range(h):
        p, q = ra[y], rb[y]
        if p == q:
            continue
        n = 0
        for x in range(w):
            if abs(p[x] - q[x]) > step:
                cols[x] += 1
                n += 1
        rows[y] = n
    if not any(cols):
        return None
    cmax = max(cols)
    x0, x1 = _longest_run([c > cmax * 0.4 for c in cols])
    if x0 < 0 or x1 - x0 < 20:
        return None
    width = x1 - x0
    # Rows of that block: most of its columns changed there.
    band = []
    for y in range(h):
        p, q = ra[y], rb[y]
        n = sum(1 for x in range(x0, x1) if abs(p[x] - q[x]) > step) if rows[y] else 0
        band.append(n > width * 0.15)
    y0, y1 = _longest_run(band)
    if y0 < 0 or y1 - y0 < 10:
        return None
    # Grow to the popup's edges over what changed only a little: a dark
    # menu opened half over a dark toolbar, half over a bright canvas
    # (Pixelorama) changes strongly only where it covers the canvas.
    fine = max(6, step // 3)

    def col_changed(x, ya, yb):
        n = sum(1 for y in range(ya, yb) if abs(ra[y][x] - rb[y][x]) > fine)
        return n > (yb - ya) * 0.3

    def row_changed(y, xa, xb):
        p, q = ra[y], rb[y]
        n = sum(1 for x in range(xa, xb) if abs(p[x] - q[x]) > fine)
        return n > (xb - xa) * 0.3

    for _ in range(2):  # columns, then rows with the wider columns, again
        while x0 > 0 and col_changed(x0 - 1, y0, y1):
            x0 -= 1
        while x1 < w and col_changed(x1, y0, y1):
            x1 += 1
        while y0 > 0 and row_changed(y0 - 1, x0, x1):
            y0 -= 1
        while y1 < h and row_changed(y1, x0, x1):
            y1 += 1
    return (max(0, x0 - pad), max(0, y0 - pad), min(w, x1 + pad), min(h, y1 + pad))


STD_TITLES = {"file", "edit", "view", "help", "tools", "go", "window", "windows", "options", "settings",
              "insert", "format", "bookmarks", "history", "search", "project", "preferences"}


def menu_bar(rows, k=1.0, top=70):
    """A menu bar drawn in the window (SDL, FLTK, Godot, Tk: no accessible
    menu bar): near the top, a row that starts with three or more titles,
    one of them a standard one (File, Edit, View, Help...). Titles are the
    row's words grouped by spacing (one space joins "Search options", a
    menu bar's wider gap separates titles); the bar ends at the first group
    that isn't a title (Pixelorama's "733 %" after Help, openboardview's
    checkboxes) or a wide gap. A title starts with a capital, ends in no
    sentence punctuation; an "(F)" mnemonic is dropped (AzPainter's
    "File(F)"). Not a line of text that happens to hold "File" ("Drag Drop
    File onto desktop icon"), nor a header bar's "View s X".
    [(title, (x, y))] in the capture's pixels."""
    for r in sorted(rows, key=lambda r: r["y0"]):
        if r["y0"] > top * k:
            break
        words = sorted((d for d in r["words"] if len(d["t"].strip("&_")) >= 2 or d["t"].isalnum()),
                       key=lambda d: d["x0"])
        if len(words) < 3:
            continue
        hs = sorted(d["y1"] - d["y0"] for d in words)
        em = max(hs[len(hs) // 2], 1)
        groups = [[words[0]]]
        for a, b in zip(words, words[1:]):
            gap = b["x0"] - a["x1"]
            if gap > em * 4:
                groups.append(None)  # the bar's end
                break
            if gap < em * 0.6:
                groups[-1].append(b)
            else:
                groups.append([b])
        titles = []
        for g in groups:
            if g is None:
                break
            t = re.sub(r"\s*\(\w\)$", "", " ".join(d["t"] for d in g).replace("&", "").replace("_", "")).strip()
            if len(t) < 2 or len(g) > 3 or not (t[0].isupper() or t[0].isdigit()) or t[-1] in ".:?!,%" \
                    or any(c.isdigit() for c in t[1:]):
                break
            titles.append((t, ((g[0]["x0"] + g[-1]["x1"]) / 2, (min(d["y0"] for d in g) + max(d["y1"] for d in g)) / 2)))
        if len(titles) < 3:
            continue
        if not {t.lower() for t, _ in titles} & STD_TITLES:
            continue
        return titles
    return []


def _ink(w, h, rows, top):
    """Pixels that differ clearly from their row's commonest value."""
    m = []
    for y in range(min(h, top)):
        r = rows[y]
        hist = [0] * 256
        for v in r:
            hist[v] += 1
        bg = max(range(256), key=hist.__getitem__)
        m.append([abs(v - bg) > 60 for v in r])
    return m


def find_burger(w, h, rows, k=1.0, top=80):
    """A ☰ the app draws (Lapce, Lorien, Oculante: no accessibility tree):
    three equal horizontal strokes, evenly spaced, near the window's top,
    with nothing else drawn around them (not text, a ruler, a grid).
    Its centre (x, y) in the capture's pixels, or None."""
    lim = int(top * k)
    ink = _ink(w, h, rows, lim + int(12 * k))
    segs = []
    for y in range(min(h, lim)):
        r, x = ink[y], 0
        while x < w:
            if r[x]:
                x0 = x
                while x < w and r[x]:
                    x += 1
                segs.append((y, x0, x))
            else:
                x += 1
    ss = []
    for y, x0, x1 in segs:  # runs on consecutive rows: one stroke
        for st in ss:
            if st[1] == y - 1 and abs(st[2] - x0) <= 1 and abs(st[3] - x1) <= 1:
                st[1] = y
                break
        else:
            ss.append([y, y, x0, x1])
    ss = [st for st in ss if 10 * k <= st[3] - st[2] <= 30 * k and st[1] - st[0] <= 3 * k]
    for a in ss:
        for b in ss:
            if b[0] <= a[0] or abs(b[2] - a[2]) > 1 or abs(b[3] - a[3]) > 1:
                continue
            d = b[0] - a[0]
            if not 3 * k <= d <= 10 * k:
                continue
            for c in ss:
                if abs(c[0] - b[0] - d) > 1 or abs(c[2] - a[2]) > 1 or abs(c[3] - a[3]) > 1:
                    continue
                m = int(6 * k)
                X0, X1 = max(0, a[2] - m), min(w, a[3] + m)
                Y0, Y1 = max(0, a[0] - m), min(len(ink), c[1] + 1 + m)
                own = {(y, x) for st in (a, b, c) for y in range(st[0], st[1] + 1) for x in range(st[2], st[3])}
                stray = sum(ink[y][x] for y in range(Y0, Y1) for x in range(X0, X1) if (y, x) not in own)
                if stray <= (X1 - X0) * (Y1 - Y0) * 0.03:
                    return ((a[2] + a[3]) / 2, (a[0] + c[1]) / 2)
    return None


def window_size(window):
    """The window's logical size from arbor (no accessibility to ask)."""
    import json
    try:
        r = subprocess.run(["arbor", "msg", "-j", "windows"], capture_output=True, text=True, timeout=5)
        for w in json.loads(r.stdout):
            if w.get("id") == window:
                ws = (w.get("layout") or {}).get("window_size")
                if ws:
                    return ws[0], ws[1]
    except Exception:
        pass
    return None


class Session:
    """Captures of one window in a private temp folder (removed on close)."""

    def __init__(self, window):
        self.window = window
        base = os.environ.get("XDG_RUNTIME_DIR") or tempfile.gettempdir()
        self.dir = tempfile.mkdtemp(prefix="hearth-ocr-", dir=base)
        self.n = 0

    def shot(self):
        self.n += 1
        p = os.path.join(self.dir, f"{self.n}.png")
        return p if capture(self.window, p) else None

    def rows(self, box=None):
        p = self.shot()
        if not p:
            return None, None
        try:
            w, h, px = read_png(p)
            self.before_px = (w, h, px)  # for read_popup's changed area
            return ocr_rows(p, box), (w, h)
        except (OSError, ValueError, zlib.error):
            return None, None
        finally:
            try:
                os.unlink(p)
            except OSError:
                pass

    def read_popup(self, before):
        """The popup open now, against `before` (rows with it closed):
        [(label, shortcut, (x, y))] in the capture's pixels, and the
        capture's size. Read twice: the second time cropped to the text
        column, so its icons can't swallow a word ("About")."""
        p = self.shot()
        if not p:
            return [], None
        try:
            w, h, px = read_png(p)
            # Only where the window changed (the menu drawn over the page:
            # DOSBox-X's console text beside it would join its lines).
            box = changed_box(getattr(self, "before_px", None), (w, h, px))
            rows = menu_rows(before or [], ocr_rows(p, box))
            col = text_column(rows)
            if rows and col is not None:
                right = box[2] if box else min(w, int(max(r["x1"] for r in rows)) + 60)
                box = (max(0, int(col) - 3), max(0, int(min(r["y0"] for r in rows)) - 4),
                       right, min(h, int(max(r["y1"] for r in rows)) + 4))
                again = ocr_rows(p, box)
                if len(again) >= len(rows):
                    rows = sorted(again, key=lambda r: r["y0"])
            if rows:
                rows = fill_shortcuts(p, rows, box[2] if box else w)
            return items_of(rows), (w, h)
        except (OSError, ValueError, zlib.error):
            return [], None
        finally:
            try:
                os.unlink(p)
            except OSError:
                pass

    def bar(self):
        """The window's drawn menu bar ([(title, (x, y))]; a drawn ☰ alone
        is [("Menu", (x, y))]) and the capture's scale (pixels per logical
        pixel), or ([], 1)."""
        p = self.shot()
        if not p:
            return [], 1.0
        try:
            w, h, _ = read_png(p)
            ws = window_size(self.window)
            k = w / ws[0] if ws and ws[0] else 1.0
            rows = ocr_rows(p, (0, 0, w, min(h, int(80 * k))))
            bar = menu_bar(rows, k)
            if not bar:
                # No drawn menu bar: a drawn ☰ is a one-menu bar.
                _, _, px = read_png(p)
                at = find_burger(w, h, px, k)
                if at:
                    bar = [("Menu", at)]
            return bar, k
        except (OSError, ValueError, zlib.error):
            return [], 1.0
        finally:
            try:
                os.unlink(p)
            except OSError:
                pass

    def close(self):
        import shutil
        shutil.rmtree(self.dir, ignore_errors=True)
