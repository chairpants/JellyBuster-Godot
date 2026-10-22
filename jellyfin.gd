extends Node
## The library, from a Jellyfin server. The first time round (or when it can't be reached) the loading screen asks
## for the server's address and an API key (Jellyfin's Dashboard → API Keys → +), and keeps them in
## user://jellyfin.cfg; F2 asks again, to change them. Or: a made-up library, to look round without a server.
## It fetches every movie and series (and the series' episodes) in two requests, makes a tape of each movie and of
## each season, puts each in the store's section that best fits (data/genres.json), sorts them by section then title.
## It's the autoload `Library`, and it goes first: the store's laid out to fit (store.gd plan(): how deep it has to
## be, Level.dz) before the store's scene opens. Covers come as they're needed, cached in user://covers720.
## --demo[=N] goes straight to a made-up library of N films (and series besides).

signal chosen(what: String)  # the settings form: "connect" or "demo"

const CFG := "user://jellyfin.cfg"
const CACHE := "user://library.json"  # the last library fetched, to open with when the server can't be reached
const RECLASS := "user://sections.cfg"  # the shelf you've put a movie or series on yourself (covers.gd's SHELF), over its genres: item id -> section

var url := ""
var key := ""
var watch_as := ""  # whose watching it's kept as on the server (a user's name; "" whoever's used Jellyfin last)
var user_id := ""  # theirs, once connected ("" in the demo: nothing's kept)
var status := ""
var demo := false
var offline := false  # opened on the library as it was last time (CACHE): nothing to play
var items: Array = []  # a tape each: { id, cover (item ids to try for its picture), t, sort, c (section), kind (movie / series), year, added (when it came to the server), seen, e (episodes, as video.gd plays them) }
var played := {}  # item id -> true: the movies and episodes watched to the end, as whoever's watching (seen on the shelf: tapes.gd's sticker)
var plan := {}  # where everything goes (store.gd plan())
var _first := 0  # a box's back being fetched: the shelf's covers wait for it (the one you're looking at goes first)


func _ready() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--demo"):
			_demo(a.get_slice("=", 1).to_int() if "=" in a else 600)
			return
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	url = cfg.get_value("server", "url", "")
	key = cfg.get_value("server", "api_key", "")
	watch_as = cfg.get_value("server", "watch_as", "")
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
		var got := {}  # both asked for at once; no images or watched state wanted (they doubled the wait for the episodes)
		var ask_for := func(k: String, what: String) -> void: got[k] = await _fetch("/Items?Recursive=true&EnableImages=false&EnableUserData=false&EnableTotalRecordCount=false&" + what)
		ask_for.call("shows", "IncludeItemTypes=Movie,Series&Fields=Genres,SortName,ProductionYear,DateCreated")
		ask_for.call("eps", "IncludeItemTypes=Episode&Fields=SortName,DateCreated")
		while got.size() < 2:
			await get_tree().process_frame
		var shows = got.shows
		var eps = got.eps
		if shows != null and eps != null:
			var cfg := ConfigFile.new()
			cfg.set_value("server", "url", url)
			cfg.set_value("server", "api_key", key)
			cfg.set_value("server", "watch_as", watch_as)
			cfg.save(CFG)
			demo = false
			offline = false
			items = build(shows.Items, eps.Items, _sections())
			var who: String = await _pick_user()
			var seen = await _fetch("/Items?Recursive=true&IsPlayed=true&IncludeItemTypes=Movie,Episode&userId=%s&EnableImages=false&EnableUserData=false&EnableTotalRecordCount=false" % user_id) if user_id else null
			played = {}
			for it: Dictionary in seen.Items if seen is Dictionary else []:
				played[it.Id] = true
			mark_seen()
			var f := FileAccess.open(CACHE, FileAccess.WRITE)
			f.store_string(JSON.stringify({ "shows": shows.Items, "eps": eps.Items, "played": played.keys(), "when": Time.get_datetime_string_from_system() }))
			f.close()
			status = "Jellyfin: %d tapes%s" % [items.size(), " · watching as " + who if who else ""]
			_open()
			return
		why = status
		if not ask and FileAccess.file_exists(CACHE):  # (not asked for, F2: the store as it was last time; F2 to try again)
			var kept: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CACHE))
			demo = false
			items = build(kept.shows, kept.eps, _sections())
			played = {}
			for id: String in kept.played:
				played[id] = true
			mark_seen()
			user_id = ""  # (nothing's told back: it'd go nowhere)
			offline = true
			status = "Offline: %s · the library as it was %s · F2 to try again" % [why.trim_prefix("Jellyfin: "), kept.when.left(10)]
			_open()
			return
		ask = true


