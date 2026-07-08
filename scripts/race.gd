extends Node2D
## Race scene root. Loads a track (chosen in the menu, or the bundled default),
## grids up the player + AI Boshis, runs a countdown, then the lap race with a
## live HUD (lap / position / time / speed) and a results panel on finish.

const KartScript := preload("res://scripts/kart.gd")
const TrackViewScript := preload("res://scripts/track_view.gd")

var track: Track
var karts: Array = []                 # Array[Kart]
var player: Kart
var camera: Camera2D
var track_view: TrackView

var race_started := false
var race_over := false
var countdown := 3.0
var race_time := 0.0
var _finish_order: Array = []         # Karts in the order they finished

# HUD
var hud: CanvasLayer
var lbl_lap: Label
var lbl_pos: Label
var lbl_time: Label
var lbl_speed: Label
var lbl_center: Label
var results_panel: Panel

const AI_NAMES := ["Turbo", "Nitro", "Vroom", "Zoomer", "Dash", "Comet"]

func _ready() -> void:
	track = _resolve_track()
	track_view = TrackViewScript.new()
	track_view.set_track(track)
	add_child(track_view)

	_spawn_karts()
	_setup_camera()
	_build_hud()
	_update_center("3")

func _resolve_track() -> Track:
	var gs := get_node_or_null("/root/GameState")
	var path: String = gs.selected_track_path if gs else ""
	if path != "":
		var t := Track.load_from(path)
		if t and t.is_valid():
			return t
	# try a bundled track, else the code default
	var bundled := Track.list_bundled_tracks()
	if bundled.size() > 0:
		var t2 := Track.load_from(bundled[0])
		if t2 and t2.is_valid():
			return t2
	return Track.make_default()

func _spawn_karts() -> void:
	var gs := get_node_or_null("/root/GameState")
	var grid := 0
	# player
	player = KartScript.new()
	player.is_ai = false
	player.racer_name = gs.selected_boshi_name if gs else "You"
	player.boshi_traits = gs.selected_boshi if gs else {}
	player.color = gs.KART_COLORS[0] if gs else Color("#e8503a")
	_add_kart(player, grid); grid += 1

	# a couple of AI racers pulled from the roster (skip the player's pick)
	var roster: Array = gs.ROSTER if gs else []
	var ai_count := 3
	for i in range(ai_count):
		var k := KartScript.new()
		k.is_ai = true
		k.ai_skill = 0.9 + 0.06 * i
		var entry: Dictionary = roster[(i + 1) % roster.size()] if roster.size() > 0 else {}
		k.racer_name = AI_NAMES[i % AI_NAMES.size()]
		k.boshi_traits = entry.get("traits", {})
		k.color = gs.KART_COLORS[(i + 1) % gs.KART_COLORS.size()] if gs else Color("#3a8ee8")
		_add_kart(k, grid); grid += 1

func _add_kart(k: Kart, grid_slot: int) -> void:
	# stagger karts across and behind the start line
	var lane := (grid_slot % 2) * 2 - 1                # -1 / +1
	var row := grid_slot
	k.setup(track, lane * 55.0)
	var f := track.start_forward()
	k.position -= f * (row * 46.0)
	k.lap_completed.connect(_on_lap)
	k.finished_race.connect(_on_finished)
	add_child(k)
	k.attach_boshi()
	karts.append(k)

func _setup_camera() -> void:
	camera = Camera2D.new()
	camera.zoom = Vector2(0.82, 0.82)
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	add_child(camera)
	camera.make_current()

func _process(dt: float) -> void:
	if camera and player:
		camera.global_position = player.global_position
	if not race_started:
		countdown -= dt
		if countdown <= 0.0:
			_start_race()
		else:
			_update_center(str(int(ceil(countdown))))
		return
	if race_over:
		if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("ui_cancel"):
			get_tree().change_scene_to_file("res://scenes/main_menu.tscn")
		return
	race_time += dt
	_update_hud()
	if Input.is_action_just_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _start_race() -> void:
	race_started = true
	for k in karts:
		k.race_active = true
	_update_center("GO!")
	# hide "GO!" after 0.8s via a one-shot timer signal (NOT await, so this stays a
	# plain function callable from _process — an awaiting func is a coroutine in 4.6).
	get_tree().create_timer(0.8).timeout.connect(_hide_center)

