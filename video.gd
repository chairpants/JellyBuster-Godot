extends Node
## Plays a video from Jellyfin: its picture onto `texture` (put that on whatever's showing it), its sound out of
## `audio`. No screen of its own. Give it a tape's episode, ["jellyfin", title, item id, seconds long]:
##     $Video.play_episode(tape.seasons[0].episodes[0])
##     some_material.albedo_texture = $Video.texture
## pause(), seek(seconds), stop(); `position` is where it's got to; `ended` when it runs out, `failed(why)` if it can't.
##
## From SpaceLife's scripts/wall_tv.gd: the picture comes from ffmpeg, not a Godot plugin and not through a video
## codec. ffmpeg opens the https stream, seeks, and writes plain uncompressed frames a chunk at a time, which are
## blitted into the texture one by one; the chunk's sound comes out beside it as plain samples, poured one chunk after
## another into a single stream, so there's never a gap between them; and the picture shows whichever frame goes with
## the sound that's being heard (the sound's the clock). (Godot's own player only reads Ogg Theora, and transcoding to
## that ran below realtime.) So ffmpeg has to be on the machine's PATH; without it,
## failed() and nothing plays. The cost is disk: raw frames are ~10 MB/s, in user://, cleared when it stops.
## The file comes straight off the Jellyfin server (static stream, no server transcode); ffmpeg seeks within it.

signal started  # the first frame's up
signal ended
signal failed(why: String)

const RES := Vector2i(1080, 720)  # 3:2, the shape of the web game's screens. Raw frames, so this is the disk-bandwidth knob (~56 MB/s at 24 fps; the ring of chunks ~3.4 GB in user://)
const MAX_FPS := 60.0  # the source's own frame rate, up to this (ffprobe asks the file first); raw frames, so it's disk bandwidth too
const FALLBACK_FPS := 24.0  # when ffprobe can't say
const FRAME_BYTES := RES.x * RES.y * 3  # rgb24
const CHUNK_SEC := 10  # fetch granularity
const WORKERS := 2  # chunks fetching at once: network-bound, not CPU-bound
const QUEUE_MAX := 2  # finished chunks allowed to pile up before we stop fetching
const RING := 7  # chunk files; must exceed WORKERS + QUEUE_MAX + the two playing (the sound runs a little ahead into the next)
const RATE := 48000  # the sound, as ffmpeg writes it: stereo float samples at this rate
const AHEAD := 0.5  # seconds of sound poured ahead of what's heard
const TARGET_LUFS := -24.0  # every film brought to this loudness (EBU R128, measured chunk by chunk as they're fetched) before the Film bus's squeeze
const TRIM_MAX := 10.0  # dB either way, at most
const TRIM_RATE := 1.0  # dB a second it moves at, as the measure firms up (slow enough not to be heard)
# 5.1 to stereo with the centre (the dialogue) at full and the rest under it; ffmpeg's own -ac 2 puts the centre 3 dB down,
# under the score and the bangs. Through 5.1 first: that takes side or back surrounds, 7.1, whatever. (< : no clipping)
const DOWNMIX := "aformat=channel_layouts=5.1,pan=stereo|FL<FC+0.6*FL+0.4*BL|FR<FC+0.6*FR+0.4*BR,"

var _img := Image.create_empty(RES.x, RES.y, false, Image.FORMAT_RGB8)
var texture := ImageTexture.create_from_image(Image.create_empty(RES.x, RES.y, false, Image.FORMAT_RGB8))
var audio := AudioStreamPlayer3D.new()  # the sound, from the screen it's playing on (tapes.gd puts it there)
var content := Rect2(Vector2.ZERO, RES)  # where the film itself sits in the frame (the rest: the black it's padded with); full screen shows just this
var url := ""  # what's playing ("" when nothing is)
var position := 0.0  # seconds into it
var duration := 0.0  # 0 when Jellyfin doesn't say
var paused := false
var tint := Color.BLACK  # the average colour of the frame on screen (black when nothing's playing): what the screens light the room with

var fps := 0.0  # what's playing plays at (the source's own); 0 while ffprobe's still asking

var _has_ffmpeg := false
var _probe := {}  # { pid, pipe }: ffprobe asking the file its frame rate
var _fps_of := {}  # url -> [its frame rate, content, its channels], once asked (a seek starts over with the same url)
var _channels := 2  # the source's sound (more than 2: DOWNMIX)
var _loud_of := {}  # url -> [summed power, chunks]: its loudness so far, from the chunks fetched (silent ones left out)
var _trim := 0.0  # dB on the Film bus's Amplify, heading for TARGET_LUFS
var _src_pos := 0.0  # where the next chunk to fetch starts
var _jobs: Array[Dictionary] = []  # { pid, file, at }: fetching now, oldest first
var _queue: Array[Dictionary] = []  # { file, at }: fetched, waiting their turn
var _live: Array[Dictionary] = []  # chunks being heard or shown, oldest first: { file, at, slot, s0 (where its sound starts, in samples poured), samples, frames, pcm (its sound, being read) }
var _gen: AudioStreamGeneratorPlayback = null
var _poured := 0  # samples into the stream since it started
var _room := 0  # the stream's buffer, in samples (how far ahead it can be)
var _slot := 0
var _empty := 0  # chunks in a row that came back with nothing: two, and it's over
var _shown := 0  # frames put up since it started


