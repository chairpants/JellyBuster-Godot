# JellyVault

VaultBuster's video store (`../VaultBusterGodot`) without the game: walk round it, take a tape off the shelf, put it
in the TV. The shelves are stocked from a Jellyfin library instead of archive.org.

Open `project.godot` in Godot 4.7 and press F5. Needs `ffmpeg` on the PATH (video.gd).

## Jellyfin

The first run writes `%APPDATA%\Godot\app_userdata\JellyVault\jellyfin.cfg`. Fill in the server and an API key
(Jellyfin Dashboard → API Keys):

```ini
[server]
url="http://192.168.1.10:8096"
api_key="..."
```

`godot --headless --path . --script tools/jellyfin_check.gd` checks the library's sort without a server.

## Kept from VaultBuster

The level (`world/world.scn`), player, clock, sky, weather, lights, room lighting, doors, seats, fixtures, loose
things, sound, the HUD, tapes and the VCR. Gone: customers, staff, checkout, register, phone, chores, snacks, shift,
cars, people, golf, arcade, menu, saves. The cover sheets and posters (`world/vaultbuster_133-150`, `166-187`) are
8×8 grey stand-ins: covers come from Jellyfin. `world.scn` can't be rebuilt from the web game here (the .glb is gone).

| Key | |
|---|---|
| WASD, mouse, Shift, Space, C | Walk, look, run, jump, crouch |
| Click | A tape off the shelf (again: in hand; on its empty slot: back) · right-click: put it back |
| E | Doors, seats, switches, lamps, ladders; at the TV, the tape in hand goes in (again: out) |
| 1-9, wheel | Which carried tape is in hand |
| [ ] / , . | Wind back/on 30 s / previous/next episode |
| L / F / M / J | Skip an hour / fly / mute / fold the log |

| File | |
|---|---|
| `jellyfin.gd` | Connects, fetches movies, series and episodes, sorts by genre then title, stocks the slots |
| `tapes.gd` | Tapes on and off the shelves, in hand, into the VCR (slots from `data/tapes.json`) |
| `video.gd` | Plays a Jellyfin item through ffmpeg onto the screens |
| the rest | As in VaultBuster's README |
