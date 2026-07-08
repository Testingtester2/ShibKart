extends CanvasLayer
## On-screen touch controls for mobile / touch web. Each button drives the SAME
## input action the keyboard uses (accelerate/brake/steer_left/steer_right/drift/
## use_item) via TouchScreenButton.action, so no gameplay code changes. Auto-hides
## when no touchscreen is present (desktop keeps using the keyboard).

const ACCENT := {
	"accelerate": Color(0.30, 0.80, 0.40),
	"brake": Color(0.92, 0.34, 0.30),
	"steer_left": Color(0.28, 0.62, 0.94),
	"steer_right": Color(0.28, 0.62, 0.94),
	"drift": Color(0.98, 0.66, 0.20),
	"use_item": Color(0.68, 0.42, 0.94),
}

var _specs: Array = []

func _ready() -> void:
	layer = 50
	if not DisplayServer.is_touchscreen_available():
		queue_free()          # desktop with a keyboard -> no touch UI
		return
	process_mode = Node.PROCESS_MODE_ALWAYS
	_specs = [
		{"action":"steer_left",  "label":"<",     "r":92.0, "anchor":"bl", "off":Vector2(120, 130)},
		{"action":"steer_right", "label":">",     "r":92.0, "anchor":"bl", "off":Vector2(332, 130)},
		{"action":"accelerate",  "label":"GAS",   "r":98.0, "anchor":"br", "off":Vector2(128, 128)},
		{"action":"brake",       "label":"BRAKE", "r":80.0, "anchor":"br", "off":Vector2(330, 120)},
		{"action":"drift",       "label":"DRIFT", "r":80.0, "anchor":"br", "off":Vector2(158, 322)},
		{"action":"use_item",    "label":"ITEM",  "r":74.0, "anchor":"br", "off":Vector2(350, 300)},
	]
	for s in _specs:
		_make_button(s)
	get_viewport().size_changed.connect(_layout)
	_layout()

func _make_button(spec: Dictionary) -> void:
	var r: float = spec["r"]
	var col: Color = ACCENT.get(spec["action"], Color(1, 1, 1))
	var btn := TouchScreenButton.new()
	btn.name = "btn_" + str(spec["action"])
	btn.texture_normal = _circle_tex(int(r), col, 0.30)
	btn.texture_pressed = _circle_tex(int(r), col, 0.58)
	var shp := CircleShape2D.new()
	shp.radius = r
	btn.shape = shp
	btn.shape_centered = true
	btn.action = spec["action"]
	add_child(btn)
	var lbl := Label.new()
	lbl.text = str(spec["label"])
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.size = Vector2(r * 2.0, r * 2.0)
	lbl.add_theme_font_size_override("font_size", int(r * 0.46))
	lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.96))
	lbl.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.65))
	lbl.add_theme_constant_override("outline_size", 5)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	btn.add_child(lbl)
	spec["node"] = btn
	spec["label_node"] = lbl

func _layout() -> void:
	var vp := get_viewport().get_visible_rect().size
	for s in _specs:
		if not s.has("node"):
			continue
		var r: float = s["r"]
		var off: Vector2 = s["off"]
		var center: Vector2
		if s["anchor"] == "bl":
			center = Vector2(off.x, vp.y - off.y)
		else:
			center = Vector2(vp.x - off.x, vp.y - off.y)
		var btn: TouchScreenButton = s["node"]
		btn.position = center - Vector2(r, r)
		var lbl: Label = s["label_node"]
		lbl.position = Vector2.ZERO

func _circle_tex(r: int, col: Color, alpha: float) -> ImageTexture:
	var d := r * 2
	var img := Image.create(d, d, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var c := Vector2(float(r), float(r))
	for y in range(d):
		for x in range(d):
			var dist := Vector2(float(x) + 0.5, float(y) + 0.5).distance_to(c)
			if dist > float(r):
				continue
			var cc := col
			var a := alpha
			if dist >= float(r) - 7.0:
				cc = col.lightened(0.45)          # bright rim
				a = minf(1.0, alpha + 0.4)
			if dist > float(r) - 1.5:
				a *= clampf(float(r) - dist, 0.0, 1.0)   # soften the outer edge
			img.set_pixel(x, y, Color(cc.r, cc.g, cc.b, a))
	return ImageTexture.create_from_image(img)

