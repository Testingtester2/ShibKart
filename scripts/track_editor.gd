extends Node2D
## In-game track editor — the headline feature.
##
## Build a course by placing centerline waypoints (the road auto-thickens to the
## chosen width), drop props (boost pads / coins / obstacles / oil), set the
## start/finish waypoint, then SAVE to user://tracks/<name>.track.json and LOAD
## any saved or bundled track. "Test Drive" jumps straight into a race on it.
##
## Controls:
##   Left click empty ....... add a waypoint (inserted into the loop sensibly)
##   Left drag on a point ... move it            Right click a point ... delete it
##   Prop mode: left click .. place current prop  Right click ... remove nearest prop
##   [S] set selected waypoint as start/finish
##   Middle-drag or arrows .. pan            Mouse wheel ... zoom

const TrackViewScript := preload("res://scripts/track_view.gd")

var track: Track
var track_view: TrackView
var camera: Camera2D

enum Mode { EDIT, PROP }
var mode: int = Mode.EDIT
var prop_type: String = "boost"

var selected: int = -1
var dragging := false
var panning := false
var _pan_last := Vector2.ZERO

# UI
var name_edit: LineEdit
var width_spin: SpinBox
var laps_spin: SpinBox
var prop_opt: OptionButton
var theme_opt: OptionButton
var weather_opt: OptionButton
var status: Label

const THEMES := ["grass", "cherry", "city", "desert", "moon", "snow", "volcano", "beach"]
const WEATHERS := ["clear", "rain", "snow", "fog"]
var load_popup: PanelContainer
var load_list: ItemList
var _load_paths: Array = []

func _ready() -> void:
	var gs := get_node_or_null("/root/GameState")
	# edit the currently-selected track if there is one, else start from a simple loop
	track = null
	if gs and gs.selected_track_path != "":
		track = Track.load_from(gs.selected_track_path)
	if track == null or not track.is_valid():
		track = Track.make_default()
		track.name = "My Track"
	track_view = TrackViewScript.new()
	track_view.show_waypoints = true
	track_view.show_smoothed = true          # preview the smoothed race ribbon
	track_view.set_track(track)
	add_child(track_view)

	camera = Camera2D.new()
	camera.zoom = Vector2(0.7, 0.7)
	add_child(camera)
	camera.make_current()
	camera.global_position = track.bounds().get_center()

	_build_ui()
	_refresh_fields()
	_set_status("Left-click to add points · drag to move · right-click to delete · S = start line")

# ------------------------------------------------------------------ world input
func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		var w := get_global_mouse_position()
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom(1.1)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom(1.0 / 1.1)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			panning = mb.pressed
			_pan_last = get_viewport().get_mouse_position()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_on_left_down(w)
			else:
				dragging = false
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_on_right_click(w)
	elif e is InputEventMouseMotion:
		if panning:
			var now := get_viewport().get_mouse_position()
			camera.global_position -= (now - _pan_last) / camera.zoom
			_pan_last = now
		elif dragging and selected >= 0 and mode == Mode.EDIT:
			track.waypoints[selected] = get_global_mouse_position()
			track_view.selected_index = selected
			track_view.queue_redraw()
	elif e is InputEventKey and e.pressed and not e.echo:
		_on_key(e.keycode)

func _on_left_down(w: Vector2) -> void:
	if mode == Mode.PROP:
		track.props.append({ "type": prop_type, "pos": w, "rot": 0.0 })
		track_view.queue_redraw()
		return
	# EDIT: grab a nearby waypoint, else add a new one
	var hit := _nearest_waypoint(w, 18.0)
	if hit >= 0:
		selected = hit
		dragging = true
		track_view.selected_index = selected
		track_view.queue_redraw()
	else:
		_insert_waypoint(w)

func _on_right_click(w: Vector2) -> void:
	if mode == Mode.PROP:
		var pi := _nearest_prop(w, 30.0)
		if pi >= 0:
			track.props.remove_at(pi)
			track_view.queue_redraw()
		return
	var hit := _nearest_waypoint(w, 18.0)
	if hit >= 0 and track.waypoints.size() > 3:
		track.waypoints.remove_at(hit)
		if track.start_index >= track.waypoints.size():
			track.start_index = 0
		selected = -1
		track_view.selected_index = -1
		track_view.queue_redraw()

func _on_key(kc: int) -> void:
	if kc == KEY_S and selected >= 0:
		track.start_index = selected
		track_view.queue_redraw()
		_set_status("Start/finish moved to waypoint %d" % selected)
	elif kc == KEY_DELETE and selected >= 0 and track.waypoints.size() > 3:
		track.waypoints.remove_at(selected)
		selected = -1
		track_view.selected_index = -1
		track_view.queue_redraw()

