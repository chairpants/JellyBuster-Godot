extends Node
## The library, from a Jellyfin server. Its address and an API key (Jellyfin's Dashboard → API Keys) go in
## user://jellyfin.cfg, written blank the first time round:
##     [server]
##     url="http://192.168.1.10:8096"
##     api_key="..."
## At the start it fetches every movie and series (and the series' episodes) in two requests, makes a tape of each
## movie and of each season, puts each in the store's section that best fits (data/genres.json), sorts them by section
## then title, and puts them on the shelves' slots in order (tapes.gd's tapes, sorted by their section): one
## slot each; the slots left over come off the shelves.
## ponytail: stocks VaultBuster's own slots, so the covers are still VaultBuster's. The shelf builder replaces this.

const CFG := "user://jellyfin.cfg"

var url := ""
var key := ""
var status := "Jellyfin: connecting…"
var items: Array = []  # a tape each: { id, cover (item ids to try for its picture), t, sort, c (section), e (episodes, as video.gd plays them) }

@onready var tapes: Node = $"../Tapes"
@onready var hud: CanvasLayer = $"../HUD"


func _ready() -> void:
	var cfg := ConfigFile.new()
	cfg.load(CFG)
	url = str(cfg.get_value("server", "url", "")).trim_suffix("/")
	key = str(cfg.get_value("server", "api_key", ""))
	if url.is_empty() or key.is_empty():
		cfg.set_value("server", "url", url)
		cfg.set_value("server", "api_key", key)
		cfg.save(CFG)
		status = "Jellyfin: no server set · fill in %s" % ProjectSettings.globalize_path(CFG)
		return
	var shows = await _fetch("/Items?Recursive=true&IncludeItemTypes=Movie,Series&Fields=Genres,SortName")
	var eps = await _fetch("/Items?Recursive=true&IncludeItemTypes=Episode&Fields=SortName")
	if shows == null or eps == null:
		return
	items = build(shows.Items, eps.Items, JSON.parse_string(FileAccess.get_file_as_string("res://data/genres.json")).sections)
	stock()


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
			out.append({ "id": it.Id, "cover": [it.Id], "t": it.Name, "sort": sort, "c": c, "e": [_ep(it, it.Name)] })
			continue
		for sid: String in by_series.get(it.Id, []):  # (a series with nothing in it has nothing to play)
			var first: Dictionary = seasons[sid][0]
			var n: int = first.get("ParentIndexNumber", 0)
			var season: String = first.get("SeasonName", "Specials" if n == 0 else "Season %d" % n)
			out.append({ "id": sid, "cover": [sid, it.Id], "t": "%s: %s" % [it.Name, season], "sort": "%s %04d" % [sort, n if n > 0 else 9999], "c": c,
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


func stock() -> void:
	var slots: Array = tapes.tapes.duplicate()
	slots.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.c < b.c)  # (VaultBuster's sections stay together)
	tapes.batch = true
	for i in slots.size():
		var t: Dictionary = slots[i]
		if i < items.size():
			t.merge({ "t": items[i].t, "c": items[i].c, "e": items[i].e, "ep": 0, "at": 0.0 }, true)
		else:
			tapes.set_on_shelf(t, false)
	tapes.batch = false
	tapes.commit()
	status = "Jellyfin: %d titles%s" % [items.size(), " (%d didn't fit on the shelves)" % (items.size() - slots.size()) if items.size() > slots.size() else ""]
	hud.toast(status)


func stream_url(id: String) -> String:  # the file as it is: ffmpeg does the rest (video.gd)
	return "%s/Videos/%s/stream?static=true&api_key=%s" % [url, id, key]


func cover_url(id: String, height := 400) -> String:  # for the shelf builder
	return "%s/Items/%s/Images/Primary?maxHeight=%d" % [url, id, height]
