#!/usr/bin/env python3
"""Collect everything into one SQLite database and a per-app table.

data/survey.sqlite (rebuilt from scratch each run; the probe workers keep
appending JSONL, which is safe with several writers):
  apps        data/apps.tsv: rank, attr, source, popularity numbers, ...
  toolkit     data/classified.jsonl + data/toolkit_overrides.tsv
  shortcuts   data/shortcuts.jsonl (GTK apps with a shortcuts window)
  probes      every attempt from data/probe*.jsonl (one row per variant)
  results     view: one row per app -- today's outcome, the best lever, routes
data/results.tsv: the `results` view, for reading on GitHub.

Queries, e.g.:
  sqlite3 data/survey.sqlite "select toolkit, today, count(*) from results group by 1,2"
  sqlite3 data/survey.sqlite "select * from results where today='none' and best='full'"
"""
import csv
import glob
import json
import os
import sqlite3

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
DB = os.path.join(ROOT, "data", "survey.sqlite")


def outcome(r):
    if r.get("result") != "menus":
        return "none" if r.get("result") == "fallback" else r.get("result") or "none"
    tops = [m for m in r.get("menus", []) if not m.endswith(":0")]
    return "full" if len(tops) >= 2 else "burger"


def main():
    if os.path.exists(DB):
        os.unlink(DB)
    db = sqlite3.connect(DB)
    db.executescript("""
    create table apps (rank int, attr text primary key, include int, source text, kind text, pop real,
                       arch real, debian real, flathub_pct real, flathub_installs int, flathub text,
                       unfree int, store text, desktops text, aliases text, runtime text, note text, descr text);
    create table toolkit (attr text primary key, toolkit text, menu_hint text, electron text, via text,
                          override int, closure text, syms text);
    create table shortcuts (attr text primary key, shortcuts_window int, shortcut_items int, accelerators int,
                            primary_menu_ui int);
    create table probes (attr text, variant text, result text, outcome text, route text, menus text,
                         n_items int, window_title text, app_id text, app_menu text, gtk_menu text,
                         after_escape int, flatpak int, flatpak_talk text, via_flathub text, toolkit text,
                         shot text, error text, log_tail text, seq int);
    """)
    with open(os.path.join(ROOT, "data", "apps.tsv")) as f:
        rd = csv.DictReader(f, delimiter="\t", quoting=csv.QUOTE_NONE)
        for r in rd:
            db.execute("insert or ignore into apps values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                       (int(r["rank"]), r["attr"], int(r["include"]), r["source"], r["kind"], float(r["pop"]),
                        float(r["arch"]), float(r["debian"]), float(r["flathub_pct"]),
                        int(float(r["flathub_installs"] or 0)), r["flathub"], int(r["unfree"] == "1"),
                        r["store"], r["desktops"], r["aliases"], r["runtime"], r["note"], r["desc"]))
    tk = {}
    for l in open(os.path.join(ROOT, "data", "classified.jsonl")):
        j = json.loads(l)
        tk[j["attr"]] = (j["attr"], j.get("toolkit"), j.get("menu_hint"), j.get("electron", ""), j.get("via", ""), 0,
                         ",".join(j.get("closure") or []), ",".join(j.get("syms") or []))
    for l in open(os.path.join(ROOT, "data", "toolkit_overrides.tsv")):
        if l.strip() and not l.startswith("#"):
            attr, t = l.split("\t")[:2]
            old = tk.get(attr, (attr, None, "", "", "", 0, "", ""))
            tk[attr] = (attr, t, old[2], old[3], "override", 1, old[6], old[7])
    db.executemany("insert into toolkit values (?,?,?,?,?,?,?,?)", tk.values())
    fn = os.path.join(ROOT, "data", "shortcuts.jsonl")
    if os.path.exists(fn):
        for l in open(fn):
            j = json.loads(l)
            db.execute("insert or replace into shortcuts values (?,?,?,?,?)",
                       (j["attr"], int(bool(j.get("shortcuts_window"))), j.get("shortcut_items", 0),
                        j.get("accelerators", 0), int(bool(j.get("primary_menu_ui")))))
    seq = 0
    for fn in sorted(glob.glob(os.path.join(ROOT, "data", "probe*.jsonl"))):
        for l in open(fn):
            try:
                r = json.loads(l)
            except ValueError:
                continue
            seq += 1
            w = r.get("window") or {}
            db.execute("insert into probes values (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                       (r["attr"], r.get("variant"), r.get("result"), outcome(r), r.get("route"),
                        " | ".join(r.get("menus") or []), r.get("n_items"), w.get("title"), w.get("app_id"),
                        json.dumps(w.get("app_menu")) if w.get("app_menu") else None,
                        json.dumps(w.get("gtk_menu")) if w.get("gtk_menu") else None,
                        int(bool(r.get("after_escape"))), int(bool(r.get("flatpak"))),
                        ",".join(r.get("flatpak_talk") or []), r.get("via_flathub"), r.get("toolkit"),
                        r.get("shot"), r.get("error"), "\n".join(r.get("log_tail") or []), seq))
    db.executescript("""
    create view last_probe as
      select p.* from probes p join (select attr, variant, max(seq) s from probes group by 1, 2) m
        on p.attr = m.attr and p.variant = m.variant and p.seq = m.s;
    create view results as
      select a.rank, a.attr, a.source, round(a.pop, 3) as pop, t.toolkit,
             s.outcome as today, s.route as route_today, s.menus as menus_today,
             coalesce((select l.outcome from last_probe l where l.attr = a.attr and l.variant not in ('session')
                       and l.outcome in ('full', 'burger') order by l.outcome = 'full' desc limit 1), s.outcome) as best,
             (select l.variant from last_probe l where l.attr = a.attr and l.variant not in ('session')
                       and l.outcome in ('full', 'burger') order by l.outcome = 'full' desc limit 1) as lever,
             (select l.menus from last_probe l where l.attr = a.attr and l.variant not in ('session')
                       and l.outcome in ('full', 'burger') order by l.outcome = 'full' desc limit 1) as menus_lever,
             s.window_title, s.after_escape, s.flatpak, s.via_flathub,
             (select result from last_probe b where b.attr = a.attr and b.variant in ('build', 'exec', 'error')) as skipped,
             sc.shortcuts_window, a.note
        from apps a
        left join toolkit t on t.attr = a.attr
        left join last_probe s on s.attr = a.attr and s.variant = 'session'
        left join shortcuts sc on sc.attr = a.attr
       where a.include = 1
       order by a.rank;
    """)
    db.commit()
    cur = db.execute("select * from results")
    cols = [d[0] for d in cur.description]
    with open(os.path.join(ROOT, "data", "results.tsv"), "w") as f:
        f.write("\t".join(cols) + "\n")
        for row in cur:
            f.write("\t".join("" if v is None else str(v).replace("\t", " ").replace("\n", " ") for v in row) + "\n")
    n = db.execute("select count(*), sum(today is not null) from results").fetchone()
    print(f"{n[0]} apps, {n[1]} measured -> {DB}, data/results.tsv")


if __name__ == "__main__":
    main()
