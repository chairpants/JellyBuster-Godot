extends Node
## Plays a video from Jellyfin: its picture onto `texture` (put that on whatever's showing it), its sound out of
## `audio`. No screen of its own. Give it a tape's episode, ["jellyfin", title, item id, seconds long]:
##     $Video.play_episode(tape.seasons[0].episodes[0])
##     some_material.albedo_texture = $Video.texture
## pause(), seek(seconds), stop(); `position` is where it's got to; `ended` when it runs out, `failed(why)` if it can't.
##
## From SpaceLife's scripts/wall_tv.gd: the picture comes from ffmpeg, not a Godot plugin and not through a video
## codec. ffmpeg opens the https stream, seeks, and writes plain uncompressed frames a chunk at a time, which are
## blitted into the texture one by one; the chunk's sound comes out beside it as Ogg. (Godot's own player only reads
## Ogg Theora, and transcoding to that ran below realtime.) So ffmpeg has to be on the machine's PATH; without it,
## failed() and nothing plays. The cost is disk: raw frames are ~10 MB/s, in user://, cleared when it stops.
## The file comes straight off the Jellyfin server (static stream, no server transcode); ffmpeg seeks within it.

signal started  # the first frame's up
signal ended
signal failed(why: String)

const RES := Vector2i(528, 352)  # 3:2, the shape of the web game's screens. Raw frames, so this is the disk-bandwidth knob
const FPS := 15
const FRAME_BYTES := RES.x * RES.y * 3  # rgb24
const CHUNK_SEC := 10  # fetch granularity
const WORKERS := 2  # chunks fetching at once: network-bound, not CPU-bound
const QUEUE_MAX := 2  # finished chunks allowed to pile up before we stop fetching
const RING := 6  # chunk files; must exceed WORKERS + QUEUE_MAX + the one playing

var texture := ImageTexture.create_from_image(Image.create_empty(RES.x, RES.y, false, Image.FORMAT_RGB8))
var audio := AudioStreamPlayer3D.new()  # the sound, from the screen it's playing on (tapes.gd puts it there)
var url := ""  # what's playing ("" when nothing is)
var position := 0.0  # seconds into it
var duration := 0.0  # 0 when Jellyfin doesn't say
var paused := false
var tint := Color.BLACK  # the average colour of the frame on screen (black when nothing's playing): what the screens light the room with

var _has_ffmpeg := false
var _src_pos := 0.0  # where the next chunk to fetch starts
var _jobs: Array[Dictionary] = []  # { pid, file, at }: fetching now, oldest first
var _queue: Array[Dictionary] = []  # { file, at }: fetched, waiting their turn
var _reader: FileAccess = null  # the chunk on screen
var _slot := 0
var _acc := 0.0
var _empty := 0  # chunks in a row that came back with nothing: two, and it's over
var _shown := 0  # frames put up since it started


func _ready() -> void:
	add_child(audio)
	audio.position = Vector3.ZERO  # (the TV's, once a tape goes in: tapes.gd)
	audio.unit_size = 3.0
	audio.max_db = 3.0
	_has_ffmpeg = OS.execute("ffmpeg", ["-version"], []) == 0


func _exit_tree() -> void:
	stop()


func play_episode(ep: Array, at := 0.0) -> void:  # ep: ["jellyfin", title, item id, seconds long] (jellyfin.gd makes them)
	play_url($"../Jellyfin".stream_url(ep[2]), at)
	duration = ep[3] if ep.size() > 3 else 0.0


func play_url(u: String, at := 0.0) -> void:
	stop()
	if not _has_ffmpeg:
		failed.emit("ffmpeg isn't on this machine's PATH")
		return
	url = u
	_src_pos = maxf(0.0, at)
	position = _src_pos
	paused = false
	_shown = 0


func pause(on := not paused) -> void:
	paused = on
	audio.stream_paused = on


func seek(to: float) -> void:
	if not url.is_empty():
		play_url(url, clampf(to, 0.0, duration if duration > 0.0 else to))