func _demo(n: int) -> void:
	demo = true
	offline = false
	var d := demo_library(n)
	items = build(d.shows, d.eps, _sections())
	played = {}
	for i in range(0, d.shows.size(), 6):  # (some of it watched, to see the stickers)
		played[d.shows[i].Id] = true
	for ep: Dictionary in d.eps:
		if ep.SeriesId.substr(1).to_int() % 3 == 0:
			played[ep.Id] = true
	mark_seen()
	status = "Demo library: %d tapes" % items.size()
	_open()


func mark_seen() -> void:  # a tape's seen when everything on it's been watched
	for t: Dictionary in items:
		t.seen = t.e.all(func(ep: Array) -> bool: return played.has(ep[2]))


func shelves(kind: String) -> Array:  # the sections a movie (or a series) can go on, in the store's order
	return _sections().filter(func(s: Dictionary) -> bool: return s.get("for", kind) == kind).map(func(s: Dictionary) -> String: return s.name)


var moved := false  # a tape's been put on another shelf since the store opened: covers.gd restocks when it's closed


func reclass(t: Dictionary, section: String) -> void:  # onto another shelf, for good: a series with all its seasons (it moves when the store's next laid out)
	var cf := ConfigFile.new()
	cf.load(RECLASS)
	cf.set_value("moved", t.cover[-1], section)  # (a movie's own id; a season's series')
	cf.save(RECLASS)
	for it: Dictionary in items:
		if it.cover[-1] == t.cover[-1]:
			it.c = section
	moved = true


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
	var who := LineEdit.new()
	who.placeholder_text = "Watch as (a Jellyfin user; blank: whoever used it last)"
	who.text = watch_as
	box.add_child(who)
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
	watch_as = who.text.strip_edges()
	box.queue_free()
	return what


func restock() -> void:  # the store laid out again round the library as it is now (a tape moved to another shelf), where you were in it kept
	var main := get_tree().current_scene
	if main != null and main.has_node("Save"):
		main.get_node("Save").save()
	var order := {}
	var secs := _sections()
	for i in secs.size():
		order[secs[i].name] = i
	items.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return order[a.c] < order[b.c] or (a.c == b.c and a.sort < b.sort))
	_open()


func _open() -> void:  # the store, laid out round the library, opens
	plan = preload("res://store.gd").plan(items, JSON.parse_string(FileAccess.get_file_as_string("res://data/genres.json")))
	get_node("/root/Level").set_depth(plan.dz)  # (by path: tools/jellyfin_check.gd loads this without the autoloads)
	moved = false
	get_tree().change_scene_to_file.call_deferred("res://main.tscn")


