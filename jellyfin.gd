extends Node
## The library, from a Jellyfin server. The first time round (or when it can't be reached) the loading screen asks
## for the server's address and an API key (Jellyfin's Dashboard → API Keys → +), and keeps them in
## user://jellyfin.cfg; F2 asks again, to change them. Or: a made-up library, to look round without a server.
## It fetches every movie and series (and the series' episodes) in two requests, makes a tape of each movie and of
## each season, puts each in the store's section that best fits (data/genres.json), sorts them by section then title.
## It's the autoload `Library`, and it goes first: the store's laid out to fit (store.gd plan(): how deep it has to
## be, Level.dz) before the store's scene opens. Covers come as they're needed, cached in user://covers.
## --demo[=N] goes straight to a made-up library of N films (and series besides).

signal chosen(what: String)  # the settings form: "connect" or "demo"

const CFG := "user://jellyfin.cfg"

var url := ""
var key := ""
var status := ""
var demo := false
var items: Array = []  # a tape each: { id, cover (item ids to try for its picture), t, sort, c (section), kind (movie / series), year, e (episodes, as video.gd plays them) }
var plan := {}  # where everything goes (store.gd plan())


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--demo"):
			_demo(a.get_slice("=", 1).to_int() if "=" in a else 600)
			return
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	url = cfg.get_value("server", "url", "")
	key = cfg.get_value("server", "api_key", "")
	_start.call_deferred(url.is_empty() or key.is_empty())


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo and e.physical_keycode == KEY_F2 and get_tree().current_scene.name == "Main":  # F2: the server's settings again
		get_tree().change_scene_to_file("res://loading.tscn")
		_start.call_deferred(true)


func _start(ask: bool) -> void:  # (on the loading screen) connect, asking for the server first if need be, and open the store
	if get_tree().current_scene == null:
		return  # (run as a script, tools/jellyfin_check.gd: no store to open)
	var why := ""
	while true:
		if ask:
			if await _form(why) == "demo":
				_demo(600)
				return
		_say("Connecting to %s…" % url)
		var shows = await _fetch("/Items?Recursive=true&IncludeItemTypes=Movie,Series&Fields=Genres,SortName,ProductionYear")
		var eps = await _fetch("/Items?Recursive=true&IncludeItemTypes=Episode&Fields=SortName") if shows != null else null
		if shows != null and eps != null:
			var cfg := ConfigFile.new()
			cfg.set_value("server", "url", url)
			cfg.set_value("server", "api_key", key)
			cfg.save(CFG)
			demo = false
			items = build(shows.Items, eps.Items, _sections())
			status = "Jellyfin: %d tapes" % items.size()
			_open()
			return
		why = status
		ask = true


func _demo(n: int) -> void:
	demo = true
	var d := demo_library(n)
	items = build(d.shows, d.eps, _sections())
	status = "Demo library: %d tapes" % items.size()
	_open()


func _sections() -> Array:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/genres.json")).sections


func _say(text: String) -> void:  # the loading screen's line
	var l = get_tree().current_scene.get_node_or_null("Label") if get_tree().current_scene else null
	if l != null:
		l.text = text


