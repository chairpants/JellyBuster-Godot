extends Node
## The store's sound, built from the physics of each sound rather than recordings: the fluorescents' hum over each
## light zone (following its switch), the air from the vents, the road through the storefront glass and cars going by
## on it (their pitch bending as they pass), rain on the roof and the glass, wind, the murmur of a crowd; footsteps
## (soft on carpet, brighter on tile), doors (a latch, a panel meeting its frame, a hinge's creak, the cooler's
## gasket and its bottles), the entry chime (two struck bars), the cooler's compressor, a flush, a running tap, the phone.
## M turns it off and on.
## From the web game's ambience.js (every recipe here is one of its: the same filters, modes and timings) and where
## store/main.js, player.js and shoppers.js set it off. The web game makes each sound as it's needed; here they're
## all made once at the start, on another thread (a second or two: it's quiet till then), and played back.
## People talking, with no words in it: each talker's a voice (a buzz at a speaking pitch through two wandering
## formants, gated into syllables), heard from where they stand; the nearest six. The two rooftop AC units (a fan's rush
## and the compressor's drone: loud out on the roof, a faint rumble through the ceiling), cycling through the warm
## months. The air a swinging door's leaf pushes, rising with its speed. Here a voice is a few seconds of talk made
## at the start and looped, and the door's air shifts in pitch rather than through a moving filter.
## Not over yet: the trash (bags, the chute).

const RATE := 22050
const HEAD := 0.5  # what's baked is kept at half, for room: the player makes it up
var ZONES: Array = [["front", 0.0, 3.45, 3.5], ["aisles", -4.0, 3.45, 13.0], ["aisles", 5.0, 3.45, 16.0], ["lounge", 0.0, 3.45, 22.5], ["hall", 6.0, 2.6, 29.0],
	["breakroom", 5.0, 2.6, 31.5], ["restroom", 9.6, 2.6, 31.5], ["lobby", -2.5, 3.0, 30.5], ["theater", -3.0, 5.0, 38.0]].map(func(z: Array) -> Array: return [z[0], z[1], z[2], Level.z(z[3])])  # a hum over each light zone (as deep as the store is: level.gd)

var muted := false

var _noise := {}  # 4 s of each colour
var _baked := {}  # name -> [AudioStreamWAV, ...]
var _task := -1
var _live := false
var _hums: Array[AudioStreamPlayer3D] = []
var _loops := {}
var _t := 0.0
var _car_t := 0.0
var _next_car := 3.0
var _pass := {}
var _tap := false
var _swings := {}  # a swinging door's leaf -> { p: its air, speed } (by the node: the door's own record changes as it swings, and can't be a key)

const VOICES := 6
const VOWELS := [[730.0, 1090.0], [530.0, 1840.0], [270.0, 2290.0], [570.0, 840.0], [300.0, 870.0], [660.0, 1720.0], [490.0, 1350.0]]
const UNITS := [[-2.6, 9.5, 0.0], [4.6, 19.5, 120.0]]  # the rooftop units: x, z, where each is in its cycle (roof.js)


func _init() -> void:  # two buses of its own: Store (so M can shut it all up), and Room into it (a little of the room on the chime, steps and doors)
	if AudioServer.get_bus_index("Store") >= 0:
		return
	AudioServer.add_bus()
	AudioServer.set_bus_name(AudioServer.bus_count - 1, "Store")
	AudioServer.add_bus()
	AudioServer.set_bus_name(AudioServer.bus_count - 1, "Room")
	AudioServer.set_bus_send(AudioServer.bus_count - 1, "Store")
	var verb := AudioEffectReverb.new()  # a small store: short, darker as it decays
	verb.room_size = 0.35
	verb.damping = 0.7
	verb.wet = 0.15
	verb.dry = 1.0
	verb.predelay_msec = 15.0
	AudioServer.add_bus_effect(AudioServer.bus_count - 1, verb)


func _ready() -> void:
	_task = WorkerThreadPool.add_task(_bake)


func _exit_tree() -> void:
	if _task >= 0:
		WorkerThreadPool.wait_for_task_completion(_task)


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_M:
		muted = not muted
		AudioServer.set_bus_mute(AudioServer.get_bus_index("Store"), muted)
		$"../HUD".toast("Store sounds off (M)" if muted else "Store sounds on (M)")


# ---- setting them off

func step(at: Vector3, weight := 1.0) -> void:  # heel strike + sole scuff: tile at the front and in back of house, carpet elsewhere
	var tile := at.z < 4.35 or (at.z > Level.z(28.0) and at.x > 2.0 and at.z < Level.z(33.0))
	_shot("step_tile" if tile else "step_carpet", at + Vector3(0, 0.05, 0), (0.16 if tile else 0.09) * weight * randf_range(0.8, 1.2), 1.2)


func door(kind: String, action: String, at: Vector3) -> void:  # kind: "wood" | "push" | "cooler"; action: "open" | "close" | "rattle" | "settle"
	_shot("%s_%s" % [kind, action], at, { "wood": 0.8 if action == "open" else 0.6, "push": 0.5, "cooler": 0.2 }[kind])


func swing(key: Node, at: Vector3, speed: float) -> void:  # the air a swinging leaf pushes: rises with its speed (rad/s). Called every frame it might be moving
	if not _live:
		return
	if not _swings.has(key):
		if speed < 0.05:
			return
		var p := AudioStreamPlayer3D.new()
		p.stream = _baked.swing[0]
		p.position = at
		p.unit_size = 1.5
		p.max_db = 0.0
		p.bus = "Store"
		p.volume_db = -80.0
		p.set_meta("g", 0.0)
		add_child(p)
		p.play(randf() * p.stream.get_length())
		_swings[key] = { "p": p, "speed": 0.0 }
	_swings[key].speed = speed


