extends SceneTree
## The library's tapes and sections, without a server: godot --headless --path . --script tools/jellyfin_check.gd

func _init() -> void:
	var J := load("res://jellyfin.gd")
	var sections: Array = JSON.parse_string(FileAccess.get_file_as_string("res://data/genres.json")).sections
	var C := func(g: Array, kind := "movie") -> String: return J.classify(g, kind, sections)
	assert(C.call(["Horror"]) == "Horror")
	assert(C.call(["Comedy", "Horror"]) == "Comedy")  # first listed wins...
	assert(C.call(["Comedy", "Anime"]) == "Anime")  # ...unless the other's strong
	assert(C.call(["Drama", "History"]) == "Drama")
	assert(C.call(["Animation", "Family", "Comedy"]) == "Animation")
	assert(C.call(["Mockumentary"]) == "Drama")  # nothing matches: the movies' fallback
	assert(C.call([]) == "Drama")
	assert(C.call(["COMEDY"], "series") == "TV Comedy")  # (any case; series to TV sections)
	assert(C.call(["Animation", "Comedy"], "series") == "Cartoons")
	assert(C.call([], "series") == "TV Drama")
	assert(C.call(["Western", "Drama"], "series") == "Westerns")  # (a section for both)
	var shows := [
		{ "Id": "m1", "Type": "Movie", "Name": "The Thing", "SortName": "Thing", "Genres": ["Horror"], "RunTimeTicks": 65000000000 },
		{ "Id": "m2", "Type": "Movie", "Name": "Alien", "Genres": ["Horror", "Science Fiction"] },
		{ "Id": "m3", "Type": "Movie", "Name": "Airplane!", "Genres": ["Comedy"] },
		{ "Id": "s1", "Type": "Series", "Name": "Cheers", "Genres": ["Comedy"] },
		{ "Id": "s2", "Type": "Series", "Name": "Empty", "Genres": ["Comedy"] },
	]
	var eps := [
		{ "Id": "e2", "SeriesId": "s1", "SeasonId": "c1", "SeasonName": "Season 1", "ParentIndexNumber": 1, "IndexNumber": 2, "Name": "Sam's Women" },
		{ "Id": "e3", "SeriesId": "s1", "SeasonId": "c2", "SeasonName": "Season 2", "ParentIndexNumber": 2, "IndexNumber": 1, "Name": "Power Play" },
		{ "Id": "e1", "SeriesId": "s1", "SeasonId": "c1", "SeasonName": "Season 1", "ParentIndexNumber": 1, "IndexNumber": 1, "Name": "Give Me a Ring" },
		{ "Id": "e0", "SeriesId": "s1", "SeasonId": "c0", "ParentIndexNumber": 0, "IndexNumber": 1, "Name": "Uncut" },
	]
	var out: Array = J.build(shows, eps, sections)
	var got := out.map(func(t: Dictionary) -> String: return "%s/%s" % [t.c, t.t])
	assert(got == ["Comedy/Airplane!", "Horror/Alien", "Horror/The Thing", "TV Comedy/Cheers: Season 1", "TV Comedy/Cheers: Season 2", "TV Comedy/Cheers: Specials"], str(got))  # section order, then title, seasons in order, specials last; the empty series gone
	assert(out[3].e.map(func(e: Array) -> String: return e[2]) == ["e1", "e2"])
	assert(out[3].cover == ["c1", "s1"])
	assert(out[2].e[0] == ["jellyfin", "The Thing", "m1", 6500.0])
	print("jellyfin_check: ok")
	quit()