func _insert_waypoint(w: Vector2) -> void:
	var n := track.waypoints.size()
	if n < 2:
		track.waypoints.append(w)
	else:
		# insert after the segment whose body is closest to the click
		var best_i := 0
		var best_d := 1e9
		for i in range(n):
			var a := track.waypoints[i]
			var b := track.waypoints[(i + 1) % n]
			var d := Track._seg_dist(w, a, b)
			if d < best_d:
				best_d = d
				best_i = i
		track.waypoints.insert(best_i + 1, w)
		if track.start_index > best_i:
			track.start_index += 1
	selected = -1
	track_view.selected_index = -1
	track_view.queue_redraw()

func _process(dt: float) -> void:
	# arrow-key pan
	var pan := Vector2(
		Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left"),
		Input.get_action_strength("brake") - Input.get_action_strength("accelerate"))
	# also raw arrows
	if Input.is_key_pressed(KEY_LEFT): pan.x -= 1
	if Input.is_key_pressed(KEY_RIGHT): pan.x += 1
	if Input.is_key_pressed(KEY_UP): pan.y -= 1
	if Input.is_key_pressed(KEY_DOWN): pan.y += 1
	if pan != Vector2.ZERO:
		camera.global_position += pan.normalized() * 500.0 * dt / camera.zoom.x

func _zoom(f: float) -> void:
	camera.zoom = (camera.zoom * f).clamp(Vector2(0.25, 0.25), Vector2(2.5, 2.5))

# ------------------------------------------------------------------ helpers
func _nearest_waypoint(w: Vector2, radius: float) -> int:
	var r := radius / camera.zoom.x
	var best := -1
	var bd := r * r
	for i in range(track.waypoints.size()):
		var d := w.distance_squared_to(track.waypoints[i])
		if d < bd:
			bd = d
			best = i
	return best

func _nearest_prop(w: Vector2, radius: float) -> int:
	var r := radius / camera.zoom.x
	var best := -1
	var bd := r * r
	for i in range(track.props.size()):
		var p: Vector2 = track.props[i].get("pos", Vector2.ZERO)
		var d := w.distance_squared_to(p)
		if d < bd:
			bd = d
			best = i
	return best