func _ready() -> void:
	add_child(audio)
	audio.position = Vector3.ZERO  # (the TV's, once a tape goes in: tapes.gd)
	audio.unit_size = 3.0
	audio.attenuation_model = AudioStreamPlayer3D.ATTENUATION_DISABLED  # (it only pans: how far off and what walls are between, ambience.gd's _hear, after the squeeze)
	audio.attenuation_filter_db = 0.0
	audio.bus = "Film"  # (evened out there: ambience.gd)
	_has_ffmpeg = OS.execute("ffmpeg", ["-version"], []) == 0


func _exit_tree() -> void:
	stop()


func play_episode(ep: Array, at := 0.0) -> void:  # ep: ["jellyfin", title, item id, seconds long] (jellyfin.gd makes them)
	play_url(Library.stream_url(ep[2]), at)
	duration = ep[3] if ep.size() > 3 else 0.0


func play_url(u: String, at := 0.0) -> void:
	var fresh := u != url  # (a seek isn't: it keeps the trim it had)
	stop()
	if not _has_ffmpeg:
		failed.emit("ffmpeg isn't on this machine's PATH")
		return
	url = u
	_src_pos = maxf(0.0, at)
	position = _src_pos
	paused = false
	_shown = 0
	fps = _fps_of.get(u, [0.0])[0]
	content = _fps_of.get(u, [0.0, Rect2(Vector2.ZERO, RES)])[1]
	_channels = _fps_of.get(u, [0.0, content, 2])[2]
	if fresh:  # (a film heard before starts where it was; a new one level till it's measured)
		_trim = _trim_for(u)
		_set_trim()
	if fps == 0.0:  # (a line a stream: "codec_type=video|width=...|...")
		var p := OS.execute_with_pipe("ffprobe", ["-v", "error", "-show_entries", "stream=codec_type,channels,avg_frame_rate,r_frame_rate,width,height,sample_aspect_ratio", "-of", "compact=p=0", url])
		if p.is_empty():
			fps = FALLBACK_FPS
		else:
			_probe = p


func pause(on := not paused) -> void:
	paused = on
	audio.stream_paused = on


func seek(to: float) -> void:
	if not url.is_empty():
		play_url(url, clampf(to, 0.0, duration if duration > 0.0 else to))


func stop() -> void:
	if not _probe.is_empty():
		OS.kill(_probe.pid)
		_probe = {}
	for job in _jobs:  # else they keep fetching chunks of something we've left
		OS.kill(job.pid)
	_jobs.clear()
	_queue.clear()
	_live.clear()
	_gen = null
	_poured = 0
	audio.stop()
	audio.stream = null
	tint = Color.BLACK
	url = ""
	_empty = 0
	for i in RING:  # (a killed ffmpeg can hold its file a moment: whatever's left goes next time)
		for path in [_raw(i), _pcm(i), _loud(i)]:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _raw(slot: int) -> String:
	return "user://video_%d.raw" % slot


func _pcm(slot: int) -> String:
	return "user://video_%d.pcm" % slot


func _loud(slot: int) -> String:
	return "user://video_%d.loud" % slot


func _heard(job: Dictionary) -> void:  # a fetched chunk's loudness (ebur128's integrated, the last it printed) into its film's
	var f := FileAccess.open(_loud(job.slot), FileAccess.READ)
	if f == null:
		return
	var lufs := 0.0
	for line in f.get_as_text().split("\n"):
		if line.begins_with("lavfi.r128.I="):
			lufs = line.get_slice("=", 1).to_float()
	if lufs > -50.0 and lufs < 0.0:  # (silence, or nothing measured: no say)
		var sofar: Array = _loud_of.get(url, [0.0, 0])
		_loud_of[url] = [sofar[0] + pow(10.0, lufs / 10.0), sofar[1] + 1]


func _trim_for(u: String) -> float:
	var sofar: Array = _loud_of.get(u, [0.0, 0])
	if sofar[1] == 0:
		return 0.0
	return clampf(TARGET_LUFS - 10.0 * log(sofar[0] / sofar[1]) / log(10.0), -TRIM_MAX, TRIM_MAX)