func chime(at: Vector3) -> void:  # ding... dong
	_shot("chime", at, 0.12, 2.0)


func ring(at: Vector3) -> void:  # the phone
	_shot("ring", at, 0.09, 3.0)


func beep(at: Vector3, f: float, after := 0.0) -> void:  # the register's: a tenth of a second of square wave (checkout.js: posBeep)
	if after > 0.0:
		get_tree().create_timer(after).timeout.connect(beep.bind(at, f))
		return
	var key := "beep%d" % int(f)
	if _live and not _baked.has(key):
		var d := _zeros(int(RATE * 0.1))
		for i in int(RATE * 0.09):
			d[i] = 1.0 if fmod(i * f / RATE, 1.0) < 0.5 else -1.0
		_baked[key] = [_wav(d)]
	_shot(key, at, 0.035, 1.0)


func buzz(at: Vector3, secs: float) -> void:  # the dot-matrix printer: a buzzy rasp, pulsing line by line (checkout.js: printBuzz)
	var key := "buzz%d" % int(secs * 10.0)
	if _live and not _baked.has(key):
		var d := _zeros(int(RATE * secs))
		for i in d.size():
			var t := float(i) / RATE
			d[i] = (fmod(t * 118.0, 1.0) * 2.0 - 1.0) * (0.014 + (0.012 if fmod(t * 9.0, 1.0) < 0.5 else -0.012)) / 0.026
		_baked[key] = [_wav(d)]
	_shot(key, at, 0.026, 1.0)


func bag(at: Vector3) -> void:  # a full liner pulled out and tied off: plastic crinkle, the can rocking back
	_shot("bag", at, 0.35)


func chute(at: Vector3, bags: int) -> void:  # the hopper door tipping open, the bag(s) in and away down the duct, the door slapping shut
	_shot("chute%d" % clampi(bags, 1, 3), at, 0.5, 2.0)


func drive(dir: int, v: float) -> void:  # a car on the road out front that's turning in to the lot: heard the same as one going by (cars.gd shows it itself)
	if _pass.is_empty():
		_pass = { "dir": float(dir), "v": v, "t": 0.0, "g": (0.7 if $"../Sky".level < 0.4 else 1.0) * (0.7 + randf() * 0.5) }


func tone(at: Vector3, f: float, dur := 0.06, wave := "square", vol := 0.05, slide := 0.0) -> void:  # a blip, from where it's made (the arcade's: siBeep): a note sliding by `slide` over `dur`, dying away
	var key := "tone%d_%d_%s_%d" % [int(f), int(dur * 1000.0), wave, int(slide)]
	if _live and not _baked.has(key):
		var d := _zeros(int(RATE * (dur + 0.02)))
		var ph := 0.0
		var n := int(RATE * dur)
		for i in n:
			ph = fmod(ph + (f + slide * float(i) / n) / RATE, 1.0)
			var w := sin(TAU * ph) if wave == "sine" else (4.0 * absf(ph - 0.5) - 1.0) if wave == "triangle" else (ph * 2.0 - 1.0) if wave == "sawtooth" else (1.0 if ph < 0.5 else -1.0)
			d[i] = w * exp(log(0.002) * float(i) / n)
		_baked[key] = [_wav(d)]
	_shot(key, at, vol * 1.6, 1.5)


func golf(kind: String, at: Vector3, vol := 1.0) -> void:  # what a golf ball does out there: clank, glass, thud, screech, horn, alarm, rattle (roof.js: golfSnd)
	if _live and not _baked.has("golf_" + kind):
		_baked["golf_" + kind] = [_wav(_golf(kind))]
	_shot("golf_" + kind, at, 0.5 * vol, 8.0)


func flush(at: Vector3) -> void:
	_shot("flush", at, 0.3, 1.2)


func water(at: Vector3, on: bool) -> void:  # a running tap
	_tap = on
	if _loops.has("tap"):
		_loops.tap.position = at


func _shot(sound: String, at: Vector3, gain: float, ref := 1.5) -> void:
	if not _live or muted or not _baked.has(sound):
		return
	var p := AudioStreamPlayer3D.new()
	p.stream = _baked[sound].pick_random()
	p.position = at
	p.unit_size = ref
	p.max_db = 0.0
	p.volume_db = linear_to_db(gain * 0.9 / HEAD)
	p.bus = "Room"
	p.finished.connect(p.queue_free)
	add_child(p)
	p.play()


func _loop(sound: String, at = null, ref := 2.0) -> Node:
	var p: Node = AudioStreamPlayer.new() if at == null else AudioStreamPlayer3D.new()
	if at != null:
		p.position = at
		p.unit_size = ref
		p.max_db = 0.0
	p.stream = _baked[sound][0]
	p.bus = "Store"
	p.volume_db = -80.0
	p.set_meta("g", 0.0)
	add_child(p)
	p.play(randf() * p.stream.get_length())
	_loops[sound] = p
	return p


func _level(p: Node, gain: float, dt: float, quick := 3.0) -> void:  # ease a loop's level to where it should be
	var g: float = lerpf(p.get_meta("g"), gain, minf(1.0, dt * quick))
	p.set_meta("g", g)
	p.volume_db = linear_to_db(maxf(g * 0.9 / HEAD, 0.00001))