func _hide_center() -> void:
	if is_instance_valid(lbl_center):
		lbl_center.visible = false

# ------------------------------------------------------------------ standings
func _progress_score(k: Kart) -> float:
	var n := track.waypoints.size()
	var rel := (k.next_cp - (track.start_index + 1) + n) % n
	var done := k.lap * n + rel
	var dist := k.position.distance_to(track.waypoints[k.next_cp])
	return float(done) * 10000.0 - dist        # higher = further ahead

func _standings() -> Array:
	var arr := karts.duplicate()
	arr.sort_custom(func(a, b): return _progress_score(a) > _progress_score(b))
	return arr

func _player_position() -> int:
	var s := _standings()
	return s.find(player) + 1

func _on_lap(k: Kart, lap: int) -> void:
	if k == player and lap < track.laps:
		_flash("LAP %d/%d" % [lap + 1, track.laps])

func _on_finished(k: Kart) -> void:
	if not _finish_order.has(k):
		_finish_order.append(k)
		k.finish_place = _finish_order.size()
	if k == player:
		_end_race()

func _end_race() -> void:
	race_over = true
	for k in karts:
		k.race_active = false
	_show_results()

# ------------------------------------------------------------------ HUD
func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	lbl_lap = _mk_label(Vector2(24, 20), 30)
	lbl_pos = _mk_label(Vector2(24, 60), 30)
	lbl_time = _mk_label(Vector2(24, 100), 24)
	lbl_speed = _mk_label(Vector2(1080, 660), 24)
	lbl_center = _mk_label(Vector2(540, 300), 90)
	lbl_center.size = Vector2(200, 120)
	lbl_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _mk_label(pos: Vector2, sz: int) -> Label:
	var l := Label.new()
	l.position = pos
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", Color.WHITE)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	hud.add_child(l)
	return l

func _update_hud() -> void:
	lbl_lap.text = "LAP  %d/%d" % [min(player.lap + 1, track.laps), track.laps]
	lbl_pos.text = "POS  %d/%d" % [_player_position(), karts.size()]
	lbl_time.text = _fmt_time(race_time)
	lbl_speed.text = "%d km/h" % int(absf(player.speed) * 0.35)

func _update_center(txt: String) -> void:
	if lbl_center:
		lbl_center.visible = true
		lbl_center.text = txt

func _flash(txt: String) -> void:
	_update_center(txt)
	# one-shot timer signal instead of await, so _flash stays a plain function
	# (callable from _on_lap without making that a coroutine).
	get_tree().create_timer(1.0).timeout.connect(_flash_hide)

func _flash_hide() -> void:
	if is_instance_valid(lbl_center) and not race_over and race_started:
		lbl_center.visible = false

func _show_results() -> void:
	# make sure everyone has a place
	var standings := _standings()
	for k in standings:
		if not _finish_order.has(k):
			_finish_order.append(k)
			k.finish_place = _finish_order.size()
	results_panel = Panel.new()
	results_panel.position = Vector2(340, 120)
	results_panel.size = Vector2(600, 480)
	hud.add_child(results_panel)
	var v := VBoxContainer.new()
	v.position = Vector2(30, 24)
	v.custom_minimum_size = Vector2(540, 420)
	results_panel.add_child(v)
	var title := Label.new()
	title.add_theme_font_size_override("font_size", 40)
	title.text = "RESULTS  —  %s" % track.name
	v.add_child(title)
	var yt := Label.new()
	yt.add_theme_font_size_override("font_size", 22)
	yt.text = "Your time: %s" % _fmt_time(race_time)
	v.add_child(yt)
	for i in range(_finish_order.size()):
		var k: Kart = _finish_order[i]
		var row := Label.new()
		row.add_theme_font_size_override("font_size", 26)
		var tag := "  (You)" if k == player else ""
		row.text = "%d.  %s%s" % [i + 1, k.racer_name, tag]
		row.add_theme_color_override("font_color", Color("#ffd23a") if k == player else Color.WHITE)
		v.add_child(row)
	var hint := Label.new()
	hint.add_theme_font_size_override("font_size", 20)
	hint.text = "\nEnter / Esc — back to menu"
	v.add_child(hint)

func _fmt_time(t: float) -> String:
	var m := int(t) / 60
	var s := int(t) % 60
	var ms := int((t - floor(t)) * 100)
	return "%d:%02d.%02d" % [m, s, ms]