func _set_trim() -> void:
	var bus := AudioServer.get_bus_index("Film")
	if bus >= 0:
		(AudioServer.get_bus_effect(bus, 0) as AudioEffectAmplify).volume_db = _trim


func _process(dt: float) -> void:
	if url.is_empty():
		return
	if fps == 0.0:  # the frame rate first: every chunk's made at it
		if OS.is_process_running(_probe.pid):
			return
		var said := {}
		_channels = 2
		while true:  # (a line a stream, till they stop: the first picture's, and the most channels any sound has, which ffmpeg picks)
			var line: String = _probe.stdio.get_line().strip_edges()
			if line.is_empty():
				break
			var stream := {}
			for f in line.split("|"):
				var kv := f.split("=")
				if kv.size() == 2:
					stream[kv[0]] = kv[1]
			if stream.get("codec_type") == "video" and said.is_empty():
				said = stream
			elif stream.get("codec_type") == "audio":
				_channels = maxi(_channels, stream.get("channels", "2").to_int())
		fps = _rate("%s,%s" % [said.get("avg_frame_rate", ""), said.get("r_frame_rate", "")])
		content = _fit(said)
		_fps_of[url] = [fps, content, _channels]
		_probe = {}
	# keep the queue stocked: ffmpeg fetches faster than it plays, so the next chunk's landed before this one runs out.
	# Workers finish out of order, so only the oldest is released: that keeps the queue in order
	while not _jobs.is_empty() and not OS.is_process_running(_jobs[0].pid):
		var job: Dictionary = _jobs.pop_front()
		if _chunk_ok(job.file):
			_queue.append(job)
			_heard(job)
			_empty = 0
		else:  # past the end, or the server gave up on it
			_empty += 1
	var more := duration <= 0.0 or _src_pos < duration
	while more and _empty < 2 and _jobs.size() < WORKERS and _queue.size() < QUEUE_MAX:
		if not _start_chunk():
			return
		more = duration <= 0.0 or _src_pos < duration
	_trim = move_toward(_trim, _trim_for(url), TRIM_RATE * dt)
	_set_trim()
	_pour()
	if _gen == null:
		return
	var heard := maxi(0, _poured - (_room - _gen.get_frames_available()))  # (what's been heard: poured, less what's still waiting in the buffer)
	while _live.size() > 0 and heard >= _live[0].s0 + _live[0].samples and (_live.size() > 1 or _queue.is_empty()):
		_live.pop_front()  # (heard all of it, and the next's begun: done with)
	if _live.is_empty():
		if _jobs.is_empty() and _queue.is_empty() and (not more or _empty >= 2):  # nothing left to come
			var was_empty := _shown == 0
			stop()
			if was_empty:
				failed.emit("the server wouldn't play it")
			else:
				ended.emit()
		return
	var c: Dictionary = _live[0]
	var into := clampf(float(heard - c.s0) / RATE, 0.0, float(c.samples) / RATE)
	position = c.at + into
	_show(c, mini(int(into * fps), c.frames - 1))


func _pour() -> void:  # the sound: into the stream as far ahead as it'll take, chunk after chunk with nothing between
	if _gen == null:
		if _queue.is_empty():
			return
		var stream := AudioStreamGenerator.new()
		stream.mix_rate = RATE
		stream.buffer_length = AHEAD
		audio.stream = stream
		audio.play()
		audio.stream_paused = paused
		_gen = audio.get_stream_playback()
		_room = _gen.get_frames_available()
	var want := _gen.get_frames_available()
	while want > 0:
		var c = _live.back() if not _live.is_empty() and _live.back().poured < _live.back().samples else null
		if c == null:
			if _queue.is_empty():
				return  # (the next chunk isn't here yet: the sound waits, and the picture with it)
			c = _queue.pop_front()
			var raw := FileAccess.open(c.file, FileAccess.READ)
			c.frames = int(raw.get_length() / FRAME_BYTES) if raw else 0
			c.pcm = FileAccess.open(c.pcm_path, FileAccess.READ)
			c.samples = int(c.pcm.get_length() / 8) if c.pcm else int(c.frames / fps * RATE)  # (no sound: as long as its picture, in silence)
			c.poured = 0
			c.s0 = _poured
			_live.append(c)
			continue
		var n := mini(want, c.samples - c.poured)
		var buf := PackedVector2Array()
		buf.resize(n)
		if c.pcm != null:
			var f: PackedFloat32Array = c.pcm.get_buffer(n * 8).to_float32_array()
			for i in mini(n, f.size() / 2):
				buf[i] = Vector2(f[i * 2], f[i * 2 + 1])
		_gen.push_buffer(buf)
		c.poured += n
		_poured += n
		want -= n