func _fetch(path: String):  # the parsed reply, or null (and the status says why)
	var http := HTTPRequest.new()
	http.use_threads = true  # (off the main thread: on it, each request waited on the frame)
	add_child(http)
	http.request(url + path, _auth())
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
	var moved := ConfigFile.new()
	moved.load(RECLASS)
	var names := sections.map(func(s: Dictionary) -> String: return s.name)
	for it: Dictionary in shows:
		var sort := str(it.get("SortName", it.Name)).to_lower()
		var c := classify(it.get("Genres", []), "series" if it.Type == "Series" else "movie", sections)
		if moved.get_value("moved", it.Id, "") in names:
			c = moved.get_value("moved", it.Id)
		if it.Type != "Series":
			out.append({ "id": it.Id, "cover": [it.Id], "t": it.Name, "sort": sort, "c": c, "kind": "movie", "year": it.get("ProductionYear", 0), "added": it.get("DateCreated", ""), "e": [_ep(it, it.Name)] })
			continue
		for sid: String in by_series.get(it.Id, []):  # (a series with nothing in it has nothing to play)
			var first: Dictionary = seasons[sid][0]
			var n: int = first.get("ParentIndexNumber", 0)
			var season: String = first.get("SeasonName", "Specials" if n == 0 else "Season %d" % n)
			out.append({ "id": sid, "cover": [sid, it.Id], "t": "%s: %s" % [it.Name, season], "sort": "%s %04d" % [sort, n if n > 0 else 9999], "c": c, "kind": "series", "year": first.get("ProductionYear", it.get("ProductionYear", 0)),
				"added": seasons[sid].reduce(func(m: String, ep: Dictionary) -> String: return m if m > str(ep.get("DateCreated", "")) else str(ep.get("DateCreated", "")), ""), "e": seasons[sid].map(func(ep: Dictionary) -> Array: return _ep(ep, "%s - S%02dE%02d - %s" % [it.Name, n, ep.get("IndexNumber", 0), ep.Name])) })
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


func _auth() -> PackedStringArray:  # the key, as Jellyfin wants it now (10.11 turned X-Emby-Token and api_key off by default)
	return ['Authorization: MediaBrowser Client="JellyVault", Token="%s"' % key]


func stream_url(id: String) -> String:  # the file as it is: ffmpeg does the rest (video.gd)
	return "%s/Videos/%s/stream?static=true&ApiKey=%s" % [url, id, key]


func cover_path(ids: Array) -> String:  # where a tape's cover is kept once it's come
	return "user://covers720/%s.jpg" % ids[0]  # (720 tall: sharp held up close; the shelf takes a smaller copy)


func cover(ids: Array) -> Image:  # a tape's cover: the first of its ids Jellyfin has a picture for (a season's own, else its series'); null if none
	var path := cover_path(ids)
	if FileAccess.file_exists(path):
		return Image.load_from_file(path)
	if demo or url.is_empty():
		return null
	for id: String in ids:
		while _first > 0:
			await get_tree().process_frame
		var http := HTTPRequest.new()
		http.use_threads = true  # (off the main thread: on it, each request waited on the frame)
		add_child(http)
		http.request("%s/Items/%s/Images/Primary?maxHeight=720&format=Jpg&quality=88" % [url, id], _auth())
		var r: Array = await http.request_completed
		http.queue_free()
		var img := Image.new()
		if r[0] == HTTPRequest.RESULT_SUCCESS and r[1] == 200 and img.load_jpg_from_buffer(r[3]) == OK:
			DirAccess.make_dir_recursive_absolute("user://covers720")
			FileAccess.open(path, FileAccess.WRITE).store_buffer(r[3])
			return img
	return null  # ponytail: asked again every start; remember the misses if a big library's start drags


const DETAIL_FIELDS := "Overview,People,Genres,Taglines,Studios,OfficialRating,CommunityRating,CriticRating,ProductionYear,RunTimeTicks,ImageTags,BackdropImageTags"


