extends Control
## Main menu — built around real hero art. Uses assets/ui/menu_bg.png (fullscreen
## splash) + assets/ui/logo.png when present, with a grouped button panel. Falls
## back to a clean gradient + text lockup if those assets aren't generated yet.

var cup_panel: Panel
var options_panel: Panel
var _t := 0.0
var _accent: Control

const BTN_COLORS := {
	"Grand Prix": Color("#f0a83a"), "Quick Race": Color("#e8503a"),
	"Time Trial": Color("#3a8ee8"), "Choose Boshi": Color("#9a5ae8"),
	"Track Editor": Color("#3ac88a"), "Options": Color("#3ac8c8"), "Quit": Color("#5a5a6a"),
}

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_background()
	_build_logo()
	_build_panel()
	_build_footer()
	AudioManager.play_music("menu")

func _click() -> void:
	AudioManager.play_sfx("click")

func _process(dt: float) -> void:
	_t += dt
	if _accent:
		_accent.position.x = fmod(_t * 46.0, 72.0) - 72.0

# ------------------------------------------------------------------ background
func _build_background() -> void:
	var hero := _tex("ui", "menu_bg")
	if hero:
		var img := TextureRect.new()
		img.texture = hero
		img.set_anchors_preset(Control.PRESET_FULL_RECT)
		img.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		add_child(img)
	else:
		var bg := TextureRect.new()
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		bg.stretch_mode = TextureRect.STRETCH_SCALE
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
		grad.colors = PackedColorArray([Color("#4a2c8f"), Color("#241357"), Color("#0d0824")])
		var gt := GradientTexture2D.new()
		gt.gradient = grad; gt.fill = GradientTexture2D.FILL_LINEAR
		gt.fill_from = Vector2(0, 0); gt.fill_to = Vector2(0, 1)
		gt.width = 256; gt.height = 144
		bg.texture = gt
		add_child(bg)

	# dark scrim so text/buttons stay legible over any hero art
	var scrim := TextureRect.new()
	scrim.set_anchors_preset(Control.PRESET_FULL_RECT)
	scrim.stretch_mode = TextureRect.STRETCH_SCALE
	var sg := Gradient.new()
	sg.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	sg.colors = PackedColorArray([Color(0.04, 0.02, 0.12, 0.30), Color(0.04, 0.02, 0.12, 0.45), Color(0.04, 0.02, 0.12, 0.82)])
	var st := GradientTexture2D.new()
	st.gradient = sg; st.fill = GradientTexture2D.FILL_LINEAR
	st.fill_from = Vector2(0, 0); st.fill_to = Vector2(0, 1)
	st.width = 16; st.height = 144
	scrim.texture = st
	add_child(scrim)

	var strip := Control.new()
	strip.position = Vector2(0, 694); strip.size = Vector2(1280, 26)
	strip.clip_contents = true
	add_child(strip)
	_accent = Control.new()
	_accent.size = Vector2(21 * 72, 26)
	strip.add_child(_accent)
	for i in range(21):
		var sq := ColorRect.new()
		sq.color = Color("#f4b942") if i % 2 == 0 else Color("#2a1560")
		sq.position = Vector2(i * 72, 0); sq.size = Vector2(72, 26)
		_accent.add_child(sq)

# ------------------------------------------------------------------ logo
func _build_logo() -> void:
	var logo := _tex("ui", "logo")
	if logo:
		var lr := TextureRect.new()
		lr.texture = logo
		lr.position = Vector2(340, 26); lr.size = Vector2(600, 230)
		lr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		lr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		add_child(lr)
		return
	if ResourceLoader.exists("res://icon.svg"):
		var em := TextureRect.new()
		em.texture = load("res://icon.svg")
		em.position = Vector2(566, 34); em.size = Vector2(148, 148)
		em.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		em.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		add_child(em)
	add_child(_title_label(Color(0, 0, 0, 0.5), Vector2(5, 190)))
	add_child(_title_label(Color("#ffd23a"), Vector2(0, 185)))

func _title_label(col: Color, pos: Vector2) -> Label:
	var l := Label.new()
	l.text = "ShibKart"
	l.add_theme_font_size_override("font_size", 96)
	l.add_theme_color_override("font_color", col)
	l.add_theme_constant_override("outline_size", 14)
	l.add_theme_color_override("font_outline_color", Color("#2a0f52"))
	l.position = pos; l.size = Vector2(1280, 120)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l

# ------------------------------------------------------------------ button panel
func _build_panel() -> void:
	var panel := Panel.new()
	panel.position = Vector2(440, 288); panel.size = Vector2(400, 384)
	panel.add_theme_stylebox_override("panel", _sb(Color(0.09, 0.05, 0.2, 0.82), Color("#f4b942")))
	add_child(panel)

	var box := VBoxContainer.new()
	box.position = Vector2(30, 22); box.custom_minimum_size = Vector2(340, 0)
	box.add_theme_constant_override("separation", 9)
	panel.add_child(box)
	box.add_child(_btn("Grand Prix", _open_cups))
	box.add_child(_btn("Quick Race", func(): _set_mode("vs")))
	box.add_child(_btn("Time Trial", func(): _set_mode("tt")))
	box.add_child(_btn("Choose Boshi", func(): get_tree().change_scene_to_file("res://scenes/character_select.tscn")))
	box.add_child(_btn("Track Editor", func(): get_tree().change_scene_to_file("res://scenes/track_editor.tscn")))
	box.add_child(_btn("Options", _open_options))
	box.add_child(_btn("Quit", func(): get_tree().quit()))

