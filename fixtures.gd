extends Node
## The fixed things E works: the counter's pass-through, the light switches, the side lamps, and the two ladders to
## the roof (the closet's, up through the hatch; the one out back, once it's been kicked down from up there).
## From the web game: store/player.js (toggleFlap) and store/main.js (the leaf lifting, the gate swinging in),
## store/clock.js (flipSwitch), store/tv.js (setLamp), store/roof.js (roofClimb, backLadderE, backLadderDrop, the
## climb in roofTick), store/checkout.js (how near: 2.6 m for the flap and a lamp, 2.2 for a switch and a ladder
## from the ground, 2.4 from the roof; the words of the tips). Where they all are: data/interact.json.
## A tap on a switch flips its own zone; held, the whole plate (flipPlate).
## Different here: the counter's pass-through has no leaf over it, and its gate's a swinging one on a spring hinge,
## like the theater's doors: whoever walks through pushes it away from them, and it swings shut behind them.
## The hatch's lid only lifts while you're on the ladder (open, you could walk into the hole); and a
## thing's found by where the crosshair lands near it, not by the mesh it hits.

var flap := {}
var ladders := {}
var aim := ""  # "flap" | "switch" | "lamp" | "hatch" | "back" | ""
var aim_what = null  # the switch or the lamp
var flap_open := false
var back_down := false

var _flap_pivot: Node3D
var _flap_gate: Node3D
var _lid: Node3D
var _slide: Node3D  # the back ladder's bottom half
var _slide_v := 0.0

@onready var player: CharacterBody3D = $"../Player"
@onready var lights: Node = $"../Lights"
@onready var hud: CanvasLayer = $"../HUD"


func _ready() -> void:
	var d: Dictionary = Level.data()
	flap = d.flap
	ladders = d.ladders
	for n: Node3D in $"../World".find_children("*", "Node3D", true, false):
		if n is MeshInstance3D or n.get_child_count() == 0:
			continue
		var p := n.global_position
		if p.distance_to(_v(flap.pivot)) < 0.02:
			_flap_pivot = n
		elif p.distance_to(_v(flap.gate)) < 0.02:
			_flap_gate = n
		elif p.distance_to(_v(ladders.hatch.lid)) < 0.02:
			_lid = n
		elif p.distance_to(Vector3(0, ladders.back.raise, Level.dz)) < 0.02 and n.get_child_count() >= 8:  # (out back: moved with the store's depth, level.gd)
			_slide = n
	if _flap_pivot:  # no leaf over the pass-through: it's an open gap in the counter, gate and all
		_flap_pivot.visible = false
		$"../Interact".no_collide.append(_flap_pivot)  # (main.gd makes the level solid after this: not these)
	if _flap_gate:  # ...and the gate swings out of the way of whoever's walking through (it doesn't stop them)
		_flap_gate.rotation_order = EULER_ORDER_YXZ
		$"../Interact".no_collide.append(_flap_gate)
	for what in [["the counter's leaf", _flap_pivot], ["its gate", _flap_gate], ["the hatch's lid", _lid], ["the back ladder", _slide]]:
		if what[1] == null:
			push_warning("%s isn't where the web game has it in the level (moved, or deleted?)" % what[0])


func _v(a: Array) -> Vector3:
	return Vector3(a[0], a[1], a[2])


func on_roof() -> bool:
	return player.global_position.y > ladders.roofY - 0.6


func _process(dt: float) -> void:
	if _flap_gate:
		_gate_tick(dt)
	if _lid:
		_lid.rotation.x += ((-ladders.hatch.lidA if player.climb != null and player.climb.L == ladders.hatch.climb else 0.0) - _lid.rotation.x) * minf(1.0, dt * 2.5)
	if _slide and back_down and _slide.position.y > 0.0:  # the back ladder coming down: it falls
		_slide_v += 14.0 * dt
		_slide.position.y = maxf(0.0, _slide.position.y - _slide_v * dt)


# ---- what the crosshair's on (called from interact.gd, after the doors); returns the tip, "" if it's nothing of ours

func take_aim(from: Vector3, dir: Vector3, hit: Dictionary, hit_d: float) -> String:
	aim = ""
	aim_what = null
	var roof := on_roof()
	# the ladders: the crosshair near the rungs' line (or, from up top, near where they come over the edge)
	var h: Dictionary = ladders.hatch
	var b: Dictionary = ladders.back
	if roof:
		if _near_ray(from, dir, _v(h.lid) + Vector3(0, -0.2, 0.3), 0.55, 2.4, hit_d):
			aim = "hatch"
			return "E — climb back down"
		if _near_ray(from, dir, Vector3(b.x - 0.2, ladders.roofY + 1.4, b.z), 0.5, 2.4, INF):
			aim = "back"
			return "E — climb down the back ladder" if back_down else "E — kick the ladder down\nit's latched up, out of reach from the ground"
	else:
		if _near_line(from, dir, h.x, h.z, 0.3, ladders.roofY - 0.1, 0.3, 2.2, hit_d):
			aim = "hatch"
			return "E — climb up to the roof"
		if _near_line(from, dir, b.x, b.z, 0.2, 2.8, 0.3, 2.6, hit_d):
			aim = "back"
			return "E — climb up to the roof" if back_down else "A ladder to the roof\npulled up, out of reach"
	if not hit:
		return ""
	var at: Vector3 = hit.position
	if hit_d < 2.2:  # a light switch: the rocker nearest where the crosshair lands
		var best := 0.05
		for s: Dictionary in lights.switches:
			if at.distance_to(_v(s.p)) < best:
				best = at.distance_to(_v(s.p))
				aim = "switch"
				aim_what = s
		if aim == "" and at.distance_to(_v(lights.closet.at)) < 0.4:  # the closet's bare bulb: it, or its chain
			aim = "switch"
			aim_what = { "zone": "closet" }
		if aim == "switch":
			return "E — turn the %s lights %s" % [lights.names[aim_what.zone], "off" if lights.zone_on[aim_what.zone] else "on"]
	if hit_d < 2.6:
		for l: Dictionary in lights.lamps:  # a lamp: its shade, or the stand under it
			if Vector2(at.x - l.at.x, at.z - l.at.z).length() < 0.4 and at.y < l.at.y + 0.4:
				aim = "lamp"
				aim_what = l
				return "E — turn lamp %s" % ("off" if l.on else "on")
	return ""