func _process(dt: float) -> void:
	if not _live:
		if _task >= 0 and WorkerThreadPool.is_task_completed(_task):
			WorkerThreadPool.wait_for_task_completion(_task)
			_task = -1
			for z: Array in ZONES:
				_hums.append(_loop("hum", Vector3(z[1], z[2], z[3]), 1.5))
			for s in ["room", "rain_roof", "wind", "crowd"]:
				_loop(s)
			_loop("traffic", Vector3(0, 1.5, -20), 6.0)
			_loop("rain_pat", Vector3(1.5, 1.6, -0.3), 3.0)
			_loop("car", Vector3(0, 0.6, -15.45), 5.0)
			_loop("comp", Vector3.ZERO, 1.2)
			_loop("tap", Vector3.ZERO, 1.2)
			for i in VOICES:
				_loop("voice%d" % i, Vector3(0, 1.55, 0), 1.6)
			for i in UNITS.size():
				_loop("unit%d" % i, Vector3(UNITS[i][0], main_roof_y() + 1.2, UNITS[i][1]), 2.5)
			_live = true
		return
	_t += dt
	var main := get_parent()
	var lights: Node = main.get_node("Lights")
	var weather: Node = main.get_node("Weather")
	var you: Vector3 = main.get_node("Player").global_position
	var night: float = 1.0 - main.get_node("Sky").level
	var outdoors := you.y > 3.3
	var rain: float = weather.k if weather.kind == "rain" else 0.0
	var snow: float = weather.k if weather.kind == "snow" else 0.0
	for i in ZONES.size():
		_level(_hums[i], lights.zone_lvl.get(ZONES[i][0], 0.0) * 0.0045, dt, 12.0)  # follows the switch (and the flicker as it strikes)
	_level(_loops.room, 0.02, dt)
	_level(_loops.traffic, (0.05 + 0.08 * (1.0 - night)) * (1.0 - 0.6 * snow) * 0.45, dt, 1.0)  # (snow hushes the road)
	_level(_loops.wind, weather.wind * (0.55 + 0.9 * weather.gust) * (0.11 if outdoors else 0.012), dt)
	_level(_loops.rain_roof, 0.05 * rain, dt, 1.2)
	_level(_loops.rain_pat, 0.02 * rain * rain, dt, 1.2)
	var cooler: Array = main.get_node("Things").T.cooler.pivot
	_loops.comp.position = Vector3(cooler[0], 0.3, cooler[2])
	_level(_loops.comp, 0.012 if fmod(_t, 150.0) < 45.0 else 0.0, dt, 2.0)  # the compressor's idle cycle
	_level(_loops.tap, 0.14 if _tap else 0.0, dt, 15.0)
	# who's talking right now (the nearest six), each where they stand
	var talkers: Array = main.get_children().filter(func(c: Node) -> bool: return c is Node3D and c.get("talking") == true and c.visible)
	talkers.sort_custom(func(a: Node3D, b: Node3D) -> bool: return a.global_position.distance_squared_to(you) < b.global_position.distance_squared_to(you))
	for i in VOICES:
		var v: AudioStreamPlayer3D = _loops["voice%d" % i]
		if i < talkers.size():
			v.position = talkers[i].global_position + Vector3(0, 1.55, 0)
		_level(v, 0.012 * 3.0 if i < talkers.size() else 0.0, dt, 5.0)
	# the rooftop units: cooling through the warm months (and the afternoons either side of them), 200 seconds in every 300
	var mo: int = Clock.date().month
	var h := fmod(Clock.h, 24.0)
	var cooling: bool = (mo >= 5 and mo <= 9) or ((mo == 4 or mo == 10) and h > 12.0 and h < 18.0)
	for i in UNITS.size():
		var on: bool = cooling and fmod(_t + UNITS[i][2], 300.0) < 200.0
		_level(_loops["unit%d" % i], (0.05 if outdoors else 0.004) if on else 0.0, dt, 1.7 if on else 0.8)
	for key: Node in _swings:
		var k: float = minf(1.0, _swings[key].speed / 3.0)
		_level(_swings[key].p, 0.2 * k * k, dt, 20.0)
		_swings[key].p.pitch_scale = (350.0 + 900.0 * k) / 700.0
		_swings[key].speed = 0.0
	# a car going by on the road out front, left to right or right to left; fewer at night
	_car_t += dt
	if _pass.is_empty() and _car_t >= _next_car:
		_car_t = 0.0
		_next_car = 25.0 + randf() * 50.0 if night > 0.6 else 5.0 + randf() * 14.0
		_pass = { "dir": 1.0 if randf() < 0.5 else -1.0, "v": 10.0 + randf() * 7.0, "t": 0.0, "g": (0.7 if night > 0.6 else 1.0) * (0.7 + randf() * 0.5) }
	if not _pass.is_empty():
		_pass.t += dt
		var x: float = _pass.dir * (_pass.v * _pass.t - 35.0)
		var lane := -15.45 if _pass.dir > 0.0 else -18.75  # right-hand lanes
		var away := Vector2(x, lane - 8.0).length()  # heard from about the middle of the store
		_loops.car.position = Vector3(x, 0.6, lane)
		_loops.car.pitch_scale = 343.0 / (343.0 + _pass.dir * _pass.v * x / away)  # the Doppler shift
		_level(_loops.car, _pass.g * 0.45, dt, 20.0)
		if _pass.t > 70.0 / _pass.v:
			_pass = {}
	else:
		_level(_loops.car, 0.0, dt, 20.0)


# ---- making them (on a worker thread)