func _form(why: String) -> String:  # the settings, on the loading screen: "connect" (url and key set) or "demo"
	_say("")
	var box := VBoxContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_KEEP_SIZE)
	box.custom_minimum_size = Vector2(460, 0)
	box.position -= Vector2(230, 140)
	box.add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.text = "Your Jellyfin server"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1, 0.83, 0))
	box.add_child(title)
	var server := LineEdit.new()
	server.placeholder_text = "Address, e.g. http://192.168.1.10:8096"
	server.text = url
	box.add_child(server)
	var api := LineEdit.new()
	api.placeholder_text = "API key (Dashboard → API Keys → +)"
	api.text = key
	api.secret = true
	box.add_child(api)
	var note := Label.new()
	note.text = why
	note.add_theme_color_override("font_color", Color(1, 0.5, 0.45))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(note)
	var go := Button.new()
	go.text = "Connect"
	box.add_child(go)
	var try := Button.new()
	try.text = "Look round with a made-up library instead"
	try.flat = true
	box.add_child(try)
	get_tree().current_scene.add_child(box)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	server.grab_focus()
	var submit := func(_t := "") -> void:
		if server.text.strip_edges() != "" and api.text.strip_edges() != "":
			chosen.emit("connect")
		else:
			note.text = "Both, please: the server's address and an API key."
	go.pressed.connect(submit)
	server.text_submitted.connect(submit)
	api.text_submitted.connect(submit)
	try.pressed.connect(func() -> void: chosen.emit("demo"))
	var what: String = await chosen
	url = server.text.strip_edges().trim_suffix("/")
	if not url.contains("://"):
		url = "http://" + url
	key = api.text.strip_edges()
	box.queue_free()
	return what


func _open() -> void:  # the store, laid out round the library, opens
	plan = preload("res://store.gd").plan(items, JSON.parse_string(FileAccess.get_file_as_string("res://data/genres.json")))
	get_node("/root/Level").set_depth(plan.dz)  # (by path: tools/jellyfin_check.gd loads this without the autoloads)
	get_tree().change_scene_to_file.call_deferred("res://main.tscn")


func _fetch(path: String):  # the parsed reply, or null (and the status says why)
	var http := HTTPRequest.new()
	add_child(http)
	http.request(url + path, ["X-Emby-Token: " + key])
	var r: Array = await http.request_completed
	http.queue_free()
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] != 200:
		status = "Jellyfin: couldn't reach %s (%s)" % [url, "HTTP %d" % r[1] if r[0] == HTTPRequest.RESULT_SUCCESS else "no answer"]
		return null
	return JSON.parse_string(r[3].get_string_from_utf8())


static func build(shows: Array, eps: Array, sections: Array) -> Array:  # Jellyfin's items as tapes: a movie each, a season of a series each; by section (in the store's order), then title
	var seasons := {}  # season id -> its episodes, in order
	eps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.get("ParentIndexNumber", 0) * 10000 + a.get("IndexNumber", 0) < b.get("ParentIndexNumber", 0) * 10000 + b.get("IndexNumber", 0))
	for ep: Dictionary in eps:
		seasons.get_or_add(ep.get("SeasonId", ""), []).append(ep)
	var by_series := {}  # series id -> [season id, ...]
	for sid: String in seasons:
		by_series.get_or_add(seasons[sid][0].get("SeriesId", ""), []).append(sid)
	var out := []
	for it: Dictionary in shows:
		var sort := str(it.get("SortName", it.Name)).to_lower()
		var c := classify(it.get("Genres", []), "series" if it.Type == "Series" else "movie", sections)
		if it.Type != "Series":
			out.append({ "id": it.Id, "cover": [it.Id], "t": it.Name, "sort": sort, "c": c, "kind": "movie", "year": it.get("ProductionYear", 0), "e": [_ep(it, it.Name)] })
			continue
		for sid: String in by_series.get(it.Id, []):  # (a series with nothing in it has nothing to play)
			var first: Dictionary = seasons[sid][0]
			var n: int = first.get("ParentIndexNumber", 0)
			var season: String = first.get("SeasonName", "Specials" if n == 0 else "Season %d" % n)
			out.append({ "id": sid, "cover": [sid, it.Id], "t": "%s: %s" % [it.Name, season], "sort": "%s %04d" % [sort, n if n > 0 else 9999], "c": c, "kind": "series", "year": first.get("ProductionYear", it.get("ProductionYear", 0)),
				"e": seasons[sid].map(func(ep: Dictionary) -> Array: return _ep(ep, "%s - S%02dE%02d - %s" % [it.Name, n, ep.get("IndexNumber", 0), ep.Name])) })
	var order := {}
	for i in sections.size():
		order[sections[i].name] = i
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return order[a.c] < order[b.c] or (a.c == b.c and a.sort < b.sort))
	return out