func details(t: Dictionary) -> Dictionary:  # what the back of a tape's box says (backbox.gd): a movie's own, a season's with its series' filling the gaps; {} in the demo or if it can't be had
	if demo or url.is_empty():
		return {}
	_first += 1
	var r = await _fetch("/Items?Ids=%s&Fields=%s" % [",".join(t.cover), DETAIL_FIELDS])  # (a season's cover ids: itself, then its series)
	_first -= 1
	if r == null or r.Items.is_empty():
		return {}
	var by := {}
	for it: Dictionary in r.Items:
		by[it.Id] = it
	var own: Dictionary = by.get(t.cover[0], r.Items[0])
	var top: Dictionary = by.get(t.cover[-1], own)  # (a movie: itself)
	var pick := func(k: String, empty: Variant) -> Variant: return own[k] if own.get(k) and own[k] != empty else top.get(k, empty)
	var people: Array = pick.call("People", [])
	return {
		"title": top.get("Name", t.t), "season": own.get("Name", "") if own != top else "", "year": own.get("ProductionYear", top.get("ProductionYear", 0)),
		"rating": top.get("OfficialRating", ""), "stars": top.get("CommunityRating", 0.0), "critics": top.get("CriticRating", 0),
		"minutes": roundi(own.get("RunTimeTicks", 0) / 600000000.0), "tagline": (pick.call("Taglines", []) + [""])[0], "overview": pick.call("Overview", ""),
		"genres": top.get("Genres", []), "studios": top.get("Studios", []).map(func(s: Dictionary) -> String: return s.Name),
		"people": people.map(func(p: Dictionary) -> Dictionary: return { "id": p.Id, "name": p.Name, "role": p.get("Role", ""), "type": p.Type, "img": p.has("PrimaryImageTag") }),
		"backdrop": own.Id if own.get("BackdropImageTags", []).size() else top.Id if top.get("BackdropImageTags", []).size() else "",
		"logo": top.Id if top.get("ImageTags", {}).has("Logo") else "",
	}


func _pick_user() -> String:  # whose watching's kept: the one named in the settings, else whoever's used Jellyfin last
	user_id = ""
	var users = await _fetch("/Users")
	if not users is Array or users.is_empty():
		return ""
	users.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return str(a.get("LastActivityDate", "")) > str(b.get("LastActivityDate", "")))
	var pick: Dictionary = users[0]
	for u: Dictionary in users:
		if u.Name.to_lower() == watch_as.to_lower():
			pick = u
	user_id = pick.Id
	return pick.Name


func resume_at(id: String) -> float:  # where they left it, on the server (0: never started, or watched to the end)
	if demo or user_id.is_empty():
		return 0.0
	var r = await _fetch("/UserItems/%s/UserData?userId=%s" % [id, user_id])
	return 0.0 if not r is Dictionary or r.get("Played", false) else r.get("PlaybackPositionTicks", 0) / 10000000.0


func intros(id: String) -> Array:  # what the server plays before it (its Cinema Mode: trailers, pre-rolls), as item ids; [] if nothing, or in the demo
	if demo or offline or user_id.is_empty():
		return []
	var r = await _fetch("/Items/%s/Intros?userId=%s" % [id, user_id])
	return r.get("Items", []).map(func(it: Dictionary) -> String: return it.Id) if r is Dictionary else []


func trailers(n: int, but: String) -> Array:  # trailers the server has for a few films picked at random (not that one), as item ids: up to n
	if demo or offline or user_id.is_empty():
		return []
	var films := items.filter(func(t: Dictionary) -> bool: return t.kind == "movie" and t.id != but)
	films.shuffle()
	var out := []
	for t: Dictionary in films.slice(0, 8):  # (most films have none: asked of a few)
		var r = await _fetch("/Items/%s/LocalTrailers?userId=%s" % [t.id, user_id])
		if r is Array and not r.is_empty():
			out.append(r.pick_random().Id)
			if out.size() >= n:
				break
	return out


func report(id: String, at: float, played := false) -> void:  # how far they've got, onto the server: other Jellyfin apps pick it up from there
	if demo or user_id.is_empty():
		return
	var http := HTTPRequest.new()
	add_child(http)
	var body := { "PlaybackPositionTicks": 0 if played else int(at * 10000000.0), "Played": played, "LastPlayedDate": Time.get_datetime_string_from_system(true) + "Z" }
	http.request("%s/UserItems/%s/UserData?userId=%s" % [url, id, user_id], _auth() + PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, JSON.stringify(body))
	await http.request_completed
	http.queue_free()


func streams(id: String) -> Array:  # what's in its file: [{ Type (Video / Audio / Subtitle), Index, Language, DisplayTitle, IsTextSubtitleStream, IsExternal, ... }]
	if demo or url.is_empty():
		return []
	var r = await _fetch("/Items?Ids=%s&Fields=MediaStreams" % id)
	return r.Items[0].get("MediaStreams", []) if r is Dictionary and not r.get("Items", []).is_empty() else []