func _bake() -> void:
	var n := RATE * 4
	var w := _zeros(n)
	var p := _zeros(n)
	var b := _zeros(n)
	var b0 := 0.0
	var b1 := 0.0
	var b2 := 0.0
	var b3 := 0.0
	var b4 := 0.0
	var b5 := 0.0
	var b6 := 0.0
	var br := 0.0
	for i in n:
		var x := randf() * 2.0 - 1.0
		w[i] = x
		b0 = 0.99886 * b0 + x * 0.0555179  # Paul Kellet's pink filter
		b1 = 0.99332 * b1 + x * 0.0750759
		b2 = 0.96900 * b2 + x * 0.1538520
		b3 = 0.86650 * b3 + x * 0.3104856
		b4 = 0.55000 * b4 + x * 0.5329522
		b5 = -0.7616 * b5 - x * 0.0168980
		p[i] = (b0 + b1 + b2 + b3 + b4 + b5 + b6 + x * 0.5362) * 0.11
		b6 = x * 0.115926
		br = (br + 0.04 * x) / 1.04  # brown: a leaky integral of white (twice the web game's leak, at half its sample rate)
		b[i] = br * 3.5
	_noise = { "white": w, "pink": p, "brown": b }
	var F := RATE / 4  # the extra a loop's made with, faded back into its start
	# the loops
	var hum := _wave(RATE, 120.0, [1.0, 0.55, 0.32, 0.22, 0.12, 0.09, 0.05, 0.03])  # 120 Hz and harmonics (magnetostriction in the ballast)...
	var rasp := _looped(_filter(_colour("white", RATE + F), "bandpass", 3600.0, 1.2), RATE)  # ...and the faint rasp of the arc
	for i in RATE:
		hum[i] += rasp[i] * 0.5 * sin(TAU * 120.0 * i / RATE) * 0.35
	_baked.hum = [_wav(hum, true)]
	_baked.room = [_wav(_looped(_filter(_colour("brown", n + F), "lowpass", 320.0, 1.0), n), true)]  # air from the vents
	_baked.traffic = [_wav(_looped(_filter(_filter(_colour("brown", n + F), "lowpass", 420.0, 1.0), "lowpass", 650.0, 0.5), n), true)]  # the road, far off, through the glass
	_baked.rain_roof = [_wav(_looped(_filter(_colour("pink", RATE * 3 + F), "lowpass", 900.0, 1.0), RATE * 3), true)]  # a dark wash on the roof
	var pat := _looped(_filter(_colour("white", RATE * 2 + F), "bandpass", 3800.0, 0.8), RATE * 2)  # a brighter patter on the storefront glass
	for i in pat.size():
		pat[i] *= 0.6 + 0.4 * (2.0 * fposmod(13.0 * i / RATE, 1.0) - 1.0)
	_baked.rain_pat = [_wav(pat, true)]
	var wn := RATE * 8  # wind: a low rumble round the building and a howl whose pitch wanders with the gusts
	var wind := _looped(_filter(_colour("brown", wn + F), "lowpass", 260.0, 1.0), wn)
	var howl := _looped(_filter(_colour("pink", wn + F), "bandpass", 520.0, 2.2, func(k: float) -> float: return 520.0 + 240.0 * sin(TAU * k * (wn + F) / wn)), wn)
	for i in wn:
		wind[i] += howl[i] * 0.55
	_baked.wind = [_wav(wind, true)]
	var cn := int(RATE * 4.0 / 0.9)  # the crowd: voiced noise in the speech band, slowly breathing
	var crowd := _looped(_filter(_filter(_colour("pink", cn + F), "bandpass", 520.0, 1.4), "lowpass", 1400.0, 1.0), cn)
	for i in cn:
		crowd[i] *= 0.65 + 0.35 * sin(TAU * 0.9 * i / RATE)
	_baked.crowd = [_wav(crowd, true)]
	var car := _filter(_colour("pink", RATE * 3 + F), "bandpass", 1025.0, 0.8)  # tires on asphalt...
	var eng := _zeros(RATE * 3 + F)  # ...and the engine: a low sawtooth rumble
	for i in eng.size():
		eng[i] = 2.0 * fposmod(48.0 * i / RATE, 1.0) - 1.0
	eng = _filter(eng, "lowpass", 180.0, 1.0)
	for i in car.size():
		car[i] += eng[i] * 0.35
	_baked.car = [_wav(_looped(_filter(car, "lowpass", 650.0, 0.5), RATE * 3), true)]  # (through the glass)
	var comp := _wave(RATE, 60.0, [1.0, 0.7, 0.35, 0.22, 0.1, 0.06])  # an induction motor's hum and harmonics, and its fan
	var fan := _looped(_filter(_colour("pink", RATE + F), "bandpass", 850.0, 0.6), RATE)
	for i in RATE:
		comp[i] = comp[i] * 0.6 + fan[i] * 0.5
	_baked.comp = [_wav(comp, true)]
	var tap := _looped(_filter(_colour("pink", RATE * 2 + F), "bandpass", 1100.0, 0.5), RATE * 2)  # a steady mid-band pour with a brighter splash on the basin
	var splash := _looped(_filter(_colour("white", RATE * 2 + F), "bandpass", 3800.0, 0.9), RATE * 2)
	for i in tap.size():
		tap[i] += splash[i] * (0.35 + 0.15 * sin(TAU * 7.5 * i / RATE))
	_baked.tap = [_wav(tap, true)]
	_baked.swing = [_wav(_looped(_filter(_colour("pink", RATE * 2 + F), "bandpass", 700.0, 0.9), RATE * 2), true)]  # the air off a swinging leaf
	for u in UNITS.size():  # a rooftop unit: the compressor's drone (a sawtooth near 59 Hz, the highs off it) under the fan's rush, beating with the blades
		var u_saw := _zeros(n)
		var u_f := float(roundi((58.8 + randf()) * 4.0)) / 4.0  # (a whole number of turns in the loop)
		for i in n:
			u_saw[i] = 2.0 * fposmod(u_f * i / RATE, 1.0) - 1.0
		var u_mix := _filter(u_saw, "lowpass", 220.0, 1.0)
		var u_fan := _looped(_filter(_colour("pink", n + F), "bandpass", 620.0, 0.5), n)
		var u_beat := float(roundi((7.5 + randf()) * 4.0)) / 4.0
		for i in n:
			u_mix[i] = u_mix[i] * 0.35 + u_fan[i] * (0.7 + 0.12 * sin(TAU * u_beat * i / RATE))
		_baked["unit%d" % u] = [_wav(u_mix, true)]
	for v in VOICES:
		_baked["voice%d" % v] = [_wav(_voice(), true)]
	# the one-offs, a few of each
	_baked.step_tile = range(4).map(func(_i: int) -> AudioStreamWAV: return _wav(_step(true)))
	_baked.step_carpet = range(4).map(func(_i: int) -> AudioStreamWAV: return _wav(_step(false)))
	_baked.wood_open = [_wav(_latch(_zeros(RATE / 4), 0.0)), _wav(_creak(_latch(_zeros(RATE), 0.0), 0.08, 0.45)), _wav(_creak(_latch(_zeros(RATE), 0.0), 0.08, 0.7))]  # a latch, and about half the time the hinge
	_baked.wood_close = [_wav(_latch(_panel(_zeros(RATE / 2), 0.0, 1.0), 0.018, 1.1))]
	var rattle := _zeros(RATE)
	for i in 5:
		var t := i * 0.06 + randf() * 0.02
		rattle = _panel(_latch(rattle, t, 0.6), t, 0.12, 1.3)
	_baked.wood_rattle = [_wav(rattle)]
	_baked.push_open = [_wav(_panel(_zeros(RATE / 2), 0.0, 0.25, 1.8)), _wav(_panel(_zeros(RATE / 2), 0.0, 0.25, 1.8)), _wav(_creak(_panel(_zeros(RATE / 2), 0.0, 0.25, 1.8), 0.05, 0.25))]  # a hand on the push plate (and now and then the spring hinge)
	_baked.push_settle = [_wav(_panel(_zeros(RATE / 2), 0.0, 0.3, 1.2))]
	_baked.cooler_open = [_wav(_modes(_burst(_zeros(RATE / 2), 0.0, 0.06, "lowpass", 260.0, 0.8, 0.9), 0.03, [[2600.0, 0.05, 0.05], [3300.0, 0.04, 0.04]]))]  # the gasket letting go
	var shut := _modes(_burst(_zeros(RATE), 0.0, 0.04, "lowpass", 900.0, 0.8, 0.6), 0.0, [[120.0, 0.5, 0.03], [310.0, 0.25, 0.02], [980.0, 0.08, 0.015]])  # glass door into the gasket
	for i in 4:  # bottles touching
		var f := 1900.0 + randf() * 2600.0
		shut = _modes(shut, 0.03 + randf() * 0.15, [[f, 0.12, 0.05 + randf() * 0.04], [f * 2.3, 0.05, 0.03]])
	_baked.cooler_close = [_wav(shut)]
	var ding := _zeros(int(RATE * 4.5))  # two struck bars. A free-free bar's modes: ratio, strength, decay time
	for bar: Array in [[659.3, 0.0], [523.3, 0.55]]:
		for m: Array in [[1.0, 1.0, 1.4], [2.756, 0.45, 0.6], [5.404, 0.22, 0.3], [8.933, 0.1, 0.15]]:
			ding = _ring(ding, bar[1], bar[0] * m[0], m[1], 0.003, m[2] * 5.0)
	_baked.chime = [_wav(ding)]
	_baked.flush = [_wav(_flush())]
	_baked.bag = [_wav(_bag())]
	for bags in [1, 2, 3]:
		_baked["chute%d" % bags] = [_wav(_chute(bags))]
	var bell := _zeros(int(RATE * 2.6))  # the phone, a desk-set ringer: a clapper buzzing between two small gongs twenty times a second for two seconds
	for gong: Array in [[1180.0, 0.0], [1390.0, 0.025]]:
		for part: Array in [[1.0, 1.0], [2.32, 0.35], [4.1, 0.12]]:
			var g := 0.0
			var to := 0.0
			var tau := 0.012
			var struck: float = gong[1]
			for i in bell.size():
				var t := float(i) / RATE
				if t >= 2.0:
					to = 0.0
					tau = 0.08
				elif t >= struck:
					struck += 0.05
					g = part[1] * minf(1.0, minf(t / 0.08, (2.0 - t) / 0.15))
					to = g * 0.25
				g += (to - g) * (1.0 - exp(-1.0 / (tau * RATE)))
				bell[i] += sin(TAU * gong[0] * part[0] * t) * g
	_baked.ring = [_wav(_filter(bell, "lowpass", 3200.0, 1.0))]  # (a real bell, but across the room and not in your ear)


