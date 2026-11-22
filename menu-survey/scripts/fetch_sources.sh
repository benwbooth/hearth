#!/usr/bin/env bash
# Re-download the popularity sources and rebuild the nixpkgs inputs (data/raw,
# data/nixpkgs_meta.tsv). Then: fetch_desktop.py, rank_apps.py, classify.py,
# classify_flathub.py, menu-probe.py (see README).
set -euo pipefail
cd "$(dirname "$0")/../data"; mkdir -p raw; cd raw
curl -sS -o popcon_by_inst.gz https://popcon.debian.org/by_inst.gz
for i in $(seq 0 9); do curl -sS "https://pkgstats.archlinux.de/api/packages?limit=4000&offset=$((i*4000))" -o pkgstats_$i.json; done
for p in $(seq 1 15); do curl -sS "https://flathub.org/api/v2/collection/popular?page=$p&per_page=250" \
  | jq -c '.hits[] | {app_id,name,installs_last_month,runtime,developer_name,main_categories,is_free_license}'; done > flathub_popular.jsonl
nix-locate --regex '/share/applications/[^/]*\.desktop$' | awk '{print $1"\t"$NF}' > nixlocate_desktop.tsv
NP=$(nix eval --raw --inputs-from /etc/nixos nixpkgs#path)
NIXPKGS_ALLOW_UNFREE=1 systemd-run --user --scope --quiet -p MemoryMax=12G \
  nix-env -qa --json --meta -f "$NP" --arg config '{allowUnfree=true; allowAliases=false;}' > nixenv_all.json
python3 -I - <<'PY'
import json
d=json.load(open('nixenv_all.json'))
with open('../nixpkgs_meta.tsv','w') as out:
    for attr,v in d.items():
        m=v.get('meta',{}); lic=m.get('license',{}); lics=lic if isinstance(lic,list) else [lic]
        unfree=any(isinstance(l,dict) and l.get('free') is False for l in lics)
        plats=m.get('platforms') or []; linux=(not plats) or ('x86_64-linux' in plats)
        hp=m.get('homepage') or ''; hp=hp[0] if isinstance(hp,list) and hp else hp
        desc=(m.get('description') or '').replace('\t',' ').replace('\n',' ')
        out.write('\t'.join([attr,v.get('pname',''),v.get('version',''),'1' if unfree else '0','1' if m.get('broken') else '0','1' if linux else '0',m.get('mainProgram') or '',hp or '',desc])+'\n')
PY
