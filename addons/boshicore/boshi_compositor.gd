extends Node2D
class_name BoshiCompositor
## Runtime Boshi compositor — stacks one AnimatedSprite2D per trait slot, in sync,
## per the BoshiCore canonical rig spec (_boshicore_canon/RIG_SPEC.md).
##
## Two draw modes:
##   LAYERED (default): one AnimatedSprite2D per non-empty trait slot, all sharing
##       one frame index so they animate in lockstep. Cheap for a few on-screen.
##   BAKED: render the composed layers once through a SubViewport into a single
##       SpriteFrames, then draw ONE AnimatedSprite2D. Use when many boshis are on
##       screen (bounties, crowds) — turns N draws/boshi into 1.
##
## Assumes every trait sheet obeys the spec: identical canvas + 1:1 frame boxes to
## the base, so slot layers line up with zero per-layer transform. If a sheet is
## off-canvas the compositor logs it and skips (never silently mis-stacks).

# ---- Canonical rig — sourced from BoshiRig (RIG_SPEC.md §1/§2). Single source. ---
# NOTE: a `const` initialized from a global class_name (`BoshiRig.RIG`) does NOT
# compile in Godot 4.6 — global class names are resolved after const-folding, so it
# errors and cascades ("Failed to compile depended scripts") into boshi_core.gd.
# Using preload() gives a valid constant expression. (Fix to fold back into the canon.)
const RIG := preload("res://addons/boshicore/boshi_rig.gd").RIG
const SLOT_ORDER := preload("res://addons/boshicore/boshi_rig.gd").SLOT_ORDER

@export var traits_root: String = "res://assets/traits"     # <cat>/<value>/maz_<anim>.png
@export var base_path_tmpl: String = "res://assets/maz_%s.png"  # %s = anim
@export var default_anim: String = "idle"
@export var bake_when_spawning_many: bool = false           # flip on for crowds

var _layers: Array[AnimatedSprite2D] = []
var _baked_sprite: AnimatedSprite2D = null
var _current_anim: String = ""
var _fur_hue: float = 0.0                                    # Fur slot = palette hue-shift

# --------------------------------------------------------------------------------
# PUBLIC API
# --------------------------------------------------------------------------------

## metadata: { "Fur": "gold", "Clothing": "suit", "Eyes": "laser", ... }
## (category -> value; matches traits.json attributes after normalization).
func build(metadata: Dictionary) -> void:
	_clear()
	_fur_hue = _fur_hue_for(metadata.get("Fur", ""))
	var frames_by_slot := {}     # slot -> SpriteFrames (all anims)
	# Body (base) is always present.
	frames_by_slot["Body"] = _sprite_frames_for_source(base_path_tmpl)
	for slot in SLOT_ORDER:
		if slot == "Body":
			continue
		var value: String = str(metadata.get(slot, "")).strip_edges()
		if value == "" or value.to_lower() == "none":
			continue
		var tmpl := "%s/%s/%s/maz_%%s.png" % [traits_root, slot.to_lower(), _slug(value)]
		var sf := _sprite_frames_for_source(tmpl)
		if sf != null:
			frames_by_slot[slot] = sf

	if bake_when_spawning_many:
		# _build_baked awaits SubViewport snapshots (coroutine); defer it so build()
		# itself stays synchronous and the public API need not become async.
		_build_baked.call_deferred(frames_by_slot)
	else:
		_build_layered(frames_by_slot)
	play(default_anim)


func play(anim: String) -> void:
	if not RIG.has(anim):
		push_warning("BoshiCompositor: unknown anim '%s'" % anim)
		return
	_current_anim = anim
	if _baked_sprite:
		_baked_sprite.play(anim)
	else:
		for s in _layers:
			if s.sprite_frames and s.sprite_frames.has_animation(anim):
				s.play(anim)
	# Layers share fps from the sheet; a single driver keeps them frame-locked
	# (see _process). Godot plays each independently, so we hard-sync frame index.


func stop() -> void:
	if _baked_sprite: _baked_sprite.stop()
	for s in _layers: s.stop()


func _process(_dt: float) -> void:
	# Hard frame-lock: all layer sprites follow layer 0's frame so a dropped tick
	# on one layer can never desync the stack. Baked mode is a single sprite -> no-op.
	if _baked_sprite or _layers.size() < 2:
		return
	var lead := _layers[0].frame
	for i in range(1, _layers.size()):
		if _layers[i].frame != lead:
			_layers[i].frame = lead

# --------------------------------------------------------------------------------
# LAYERED
# --------------------------------------------------------------------------------

func _build_layered(frames_by_slot: Dictionary) -> void:
	var z := 0
	for slot in SLOT_ORDER:
		if not frames_by_slot.has(slot):
			continue
		var spr := AnimatedSprite2D.new()
		spr.sprite_frames = frames_by_slot[slot]
		spr.centered = false
		spr.z_index = z             # SLOT_ORDER index = z-order (back-most first)
		spr.offset = Vector2.ZERO   # sheets are pre-registered; NO per-layer transform
		if slot == "Body" and _fur_hue != 0.0:
			spr.material = _make_hue_material(_fur_hue)
		add_child(spr)
		_layers.append(spr)
		z += 1

# --------------------------------------------------------------------------------
# BAKED (SubViewport -> single SpriteFrames)
# --------------------------------------------------------------------------------

