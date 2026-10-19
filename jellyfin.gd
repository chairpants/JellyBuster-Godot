extends Node
## The library, from a Jellyfin server. Its address and an API key (Jellyfin's Dashboard → API Keys) go in
## user://jellyfin.cfg, written blank the first time round:
##     [server]
##     url="http://192.168.1.10:8096"
##     api_key="..."
## At the start it fetches every movie and series (and the series' episodes) in two requests, sorts them by genre
## then title, and puts them on the shelves' slots in order (tapes.gd's tapes, sorted by their section): one
## slot each; the slots left over come off the shelves.
## ponytail: stocks VaultBuster's own slots, so the covers are still VaultBuster's. The shelf builder replaces this.

const CFG := "user://jellyfin.cfg"

var url := ""
var key := ""
var status := "Jellyfin: connecting…"
var items: Array = []  # every movie and series: { id, t, sort, c (genre), e (episodes, as video.gd plays them) }

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
	items = build(shows.Items, eps.Items)
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


static func build(shows: Array, eps: Array) -> Array:  # Jellyfin's items as tapes: sorted by genre, then title
	var by_series := {}
	eps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.get("ParentIndexNumber", 0) * 10000 + a.get("IndexNumber", 0) < b.get("ParentIndexNumber", 0) * 10000 + b.get("IndexNumber", 0))
	for ep: Dictionary in eps:
		by_series.get_or_add(ep.get("SeriesId", ""), []).append(_ep(ep, "%s - S%02dE%02d - %s" % [ep.get("SeriesName", ""), ep.get("ParentIndexNumber", 0), ep.get("IndexNumber", 0), ep.Name]))
	var out := []
	for it: Dictionary in shows:
		var genres: Array = it.get("Genres", [])
		var e: Array = by_series.get(it.Id, []) if it.Type == "Series" else [_ep(it, it.Name)]
		if not e.is_empty():  # (a series with nothing in it has nothing to play)
			out.append({ "id": it.Id, "t": it.Name, "sort": str(it.get("SortName", it.Name)).to_lower(), "c": genres[0] if genres.size() else "Other", "e": e })
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.c < b.c or (a.c == b.c and a.sort < b.sort))
	return out


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
