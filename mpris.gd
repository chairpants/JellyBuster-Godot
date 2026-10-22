extends Node
## The keyboard's media keys, and the desktop's own player controls (KDE's media applet, GNOME's, playerctl). On Linux
## those mostly never come to the window as keys: the desktop keeps them and hands them over D-Bus (MPRIS) to whatever
## player says it's playing. mpris.py is that player for us: what the VCR's doing goes to it a line at a time, and
## what it's asked to do comes back (_heard), to tapes.gd's transport like the VCR's own keys.

const EVERY := 1.0  # how often it's told where the tape's got to (it runs Position on between)

@onready var main := get_parent()
@onready var tapes: Node = main.get_node("Tapes")
@onready var video: Node = main.get_node("Video")
var _p := {}  # { stdio, stderr, pid }: mpris.py
var _listen := Thread.new()
var _said := ""
var _t := 0.0


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if OS.get_name() != "Linux" or "--shot" in args or "--snapshot" in args:
		return
	_p = OS.execute_with_pipe("python3", [ProjectSettings.globalize_path("res://mpris.py")])
	if _p.is_empty():
		print("mpris: no python3, so no media keys")
		return
	_listen.start(_read)


func _exit_tree() -> void:
	if _p.is_empty():
		return
	OS.kill(_p.pid)
	_listen.wait_to_finish()


func _read() -> void:  # (its own thread: a line blocks till one comes)
	var io: FileAccess = _p.stdio
	while OS.is_process_running(_p.pid):
		var line := io.get_line().strip_edges()
		if not line.is_empty():
			_heard.call_deferred(line)


func _heard(line: String) -> void:
	var w := line.split(" ")
	match w[0]:
		"raise":
			DisplayServer.window_move_to_foreground()
		"quit":
			get_tree().root.propagate_notification(NOTIFICATION_WM_CLOSE_REQUEST)  # (as the window's close: save.gd keeps everything first)
		_:
			tapes.transport(w[0], w[1].to_float() if w.size() > 1 else 0.0)


func _process(dt: float) -> void:
	if _p.is_empty():
		return
	if not OS.is_process_running(_p.pid):  # (gone on its own: another JellyVault has the bus name, say)
		_listen.wait_to_finish()
		_p = {}
		return
	_t += dt
	var now := _now()
	var said := JSON.stringify(now)
	now.erase("pos")
	if _t < EVERY and JSON.stringify(now) == _said:  # (anything but how far in: told straight away)
		return
	_t = 0.0
	_said = JSON.stringify(now)
	_p.stdio.store_line(said)
	_p.stdio.flush()


func _now() -> Dictionary:
	if tapes.playing == null:
		return { "status": "Stopped" }
	var tape: Dictionary = tapes.playing.tape
	var ep: Array = tape.e[tapes.playing.idx]
	var art: String = Library.cover_path(tape.cover) if not tape.get("cover", []).is_empty() else ""
	return {
		"status": "Paused" if video.paused or video.url.is_empty() else "Playing",
		"id": ep[2],
		"title": ep[1],
		"album": tape.t if tape.e.size() > 1 else "",
		"length": video.duration,
		"pos": snappedf(video.position, 0.1),
		"art": "file://" + ProjectSettings.globalize_path(art) if not art.is_empty() and FileAccess.file_exists(art) else "",
	}
