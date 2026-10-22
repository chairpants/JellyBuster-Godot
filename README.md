# JellyVault

A 90s video store to walk round, stocked from your own Jellyfin library. Every movie is a tape on the shelf, every
season of a show is a tape; pick one up, carry it to the theater in back, and it plays on the big screen.

The store is VaultBuster's (the web game), its shelves laid out the way VaultBuster lays them out: new releases round
the outer walls, kids' titles in the front corner by the windows, older movies and TV on the low shelving in the
middle, a section at a time, A to Z. A bigger library makes a deeper store; a smaller one still gets VaultBuster's
whole store, the spare shelf space stocked with extra copies beside the originals (the newest releases most), the way a
rental store has a few of the hits.

## Running it

- [Godot 4.7](https://godotengine.org/) or later: open `project.godot`, press F5.
- `ffmpeg` on your PATH (it's what plays the video).
- A Jellyfin server, and an API key for it: in Jellyfin, Dashboard → API Keys → +.

The first time it starts it asks for the server's address and the API key, and remembers them (in Godot's user data
folder, `jellyfin.cfg`). F2 in the store asks again. Or pick the made-up library to look round without a server
(`godot --path . -- --demo`, or `--demo=5000` for a big one). If the server can't be reached, the store opens on the
library as it was last time (`library.json`): everything to look at, nothing to play, till F2 connects again.

What you watch is kept on Jellyfin as the user named in F2's **Watch as** (blank: whoever used Jellyfin last): a tape
starts where any Jellyfin app left off, and how far you've got goes back to the server. Tapes you've watched to the end
wear a SEEN IT sticker. The game keeps where you left everything (where you stood, the clock, the weather, the lights,
the doors, what you're carrying) and puts it back next time; the settings' NEW SHIFT forgets it all.

| Key | |
|---|---|
| WASD, mouse, Shift, Space, C | Walk, look, run, jump, crouch |
| Click | A tape off the shelf, held up to look at; again: in your hand; on its empty slot: back it goes. Right-click: put it back |
| 1-9, wheel | Which of the tapes you're carrying is in your hand |
| E | Doors, seats, light switches, lamps, ladders; at the theater's screen or the lounge TV, the tape in your hand goes in (again: out) |
| E on the register | The store's terminal: search for a title, browse a section, new arrivals, a staff pick you haven't seen; on a title, S lights its slot on the shelf, E (a season) lists its episodes to wind the tape to. Click to pick, right-click or Esc to go back |
| R | Turn the tape in your hand over: the back of the box, from Jellyfin (the blurb, the cast, the credits); again: the front |
| I | A new cover for the tape in your hand, from Jellyfin's providers (search by another name; IT'S THIS ONE re-identifies a wrong match); its SHELF moves it to another section |
| T / Y | Subtitles (each text track the film has, then off) / the next sound track: both remembered by language for the next film |
| , . (held) / [ ] | Rewind / fast-forward (a bar shows where to; plays from there half a second after letting go); the episode before / after |
| / | Pause the tape that's playing; again: play |
| Media keys | Play/pause, stop (pauses), previous / next episode. On Linux the desktop hands these over MPRIS, so they work with the game in the background too, and JellyVault shows up in the desktop's media controls (needs `python3` with PyGObject, which most desktops have) |
| Wheel, sat down | Zoom; all the way in on a screen that's playing, one more notch: the picture full screen (back out: the room) |
| F | Sat down with a tape on: full screen and back; stood up: fly. Held: the time and weather wheel (pick with the mouse) |
| L / M / J / H | Skip an hour / mute / fold the log / hide everything written on screen |
| P (or right-click sat down) | Settings: the picture, the volume, GRAPHICS (lighting effects, smooth edges, render scale, full screen), CONTROLS (field of view, mouse speed, invert Y), NEW SHIFT |
| F1 / F2 / F11 | The keys / the server settings / full screen |
| Esc | Free the mouse |

## Sections

`data/genres.json` is the store's sections, in the order they're laid out, and which of Jellyfin's genres go in each.
An item goes to the section that best fits its genres (its first genre counts most; a `strong` section, like Anime or
Documentary, wins whenever it matches). `kids` sections go in the kids' corner. `new_from` is the year from which a
movie's a new release, out on the walls. Edit it to taste.

## What's what

| File | |
|---|---|
| `jellyfin.gd` | The library (autoload `Library`): the settings, fetching, a tape per movie and per season, sorting into sections; covers, cached; what's been watched, and how far, to and from the server; subtitles |
| `store.gd` | The shelves: the layout (walls, kids, centre), the gondolas, the signs; how deep the store has to be |
| `level.gd` | The level made that deep (autoload `Level`): what's past the lounge slides back, what crosses stretches |
| `tapes.gd` | Tapes on and off the shelves, in hand, into the theater's projector |
| `backbox.gd` | The back of a tape's box: Jellyfin's details laid out like a rental's, drawn once into a texture |
| `video.gd` | Plays a Jellyfin item through ffmpeg onto the screens, its sound one gapless stream |
| `pos.gd` | The register's terminal (VaultBuster's POS/NET) |
| `covers.gd` | I: a new cover, a re-identify, another shelf |
| `save.gd` | Where everything was left, kept and put back |
| `picture.gd` | The settings (P) |
| `world/world.scn`, `data/interact.json` | VaultBuster's level and where everything in it is; its back reworked by `tools/remodel.gd` (the closet in, deeper back rooms, a taller theater with a projection booth upstairs) |
| the rest | The player, doors, lights, the sky and weather, sound: VaultBuster's |

`godot --headless --path . --script tools/jellyfin_check.gd` checks the sections, the layout and the subtitle reader without a server.
`godot --path . -- --demo --shot --at=x,y,z,yaw,pitch` saves `shot.png` from there (`--hour=h`, `--weather=rain|snow|fog`, `--lights` for every room's lights on, `--walk=s` to walk forward that long first and print where it got to).
`godot --path . --resolution 1400x1400 -s tools/plan.gd -- [--area=x0,z0,x1,z1] [--cut=y] [--out]` saves `plan.png`, the level from straight above with its roof off; `tools/inventory.gd` lists what's where in it.
`tools/shots.sh <name>` takes the same seven views every time into `shots/<name>/`, to compare before and after a change.
`godot --path . -- --demo --snapshot [--hour=h]` saves the store as the game built it to `baked/snapshot.scn`: open it in
the editor to look round everything the scripts make (a still to look at: edits to it don't go back into the game).
