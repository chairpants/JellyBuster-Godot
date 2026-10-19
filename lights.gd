extends Node
## The store's lights: nine zones, each on its own switch, fluorescents that stutter before they strike; and the two
## side lamps by the couch.
## From the web game: store/lounge.js (zoneOn, zoneLvl, setZone, lightingTick, buildFlickerSchedule, flickerLit),
## store/clock.js (flipSwitch), store/tv.js (setLamp), and the room shader in store/core.js (ROOM_FRAG) for which
## zone lights where: the sales floor is three zones along z (front to 10 m, aisles to 19, lounge behind), the back of
## house is the hall, the break room and the restroom, then the theater's lobby and its auditorium (both start off).
## The switches, the zones' rooms and the lamps are the web game's, from data/interact.json.
##
## What a zone's level does to the room is room.gd's business. The real lights are here: the lamps, daylight coming
## in through the storefront (so the back of a dark store is dark, and darker where something's in the way), and the
## screens, which light the room with the colour of the frame on them (SpaceLife's wall TV did the same).
## And light through a doorway (not the web game's, where a room's light stops dead at its walls): wherever two rooms
## meet at a door, or at a gap in the sales floor's back wall, the brighter one spills into the darker, as far as the
## door's open, with what's in the way throwing a shadow.

var zone_on := {}  # zone -> bool
var zone_lvl := {}  # zone -> 0..1, flickering while the tubes warm up (what the lights get)
var names := {}
var switches: Array = []
var lamps: Array = []

var _warm := {}  # zone -> { t, duration, schedules } while its tubes restrike
var _windows: Array[SpotLight3D] = []  # daylight (or the night) in through the storefront glass
var _glows: Array[Light3D] = []  # the screens: lit with the colour of what's on them
var _glow := Color.BLACK
var _panels := {}  # zone -> [the material of each ceiling panel in it]
var _boxes := {}
var plates := {}  # zone -> the zones that share its switch plate
var closet := {}  # the bare bulb's pull, and the bulb
var _bulb: StandardMaterial3D
var _night: Array[Dictionary] = []  # the lot's lamps and the street's: { light, on, delay, sodium }
var _night_t := -1.0  # seconds since dusk while the lot's lamps warm up (-1: it's day)
var _zoned: Array[Dictionary] = []  # the few real lights that are on a switch
var _portals: Array[Dictionary] = []  # doorways: { light, at, n, a, b (the zones either side), door (interact.gd's, or null: always open) }

@onready var sky: Node3D = $"../Sky"
@onready var video: Node = $"../Video"
const WINDOWS := 5  # lights along the storefront
const SODIUM := 72.0  # the lot lamps' strength once they're warm (the web game's)
const SODIUM_WARM := 5.0  # seconds to get there, from a cold orange
const BULB_ON := Color(1.0, 0.949, 0.769)  # 0xfff2c4
const BULB_OFF := Color(0.227, 0.22, 0.2)  # 0x3a3833
const DAYLIGHT := 1.5  # how strong each is at noon
const SCREEN_GAIN := 7.0  # the TV's light, for a full-white frame
const PANEL_ON := Color(1.31, 1.33, 1.35)  # 0xf8fbff, and brighter than white: a lit panel blooms (room.gd)
const SPILL := 0.55  # light through a doorway, for a fully lit room next to a dark one
const ZONE_K := { "closet": 0.8, "theater": 0.3 }  # how bright a room is with its light on, next to the rest (room.gd's shader)
const ZONE_TINT := { "closet": Color(1.0, 0.85, 0.66), "lobby": Color(1.0, 0.86, 0.74), "theater": Color(1.0, 0.71, 0.48) }
const PANEL_COLD := Color(0.188, 0.204, 0.239)  # 0x30343d: between stutters
const PANEL_OFF := Color(0.051, 0.063, 0.086)  # 0x0d1016


