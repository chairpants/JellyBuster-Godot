# JellyVault

A 90s video store to walk round, stocked from your own Jellyfin library. Every movie is a tape on the shelf, every
season of a show is a tape; pick one up, carry it to the theater in back, and it plays on the big screen.

The store is VaultBuster's (the web game), its shelves laid out the way VaultBuster lays them out: new releases round
the outer walls, kids' titles in the front corner by the windows, older movies and TV on the low shelving in the
middle, a section at a time, A to Z. A bigger library makes a deeper store.

## Running it

- [Godot 4.7](https://godotengine.org/) or later: open `project.godot`, press F5.
- `ffmpeg` on your PATH (it's what plays the video).
- A Jellyfin server, and an API key for it: in Jellyfin, Dashboard → API Keys → +.

The first time it starts it asks for the server's address and the API key, and remembers them (in Godot's user data
folder, `jellyfin.cfg`). F2 in the store asks again. Or pick the made-up library to look round without a server
(`godot --path . -- --demo`, or `--demo=5000` for a big one).

| Key | |
|---|---|
| WASD, mouse, Shift, Space, C | Walk, look, run, jump, crouch |
| Click | A tape off the shelf, held up to look at; again: in your hand; on its empty slot: back it goes. Right-click: put it back |
| 1-9, wheel | Which of the tapes you're carrying is in your hand |
| E | Doors, seats, light switches, lamps, ladders; at the theater's screen or the lounge TV, the tape in your hand goes in (again: out) |
| R | Turn the tape in your hand over: the back of the box, from Jellyfin (the blurb, the cast, the credits); again: the front |
| , . (held) / [ ] | Rewind / fast-forward (a bar shows where to; plays from there half a second after letting go); the episode before / after |
| Wheel, sat down | Zoom; all the way in on a screen that's playing, one more notch: the picture full screen (back out: the room) |
| F | Sat down with a tape on: full screen and back; stood up: fly. Held: the time and weather wheel (pick with the mouse) |
| L / M / J / H | Skip an hour / mute / fold the log / hide everything written on screen |
| F2 | The server settings |
| Esc | Free the mouse |

## Sections

`data/genres.json` is the store's sections, in the order they're laid out, and which of Jellyfin's genres go in each.
An item goes to the section that best fits its genres (its first genre counts most; a `strong` section, like Anime or
Documentary, wins whenever it matches). `kids` sections go in the kids' corner. `new_from` is the year from which a
movie's a new release, out on the walls. Edit it to taste.

## What's what

| File | |
|---|---|
| `jellyfin.gd` | The library (autoload `Library`): the settings, fetching, a tape per movie and per season, sorting into sections; covers, cached |
| `store.gd` | The shelves: the layout (walls, kids, centre), the gondolas, the signs; how deep the store has to be |
| `level.gd` | The level made that deep (autoload `Level`): what's past the lounge slides back, what crosses stretches |
| `tapes.gd` | Tapes on and off the shelves, in hand, into the theater's projector |
| `backbox.gd` | The back of a tape's box: Jellyfin's details laid out like a rental's, drawn once into a texture |
| `video.gd` | Plays a Jellyfin item through ffmpeg onto the screens |
| `world/world.scn`, `data/interact.json` | VaultBuster's level and where everything in it is |
| the rest | The player, doors, lights, the sky and weather, sound: VaultBuster's |

`godot --headless --path . --script tools/jellyfin_check.gd` checks the sections and the layout without a server.
`godot --path . -- --demo --shot --at=x,y,z,yaw,pitch` saves `shot.png` from there.