func _start_chunk() -> bool:
	var file := _raw(_slot)
	var pid := OS.create_process("ffmpeg", [
		"-hide_banner", "-loglevel", "error",
		# a server can drop the connection mid-transfer; without this the tail of a chunk is whatever arrived before the socket died
		"-reconnect", "1", "-reconnect_streamed", "1", "-reconnect_delay_max", "5",
		"-ss", str(_src_pos), "-t", str(CHUNK_SEC), "-i", url,  # -t before -i bounds the input, so it covers both outputs
		# fitted inside the frame at its own shape, black round it (never stretched)
		"-vf", "scale=%d:%d:force_original_aspect_ratio=decrease:flags=lanczos,pad=%d:%d:(ow-iw)/2:(oh-ih)/2,fps=%s" % [RES.x, RES.y, RES.x, RES.y, fps],  # the picture: uncompressed rgb24, byte for byte what Image.FORMAT_RGB8 wants
		"-f", "rawvideo", "-pix_fmt", "rgb24", "-y", ProjectSettings.globalize_path(file),
		# the sound: a second output of the same process (surround mixed down to stereo), measured on its way (_heard)
		"-vn", "-af", (DOWNMIX if _channels > 2 else "") + "ebur128=metadata=1,ametadata=print:key=lavfi.r128.I:file='%s'" % _escaped(_loud(_slot)),
		"-ac", "2", "-ar", str(RATE), "-f", "f32le", "-y", ProjectSettings.globalize_path(_pcm(_slot)),
	])
	if pid == -1:
		_has_ffmpeg = false
		stop()
		failed.emit("ffmpeg wouldn't start")
		return false
	_jobs.append({ "pid": pid, "file": file, "pcm_path": _pcm(_slot), "at": _src_pos, "slot": _slot })
	_slot = (_slot + 1) % RING
	_src_pos += CHUNK_SEC
	return true


static func _escaped(path: String) -> String:  # a path inside a filter's quotes (Windows' "C:" would end the option)
	return ProjectSettings.globalize_path(path).replace("\\", "/").replace(":", "\\:")


static func _fit(said: Dictionary) -> Rect2:  # the film's own shape, fitted inside RES as ffmpeg's scale and pad put it (a pixel in from each edge: no black seam)
	var w: float = said.get("width", "0").to_float()
	var h: float = said.get("height", "0").to_float()
	var sar := str(said.get("sample_aspect_ratio", "1:1")).split_floats(":")
	if w <= 0.0 or h <= 0.0:
		return Rect2(Vector2.ZERO, RES)
	var shape := w / h * (sar[0] / sar[1] if sar.size() == 2 and sar[0] > 0.0 and sar[1] > 0.0 else 1.0)
	var size := Vector2(RES.x, RES.x / shape) if shape > float(RES.x) / RES.y else Vector2(RES.y * shape, RES.y)
	return Rect2((Vector2(RES) - size) / 2.0, size).grow(-1.0)


static func _rate(line: String) -> float:  # ffprobe's "avg,r" (each "24000/1001"): the average if it has one, else the nominal
	for f in line.strip_edges().split(","):
		var nd := f.split_floats("/")
		if nd.size() == 2 and nd[0] > 0.0 and nd[1] > 0.0:
			return clampf(nd[0] / nd[1], 1.0, MAX_FPS)
	return FALLBACK_FPS


func _chunk_ok(path: String) -> bool:  # (against a whole frame: that catches truncated ones too)
	var f := FileAccess.open(path, FileAccess.READ)
	return f != null and f.get_length() >= FRAME_BYTES


func _frame_tint(buf: PackedByteArray) -> Color:  # a sparse stride, not every pixel: a light needs the gist
	var step := maxi(1, (RES.x * RES.y) / 1000) * 3
	var r := 0
	var g := 0
	var b := 0
	var n := 0
	for i in range(0, buf.size() - 2, step):
		r += buf[i]
		g += buf[i + 1]
		b += buf[i + 2]
		n += 1
	return Color(r, g, b) / (255.0 * maxi(1, n))


func _show(c: Dictionary, i: int) -> void:  # that frame of the chunk up, if it isn't already (read straight from where it sits in the file)
	if i < 0 or c.get("shown", -1) == i:
		return
	if not c.has("raw"):
		c.raw = FileAccess.open(c.file, FileAccess.READ)
	if c.raw == null:
		return
	c.raw.seek(i * FRAME_BYTES)
	var buf: PackedByteArray = c.raw.get_buffer(FRAME_BYTES)
	if buf.size() != FRAME_BYTES:
		return
	c.shown = i
	_img.set_data(RES.x, RES.y, false, Image.FORMAT_RGB8, buf)  # (the one image, refilled: not 2 MB made and thrown away a frame)
	texture.update(_img)
	tint = _frame_tint(buf)
	_shown += 1
	if _shown == 1:
		started.emit()
