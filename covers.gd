extends CanvasLayer
## A new cover for the tape in hand (I): what Jellyfin's providers have for it, as its own Identify > Images
## shows them, a grid to click. The pick goes to the server (it fetches it and keeps it as the cover), then
## onto the shelf and into your hand (tapes.gd's recover()). I or Esc closes it; the mouse comes back after.
## Or a search of your own (Identify's: the providers' matches for a name, a year on the end narrows it), when
## the tape's own match is the wrong film, or has nothing good: a cover per match.

const THUMB := Vector2(150, 225)  # a cover's shape, 2:3
const MAX := 40  # the first this many: the providers' best, by rating

var tape = null
var _panel := PanelContainer.new()
var _title := Label.new()
var _grid := GridContainer.new()
var _term := LineEdit.new()
var _shelf := OptionButton.new()
var _ask := 0  # which asking the grid's showing (a slow answer to an older one is dropped)


func _ready() -> void:
	layer = 6
	_panel.visible = false
	_panel.set_anchors_preset(Control.PRESET_CENTER)
	_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	var style := StyleBoxFlat.new()  # (the picture menu's look: picture.gd)
	style.bg_color = Color(0, 0.03, 0.12, 0.88)
	style.border_color = Color("#7dff9a")
	style.set_border_width_all(2)
	style.set_content_margin_all(14)
	_panel.add_theme_stylebox_override("panel", style)
	add_child(_panel)
	var box := VBoxContainer.new()
	_panel.add_child(box)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	var row := HBoxContainer.new()
	box.add_child(row)
	_term.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_term.placeholder_text = "Search for a title (a year on the end narrows it: Alien 1979)"
	_term.text_submitted.connect(func(_s: String) -> void: _search())
	row.add_child(_term)
	for b: Array in [["SEARCH", _search], ["ITS OWN", func() -> void: _own()]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.pressed.connect(b[1])
		row.add_child(btn)
	var shelf_row := HBoxContainer.new()  # which section it's shelved in: its genres' pick, or yours
	box.add_child(shelf_row)
	var l := Label.new()
	l.text = "SHELF"
	shelf_row.add_child(l)
	_shelf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shelf.item_selected.connect(func(i: int) -> void:
		var to := _shelf.get_item_text(i)
		if tape != null and to != tape.c:
			Library.reclass(tape, to)
			$"../HUD".toast("%s goes on the %s shelf: restocking when you close this" % [tape.t.get_slice(": Season", 0), to]))
	shelf_row.add_child(_shelf)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(5 * (THUMB.x + 8) + 16, 2.2 * (THUMB.y + 30))
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	_grid.columns = 5
	scroll.add_child(_grid)


func open(t: Dictionary) -> void:
	tape = t
	_panel.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_term.text = t.t.get_slice(": Season", 0)  # (a season's: its series' name)
	_shelf.clear()
	for s: String in Library.shelves(t.kind):
		_shelf.add_item(s)
		if s == t.c:
			_shelf.select(_shelf.item_count - 1)
	_own()


func _own() -> void:  # what its own match has
	var t: Dictionary = tape
	_list(t.t.to_upper(), Library.remote_covers.bind(t.cover[0]))  # (a season's own: its cover is its own, not its series')


func _search() -> void:
	_term.release_focus()  # (so the keys are the game's again)
	_list('"%s"' % _term.text.strip_edges(), Library.search_covers.bind(_term.text, tape.kind))


func _list(what: String, asking: Callable) -> void:  # asking: the call that finds them
	_ask += 1
	var ask := _ask
	for c in _grid.get_children():
		c.queue_free()
	_title.text = "COVERS FOR %s: asking Jellyfin..." % what
	var found: Array = await asking.call()
	if ask != _ask or tape == null:
		return
	_title.text = "COVERS FOR %s (%d): click one to use it" % [what, found.size()] if found.size() else "Nothing found for %s" % what
	for im: Dictionary in found.slice(0, MAX):
		var cell := VBoxContainer.new()
		var b := TextureButton.new()
		b.custom_minimum_size = THUMB
		b.ignore_texture_size = true
		b.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
		b.pressed.connect(_pick.bind(im.Url))
		cell.add_child(b)
		var l := Label.new()
		l.text = im.get("ProviderName", "") + ("  %dx%d" % [im.Width, im.Height] if im.get("Width") else "")
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.add_theme_font_size_override("font_size", 11)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.custom_minimum_size.x = THUMB.x
		cell.add_child(l)
		if im.has("Match"):  # (a search's: it can be what the tape is, not only how it looks)
			var it := Button.new()
			it.text = "IT'S THIS ONE"
			it.add_theme_font_size_override("font_size", 11)
			it.tooltip_text = "Jellyfin re-identifies the movie (or the whole series) as this: its title, details and cover"
			it.pressed.connect(func() -> void:
				if it.text == "IT'S THIS ONE":
					it.text = "SURE? CLICK AGAIN"
				else:
					_identify(im.Match))
			cell.add_child(it)
		_grid.add_child(cell)
		_thumb(b, im.get("ThumbnailUrl", "") if im.get("ThumbnailUrl") else im.Url)  # (they fill in as they come)


func _thumb(b: TextureButton, at: String) -> void:
	var img: Image = await Library.web_image(at)
	if img != null and is_instance_valid(b):
		b.texture_normal = ImageTexture.create_from_image(img)


func _pick(image_url: String) -> void:
	var t: Dictionary = tape
	_title.text = "Changing the cover..."
	if await Library.set_cover(t.cover[0], image_url):
		close()
		$"../Tapes".recover(t)
	else:
		_title.text = Library.status


func _identify(match: Dictionary) -> void:  # Jellyfin's Identify: it's this film (or series), not the one it matched; the server fetches its details and cover
	var t: Dictionary = tape
	_title.text = "Telling Jellyfin it's %s..." % match.get("Name", "that")
	if not await Library.identify(t.cover[-1], match):
		_title.text = Library.status
		return
	close()
	$"../HUD".toast("Jellyfin has it as %s now: the new cover's on its way; its name changes when the store next opens" % match.get("Name", "that"))
	await get_tree().create_timer(6.0).timeout  # (the server's fetching the new details and pictures)
	$"../Tapes".recover(t)


func close() -> void:
	tape = null
	_panel.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if Library.moved:  # (a tape put on another shelf: the store's laid out again, now)
		$"../HUD".toast("Restocking the shelves...")
		Library.restock()


func _unhandled_input(e: InputEvent) -> void:
	if _panel.visible and (e is InputEventKey and e.pressed and not e.echo and e.physical_keycode in [KEY_I, KEY_ESCAPE] or e is InputEventMouseButton and e.pressed and e.button_index <= MOUSE_BUTTON_RIGHT):  # (a click off the panel: closed, as the picture menu is)
		close()
		get_viewport().set_input_as_handled()