func _near_ray(from: Vector3, dir: Vector3, p: Vector3, off: float, reach: float, hit_d: float) -> bool:
	var t := (p - from).dot(dir)
	return t > 0.2 and t < reach and t < hit_d + 0.5 and (p - from - dir * t).length() < off


func _near_line(from: Vector3, dir: Vector3, x: float, z: float, y0: float, y1: float, off: float, reach: float, hit_d: float) -> bool:
	var flat := Vector2(dir.x, dir.z)  # where the ray passes the rungs' line, seen from above
	if flat.length() < 0.05:
		return false
	var t := (Vector2(x - from.x, z - from.z).dot(flat)) / flat.length_squared()
	var p := from + dir * t
	return t > 0.2 and t < reach and t < hit_d + 0.5 and Vector2(p.x - x, p.z - z).length() < off and p.y > y0 and p.y < y1


func holdable() -> bool:  # E held on a switch that shares its plate: the whole plate
	return aim == "switch" and lights.plates[aim_what.zone].size() > 1


func hold_done() -> void:
	if holdable():
		lights.flip_plate(aim_what.zone)


# the gate: pushed from whichever side they come at it (you, the staff), it swings away from them, quick and firm,
# and once the gap's clear it springs back, swinging past shut a few times (interact.gd's push doors: the same spring)

var gate := { "a": 0.0, "v": 0.0, "side": 0, "moving": false }


func _gate_tick(dt: float) -> void:
	dt = minf(dt, 0.05)
	var c: Dictionary = flap.box
	var mid_z: float = (c.z0 + c.z1) / 2.0
	var who: Array = [player.global_position]
	var near = null
	for p: Vector3 in who:
		if p.x > c.x0 - 0.1 and p.x < c.x1 + 0.1 and absf(p.z - mid_z) < 0.8 and p.y < 2.2:
			near = p
			break
	if near != null:
		if gate.side == 0:
			gate.side = 1 if near.z > mid_z else -1  # away from them: in behind the counter, or out to the lobby; held that way till the gap's clear
			if absf(gate.a) < 0.15:
				$"../Ambience".door("push", "open", _flap_gate.global_position + Vector3(0.8, 1.0, 0.0))
	else:
		gate.side = 0
	var target: float = flap.gateA * 0.95 * gate.side
	gate.v += ((90.0 if gate.side else 30.0) * (target - gate.a) - (16.0 if gate.side else 2.2) * gate.v) * dt  # pushed: quick and firm; let go: a loose spring
	gate.a += gate.v * dt
	if absf(gate.v) > 0.4:
		gate.moving = true
	if gate.side == 0 and absf(gate.a) < 0.002 and absf(gate.v) < 0.01:
		gate.a = 0.0
		gate.v = 0.0
		if gate.moving:
			gate.moving = false
			$"../Ambience".door("push", "settle", _flap_gate.global_position + Vector3(0.8, 1.0, 0.0))
	_flap_gate.rotation.y = gate.a
	$"../Ambience".swing(_flap_gate, _flap_gate.global_position + Vector3(0.8, 1.0, 0.0), absf(gate.v))


func on_e() -> bool:  # true if E was ours
	match aim:
		"flap":
			var c: Dictionary = flap.box
			var p := player.global_position
			if flap_open and p.x > c.x0 - 0.32 and p.x < c.x1 + 0.32 and p.z > c.z0 - 0.32 and p.z < c.z1 + 0.32:
				return true  # trying to close it: not while you're standing in the gap
			flap_open = not flap_open
		"switch":
			lights.flip_switch(aim_what.zone)
		"lamp":
			lights.set_lamp(aim_what, not aim_what.on)
		"hatch":
			player.start_climb(-1 if on_roof() else 1, ladders.hatch.climb, ladders)
		"back":
			if on_roof():
				if back_down:
					player.start_climb(-1, ladders.back.climb, ladders)
				else:  # kicked loose
					back_down = true
					_slide_v = 0.0
					hud.toast("You kick the latch loose. The ladder rattles down: a way back up from outside")
			elif back_down and (_slide == null or _slide.position.y == 0.0):
				player.start_climb(1, ladders.back.climb, ladders)
		_:
			return false
	return true