func main_roof_y() -> float:
	return get_parent().get_node("Fixtures").ladders.roofY


func _voice() -> PackedFloat32Array:  # one talker: a few seconds of syllables and pauses (ambience.js: voice, talk), to go round
	var f0 := 95.0 + randf() * 140.0
	var up := 1.15 if f0 > 170.0 else 1.0  # (a higher voice: its formants a little higher too)
	var vib := 4.0 + randf() * 2.0
	var out := PackedFloat32Array()
	var ph := 0.0
	var pitch := f0
	var t := 0.0
	while out.size() < RATE * 6:
		if randf() < 0.12:  # a breath between phrases
			out.append_array(_zeros(int(RATE * (0.35 + randf() * 1.1))))
			continue
		var vowel: Array = VOWELS.pick_random()
		var len := 0.09 + randf() * 0.17
		var m := int(RATE * len)
		var to := f0 * (0.88 + randf() * 0.3)  # the pitch rising and falling with the phrase
		var saw := _zeros(m)
		for i in m:
			pitch += (to - pitch) * (1.0 - exp(-1.0 / (0.06 * RATE)))
			t += 1.0 / RATE
			ph = fposmod(ph + pitch * (1.0 + 0.02 * sin(TAU * vib * t)) / RATE, 1.0)
			saw[i] = 2.0 * ph - 1.0
		var a := _filter(saw.duplicate(), "bandpass", vowel[0] * up, 5.0)
		var b := _filter(saw, "bandpass", vowel[1] * up, 7.0)
		var peak := 0.7 + randf() * 0.3
		for i in m:  # the syllable: up fast, then falling away from 70% of the way through
			var k := float(i) / m
			var e := peak * minf(1.0, k * len / 0.02) if k < 0.7 else lerpf(peak, 0.08, minf(1.0, (k - 0.7) * len / 0.06))
			a[i] = (a[i] + b[i]) * e * minf(1.0, (1.0 - k) * len / 0.008)
		out.append_array(a)
	return _filter(out, "lowpass", 1700.0, 1.0)


