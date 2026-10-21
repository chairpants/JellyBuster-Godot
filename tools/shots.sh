#!/usr/bin/env bash
# The same views every time, to see what a change did: shots/<set>/<view>.png (each one a run of the game's --shot)
#     tools/shots.sh baseline        then, after a change:  tools/shots.sh after
# The demo library (959 tapes), so the store's always the same depth: 6.2 m shallower than VaultBuster's, past SEAM (level.gd)
set -eu
cd "$(dirname "$0")/.."
SET="${1:-now}"
mkdir -p "shots/$SET"
VIEWS=(  # name  x,y,z,yaw,pitch  hour
	"front_day     1.8,1.6,-9,180,2      14"
	"front_night   1.8,1.6,-9,180,2      22"
	"entrance      1.8,1.6,1.5,180,-8    14"
	"aisles_day    -3,1.6,8,180,-5       14"
	"aisles_night  -3,1.6,8,180,-5       22"
	"lounge_tv     0,1.6,16.5,180,-4     20"
	"theater       -2.87,1.4,32.5,180,3  20"
)
for v in "${VIEWS[@]}"; do
	read -r name at hour <<<"$v"
	rm -f shot.png
	timeout 90 godot --path . --resolution 1280x720 -- --demo --shot --at="$at" --hour="$hour" >/dev/null 2>&1 || true
	if [[ -f shot.png ]]; then mv shot.png "shots/$SET/$name.png"; echo "shots/$SET/$name.png"; else echo "$name: no shot" >&2; fi
done