func _ready() -> void:
	_find_rockers.call_deferred()
	var d: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/interact.json")).lights
	names = d.names
	switches = d.switches
	for zone: String in d.zones:
		zone_on[zone] = d.zones[zone]
		zone_lvl[zone] = 1.0 if zone_on[zone] else 0.0
	var all: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/interact.json"))
	_boxes = d.boxes
	plates = d.plates
	closet = d.closet
	if closet.bulb != null:
		for mi: MeshInstance3D in $"../World".find_children("*", "MeshInstance3D", true, false):
			if mi.global_position.distance_to(Vector3(closet.bulb[0], closet.bulb[1], closet.bulb[2])) < 0.01 and mi.mesh.surface_get_material(0) is StandardMaterial3D:
				_bulb = mi.mesh.surface_get_material(0).duplicate()
				mi.set_surface_override_material(0, _bulb)
	# the scene's own lights (store/theater.js, exterior/lot.js): the one on a switch, and those that only come on at night
	for s: Dictionary in d.scene:
		var at := Vector3(s.p[0], s.p[1], s.p[2])
		var mine := false
		for lp: Dictionary in d.lamps:
			mine = mine or at.distance_to(Vector3(lp.p[0], lp.p[1], lp.p[2])) < 0.01
		if mine or (s.zone == null and s.kind == "point" and s.on == 0.0):
			continue  # (the side lamps are below; the screens' glows are the screens' business)
		var l: Light3D
		if s.kind == "spot":
			var sp := SpotLight3D.new()
			sp.spot_range = s.range
			sp.spot_angle = rad_to_deg(s.angle)
			sp.position = at
			sp.basis = Basis.looking_at((Vector3(s.to[0], s.to[1], s.to[2]) - at).normalized(), Vector3.FORWARD)
			l = sp
		else:
			var om := OmniLight3D.new()
			om.omni_range = s.range
			om.position = at
			l = om
		l.light_color = Color.hex((int(s.color) << 8) | 0xff)
		l.light_specular = 0.0
		l.light_energy = 0.0
		l.light_volumetric_fog_energy = 1.0 if s.kind == "spot" and s.zone == null else 0.0  # (the lot's lamps: a cone in the night air)
		add_child(l)
		# three's candela to Godot's energy, matched a few metres out (three falls off by the square, Godot to its range)
		var ref: float = minf(s.range / 3.0, 5.0)
		var full: float = (SODIUM if s.kind == "spot" else s.on) / (PI * ref * ref) / (1.0 - ref / s.range)
		if s.zone != null:
			_zoned.append({ "light": l, "on": full, "zone": s.zone })
		else:
			_night.append({ "light": l, "on": full, "delay": 0.0, "sodium": s.kind == "spot" })
	# the ceiling's light panels: flat, white and unlit, up under a ceiling, a few meshes to a zone. Each gets a material
	# of its own, to go dark with its zone's switch and stutter back on with it (the web game's panelMats)
	for zone: String in zone_on:
		_panels[zone] = []
	for mi: MeshInstance3D in $"../World".find_children("*", "MeshInstance3D", true, false):
		if mi.mesh == null or mi.mesh.get_surface_count() != 1:
			continue
		var m := mi.mesh.surface_get_material(0)
		var box := mi.global_transform * mi.get_aabb()
		if not m is StandardMaterial3D or m.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED or m.albedo_color.v < 0.85 or m.albedo_color.s > 0.12:
			continue
		if box.size.y > 0.06 or box.position.y < 2.3:  # (a zone's panels are one mesh, or a few: flat, and up at the ceiling)
			continue
		var zone := zone_at(box.get_center())
		if zone == "":
			continue
		var own: StandardMaterial3D = m.duplicate()
		mi.set_surface_override_material(0, own)
		own.albedo_color = PANEL_ON if zone_on[zone] else PANEL_OFF
		_panels[zone].append(own)
	var f: Array = d.boxes.floor  # the sales floor: x0, x1, back wall z, ceiling
	for i in WINDOWS:  # along the glass, just inside it, shining back into the store: what's in the way throws a shadow
		var w := SpotLight3D.new()
		w.position = Vector3(lerpf(f[0], f[1], (i + 0.5) / WINDOWS), 2.0, 0.45)
		w.basis = Basis.looking_at(Vector3(0, -0.1, 1).normalized())
		w.spot_range = 36.0
		w.spot_angle = 80.0
		w.spot_attenuation = 1.4  # (fading toward the back, as the web game's does)
		w.light_specular = 0.0
		w.shadow_enabled = true
		w.light_volumetric_fog_energy = 0.5  # (shafts in from the storefront)
		add_child(w)
		_windows.append(w)
	for sc: Dictionary in all.screens:  # the TV and the theater's screen: out into the room they face, with shadows
		var g := SpotLight3D.new()
		var dir := Vector3(sin(sc.ry), 0, cos(sc.ry))
		g.position = Vector3(sc.x, sc.y, sc.z) + dir * 0.1
		g.basis = Basis.looking_at(dir)
		g.spot_range = 24.0 if sc.kind == "tv" else 15.0
		g.spot_angle = 82.0
		g.spot_attenuation = 1.2
		g.light_specular = 0.0
		g.shadow_enabled = true
		g.set_meta("gain", SCREEN_GAIN * (sc.w * sc.h) / 2.16)  # (a bigger screen's more light: the TV's is 1.8 x 1.2)
		add_child(g)
		_glows.append(g)
	for m: Dictionary in all.minis:  # the monitors over the aisles: a little pool under each
		var g := OmniLight3D.new()
		g.position = Vector3(m.p[0], m.p[1], m.p[2]) + Basis(Quaternion(m.q[0], m.q[1], m.q[2], m.q[3])).z * 0.25
		g.omni_range = 4.5
		g.light_specular = 0.0
		g.light_volumetric_fog_energy = 0.0
		g.set_meta("gain", SCREEN_GAIN * 0.12)
		add_child(g)
		_glows.append(g)
	for lp: Dictionary in d.lamps:  # the side lamps: mood lighting only, barely past their own pool
		var l := OmniLight3D.new()
		l.position = Vector3(lp.p[0], lp.p[1], lp.p[2])
		l.omni_range = lp.range
		l.light_color = Color.hex((int(lp.color) << 8) | 0xff)
		l.light_specular = 0.0
		l.light_volumetric_fog_energy = 0.4
		add_child(l)
		var shades := []  # its shade and bulb: what glows on it, to go out with it
		for mi: MeshInstance3D in $"../World".find_children("*", "MeshInstance3D", true, false):
			var c := mi.global_transform * mi.get_aabb().get_center()
			if mi.mesh != null and Vector2(c.x - l.position.x, c.z - l.position.z).length() < 0.3 and absf(c.y - l.position.y) < 0.45:
				for s in mi.mesh.get_surface_count():
					var m := mi.mesh.surface_get_material(s)
					if m is ShaderMaterial and m.get_shader_parameter("emission") != null and m.get_shader_parameter("emission") != Vector3.ZERO:
						shades.append([m, m.get_shader_parameter("emission")])
		lamps.append({ "light": l, "on": lp.on, "at": l.position, "energy": lp.energy * 1.6, "shades": shades })
		l.light_energy = lp.energy * 1.6 if lp.on else 0.0
	_find_portals.call_deferred(all.doors)