func subtitles(id: String, index: int) -> Array:  # a subtitle track, as srt() cues ([]: none to be had). The server makes it the first time, which can take a while: kept in user://subs after
	var path := "user://subs/%s_%d.srt" % [id, index]
	if FileAccess.file_exists(path):
		return srt(FileAccess.get_file_as_string(path))
	if demo or url.is_empty():
		return []
	var http := HTTPRequest.new()
	http.use_threads = true
	add_child(http)
	http.timeout = 120.0
	http.request("%s/Videos/%s/%s/Subtitles/%d/0/Stream.srt" % [url, id, id, index], _auth())
	var r: Array = await http.request_completed
	http.queue_free()
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] != 200:
		return []
	DirAccess.make_dir_recursive_absolute("user://subs")
	FileAccess.open(path, FileAccess.WRITE).store_buffer(r[3])
	return srt(r[3].get_string_from_utf8())


static func srt(text: String) -> Array:  # SubRip as cues; their markup (<i>, <font>, ASS's {\...}) dropped
	var out: Array = []
	var tags := RegEx.create_from_string("<[^>]*>|\\{[^}]*\\}")
	var t := func(hms: String) -> float:
		var p := hms.strip_edges().replace(",", ".").split(":")
		return p[0].to_float() * 3600.0 + p[1].to_float() * 60.0 + p[2].to_float() if p.size() == 3 else 0.0
	for block: String in text.replace("\r", "").split("\n\n", false):
		var lines := block.strip_edges().split("\n")
		for i in lines.size():
			if " --> " in lines[i]:
				var words := tags.sub("\n".join(lines.slice(i + 1)), "", true).replace("\\N", "\n").strip_edges()
				if words != "":
					out.append([t.call(lines[i].get_slice(" --> ", 0)), t.call(lines[i].get_slice(" --> ", 1)), words])
				break
	out.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	return out


func remote_covers(id: String) -> Array:  # the covers Jellyfin's providers (TMDb, Fanart...) have for it, as its Identify > Images shows: [{ Url, ThumbnailUrl, ProviderName, Width, Height, Language, CommunityRating }]
	if demo or url.is_empty():
		return []
	var r = await _fetch("/Items/%s/RemoteImages?type=Primary&includeAllLanguages=true" % id)
	return r.get("Images", []) if r is Dictionary else []


func search_covers(term: String, kind: String) -> Array:  # Identify's search: the providers' matches for a name (and a year, "Alien 1979"), a cover each; shaped as remote_covers' are
	if demo or url.is_empty() or term.strip_edges().is_empty():
		return []
	var info := { "Name": term.strip_edges() }
	var year := RegEx.create_from_string("\\s(\\d{4})$").search(info.Name)
	if year:
		info.Name = info.Name.left(year.get_start()).strip_edges()
		info.Year = year.get_string(1).to_int()
	var http := HTTPRequest.new()
	http.use_threads = true
	add_child(http)
	http.request("%s/Items/RemoteSearch/%s" % [url, "Series" if kind == "series" else "Movie"], _auth() + PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, JSON.stringify({ "SearchInfo": info, "IncludeDisabledProviders": true }))
	var r: Array = await http.request_completed
	http.queue_free()
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] != 200:
		return []
	var out := []
	for m: Dictionary in JSON.parse_string(r[3].get_string_from_utf8()):
		if m.get("ImageUrl"):
			out.append({ "Url": m.ImageUrl, "ThumbnailUrl": m.ImageUrl.replace("/t/p/original/", "/t/p/w342/"),  # (TMDb's: a small one to show)
				"ProviderName": "%s %s" % [m.get("Name", ""), "(%d)" % m.ProductionYear if m.get("ProductionYear") else ""], "Match": m })
	return out


