extends Control
## Character select — pick which Boshi you race as. Each roster entry is rendered
## live through the shared BoshiCore compositor (chibi rig), so the same art the
## other Boshi games use shows up here. Falls back to a colored placeholder card
## when the rig art hasn't been generated yet.

var preview_holder: Node2D
var current_preview: Node2D
var name_label: Label
var selected_index := 0
var stat_bars := {}

func _ready() -> void:
	var bg := ColorRect.new()
	bg.color = Color("#151a2e")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var title := Label.new()
	title.text = "Choose your Boshi"
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color("#f4b942"))
	title.position = Vector2(40, 24)
	add_child(title)

	# a Node2D layer for the live compositor preview (Control can't hold Node2D directly
	# in a laid-out way, so we park it at a fixed spot)
	preview_holder = Node2D.new()
	preview_holder.position = Vector2(950, 420)
	add_child(preview_holder)

	name_label = Label.new()
	name_label.add_theme_font_size_override("font_size", 40)
	name_label.add_theme_color_override("font_color", Color.WHITE)
	name_label.position = Vector2(820, 470)
	name_label.size = Vector2(360, 50)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(name_label)

	var gs := get_node_or_null("/root/GameState")
	var roster: Array = gs.ROSTER if gs else []

	var grid := GridContainer.new()
	grid.columns = 2
	grid.position = Vector2(60, 110)
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	add_child(grid)
	for i in range(roster.size()):
		var idx := i
		var entry: Dictionary = roster[i]
		var b := Button.new()
		b.text = entry.get("name", "Boshi")
		b.custom_minimum_size = Vector2(320, 66)
		b.add_theme_font_size_override("font_size", 28)
		b.pressed.connect(func(): _select(idx))
		grid.add_child(b)

	var race_btn := Button.new()
	race_btn.text = "Race!"
	race_btn.custom_minimum_size = Vector2(240, 64)
	race_btn.add_theme_font_size_override("font_size", 32)
	race_btn.position = Vector2(830, 560)
	race_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/race.tscn"))
	add_child(race_btn)

	var back_btn := Button.new()
	back_btn.text = "Back"
	back_btn.custom_minimum_size = Vector2(160, 50)
	back_btn.position = Vector2(40, 650)
	back_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	add_child(back_btn)

	# kart stat bars (updated per selected Boshi)
	var sp := VBoxContainer.new()
	sp.position = Vector2(740, 120)
	sp.add_theme_constant_override("separation", 10)
	add_child(sp)
	var sh := Label.new(); sh.text = "KART STATS"
	sh.add_theme_font_size_override("font_size", 26)
	sh.add_theme_color_override("font_color", Color("#f4b942"))
	sp.add_child(sh)
	for key in ["speed", "accel", "handling", "weight"]:
		var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 12)
		var l := Label.new(); l.text = key.capitalize(); l.custom_minimum_size = Vector2(130, 0)
		l.add_theme_font_size_override("font_size", 22); l.add_theme_color_override("font_color", Color.WHITE)
		row.add_child(l)
		var pb := ProgressBar.new()
		pb.min_value = 0; pb.max_value = 5; pb.value = 3
		pb.custom_minimum_size = Vector2(200, 22); pb.show_percentage = false
		var bar_fill := StyleBoxFlat.new(); bar_fill.bg_color = Color("#3ac86a"); bar_fill.set_corner_radius_all(6)
		var bar_bg := StyleBoxFlat.new(); bar_bg.bg_color = Color(0.2, 0.2, 0.28, 0.85); bar_bg.set_corner_radius_all(6)
		pb.add_theme_stylebox_override("fill", bar_fill)
		pb.add_theme_stylebox_override("background", bar_bg)
		row.add_child(pb)
		stat_bars[key] = pb
		sp.add_child(row)

	# start on the currently-chosen boshi
	if gs:
		for i in range(roster.size()):
			if roster[i].get("name", "") == gs.selected_boshi_name:
				selected_index = i
				break
	_select(selected_index)

func _select(i: int) -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs == null:
		return
	selected_index = i
	AudioManager.play_sfx("select")
	var entry: Dictionary = gs.ROSTER[i]
	gs.set_boshi(entry)
	name_label.text = entry.get("name", "Boshi")
	var st: Dictionary = entry.get("stats", {})
	for key in stat_bars:
		stat_bars[key].value = float(st.get(key, 3))
	_rebuild_preview(entry)

func _rebuild_preview(entry: Dictionary) -> void:
	if current_preview and is_instance_valid(current_preview):
		current_preview.queue_free()
	# colored pedestal so there's always something on screen
	var bc := get_node_or_null("/root/BoshiCore")
	if bc != null:
		var old: float = bc.display_height
		bc.display_height = 260.0                       # big preview
		current_preview = bc.spawn(entry.get("traits", {}), preview_holder)
		bc.display_height = old
		if current_preview:
			current_preview.position = Vector2(-60, -220)
			if current_preview.has_method("play"):
				current_preview.play("idle")