func _find_portals(door_list: Array) -> void:  # (after the level's been made solid: the gaps in the back wall are felt for)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var found: Array = []  # [center, normal, door or null]
	var live: Array = $"../Interact".doors
	for d: Dictionary in door_list:
		var at := Vector3(d.c, 0, d.at) if d.alongX else Vector3(d.at, 0, d.c)
		var mine: Array = live.filter(func(q: Dictionary) -> bool: return is_equal_approx(q.x, d.x) and is_equal_approx(q.z, d.z))
		if mine.size():
			found.append([at, Vector3(0, 0, 1) if d.alongX else Vector3(1, 0, 0), mine[0]])
	var f: Array = _boxes.floor
	var space := get_viewport().world_3d.direct_space_state
	var run0 := NAN
	var x: float = f[0] + 0.2
	while x < f[1]:  # the sales floor's back wall, a step at a time: where nothing's in the way for a doorway's width, that's one
		var open: bool = x < f[1] - 0.25 and space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 1.0, f[2] - 0.5), Vector3(x, 1.0, f[2] + 0.5))).is_empty()
		if open and is_nan(run0):
			run0 = x
		elif not open and not is_nan(run0):
			if x - run0 >= 0.7:
				found.append([Vector3((run0 + x - 0.1) / 2.0, 0, f[2]), Vector3(0, 0, 1), null])
			run0 = NAN
		x += 0.1
	for p: Array in found:
		var a := zone_at(p[0] - p[1] * 0.7)
		var b := zone_at(p[0] + p[1] * 0.7)
		if a == "" or b == "" or a == b:
			continue
		var l := SpotLight3D.new()
		l.spot_range = 6.5
		l.spot_angle = 75.0
		l.spot_attenuation = 1.3
		l.light_specular = 0.0
		l.light_energy = 0.0
		l.light_volumetric_fog_energy = 0.3
		l.shadow_enabled = _fancy
		l.visible = false
		add_child(l)
		_portals.append({ "light": l, "at": p[0], "n": p[1], "a": a, "b": b, "door": p[2] })
	print("lights: %d doorways for light to come through" % _portals.size())


