extends SceneTree
## The library's sort, without a server: godot --headless --path . --script tools/jellyfin_check.gd

func _init() -> void:
	var J := load("res://jellyfin.gd")
	var shows := [
		{ "Id": "m1", "Type": "Movie", "Name": "The Thing", "SortName": "Thing", "Genres": ["Horror"], "RunTimeTicks": 65000000000 },
		{ "Id": "m2", "Type": "Movie", "Name": "Alien", "Genres": ["Horror", "Sci-Fi"] },
		{ "Id": "m3", "Type": "Movie", "Name": "Airplane!", "Genres": [] },
		{ "Id": "s1", "Type": "Series", "Name": "Cheers", "Genres": ["Comedy"] },
		{ "Id": "s2", "Type": "Series", "Name": "Empty", "Genres": ["Comedy"] },
	]
	var eps := [
		{ "Id": "e2", "SeriesId": "s1", "SeriesName": "Cheers", "ParentIndexNumber": 1, "IndexNumber": 2, "Name": "Sam's Women" },
		{ "Id": "e3", "SeriesId": "s1", "SeriesName": "Cheers", "ParentIndexNumber": 2, "IndexNumber": 1, "Name": "Power Play" },
		{ "Id": "e1", "SeriesId": "s1", "SeriesName": "Cheers", "ParentIndexNumber": 1, "IndexNumber": 1, "Name": "Give Me a Ring" },
	]
	var out: Array = J.build(shows, eps)
	var got := out.map(func(t: Dictionary) -> String: return "%s/%s" % [t.c, t.t])
	assert(got == ["Comedy/Cheers", "Horror/Alien", "Horror/The Thing", "Other/Airplane!"], str(got))  # genre, then sort name; empty series gone
	assert(out[0].e.map(func(e: Array) -> String: return e[2]) == ["e1", "e2", "e3"])
	assert(out[2].e[0] == ["jellyfin", "The Thing", "m1", 6500.0])
	print("jellyfin_check: ok")
	quit()