func _zeros(n: int) -> PackedFloat32Array:
	var d := PackedFloat32Array()
	d.resize(n)
	return d


func _wav(d: PackedFloat32Array, loop := false) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	bytes.resize(d.size() * 2)
	for i in d.size():
		bytes.encode_s16(i * 2, int(clampf(d[i] * HEAD, -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = RATE
	s.data = bytes
	if loop:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = d.size()
	return s


func _colour(kind: String, n: int) -> PackedFloat32Array:  # a stretch of noise, from anywhere in the four seconds of it
	var src: PackedFloat32Array = _noise[kind]
	var out := PackedFloat32Array()
	while out.size() < n:
		var o := randi() % src.size()
		out.append_array(src.slice(o, mini(src.size(), o + n - out.size())))
	return out


func _looped(d: PackedFloat32Array, n: int) -> PackedFloat32Array:  # the extra past n, faded back into the start: no click where it comes round
	var f := d.size() - n
	for i in f:
		var k := float(i) / f
		d[i] = d[i] * k + d[n + i] * (1.0 - k)
	d.resize(n)
	return d


func _wave(n: int, f: float, harmonics: Array) -> PackedFloat32Array:  # a periodic wave from its harmonics, its peak at 1
	var d := _zeros(n)
	var peak := 0.0001
	for i in n:
		var v := 0.0
		for h in harmonics.size():
			v += harmonics[h] * sin(TAU * f * (h + 1) * i / RATE)
		d[i] = v
		peak = maxf(peak, absf(v))
	for i in n:
		d[i] /= peak
	return d


func _filter(d: PackedFloat32Array, type: String, f0: float, q: float, sweep := Callable()) -> PackedFloat32Array:  # Web Audio's biquads: "lowpass" | "highpass" (q in dB) | "bandpass". sweep: where the band is, from how far through (0..1)
	var n := d.size()
	var x1 := 0.0
	var x2 := 0.0
	var y1 := 0.0
	var y2 := 0.0
	var c0 := 0.0
	var c1 := 0.0
	var c2 := 0.0
	var a1 := 0.0
	var a2 := 0.0
	for i in n:
		if i == 0 or (i % 64 == 0 and sweep.is_valid()):
			var f: float = sweep.call(float(i) / n) if sweep.is_valid() else f0
			var w := TAU * f / RATE
			var c := cos(w)
			var alpha := sin(w) / (2.0 * (q if type == "bandpass" else pow(10.0, q / 20.0)))
			var a0 := 1.0 + alpha
			if type == "lowpass":
				c0 = (1.0 - c) / 2.0 / a0
				c1 = (1.0 - c) / a0
				c2 = c0
			elif type == "highpass":
				c0 = (1.0 + c) / 2.0 / a0
				c1 = -(1.0 + c) / a0
				c2 = c0
			else:
				c0 = alpha / a0
				c1 = 0.0
				c2 = -alpha / a0
			a1 = -2.0 * c / a0
			a2 = (1.0 - alpha) / a0
		var x := d[i]
		var y := c0 * x + c1 * x1 + c2 * x2 - a1 * y1 - a2 * y2
		x2 = x1
		x1 = x
		y2 = y1
		y1 = y
		d[i] = y
	return d


func _env(d: PackedFloat32Array, amp: float, attack: float, dur: float) -> PackedFloat32Array:  # up to amp in the attack, then dying away to nothing by dur
	var a := maxi(1, int(attack * RATE))
	var k := log(0.0001 / amp) / maxf(1.0, dur * RATE - a)
	for i in d.size():
		d[i] *= amp * (float(i) / a if i < a else exp(k * (i - a)))
	return d


func _mix(out: PackedFloat32Array, src: PackedFloat32Array, at: float, k := 1.0) -> PackedFloat32Array:
	var o := int(at * RATE)
	for i in mini(src.size(), out.size() - o):
		out[o + i] += src[i] * k
	return out


func _burst(out: PackedFloat32Array, t0: float, dur: float, type: String, f: float, q := 0.8, amp := 1.0) -> PackedFloat32Array:  # a short shaped noise burst
	return _mix(out, _env(_filter(_colour("white", int((dur + 0.02) * RATE)), type, f, q), amp, minf(0.002, dur / 4.0), dur), t0)


func _ring(out: PackedFloat32Array, t0: float, f: float, amp: float, attack: float, dur: float, f1 := 0.0, bend := 0.0) -> PackedFloat32Array:  # a decaying sinusoid (its pitch sliding to f1 over `bend`, if given)
	var o := int(t0 * RATE)
	var a := maxi(1, int(attack * RATE))
	var k := log(0.0001 / amp) / maxf(1.0, dur * RATE - a)
	var ph := 0.0
	for i in mini(int(dur * RATE), out.size() - o):
		ph += (f if f1 <= 0.0 else f * pow(f1 / f, minf(1.0, i / (bend * RATE)))) / RATE
		out[o + i] += sin(TAU * ph) * amp * (float(i) / a if i < a else exp(k * (i - a)))
	return out


func _modes(out: PackedFloat32Array, t0: float, list: Array) -> PackedFloat32Array:  # decaying sinusoids: [frequency, amplitude, decay time]
	for m: Array in list:
		out = _ring(out, t0, m[0] * (1.0 + (randf() - 0.5) * 0.02), m[1], 0.002, m[2] * 6.0)
	return out


func _latch(out: PackedFloat32Array, t0: float, k := 1.0) -> PackedFloat32Array:  # a steel tongue snapping into a strike plate
	return _modes(_burst(out, t0, 0.012, "bandpass", 4200.0, 1.5, 0.8 * k), t0, [[2300.0, 0.25 * k, 0.012], [3900.0, 0.15 * k, 0.008]])


func _panel(out: PackedFloat32Array, t0: float, k := 1.0, lo := 1.0) -> PackedFloat32Array:  # a wooden door meeting its frame
	return _modes(_burst(out, t0, 0.05, "lowpass", 1400.0, 0.8, 0.7 * k), t0, [[72.0 * lo, 0.9 * k, 0.05], [148.0 * lo, 0.5 * k, 0.035], [231.0 * lo, 0.3 * k, 0.025], [340.0 * lo, 0.18 * k, 0.018]])


func _creak(out: PackedFloat32Array, t0: float, dur: float) -> PackedFloat32Array:  # stick-slip: impulses at a wandering rate, ringing the hinge's resonances
	var n := int(RATE * dur)
	var d := _zeros(n)
	var ph := 0.0
	var rate := 25.0 + randf() * 20.0
	for i in n:
		rate = clampf(rate + (randf() - 0.5) * 1.3 + (0.32 if float(i) / n < 0.5 else -0.32), 12.0, 90.0)
		ph += rate / RATE
		if ph >= 1.0:
			ph -= 1.0
			d[i] = 0.9 * (0.6 + randf() * 0.4) * sin(PI * i / n)
	for r: Array in [[720.0 + randf() * 200.0, 18.0, 1.0], [1580.0 + randf() * 300.0, 22.0, 0.6], [2900.0, 25.0, 0.3]]:
		out = _mix(out, _filter(d.duplicate(), "bandpass", r[0], r[1]), t0, r[2] * 4.0)
	return out


func _step(tile: bool) -> PackedFloat32Array:
	var out := _ring(_zeros(int(RATE * 0.16)), 0.0, 140.0 if tile else 95.0, 0.5 if tile else 0.8, 0.004, 0.09, 55.0, 0.06)  # the heel: a damped low thump
	var sole := _filter(_colour("white", int(RATE * 0.15)), "bandpass" if tile else "lowpass", 2400.0 + randf() * 800.0 if tile else 600.0 + randf() * 300.0, 0.9 if tile else 0.7)
	return _mix(out, _env(sole, 0.9 if tile else 0.6, 0.006, 0.07 if tile else 0.12), 0.0)  # the scuff of the sole


func _golf(kind: String) -> PackedFloat32Array:  # (roof.js: golfSnd)
	var tone := func(o: PackedFloat32Array, wave: String, f: float, a: float, t0: float, t1: float) -> PackedFloat32Array:
		var i0 := int(t0 * RATE)
		var n := mini(int((t1 - t0) * RATE), o.size() - i0)
		var k := log(0.0005 / a) / maxf(1.0, n)
		for i in n:
			var ph := fmod(i * f / RATE, 1.0)
			var w := sin(TAU * ph) if wave == "sine" else (4.0 * absf(ph - 0.5) - 1.0) if wave == "triangle" else (1.0 if ph < 0.5 else -1.0)
			o[i0 + i] += w * a * exp(k * i)
		return o
	var out: PackedFloat32Array
	match kind:
		"clank":
			out = _zeros(int(RATE * 0.4))
			for m: Array in [[1150.0, 0.12], [1720.0, 0.08], [2630.0, 0.05], [420.0, 0.1]]:
				out = tone.call(out, "sine", m[0], m[1], 0.0, 0.35)
			out = _burst(out, 0.0, 0.05, "bandpass", 3000.0, 0.5, 0.2)
		"glass":
			out = _zeros(int(RATE * 0.65))
			out = _burst(out, 0.0, 0.35, "highpass", 2500.0, 0.7, 0.25)
			out = tone.call(out, "sine", 3900.0, 0.05, 0.0, 0.6)
			out = tone.call(out, "sine", 5200.0, 0.03, 0.02, 0.5)
		"thud":
			out = _zeros(int(RATE * 0.45))
			out = tone.call(out, "sine", 70.0, 0.4, 0.0, 0.4)
			out = _burst(out, 0.0, 0.25, "lowpass", 500.0, 0.8, 0.4)
		"screech":  # tires: a narrow band of noise, sliding down
			out = _filter(_colour("white", int(RATE * 1.3)), "bandpass", 2300.0, 9.0, func(k: float) -> float: return 2300.0 - 800.0 * minf(1.0, k * 1.3 / 1.2))
			for i in out.size():
				out[i] *= 0.5 * exp(log(0.001) * float(i) / out.size())
		"horn":  # two notes, beeped twice
			out = _zeros(int(RATE * 1.4))
			for f: float in [392.0, 494.0]:
				for i in out.size():
					var t := float(i) / RATE
					if (t > 0.05 and t < 0.3) or (t > 0.42 and t < 1.3):
						out[i] += (1.0 if fmod(t * f, 1.0) < 0.5 else -1.0) * 0.06
			out = _filter(out, "lowpass", 1400.0, 0.7)
		"alarm":  # the classic: a whoop, chirps, the two-tone, round again for ten seconds
			out = _zeros(RATE * 10)
			var ph := 0.0
			for i in out.size():
				var t := float(i) / RATE
				var c := fmod(t, 3.3)
				var f := 600.0 + 900.0 * c / 0.9 if c < 0.9 else (900.0 if int((c - 1.0) / 0.16) % 2 else 1300.0) if c < 1.96 else (700.0 if int((c - 2.0) / 0.22) % 2 else 1000.0) if c < 3.32 else 1000.0
				ph = fmod(ph + f / RATE, 1.0)
				out[i] = (ph * 2.0 - 1.0) * 0.05
		_:  # "rattle": down a downspout
			out = _zeros(int(RATE * 1.6))
			var tt := 0.0
			for k in 16:
				out = tone.call(out, "triangle", 900.0 + randf() * 900.0, 0.07 * (1.0 - k / 20.0), tt, tt + 0.04)
				tt += 0.05 + k * 0.006
			out = tone.call(out, "sine", 160.0, 0.12, 1.3, 1.5)
	for i in out.size():  # (the web game's levels are for its quieter mix: up to ours)
		out[i] *= 4.0
	return out


func _bag() -> PackedFloat32Array:  # (ambience.js: bag)
	var out := _zeros(int(RATE * 1.0))
	for i in 28:  # the plastic crinkling
		out = _burst(out, randf() * 0.75, 0.01 + randf() * 0.03, "highpass", 2500.0 + randf() * 4000.0, 0.7, 0.2 + randf() * 0.5)
	return _burst(out, 0.8, 0.08, "lowpass", 500.0, 0.8, 0.5)  # the can rocking back


func _chute(bags: int) -> PackedFloat32Array:  # (ambience.js: chute)
	var out := _zeros(int(RATE * (2.8 + bags * 0.22)))
	var clank := func(o: PackedFloat32Array, t: float, k: float) -> PackedFloat32Array:
		o = _burst(o, t, 0.05, "bandpass", 1800.0, 1.2, 0.6 * k)
		return _modes(o, t, [[310.0, 0.45 * k, 0.05], [742.0, 0.3 * k, 0.04], [1660.0, 0.18 * k, 0.03], [3120.0, 0.08 * k, 0.02]])
	out = clank.call(out, 0.28, 0.5)  # open, on its stop
	for i in bags:
		var tb := 0.38 + i * 0.22
		out = _burst(out, tb, 0.12, "lowpass", 700.0, 0.8, 0.7)  # onto the hopper's floor
		var rush := _filter(_colour("brown", int(RATE * 2.0)), "bandpass", 900.0, 1.2, func(k: float) -> float: return 900.0 * pow(110.0 / 900.0, minf(1.0, k * 2.0 / 1.75)))  # sliding off down the duct, falling away
		var o := int((tb + 0.05) * RATE)
		for j in mini(rush.size(), out.size() - o):
			var t := float(j) / RATE
			out[o + j] += rush[j] * 0.9 * (t / 0.15 if t < 0.15 else exp(-(t - 0.15) / 0.27))
		for j in 5:  # knocking the duct on the way down
			out = _modes(out, tb + 0.25 + j * 0.28 + randf() * 0.1, [[180.0 - j * 15.0, 0.25 * (1.0 - j / 6.0), 0.06], [410.0 - j * 30.0, 0.12 * (1.0 - j / 6.0), 0.04]])
		out = _modes(out, tb + 2.1, [[55.0, 0.25, 0.08], [90.0, 0.15, 0.06]])  # into the dumpster, far below
	return clank.call(out, 1.3, 1.0)  # shut


func _flush() -> PackedFloat32Array:
	var out := _panel(_zeros(int(RATE * 12.2)), 0.0, 0.35, 2.2)  # the lever and flapper
	var rush := _filter(_colour("pink", RATE * 6), "bandpass", 1900.0, 0.7, func(k: float) -> float: return 1900.0 * pow(420.0 / 1900.0, minf(1.0, k * 6.0 / 3.2)))  # water through the trapway, its band sweeping down as the bowl empties...
	var rum := _filter(_colour("brown", RATE * 6), "lowpass", 240.0, 1.0)  # ...over a low rumble
	for i in RATE * 6:
		var t := float(i) / RATE
		out[i] += rush[i] * 0.9 * (t / 0.18 if t < 0.18 else 1.0 if t < 1.6 else exp(-(t - 1.6) / 0.9))
		out[i] += rum[i] * 0.6 * (t / 0.3 if t < 0.3 else 1.0 if t < 1.8 else exp(-(t - 1.8) / 0.8))
	for i in 14:  # air bubbles through the trap as it siphons: each one a pitch rising as it collapses
		var f := 260.0 + randf() * 420.0
		out = _ring(out, 1.2 + randf() * 2.4, f, 0.18, 0.004, 0.07, f * 2.6, 0.05)
	var hiss := _filter(_colour("white", int(RATE * 9.2)), "highpass", 2200.0, 1.0)  # the tank refilling
	var o := RATE * 3
	for i in hiss.size():
		var t := float(i) / RATE
		out[o + i] += hiss[i] * 0.06 * (t / 0.6 if t < 0.6 else 1.0 if t < 7.0 else maxf(0.0, 1.0 - (t - 7.0) / 2.0))
	return out