func _build_baked(frames_by_slot: Dictionary) -> void:
	var baked := SpriteFrames.new()
	for anim in RIG.keys():
		var rig: Dictionary = RIG[anim]
		if not (frames_by_slot["Body"] as SpriteFrames).has_animation(anim):
			continue
		baked.add_animation(anim)
		baked.set_animation_speed(anim, rig.fps)
		baked.set_animation_loop(anim, true)
		var frame_w: int = int(rig.w) / int(rig.frames)  # spec frame width (see §1)
		for f in range(int(rig.frames)):
			var tex := await _bake_one_frame(frames_by_slot, anim, f, frame_w, int(rig.h))
			if tex:
				baked.add_frame(anim, tex)
	_baked_sprite = AnimatedSprite2D.new()
	_baked_sprite.sprite_frames = baked
	_baked_sprite.centered = false
	add_child(_baked_sprite)
	play(default_anim)   # deferred bake finished after build()'s play(); start it now


## Render one composited frame via a SubViewport and grab it as a texture.
## Stacks each slot's frame f in SLOT_ORDER (back-most first) at (0,0) — all in
## register — then reads the viewport. One-time cost at spawn; cheap draws after.
func _bake_one_frame(frames_by_slot: Dictionary, anim: String, f: int,
		frame_w: int, frame_h: int) -> Texture2D:
	var vp := SubViewport.new()
	vp.size = Vector2i(frame_w, frame_h)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(vp)
	var z := 0
	for slot in SLOT_ORDER:
		if not frames_by_slot.has(slot):
			continue
		var sf: SpriteFrames = frames_by_slot[slot]
		if not sf.has_animation(anim) or f >= sf.get_frame_count(anim):
			continue
		var s := Sprite2D.new()
		s.texture = sf.get_frame_texture(anim, f)
		s.centered = false
		s.z_index = z
		if slot == "Body" and _fur_hue != 0.0:
			s.material = _make_hue_material(_fur_hue)
		vp.add_child(s)
		z += 1
	# Force one render, then snapshot. (In real use, await RenderingServer frame.)
	await RenderingServer.frame_post_draw
	var img := vp.get_texture().get_image()
	vp.queue_free()
	return ImageTexture.create_from_image(img)

# --------------------------------------------------------------------------------
# HELPERS
# --------------------------------------------------------------------------------

## Build a SpriteFrames covering all anims for a path template ("...maz_%s.png").
## Slices each strip on the spec frame boxes. Returns null if no sheet resolves.
func _sprite_frames_for_source(path_tmpl: String) -> SpriteFrames:
	var sf := SpriteFrames.new()
	var any := false
	for anim in RIG.keys():
		var rig: Dictionary = RIG[anim]
		var path := path_tmpl % anim
		if not ResourceLoader.exists(path):
			continue
		var tex: Texture2D = load(path)
		if tex == null:
			continue
		if tex.get_width() != int(rig.w) or tex.get_height() != int(rig.h):
			push_warning("BoshiCompositor: %s is %dx%d, spec %s=%dx%d — skipping (off-canvas)"
				% [path, tex.get_width(), tex.get_height(), anim, rig.w, rig.h])
			continue
		sf.add_animation(anim)
		sf.set_animation_speed(anim, rig.fps)
		sf.set_animation_loop(anim, true)
		var boxes := _frame_boxes(int(rig.w), int(rig.frames))
		for b in boxes:
			var atlas := AtlasTexture.new()
			atlas.atlas = tex
			atlas.region = Rect2(b.x, 0, b.y - b.x, rig.h)
			sf.add_frame(anim, atlas)
		any = true
	return sf if any else null


## Rounded fractional cuts — delegates to BoshiRig (matches run.py / comfy_conform.py).
func _frame_boxes(width: int, n: int) -> Array[Vector2i]:
	return BoshiRig.frame_boxes(width, n)


## The single baked SpriteFrames (BAKED mode). Null until a baked build completes.
## BoshiCore.bake_frames() caches this across identical trait sets.
func get_baked_frames() -> SpriteFrames:
	return _baked_sprite.sprite_frames if _baked_sprite else null


func _make_hue_material(hue: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """
shader_type canvas_item;
uniform float hue = 0.0;
vec3 hue_shift(vec3 c, float h){
	const vec3 k = vec3(0.57735);
	float ca = cos(h*6.2831853), sa = sin(h*6.2831853);
	return c*ca + cross(k,c)*sa + k*dot(k,c)*(1.0-ca);
}
void fragment(){
	vec4 t = texture(TEXTURE, UV);
	COLOR = vec4(hue_shift(t.rgb, hue), t.a);
}
"""
	mat.shader = sh
	mat.set_shader_parameter("hue", hue)
	return mat


func _fur_hue_for(fur_value: String) -> float:
	match fur_value.to_lower():
		"gold", "": return 0.0        # base palette
		"red":       return 0.95
		"pink":      return 0.88
		"blue":      return 0.55
		"green":     return 0.33
		_:           return 0.0


func _slug(s: String) -> String:
	return s.to_lower().replace(" ", "_")


func _clear() -> void:
	for s in _layers:
		s.queue_free()
	_layers.clear()
	if _baked_sprite:
		_baked_sprite.queue_free()
		_baked_sprite = null
