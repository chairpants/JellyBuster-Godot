extends Node
## The shift's clock (the autoload `Clock`). From the web game: store/shift.js (SHIFT, afterClose, fmtClock) and
## store/clock.js (shiftTick, skipHour). The store's open 10 AM to midnight; while it is, a store hour goes by every
## HOUR real seconds, and after midnight the clock runs in real time. L skips an hour.

signal toast(text: String)

const START := 9.0
const OPEN := 10.0
const LAST_IN := 23.75
const CLOSE := 24.0
const SHIFT_MIN := 21.0  # the web game's SETTINGS.shiftMin: a ~21 minute shift
var HOUR := SHIFT_MIN * 60.0 / 14.0  # real seconds per store hour while open (the settings' shift length changes it: menu.gd)
const WEEKDAYS: Array[String] = ["SUN", "MON", "TUE", "WED", "THU", "FRI", "SAT"]

var h := START  # hours since the shift day's midnight
var day := 1  # day 1 is Monday, September 30, 1996
var warp := 0.0


func _process(dt: float) -> void:
	var was := h
	if warp > h:
		h = minf(warp, h + dt / 2.5)  # L: an hour in 2.5 s
	else:
		h += dt / (HOUR if h < CLOSE else 3600.0)  # after close: real time
	if was < OPEN and h >= OPEN:
		toast.emit("10:00 AM — we're open")
	if was < LAST_IN and h >= LAST_IN:
		toast.emit("11:45 PM — last customers of the night")
	if was < CLOSE and h >= CLOSE:
		toast.emit("Midnight — closing time")


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_L:
		skip_hour()


func skip_hour() -> void:  # never past close: after that the clock's real
	if after_close():
		toast.emit("After close the clock's running for real")
		return
	warp = minf(CLOSE, maxf(warp, h) + 1.0)


func after_close() -> bool:
	return h >= CLOSE


func fmt_clock(at: float) -> String:
	var t := int(floor(at * 3600.0))
	var hh := (t / 3600) % 24
	var mm := (t / 60) % 60
	return "%d:%02d %s" % [12 if hh % 12 == 0 else hh % 12, mm, "AM" if hh < 12 else "PM"]


func date() -> Dictionary:  # the shift's date: { year, month, day, weekday (0 = Sunday), ... }
	var first := Time.get_unix_time_from_datetime_dict({ "year": 1996, "month": 9, "day": 30, "hour": 12, "minute": 0, "second": 0 })
	return Time.get_datetime_dict_from_unix_time(first + (day - 1) * 86400)


func weekday() -> String:
	return WEEKDAYS[date().weekday]


func status() -> String:  # the web HUD's word for it
	return "CLOSED" if after_close() else "OPENS 10 AM" if h < OPEN else "OPEN"