var _fancy := true


func fancy(on: bool) -> void:  # (room.gd's: the doorways' light stays, their shadows go)
	_fancy = on
	for p in _portals:
		p.light.shadow_enabled = on


func set_zone(zone: String, on: bool) -> void:
	zone_on[zone] = on
	if on:
		var duration := 1.1 + randf() * 0.6
		var schedules := []
		for i in maxi(1, _panels[zone].size()):
			schedules.append(_flicker_schedule(duration))
		_warm[zone] = { "t": 0.0, "duration": duration, "schedules": schedules }
	else:
		_warm.erase(zone)
		zone_lvl[zone] = 0.0
		for p: StandardMaterial3D in _panels[zone]:
			p.albedo_color = PANEL_OFF


var _rockers: Array = []  # each switch's rocker, in the level: [node, zone, the angle it sits at flat]


func _find_rockers() -> void:  # the smallest thing right at each switch
	for s: Dictionary in switches:
		var at := Vector3(s.p[0], s.p[1], s.p[2])
		var best: MeshInstance3D = null
		for mi: MeshInstance3D in $"../World".find_children("*", "MeshInstance3D", true, false):
			if mi.global_position.distance_to(at) < 0.03 and (best == null or mi.get_aabb().get_longest_axis_size() < best.get_aabb().get_longest_axis_size()):
				best = mi
		if best != null:
			best.rotation_order = EULER_ORDER_XYZ
			_rockers.append([best, s.zone])
	if _rockers.size() != switches.size():
		push_warning("light switches: %d of %d rockers found in the level" % [_rockers.size(), switches.size()])


func flip_switch(zone: String) -> void:
	set_zone(zone, not zone_on[zone])


func flip_plate(zone: String) -> void:  # the whole plate at once: all on, unless the first is (then all off)
	var on: bool = not zone_on[plates[zone][0]]
	for z: String in plates[zone]:
		if zone_on[z] != on:
			set_zone(z, on)


func zone_at(p: Vector3) -> String:  # which switch lights this spot ("" outdoors): the room shader's boxes
	var f: Array = _boxes.floor
	var b: Array = _boxes.boh
	var lo: Array = _boxes.lobby
	var th: Array = _boxes.theater
	if p.x > f[0] and p.x < f[1] and p.z > -0.05 and p.z < f[2]:
		return "front" if p.z < 10.0 else "aisles" if p.z < 19.0 else "lounge"
	if p.x > b[0] and p.x < b[1] and p.z >= f[2] and p.z < b[3] and (p.z < b[2] or p.x < f[1]):
		if p.x > f[1]:
			return "closet"
		return "hall" if p.z < b[2] else "breakroom" if p.x < _boxes.bohSplit[0] else "restroom"
	if p.x > lo[0] and p.x < lo[1] and p.z >= lo[2] and p.z < lo[3]:
		return "lobby"
	if p.x > th[0] and p.x < th[1] and p.z >= th[2] and p.z < th[3]:
		return "theater"
	return ""


func set_lamp(lamp: Dictionary, on: bool) -> void:
	lamp.on = on
	lamp.light.light_energy = lamp.energy if on else 0.0
	for s: Array in lamp.shades:
		s[0].set_shader_parameter("emission", s[1] if on else Vector3.ZERO)