func set_cover(id: String, image_url: String) -> bool:  # Jellyfin fetches that one and makes it the cover (the key has to be an admin's); the copy kept here goes
	var http := HTTPRequest.new()
	add_child(http)
	http.request("%s/Items/%s/RemoteImages/Download?type=Primary&imageUrl=%s" % [url, id, image_url.uri_encode()], _auth(), HTTPClient.METHOD_POST)
	var r: Array = await http.request_completed
	http.queue_free()
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] >= 300:
		status = "Jellyfin wouldn't change the cover (%s)" % ("HTTP %d: is the key an admin's?" % r[1] if r[0] == HTTPRequest.RESULT_SUCCESS else "no answer")
		return false
	for f in DirAccess.get_files_at("user://covers720"):
		if f.begins_with(id):
			DirAccess.remove_absolute("user://covers720/" + f)
	return true


func identify(id: String, match: Dictionary) -> bool:  # Jellyfin's Identify: the item is this match (its ids, details and pictures fetched again); an admin's key
	var http := HTTPRequest.new()
	add_child(http)
	http.request("%s/Items/RemoteSearch/Apply/%s?replaceAllImages=true" % [url, id], _auth() + PackedStringArray(["Content-Type: application/json"]), HTTPClient.METHOD_POST, JSON.stringify(match))
	var r: Array = await http.request_completed
	http.queue_free()
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] >= 300:
		status = "Jellyfin wouldn't re-identify it (%s)" % ("HTTP %d: is the key an admin's?" % r[1] if r[0] == HTTPRequest.RESULT_SUCCESS else "no answer")
		return false
	for f in DirAccess.get_files_at("user://covers720"):  # (its old cover, and its seasons')
		if f.begins_with(id):
			DirAccess.remove_absolute("user://covers720/" + f)
	return true


func web_image(at: String) -> Image:  # a picture straight off the web (a provider's thumbnail): no key, not kept
	var http := HTTPRequest.new()
	http.use_threads = true
	add_child(http)
	http.request(at)
	var r: Array = await http.request_completed
	http.queue_free()
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] != 200:
		return null
	var img := Image.new()
	for load: Callable in [img.load_jpg_from_buffer, img.load_png_from_buffer, img.load_webp_from_buffer]:
		if load.call(r[3]) == OK:
			return img
	return null


func image(id: String, kind: String, max_w: int) -> Image:  # any picture Jellyfin has (a backdrop, a logo, a face), cached in user://art; null if none
	var path := "user://art/%s_%s_%d.%s" % [id, kind, max_w, "png" if kind == "Logo" else "jpg"]  # (logos keep their see-through)
	if FileAccess.file_exists(path):
		return Image.load_from_file(path)
	if demo or url.is_empty() or id.is_empty():
		return null
	var http := HTTPRequest.new()
	http.use_threads = true  # (off the main thread: on it, each request waited on the frame)
	add_child(http)
	http.request("%s/Items/%s/Images/%s?maxWidth=%d&format=%s&quality=85" % [url, id, kind, max_w, "Png" if kind == "Logo" else "Jpg"], _auth())
	var r: Array = await http.request_completed
	http.queue_free()
	var img := Image.new()
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] != 200 or (img.load_png_from_buffer(r[3]) if kind == "Logo" else img.load_jpg_from_buffer(r[3])) != OK:
		return null
	DirAccess.make_dir_recursive_absolute("user://art")
	FileAccess.open(path, FileAccess.WRITE).store_buffer(r[3])
	return img


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
		var added := Time.get_datetime_string_from_unix_time(1600000000 + i * 7919 % 1000 * 160000)  # (not from rng: the same library as ever, tape for tape)
		shows.append({ "Id": "d%d" % i, "Type": "Series" if series else "Movie", "Name": title.strip_edges(), "Genres": g, "RunTimeTicks": 54000000000, "ProductionYear": rng.randi_range(1965, 2025), "DateCreated": added })
		if series:
			for s in rng.randi_range(1, 5):
				for e in rng.randi_range(6, 22):
					eps.append({ "Id": "d%de%d_%d" % [i, s, e], "SeriesId": "d%d" % i, "SeasonId": "d%ds%d" % [i, s + 1], "SeasonName": "Season %d" % (s + 1), "ParentIndexNumber": s + 1, "IndexNumber": e + 1, "Name": "Episode %d" % (e + 1), "RunTimeTicks": 13200000000, "DateCreated": added })
	return { "shows": shows, "eps": eps }