func stop() -> void:
	for job in _jobs:  # else they keep fetching chunks of something we've left
		OS.kill(job.pid)
	_jobs.clear()
	_queue.clear()
	_reader = null
	audio.stop()
	audio.stream = null
	tint = Color.BLACK
	url = ""
	_empty = 0
	_acc = 0.0
	for i in RING:  # (a killed ffmpeg can hold its file a moment: whatever's left goes next time)
		for path in [_raw(i), _ogg(i)]:
			if FileAccess.file_exists(path):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _raw(slot: int) -> String:
	return "user://video_%d.raw" % slot


func _ogg(slot: int) -> String:
	return "user://video_%d.ogg" % slot


func _process(dt: float) -> void:
	if url.is_empty():
		return
	# keep the queue stocked: ffmpeg fetches faster than it plays, so the next chunk's landed before this one runs out.
	# Workers finish out of order, so only the oldest is released: that keeps the queue in order
	while not _jobs.is_empty() and not OS.is_process_running(_jobs[0].pid):
		var job: Dictionary = _jobs.pop_front()
		if _chunk_ok(job.file):
			_queue.append(job)
			_empty = 0
		else:  # past the end, or the server gave up on it
			_empty += 1
	var more := duration <= 0.0 or _src_pos < duration
	while more and _empty < 2 and _jobs.size() < WORKERS and _queue.size() < QUEUE_MAX:
		if not _start_chunk():
			return
		more = duration <= 0.0 or _src_pos < duration
	if paused:
		return
	_acc += dt
	while _acc >= 1.0 / FPS:
		_acc -= 1.0 / FPS
		if not _next_frame():
			_acc = 0.0
			if _jobs.is_empty() and _queue.is_empty() and (not more or _empty >= 2):  # nothing left to come
				var was_empty := _shown == 0
				stop()
				if was_empty:
					failed.emit("the server wouldn't play it")
				else:
					ended.emit()
			break


func _start_chunk() -> bool:
	var file := _raw(_slot)
	var pid := OS.create_process("ffmpeg", [
		"-hide_banner", "-loglevel", "error",
		# a server can drop the connection mid-transfer; without this the tail of a chunk is whatever arrived before the socket died
		"-reconnect", "1", "-reconnect_streamed", "1", "-reconnect_delay_max", "5",
		"-ss", str(_src_pos), "-t", str(CHUNK_SEC), "-i", url,  # -t before -i bounds the input, so it covers both outputs
		# fitted inside the frame at its own shape, black round it (never stretched)
		"-vf", "scale=%d:%d:force_original_aspect_ratio=decrease,pad=%d:%d:(ow-iw)/2:(oh-ih)/2,fps=%d" % [RES.x, RES.y, RES.x, RES.y, FPS],  # the picture: uncompressed rgb24, byte for byte what Image.FORMAT_RGB8 wants
		"-f", "rawvideo", "-pix_fmt", "rgb24", "-y", ProjectSettings.globalize_path(file),
		"-vn", "-c:a", "libvorbis", "-q:a", "3", "-y", ProjectSettings.globalize_path(_ogg(_slot)),  # the sound: a second output of the same process
	])
	if pid == -1:
		_has_ffmpeg = false
		stop()
		failed.emit("ffmpeg wouldn't start")
		return false
	_jobs.append({ "pid": pid, "file": file, "at": _src_pos, "slot": _slot })
	_slot = (_slot + 1) % RING
	_src_pos += CHUNK_SEC
	return true


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


func _next_frame() -> bool:
	for _attempt in 2:
		if _reader == null:
			if _queue.is_empty():
				return false
			var chunk: Dictionary = _queue.pop_front()
			_reader = FileAccess.open(chunk.file, FileAccess.READ)
			position = chunk.at
			# sound rides along with the picture: both start at the top of the chunk, so drift is bounded by one chunk
			var ogg := AudioStreamOggVorbis.load_from_file(ProjectSettings.globalize_path(_ogg(chunk.slot)))
			if ogg != null:
				audio.stream = ogg
				audio.play()
			continue
		var buf := _reader.get_buffer(FRAME_BYTES)
		if buf.size() == FRAME_BYTES:
			texture.update(Image.create_from_data(RES.x, RES.y, false, Image.FORMAT_RGB8, buf))
			tint = _frame_tint(buf)
			position += 1.0 / FPS
			_shown += 1
			if _shown == 1:
				started.emit()
			return true
		_reader = null  # short read: the chunk's run out
	return false