func _flicker_schedule(duration: float) -> Array:  # when one tube's lit while it's warming up: [[on, off], ...]
	if randf() > 0.4:
		return [[randf() * 0.5, duration]]  # comes on cleanly, just staggered
	var pulses := []
	var t := randf() * 0.15
	for i in 2 + randi() % 3:  # 2-4 stutters before it strikes
		var on := t + 0.03 + randf() * 0.12
		pulses.append([t, on])
		t = on + 0.05 + randf() * 0.22
	pulses.append([t, duration])
	return pulses


func _process(dt: float) -> void:  # fluorescents restriking, tube by tube (lightingTick)
	for r: Array in _rockers:  # the rocker snaps up / down with its zone (main.js)
		r[0].rotation.x += ((-0.32 if zone_on[r[1]] else 0.32) - r[0].rotation.x) * minf(1.0, dt * 25.0)
	var day: Vector3 = sky.day_c * sky.level + Vector3(0.035, 0.045, 0.08) * (1.0 - sky.level)  # what comes in through the glass: daylight, or moonlight and the lot's lamps
	for w in _windows:
		w.light_color = Color(day.x, day.y, day.z).linear_to_srgb()
		w.light_energy = DAYLIGHT
	if _bulb:
		_bulb.albedo_color = BULB_ON if zone_on.closet else BULB_OFF
	for z: Dictionary in _zoned:
		z.light.light_energy = z.on * zone_lvl[z.zone]
	# lamps and lot lights from dusk on: the park's lamp straight on, the lot's sodiums each after its own delay, a slow
	# start from a cold orange, then climbing to full
	var night: bool = sky.level <= 0.5
	if night and _night_t < 0.0:
		_night_t = 0.0
		for n in _night:
			n.delay = 1.2 + randf() * 1.3
	elif not night:
		_night_t = -1.0
	if _night_t >= 0.0:
		_night_t += dt
	for n in _night:
		var k := 0.0
		if _night_t >= 0.0:
			k = clampf((_night_t - n.delay) / SODIUM_WARM, 0.0, 1.0) if n.sodium else 1.0
		n.light.light_energy = n.on * k * k
		if n.sodium:
			n.light.light_color = Color(1.0, 0.302, 0.102).lerp(Color(1.0, 0.682, 0.29), k)  # 0xff4d1a to 0xffae4a
	for p in _portals:  # through each doorway, from the brighter room into the darker, as far as the door's open
		var la: float = zone_lvl[p.a] * ZONE_K.get(p.a, 1.0)
		var lb: float = zone_lvl[p.b] * ZONE_K.get(p.b, 1.0)
		var open: float = 1.0 if p.door == null else clampf(absf(p.door.a) / 1.0, 0.0, 1.0)
		var l: SpotLight3D = p.light
		l.light_energy = SPILL * absf(la - lb) * open
		l.visible = l.light_energy > 0.004
		if l.visible:
			var into: Vector3 = p.n if la > lb else -p.n
			l.position = p.at + Vector3(0, 2.0, 0) + into * 0.15
			l.basis = Basis.looking_at((into * 0.8 + Vector3.DOWN * 0.6).normalized())
			l.light_color = ZONE_TINT.get(p.a if la > lb else p.b, Color.WHITE)
	_glow = _glow.lerp(video.tint, minf(1.0, dt * 6.0))  # the light chases the picture
	for g in _glows:
		g.light_color = _glow
		g.light_energy = g.get_meta("gain")
		g.visible = _glow.v > 0.004
	for zone: String in _warm.keys():
		var w: Dictionary = _warm[zone]
		w.t += dt
		var done: bool = w.t >= w.duration
		var lit := 0
		for k in w.schedules.size():
			var s: Array = w.schedules[k]
			var on: bool = done or s.any(func(p: Array) -> bool: return w.t >= p[0] and w.t < p[1])
			lit += int(on)
			if k < _panels[zone].size():
				_panels[zone][k].albedo_color = PANEL_ON if on else PANEL_COLD
		zone_lvl[zone] = float(lit) / w.schedules.size()
		if done:
			_warm.erase(zone)
