extends Node
## Where things were left: kept on the way out (and every half minute, in case it never gets a proper way out), put
## back as the store opens. You (where you stand or sit, which way you look, flying), the clock, the weather, the
## switches and lamps, the doors, what you're carrying and which is in hand, how far each tape's wound, the store
## sounds (M), the words on screen (H). The picture menu (picture.cfg) and the VCR (vcr.cfg) keep their own.
## reset() forgets all of it, those two as well, and opens the store fresh (the picture menu's NEW SHIFT).

const FILE := "user://state.cfg"
const EVERY := 30.0

@onready var main := get_parent()
var _t := 0.0
var _ready_to_save := false


func _ready() -> void:
	get_tree().auto_accept_quit = false  # (so the last state's kept before it goes: _notification)
	var args := OS.get_cmdline_user_args()
	if "--shot" in args or "--snapshot" in args:  # (the same views every time: not wherever someone last stood)
		return
	await get_tree().process_frame  # (everything's ready and the tapes are on their shelves)
	await get_tree().process_frame
	_load()
	_ready_to_save = true


func _process(dt: float) -> void:
	_t += dt
	if _t >= EVERY:
		_t = 0.0
		save()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		save()
		get_tree().quit()


func save() -> void:
	if not _ready_to_save:
		return
	var player: CharacterBody3D = main.get_node("Player")
	var interact: Node = main.get_node("Interact")
	var tapes: Node = main.get_node("Tapes")
	var lights: Node = main.get_node("Lights")
	var weather: Node = main.get_node("Weather")
	var cf := ConfigFile.new()
	var sat: bool = player.seat != null
	cf.set_value("you", "at", interact.stood_at.at if sat else player.global_position)  # (sat down: where you got up from, the seat's below)
	cf.set_value("you", "yaw", interact.stood_at.yaw if sat else player.rotation.y)
	cf.set_value("you", "pitch", player.get_node("Camera").rotation.x)
	cf.set_value("you", "seat", interact.seats.find(player.seat))
	cf.set_value("you", "fly", player.fly)
	cf.set_value("clock", "h", Clock.h)
	cf.set_value("clock", "day", Clock.day)
	for k in ["kind", "k", "wet", "cover", "drift", "fog", "clouds", "_forced", "severe"]:
		cf.set_value("weather", k, weather.get(k))
	cf.set_value("lights", "zones", lights.zone_on)
	cf.set_value("lights", "lamps", lights.lamps.map(func(l: Dictionary) -> bool: return l.on))
	cf.set_value("doors", "open", interact.doors.map(func(d: Dictionary) -> bool: return d.get("open", false)))
	cf.set_value("hands", "inv", tapes.inv.map(func(t: Dictionary) -> String: return t.id))
	cf.set_value("hands", "sel", tapes.inv_sel)
	var wound := {}  # tape id -> [episode, seconds in]: only the ones that have been played
	for t: Dictionary in tapes.tapes:
		if t.get("at", 0.0) > 0.0 or t.get("ep", 0) > 0:
			wound[t.id] = [t.get("ep", 0), t.get("at", 0.0)]
	cf.set_value("hands", "wound", wound)
	cf.set_value("doors", "locked", main.get_node("Things").locked)
	cf.set_value("screen", "muted", main.get_node("Ambience").muted)
	cf.set_value("screen", "hud", main.get_node("HUD").visible)
	cf.save(FILE)
	tapes._resume_save()  # (and the VCR, to the second)


func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(FILE) != OK:
		return
	var player: CharacterBody3D = main.get_node("Player")
	var interact: Node = main.get_node("Interact")
	var tapes: Node = main.get_node("Tapes")
	var lights: Node = main.get_node("Lights")
	var weather: Node = main.get_node("Weather")
	Clock.h = cf.get_value("clock", "h", Clock.h)
	Clock.day = cf.get_value("clock", "day", Clock.day)
	Clock.warp = 0.0
	for k in ["kind", "k", "wet", "cover", "drift", "fog", "clouds", "_forced", "severe"]:
		weather.set(k, cf.get_value("weather", k, weather.get(k)))
	var zones: Dictionary = cf.get_value("lights", "zones", {})
	for z: String in zones:
		if lights.zone_on.has(z):
			lights.put_zone(z, zones[z])
	var lamps: Array = cf.get_value("lights", "lamps", [])
	for i in mini(lamps.size(), lights.lamps.size()):
		lights.set_lamp(lights.lamps[i], lamps[i])
	lights._night_t = 100.0  # (the lot's lamps already warm, if it's night: they've been on)
	var doors: Array = cf.get_value("doors", "open", [])
	for i in mini(doors.size(), interact.doors.size()):
		if interact.doors[i].has("open"):
			interact.doors[i].open = doors[i]
	main.get_node("Things").set_locked(cf.get_value("doors", "locked", false))
	var by_id := {}
	for t: Dictionary in tapes.tapes:
		by_id[t.id] = t
	var wound: Dictionary = cf.get_value("hands", "wound", {})
	for id: String in wound:
		if by_id.has(id) and not (tapes.playing != null and tapes.playing.tape == by_id[id]):  # (the one in the VCR: vcr.cfg has it, to the second)
			by_id[id].ep = wound[id][0]
			by_id[id].at = wound[id][1]
	for id: String in cf.get_value("hands", "inv", []):
		if by_id.has(id) and not by_id[id].get("off", false):  # (a library that's changed since: gone, or in the VCR)
			tapes.set_on_shelf(by_id[id], false)
			tapes.inv.append(by_id[id])
	tapes.inv_select(cf.get_value("hands", "sel", -1))
	player.fly = cf.get_value("you", "fly", false)
	player.get_node("Shape").disabled = player.fly
	player.stand(cf.get_value("you", "at", player.global_position) + Vector3(0, 0.05, 0), cf.get_value("you", "yaw", player.rotation.y))  # (a hair up: never put back a step under the floor)
	player.get_node("Camera").rotation.x = cf.get_value("you", "pitch", 0.0)
	var seat: int = cf.get_value("you", "seat", -1)
	if seat >= 0 and seat < interact.seats.size():
		interact.stood_at = { "at": player.global_position, "yaw": player.rotation.y }
		player.sit(interact.seats[seat])
	var amb: Node = main.get_node("Ambience")
	amb.muted = cf.get_value("screen", "muted", false)
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Store"), amb.muted)
	main.get_node("HUD").visible = cf.get_value("screen", "hud", true)
	print("save: back where you left it, %s day %d" % [Clock.fmt_clock(Clock.h), Clock.day])


func reset() -> void:  # everything forgotten, the store opened fresh
	_ready_to_save = false
	for f in [FILE, "user://picture.cfg", "user://vcr.cfg"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
	Clock.h = Clock.START
	Clock.day = 1
	Clock.warp = 0.0
	main.get_node("Tapes").playing = null  # (else it writes the VCR's file again on its way out)
	main.get_node("Video").stop()
	get_tree().reload_current_scene()
