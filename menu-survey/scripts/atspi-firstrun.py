#!/usr/bin/env python3
"""Get an app past its first-run wizard in the survey's throwaway home
(PCSX2's Setup Wizard, puNES's folder wizard...), so its main window and
menus can be measured. Run by menu-probe.py inside the rig, with hearth's
Python (gi/Atspi).

Presses, over AT-SPI, a showing button of the app named like a wizard step:
Finish/Done/Skip first, then Next/Continue/Get Started, then Close/OK. Never
Accept/Agree (that would accept a license on the user's behalf), Cancel,
Quit or Exit. Up to ROUNDS presses, a second apart, until none is left.

Usage: atspi-firstrun.py PID
Prints one JSON object: {"pressed": [labels]}.
"""
import json
import re
import sys
import time

import gi

gi.require_version("Atspi", "2.0")
from gi.repository import Atspi  # noqa: E402

ORDER = [re.compile(p, re.I) for p in (
    r"^(&)?(finish|done|skip( (this|setup|tour|for now))?|not now|maybe later|later|no,? thanks)\W*$",
    r"^(&)?(next|continue|get started|start|let'?s go|begin)\W*[>›»]*$",
    r"^(&)?(close|ok|got it|dismiss)\W*$",
)]
NEVER = re.compile(r"accept|agree|cancel|quit|exit|delete|remove|install|buy|sign ?in|log ?in|register", re.I)
ROUNDS = 8


def ancestors(pid):
    seen = []
    try:
        while pid > 1 and len(seen) < 32:
            seen.append(pid)
            with open(f"/proc/{pid}/stat") as f:
                pid = int(f.read().rsplit(")", 1)[1].split()[1])
    except (OSError, ValueError, IndexError):
        pass
    return seen


def app_of(pid):
    desk = Atspi.get_desktop(0)
    mine = set(ancestors(pid))
    for i in range(desk.get_child_count()):
        a = desk.get_child_at_index(i)
        try:
            if a and a.get_process_id() in mine:
                return a
        except Exception:
            continue
    return None


def buttons(app):
    R = Atspi.Role
    roles = {R.PUSH_BUTTON, R.BUTTON} if hasattr(R, "BUTTON") else {R.PUSH_BUTTON}
    found, todo = [], [(app, 0)]
    while todo and len(found) < 200:
        o, d = todo.pop()
        try:
            if o.get_role() in roles:
                name = (o.get_name() or "").strip()
                st = o.get_state_set()
                if name and st.contains(Atspi.StateType.SHOWING) and st.contains(Atspi.StateType.SENSITIVE):
                    found.append((name, o))
                continue
            if d < 25:
                for i in range(min(o.get_child_count(), 200)):
                    c = o.get_child_at_index(i)
                    if c:
                        todo.append((c, d + 1))
        except Exception:
            continue
    return found


def press(o):
    a = o.get_action_iface()
    if not a or not a.get_n_actions():
        return False
    names = [(a.get_action_name(i) or "").lower() for i in range(a.get_n_actions())]  # noqa
    idx = next((i for i, n in enumerate(names) if n in ("press", "click", "activate")), 0)
    return a.do_action(idx)


def main():
    pid = int(sys.argv[1])
    Atspi.init()
    pressed, last, same = [], None, 0
    for _ in range(ROUNDS):
        app = app_of(pid)
        if app is None:
            break
        try:
            app.clear_cache()
        except Exception:
            pass
        cands = [(n, o) for n, o in buttons(app) if not NEVER.search(n)]
        pick = None
        for pat in ORDER:
            pick = next(((n, o) for n, o in cands if pat.search(n)), None)
            if pick:
                break
        if not pick:
            break
        # The same buttons after a press: it changed nothing (PCSX2's Next
        # without a BIOS only raises a warning). Stop after two of those.
        sig = tuple(sorted(n for n, _ in cands))
        same = same + 1 if sig == last else 0
        last = sig
        if same >= 2:
            break
        try:
            if not press(pick[1]):
                break
        except Exception:
            break
        pressed.append(pick[0])
        time.sleep(1.2)
    print(json.dumps({"pressed": pressed}))


if __name__ == "__main__":
    main()