static func classify(genres: Array, kind: String, sections: Array) -> String:  # the section that best matches (data/genres.json says how)
	var best := ""
	var best_score := 0.0
	var fallback := ""
	for s: Dictionary in sections:
		if s.get("for", kind) != kind:
			continue
		if s.get("fallback", false) and fallback.is_empty():
			fallback = s.name
		var score := 0.0
		for i in genres.size():
			if str(genres[i]).to_lower() in s.match:
				score += 1.0 / (i + 1)
		if score > 0.0 and s.get("strong", false):
			score += 1.0
		if score > best_score:
			best = s.name
			best_score = score
	return best if not best.is_empty() else fallback


static func _ep(it: Dictionary, title: String) -> Array:
	return ["jellyfin", title, it.Id, it.get("RunTimeTicks", 0) / 10000000.0]


func stream_url(id: String) -> String:  # the file as it is: ffmpeg does the rest (video.gd)
	return "%s/Videos/%s/stream?static=true&api_key=%s" % [url, id, key]


func cover_path(ids: Array) -> String:  # where a tape's cover is kept once it's come
	return "user://covers/%s.jpg" % ids[0]


func cover(ids: Array) -> Image:  # a tape's cover: the first of its ids Jellyfin has a picture for (a season's own, else its series'); null if none
	var path := cover_path(ids)
	if FileAccess.file_exists(path):
		return Image.load_from_file(path)
	if demo or url.is_empty():
		return null
	for id: String in ids:
		var http := HTTPRequest.new()
		add_child(http)
		http.request("%s/Items/%s/Images/Primary?maxHeight=360&format=Jpg&quality=85" % [url, id], ["X-Emby-Token: " + key])
		var r: Array = await http.request_completed
		http.queue_free()
		var img := Image.new()
		if r[0] == HTTPRequest.RESULT_SUCCESS and r[1] == 200 and img.load_jpg_from_buffer(r[3]) == OK:
			DirAccess.make_dir_recursive_absolute("user://covers")
			FileAccess.open(path, FileAccess.WRITE).store_buffer(r[3])
			return img
	return null  # ponytail: asked again every start; remember the misses if a big library's start drags


static func demo_library(n: int) -> Dictionary:  # Jellyfin-shaped: n movies, and a series for every fifth, each with a few seasons
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var pool := ["Action", "Adventure", "Comedy", "Drama", "Romance", "Thriller", "Crime", "Mystery", "Horror", "Science Fiction", "Fantasy", "Western", "Family", "Animation", "Anime", "Music", "Documentary", "Christmas", "War", "History", "Reality"]
	var words := ["Night", "Return", "City", "Last", "Dark", "Summer", "Killer", "Love", "Space", "Ghost", "River", "Heat", "Blue", "Iron", "Road", "Dream", "Wild", "Secret", "Storm", "Star"]
	var shows := []
	var eps := []
	for i in n + n / 5:
		var series := i >= n
		var g := []
		for k in rng.randi_range(1, 3):
			g.append(pool[rng.randi() % pool.size()])
		var title := "%s %s %s" % ["The" if rng.randf() < 0.3 else "", words[rng.randi() % words.size()], words[rng.randi() % words.size()]]
		shows.append({ "Id": "d%d" % i, "Type": "Series" if series else "Movie", "Name": title.strip_edges(), "Genres": g, "RunTimeTicks": 54000000000, "ProductionYear": rng.randi_range(1965, 2025) })
		if series:
			for s in rng.randi_range(1, 5):
				for e in rng.randi_range(6, 22):
					eps.append({ "Id": "d%de%d_%d" % [i, s, e], "SeriesId": "d%d" % i, "SeasonId": "d%ds%d" % [i, s + 1], "SeasonName": "Season %d" % (s + 1), "ParentIndexNumber": s + 1, "IndexNumber": e + 1, "Name": "Episode %d" % (e + 1), "RunTimeTicks": 13200000000 })
	return { "shows": shows, "eps": eps }