# ------------------------------------------------------------------ UI
func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var bar := Panel.new()
	bar.position = Vector2(0, 0)
	bar.size = Vector2(1280, 52)
	layer.add_child(bar)

	var h := HBoxContainer.new()
	h.position = Vector2(12, 8)
	h.add_theme_constant_override("separation", 8)
	bar.add_child(h)

	h.add_child(_mk_static("Name"))
	name_edit = LineEdit.new()
	name_edit.custom_minimum_size = Vector2(160, 36)
	name_edit.text_changed.connect(func(t): track.name = t)
	h.add_child(name_edit)

	h.add_child(_mk_static("Width"))
	width_spin = SpinBox.new()
	width_spin.min_value = 80; width_spin.max_value = 500; width_spin.step = 10
	width_spin.value_changed.connect(_on_width_changed)
	h.add_child(width_spin)

	h.add_child(_mk_static("Laps"))
	laps_spin = SpinBox.new()
	laps_spin.min_value = 1; laps_spin.max_value = 9; laps_spin.step = 1
	laps_spin.value_changed.connect(func(v): track.laps = int(v))
	h.add_child(laps_spin)

	h.add_child(_mk_static("Theme"))
	theme_opt = OptionButton.new()
	for t in THEMES:
		theme_opt.add_item(t)
	theme_opt.item_selected.connect(_on_theme_selected)
	h.add_child(theme_opt)

	h.add_child(_mk_static("Weather"))
	weather_opt = OptionButton.new()
	for wv in WEATHERS:
		weather_opt.add_item(wv)
	weather_opt.item_selected.connect(_on_weather_selected)
	h.add_child(weather_opt)

	h.add_child(_mk_btn("Points", _mode_edit))
	prop_opt = OptionButton.new()
	for t in ["boost", "coin", "obstacle", "oil"]:
		prop_opt.add_item(t)
	prop_opt.item_selected.connect(_on_prop_selected)
	h.add_child(_mk_static("Prop"))
	h.add_child(prop_opt)
	h.add_child(_mk_btn("Place Props", _mode_prop))

	h.add_child(_mk_btn("Save", _on_save))
	h.add_child(_mk_btn("Load", _open_load))
	h.add_child(_mk_btn("Test Drive", _on_test))
	h.add_child(_mk_btn("Menu", func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn")))

	status = Label.new()
	status.position = Vector2(14, 62)
	status.add_theme_color_override("font_color", Color.WHITE)
	status.add_theme_color_override("font_outline_color", Color.BLACK)
	status.add_theme_constant_override("outline_size", 5)
	layer.add_child(status)

	_build_load_popup(layer)

func _mk_static(t: String) -> Label:
	var l := Label.new()
	l.text = t
	return l

func _mk_btn(t: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = t
	b.pressed.connect(cb)
	return b

func _on_width_changed(v: float) -> void:
	track.width = v
	track_view.queue_redraw()

func _mode_edit() -> void:
	mode = Mode.EDIT
	_set_status("Edit points: click add · drag move · right-click delete · S=start")

func _mode_prop() -> void:
	mode = Mode.PROP
	_set_status("Prop mode: click to place '%s' · right-click remove" % prop_type)

func _on_prop_selected(i: int) -> void:
	prop_type = prop_opt.get_item_text(i)
	_mode_prop()

func _on_theme_selected(i: int) -> void:
	track.theme = theme_opt.get_item_text(i)
	_set_status("Biome set to '%s' (re-skins the 3D race world)" % track.theme)

func _on_weather_selected(i: int) -> void:
	track.weather = weather_opt.get_item_text(i)
	_set_status("Weather set to '%s'" % track.weather)

func _refresh_fields() -> void:
	name_edit.text = track.name
	width_spin.value = track.width
	laps_spin.value = track.laps
	var ti := THEMES.find(track.theme)
	if ti >= 0 and theme_opt:
		theme_opt.select(ti)
	var wi := WEATHERS.find(track.weather)
	if wi >= 0 and weather_opt:
		weather_opt.select(wi)

func _set_status(t: String) -> void:
	if status:
		status.text = t

## Returns a warning string for a broken/awkward loop, or "" if the track is good.
func _track_warning() -> String:
	if not track.is_valid():
		return "Need at least 3 waypoints to make a loop."
	var n := track.waypoints.size()
	for i in range(n):
		if track.waypoints[i].distance_to(track.waypoints[(i + 1) % n]) < track.width * 0.25:
			return "Warning: some points are too close — the road may pinch. Space them out."
	if n < 5:
		return "Tip: add a few more points for smoother curves."
	return ""

# ---- save / load ----
func _on_save() -> void:
	if not track.is_valid():
		_set_status("Cannot save: need at least 3 waypoints."); return
	var path := track.save_to_user()
	if path != "":
		var gs := get_node_or_null("/root/GameState")
		if gs: gs.selected_track_path = path
		var warn := _track_warning()
		_set_status(("Saved to %s" % path) if warn == "" else ("Saved — %s" % warn))
	else:
		_set_status("Save failed (see output).")

func _on_test() -> void:
	if not track.is_valid():
		_set_status("Cannot test: need at least 3 waypoints."); return
	var path := track.save_to_user()          # autosave, then race it
	var gs := get_node_or_null("/root/GameState")
	if gs: gs.selected_track_path = path
	get_tree().change_scene_to_file("res://scenes/race.tscn")

func _build_load_popup(layer: CanvasLayer) -> void:
	load_popup = PanelContainer.new()
	load_popup.position = Vector2(420, 150)
	load_popup.custom_minimum_size = Vector2(440, 380)
	load_popup.visible = false
	layer.add_child(load_popup)
	var v := VBoxContainer.new()
	load_popup.add_child(v)
	var t := Label.new(); t.text = "Load a track"; t.add_theme_font_size_override("font_size", 26)
	v.add_child(t)
	load_list = ItemList.new()
	load_list.custom_minimum_size = Vector2(410, 280)
	v.add_child(load_list)
	var row := HBoxContainer.new()
	v.add_child(row)
	row.add_child(_mk_btn("Load Selected", _load_selected))
	row.add_child(_mk_btn("Close", func(): load_popup.visible = false))

func _open_load() -> void:
	_load_paths.clear()
	load_list.clear()
	for p in Track.list_bundled_tracks():
		_load_paths.append(p)
		load_list.add_item("[bundled]  " + p.get_file())
	for p in Track.list_user_tracks():
		_load_paths.append(p)
		load_list.add_item("[yours]  " + p.get_file())
	if _load_paths.is_empty():
		load_list.add_item("(no saved tracks yet)")
	load_popup.visible = true

func _load_selected() -> void:
	var sel := load_list.get_selected_items()
	if sel.is_empty() or sel[0] >= _load_paths.size():
		return
	var t := Track.load_from(_load_paths[sel[0]])
	if t and t.is_valid():
		track = t
		track_view.set_track(track)
		selected = -1
		track_view.selected_index = -1
		_refresh_fields()
		camera.global_position = track.bounds().get_center()
		load_popup.visible = false
		_set_status("Loaded %s" % _load_paths[sel[0]].get_file())