func _open_options() -> void:
	if options_panel and is_instance_valid(options_panel):
		options_panel.queue_free()
	options_panel = Panel.new()
	options_panel.position = Vector2(430, 240); options_panel.size = Vector2(420, 300)
	options_panel.add_theme_stylebox_override("panel", _sb(Color("#1a0e3e"), Color("#3ac8c8")))
	add_child(options_panel)
	var v := VBoxContainer.new()
	v.position = Vector2(30, 22); v.custom_minimum_size = Vector2(360, 0)
	v.add_theme_constant_override("separation", 14)
	options_panel.add_child(v)
	var t := Label.new(); t.text = "Options"; t.add_theme_font_size_override("font_size", 32)
	t.add_theme_color_override("font_color", Color("#7ff0f0"))
	v.add_child(t)
	v.add_child(_slider_row("Music", "Music"))
	v.add_child(_slider_row("SFX", "SFX"))
	v.add_child(_btn("Close", func(): options_panel.queue_free(), Color("#5a5a6a")))

func _slider_row(label: String, bus: String) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var l := Label.new(); l.text = label; l.custom_minimum_size = Vector2(90, 0)
	l.add_theme_font_size_override("font_size", 24)
	row.add_child(l)
	var sl := HSlider.new()
	sl.min_value = 0.0; sl.max_value = 1.0; sl.step = 0.05
	sl.custom_minimum_size = Vector2(230, 30)
	sl.value = AudioManager.get_bus_volume(bus)
	sl.value_changed.connect(func(val): AudioManager.set_bus_volume(bus, val))
	row.add_child(sl)
	return row

func _build_footer() -> void:
	var gs := get_node_or_null("/root/GameState")
	var footer := Label.new()
	footer.add_theme_font_size_override("font_size", 20)
	footer.add_theme_color_override("font_color", Color("#e0d8ff"))
	footer.add_theme_constant_override("outline_size", 4)
	footer.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
	footer.position = Vector2(0, 664); footer.size = Vector2(1280, 26)
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.text = "Racer:  %s        WASD drive  ·  Space drift  ·  E item" % (gs.selected_boshi_name if gs else "Boshi")
	add_child(footer)

# ------------------------------------------------------------------ cups
func _set_mode(m: String) -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs:
		gs.mode = m
		gs.theme_override = ""
	get_tree().change_scene_to_file("res://scenes/character_select.tscn")

func _open_cups() -> void:
	if cup_panel and is_instance_valid(cup_panel):
		cup_panel.queue_free()
	cup_panel = Panel.new()
	cup_panel.position = Vector2(430, 250); cup_panel.size = Vector2(420, 330)
	cup_panel.add_theme_stylebox_override("panel", _sb(Color("#1a0e3e"), Color("#f4b942")))
	add_child(cup_panel)
	var v := VBoxContainer.new()
	v.position = Vector2(36, 22); v.custom_minimum_size = Vector2(348, 0)
	v.add_theme_constant_override("separation", 12)
	cup_panel.add_child(v)
	var t := Label.new(); t.text = "Pick a Cup"; t.add_theme_font_size_override("font_size", 32)
	t.add_theme_color_override("font_color", Color("#ffd23a"))
	v.add_child(t)
	var gs := get_node_or_null("/root/GameState")
	if gs:
		for cup in gs.CUPS.keys():
			var cup_name: String = cup
			v.add_child(_btn(cup_name, func(): _start_cup(cup_name), Color("#f0a83a")))
	v.add_child(_btn("Back", func(): cup_panel.queue_free(), Color("#5a5a6a")))

func _start_cup(cup: String) -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs:
		gs.start_gp(cup)
	get_tree().change_scene_to_file("res://scenes/character_select.tscn")

# ------------------------------------------------------------------ helpers
func _tex(subdir: String, fname: String) -> Texture2D:
	var p := "res://assets/%s/%s.png" % [subdir, fname]
	return load(p) if ResourceLoader.exists(p) else null

func _sb(fill: Color, border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = fill
	s.set_corner_radius_all(16)
	s.border_color = border
	s.set_border_width_all(3)
	s.content_margin_left = 16; s.content_margin_right = 16
	s.content_margin_top = 12; s.content_margin_bottom = 12
	s.shadow_color = Color(0, 0, 0, 0.45); s.shadow_size = 8
	return s

func _btn(label: String, cb: Callable, override_color := Color(0, 0, 0, 0)) -> Button:
	var base: Color = override_color if override_color.a > 0.0 else BTN_COLORS.get(label, Color("#9a5ae8"))
	var b := Button.new()
	b.text = label
	b.custom_minimum_size = Vector2(340, 50)
	b.add_theme_font_size_override("font_size", 25)
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color("#ffe9b0"))
	b.add_theme_stylebox_override("normal", _sb(base, base.lightened(0.35)))
	b.add_theme_stylebox_override("hover", _sb(base.lightened(0.22), Color.WHITE))
	b.add_theme_stylebox_override("pressed", _sb(base.darkened(0.22), Color.WHITE))
	b.add_theme_stylebox_override("focus", _sb(base, base.lightened(0.5)))
	b.pressed.connect(_click)
	b.pressed.connect(cb)
	return b
