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
KEY_RE = re.compile(r"^(?:(?:Ctrl|Shift|Alt|Meta|Super)\+)+\S+$|^F(?:[1-9]|1[0-2])$|^(?:Del|Delete|Esc|Return|Enter|Backspace|Tab)$")


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
    """The rows (cropped to box=(x0, y0, x1, y1)) scaled SCALE times."""
    x0, y0, x1, y1 = box or (0, 0, w, h)
    out = []
    for r in rows[y0:y1]:
        big = bytes(b for b in r[x0:x1] for _ in range(SCALE))
        out.extend([big] * SCALE)
    return (x1 - x0) * SCALE, (y1 - y0) * SCALE, out


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


def items_of(rows):
    """[(label, shortcut, (cx, cy))] from the popup's rows: a leading icon
    read as a stray character dropped, a trailing key combination split
    off, a submenu arrow dropped."""
    if not rows:
        return []
    col = text_column(rows)
    res = []
    for r in rows:
        ws = list(r["words"])
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
        while ws and ws[-1]["t"] in (">", "›", "»", "▸", "▶"):
            ws = ws[:-1]
        label = " ".join(d["t"] for d in ws).strip(" .")
        if r["text"].rstrip().endswith("..."):
            label += "…"
        if not label or len(norm(label)) < 2:
            continue
        x0 = ws[0]["x0"] if ws else r["x0"]
        res.append((label, sc, ((x0 + r["x1"]) / 2, (r["y0"] + r["y1"]) / 2)))
    return res


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
            w, h, _ = read_png(p)
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
            w, h, _ = read_png(p)
            rows = menu_rows(before or [], ocr_rows(p))
            col = text_column(rows)
            if rows and col is not None:
                box = (max(0, int(col) - 3), max(0, int(min(r["y0"] for r in rows)) - 4),
                       min(w, int(max(r["x1"] for r in rows)) + 60), min(h, int(max(r["y1"] for r in rows)) + 4))
                again = ocr_rows(p, box)
                if len(again) >= len(rows):
                    rows = sorted(again, key=lambda r: r["y0"])
            return items_of(rows), (w, h)
        except (OSError, ValueError, zlib.error):
            return [], None
        finally:
            try:
                os.unlink(p)
            except OSError:
                pass

    def close(self):
        import shutil
        shutil.rmtree(self.dir, ignore_errors=True)
