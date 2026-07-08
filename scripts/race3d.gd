extends Node3D
## 3D race view — behind-the-kart perspective, the reference "3D track + billboard
## sprites" kart-racer look. Reuses the Track model, physics, AI, laps and HUD from
## the 2D prototype; only the presentation is 3D. Track authoring stays top-down in
## the editor. World is built by scaling the 2D track (pixels) onto the ground plane.

const KartScript := preload("res://scripts/kart3d.gd")
const WORLD_SCALE := 0.06

# Each track theme re-skins the world with generated tiles + scenery billboards.
# Names match tools/asset_manifest.json; missing files fall back to procedural art.
const THEME_SETS := {
	"grass":   { "ground": "grass_ground",  "road": "grass_road",  "ground_col": Color("#4a9a3f"), "road_col": Color("#4a4a55"), "sky_top": Color("#2a6ad0"), "sky_hor": Color("#bcd8ea"), "scenery": ["tree_pine", "tree_round", "bush", "fence"], "landmarks": ["windmill", "red_barn"] },
	"cherry":  { "ground": "cherry_ground", "road": "grass_road",  "ground_col": Color("#66b04f"), "road_col": Color("#4a4a55"), "sky_top": Color("#e57ba8"), "sky_hor": Color("#ffe0ef"), "scenery": ["blossom_tree", "lantern", "bush"], "landmarks": ["pagoda", "torii_gate"] },
	"city":    { "ground": "city_ground",   "road": "city_road",   "ground_col": Color("#2b2f45"), "road_col": Color("#33343f"), "sky_top": Color("#0b1030"), "sky_hor": Color("#3a2a6a"), "scenery": ["building", "streetlight", "fence"], "landmarks": ["skyscraper", "clock_tower"] },
	"desert":  { "ground": "desert_ground", "road": "desert_road", "ground_col": Color("#d9b56a"), "road_col": Color("#7a6a52"), "sky_top": Color("#4a9adf"), "sky_hor": Color("#f3e0b0"), "scenery": ["cactus", "rock_arch", "bush"], "landmarks": ["pyramid", "sand_temple"] },
	"moon":    { "ground": "moon_ground",   "road": "moon_road",   "ground_col": Color("#6a6a72"), "road_col": Color("#2a3a4a"), "sky_top": Color("#05060f"), "sky_hor": Color("#1a1030"), "scenery": ["moon_panel"], "landmarks": ["moon_dome", "rocket"] },
	"snow":    { "ground": "snow_ground",   "road": "snow_road",   "ground_col": Color("#e8f0f6"), "road_col": Color("#93a8ba"), "sky_top": Color("#7fa8d8"), "sky_hor": Color("#dbe8f4"), "scenery": ["tree_pine", "snowman", "fence"], "landmarks": ["log_cabin", "ice_castle"] },
	"volcano": { "ground": "volcano_ground","road": "volcano_road","ground_col": Color("#3a2420"), "road_col": Color("#2a1c18"), "sky_top": Color("#3a1010"), "sky_hor": Color("#e0602a"), "scenery": ["rock_arch", "volcano_rock"], "landmarks": ["dark_castle", "stone_ruins"] },
	"beach":   { "ground": "beach_ground",  "road": "beach_road",  "ground_col": Color("#eddba0"), "road_col": Color("#8a7a5a"), "sky_top": Color("#2aa0e0"), "sky_hor": Color("#bfeaff"), "scenery": ["palm", "umbrella", "bush"], "landmarks": ["lighthouse", "beach_resort"] },
}
var theme_set: Dictionary = {}

func _tex(subdir: String, fname: String) -> Texture2D:
	if fname == "":
		return null
	var p := "res://assets/%s/%s.png" % [subdir, fname]
	return load(p) if ResourceLoader.exists(p) else null

var track: Track
var karts: Array = []
var player: Kart3D
var camera: Camera3D

var race_started := false
var race_over := false
var countdown := 3.0
var race_time := 0.0
var _finish_order: Array = []

# items / combat
var item_boxes: Array = []      # [{pos, cd, node, vis}]
var hazards: Array = []          # [{kind, pos, node, owner, life}]
var shells: Array = []           # [{node, pos, heading, target, life, owner}]
var lbl_item: Label
var _item_key_down := false

# FX
var _env: Environment
var _speed_mat: ShaderMaterial
var _item_mat: ShaderMaterial
var _fx_t := 0.0
# audio
var _last_beep := 4
var _bump_cd := 0.0
# timing / results
var _finish_times := {}          # kart -> finish time (sec)
var _last_lap_t := 0.0
var _best_lap := 0.0
var lbl_best: Label
const ITEM_SFX := {
	"bone": "boost", "triple_bone": "boost", "banana": "banana", "oil": "oil",
	"shell": "shell", "shield": "shield", "lightning": "lightning", "ghost": "ghost",
}
const CAM_FOV_BASE := 70.0
const CAM_FOV_BOOST := 84.0

# real-3D road extrusion — kept FLAT and nearly flush with the ground. The road is
# wide, so any banking lifts the edges metres up into a bowl the kart (which drives a
# pure-2D centerline) appears to clip through / get stranded beside. Flat reads best.
const ROAD_Y := 0.06          # road surface height above the ground plane (metres)
const BANK := 0.0             # banking disabled (see note above)
const MAXBANK := 0.0          # radians
const KERB_W := 1.6           # metres
const RAIL_H := 1.15          # metres

# camera rig
var _cam_pos := Vector3.ZERO
const CAM_DIST := 7.0
const CAM_HEIGHT := 3.4
const CAM_LOOKAHEAD := 5.0

# HUD
var hud: CanvasLayer
var lbl_lap: Label
var lbl_pos: Label
var lbl_time: Label
var lbl_speed: Label
var lbl_center: Label

const AI_NAMES := ["Turbo", "Nitro", "Vroom", "Zoomer", "Dash", "Comet"]

func _ready() -> void:
	track = _resolve_track()
	var gs0 := get_node_or_null("/root/GameState")
	if gs0 and gs0.theme_override != "":
		track.theme = gs0.theme_override
	theme_set = THEME_SETS.get(track.theme, THEME_SETS["grass"])
	_build_environment()
	_build_track_mesh()
	_build_center_line()
	_build_edge_lines()
	_build_scenery()
	_build_banners()
	_build_roadside_boards()
	_build_corner_signs()
	_build_clouds()
	_build_props()
	_build_item_boxes()
	_spawn_karts()
	_build_weather()
	_build_camera()
	_build_hud()
	_update_center("3")
	# music for this map (per-track mp3, else per-biome, else silent) + engine loop
	var tid := "boshi_speedway"
	var gs := get_node_or_null("/root/GameState")
	if gs and gs.selected_track_path != "":
		tid = gs.selected_track_path.get_file().replace(".track.json", "")
	AudioManager.play_music(tid, track.theme)
	AudioManager.engine_start()

func _exit_tree() -> void:
	# leaving the race: silence the looping engine/off-road SFX
	AudioManager.engine_stop()
	AudioManager.offroad(false)

func _resolve_track() -> Track:
	var raw := _load_raw_track()
	return raw.smoothed() if (raw != null and raw.is_valid()) else raw

func _load_raw_track() -> Track:
	var gs := get_node_or_null("/root/GameState")
	var path: String = gs.selected_track_path if gs else ""
	if path != "":
		var t := Track.load_from(path)
		if t and t.is_valid():
			return t
	var bundled := Track.list_bundled_tracks()
	if bundled.size() > 0:
		var t2 := Track.load_from(bundled[0])
		if t2 and t2.is_valid():
			return t2
	return Track.make_default()

# ------------------------------------------------------------------ world
func _v3(p: Vector2, y: float = 0.0) -> Vector3:
	return Vector3(p.x, y / WORLD_SCALE, p.y) * WORLD_SCALE

func _build_environment() -> void:
	var we := WorldEnvironment.new()
	var env := Environment.new()
	var sky := Sky.new()
	var sky_top: Color = theme_set.get("sky_top", Color("#2a4a8a"))
	var sky_hor: Color = theme_set.get("sky_hor", Color("#bcd3ea"))
	var ground_col: Color = theme_set.get("ground_col", Color("#3f7d3a"))
	var wet: String = track.weather
	if wet == "rain" or wet == "fog":
		sky_top = sky_top.darkened(0.45); sky_hor = sky_hor.darkened(0.35)
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = sky_top
	sky_mat.sky_horizon_color = sky_hor
	sky_mat.ground_horizon_color = sky_hor
	sky_mat.ground_bottom_color = ground_col.darkened(0.2)
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6 if (wet == "rain" or wet == "fog") else 0.82
	# distance fog — denser in foggy/rainy/snowy weather
	env.fog_enabled = true
	env.fog_light_color = sky_hor
	env.fog_sun_scatter = 0.1
	# lighter fog so colours don't wash out (was too hazy)
	env.fog_density = {"fog": 0.028, "rain": 0.014, "snow": 0.012}.get(wet, 0.0022)
	# bloom / tonemap for the polished arcade look (Forward+ only)
	env.glow_enabled = true
	env.glow_intensity = 0.28
	env.glow_bloom = 0.04
	env.glow_hdr_threshold = 1.2
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 1.0
	# punchier, cuter colour grade so nothing looks washed out
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.3
	env.adjustment_contrast = 1.1
	env.adjustment_brightness = 0.95
	# soft ambient-occlusion contact shadows for the modern stylized look (Forward+)
	env.ssao_enabled = true
	env.ssao_radius = 2.0
	env.ssao_intensity = 1.7
	env.ssao_power = 1.5
	_env = env
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52, -40, 0)
	sun.light_energy = 0.85 if (wet == "rain" or wet == "fog") else 1.28
	sun.light_color = ground_col.lightened(0.6) if track.theme == "volcano" else Color(1.0, 0.96, 0.88)
	sun.shadow_enabled = true
	add_child(sun)
	# soft fill light from the opposite side for rim/roundness
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-24, 140, 0)
	fill.light_energy = 0.35
	fill.light_color = sky_hor.lightened(0.2)
	add_child(fill)

	# large ground plane under everything, tinted to the biome (textured if art exists)
	var ground := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(4000, 4000) * WORLD_SCALE
	ground.mesh = pm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = ground_col
	gmat.roughness = 1.0
	var gt := _tex("tiles", theme_set.get("ground", ""))
	if gt:
		gmat.albedo_texture = gt
		gmat.uv1_scale = Vector3(60, 60, 1)      # tile the big ground plane
		gmat.albedo_color = Color.WHITE
	ground.material_override = gmat
	var b := track.bounds()
	ground.position = _v3(b.get_center(), -0.05)
	add_child(ground)

func _build_weather() -> void:
	# rain / snow particles that follow the player (CPU particles work in GL Compat)
	var w := track.weather
	if w != "rain" and w != "snow":
		return
	var p := CPUParticles3D.new()
	p.amount = 260
	p.lifetime = 1.4
	p.local_coords = false
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = Vector3(45, 0.5, 45)
	p.direction = Vector3(0, -1, 0)
	p.spread = 6.0
	var mesh := SphereMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if w == "rain":
		mesh.radius = 0.06; mesh.height = 0.7
		mat.albedo_color = Color("#a8c8e8")
		p.gravity = Vector3(0, -120, 0)
		p.initial_velocity_min = 40.0; p.initial_velocity_max = 60.0
	else:
		mesh.radius = 0.14; mesh.height = 0.28
		mat.albedo_color = Color.WHITE
		p.gravity = Vector3(0, -14, 0)
		p.initial_velocity_min = 4.0; p.initial_velocity_max = 8.0
	mesh.material = mat
	p.mesh = mesh
	p.position = Vector3(0, 34, 0)
	player.add_child(p)

## Real-3D banked road: extrude the smoothed spline into a ribbon whose cross-section
## rolls into curves, with raised rounded kerbs and low outer rails.
var _road_roll := PackedFloat32Array()   # bank per centerline point (for kart tilt)

func _build_track_mesh() -> void:
	var n := track.waypoints.size()
	var half := track.width * 0.5 * WORLD_SCALE
	var roadL := PackedVector3Array()
	var roadR := PackedVector3Array()
	var kerbLo := PackedVector3Array()
	var kerbRo := PackedVector3Array()
	_road_roll = PackedFloat32Array()
	_road_roll.resize(n)
	for i in range(n):
		var a := track.waypoints[(i - 1 + n) % n]
		var b := track.waypoints[(i + 1) % n]
		var c := track.waypoints[i]
		var dir := b - a
		dir = dir.normalized() if dir.length() > 0.001 else Vector2.RIGHT
		var d0 := (c - a).normalized()
		var d1 := (b - c).normalized()
		var crossz := d0.x * d1.y - d0.y * d1.x        # signed curvature
		var bank := clampf(crossz * BANK, -MAXBANK, MAXBANK)
		_road_roll[i] = bank
		var fwd3 := Vector3(dir.x, 0, dir.y)
		var right3 := Vector3(-dir.y, 0, dir.x).rotated(fwd3, bank)
		var ctr := _v3(c, ROAD_Y)
		var rl := ctr - right3 * half
		var rr := ctr + right3 * half
		roadL.append(rl); roadR.append(rr)
		kerbLo.append(rl - right3 * KERB_W + Vector3.UP * 0.2)
		kerbRo.append(rr + right3 * KERB_W + Vector3.UP * 0.2)

	# road surface (UVs: u across 0..1, v along by distance for tiling)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var vd := 0.0
	for i in range(n):
		var j := (i + 1) % n
		var v0 := vd
		var v1 := vd + roadL[i].distance_to(roadL[j]) * 0.4
		vd = v1
		st.set_uv(Vector2(0, v0)); st.add_vertex(roadL[i])
		st.set_uv(Vector2(0, v1)); st.add_vertex(roadL[j])
		st.set_uv(Vector2(1, v1)); st.add_vertex(roadR[j])
		st.set_uv(Vector2(0, v0)); st.add_vertex(roadL[i])
		st.set_uv(Vector2(1, v1)); st.add_vertex(roadR[j])
		st.set_uv(Vector2(1, v0)); st.add_vertex(roadR[i])
	st.generate_normals()
	st.generate_tangents()
	var road := MeshInstance3D.new()
	road.mesh = st.commit()
	road.material_override = _road_material()
	add_child(road)

	_build_kerb_strip(roadL, kerbLo)
	_build_kerb_strip(roadR, kerbRo)
	_build_rail(kerbLo)
	_build_rail(kerbRo)
	_build_start_line_3d()

func _road_material() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = theme_set.get("road_col", Color("#4a4a55"))
	m.roughness = 0.85
	var rt := _tex("tiles", theme_set.get("road", ""))
	if rt:
		m.albedo_texture = rt
		m.uv1_scale = Vector3(3.0, 1.0, 1.0)   # tile across the road so asphalt detail shows
		m.albedo_color = Color.WHITE
	return m

func _build_kerb_strip(inner: PackedVector3Array, outer: PackedVector3Array) -> void:
	var n := inner.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(n):
		var j := (i + 1) % n
		st.set_color(Color("#e23b3b") if i % 2 == 0 else Color("#ffffff"))
		for v in [inner[i], inner[j], outer[j], inner[i], outer[j], outer[i]]:
			st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.7
	mi.material_override = m
	add_child(mi)

func _build_rail(top: PackedVector3Array) -> void:
	var n := top.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(n):
		var j := (i + 1) % n
		var a0 := top[i]
		var a1 := top[j]
		var b0 := a0 + Vector3.UP * RAIL_H
		var b1 := a1 + Vector3.UP * RAIL_H
		for v in [a0, a1, b1, a0, b1, b0]:
			st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	var rail_col: Color = theme_set.get("sky_hor", Color("#dddddd"))
	m.albedo_color = rail_col.lightened(0.15)
	m.roughness = 0.5
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = m
	add_child(mi)

func _build_start_line_3d() -> void:
	var i := track.start_index
	var n := track.waypoints.size()
	var a := track.waypoints[(i - 1 + n) % n]
	var b := track.waypoints[(i + 1) % n]
	var c := track.waypoints[i]
	var dir := (b - a)
	dir = dir.normalized() if dir.length() > 0.001 else Vector2.RIGHT
	var fwd3 := Vector3(dir.x, 0, dir.y)
	var right3 := Vector3(-dir.y, 0, dir.x)
	var ctr := _v3(c, ROAD_Y + 0.03)
	var half := track.width * 0.5 * WORLD_SCALE
	var depth := fwd3 * 1.1
	var squares := 10
	for s in range(squares):
		var t0 := (float(s) / squares - 0.5) * 2.0 * half
		var t1 := (float(s + 1) / squares - 0.5) * 2.0 * half
		var q0 := ctr + right3 * t0
		var q1 := ctr + right3 * t1
		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		for v in [q0 - depth, q1 - depth, q1 + depth, q0 - depth, q1 + depth, q0 + depth]:
			st.add_vertex(v)
		st.generate_normals()
		var mi := MeshInstance3D.new()
		mi.mesh = st.commit()
		var m := StandardMaterial3D.new()
		m.albedo_color = Color.WHITE if s % 2 == 0 else Color("#111111")
		mi.material_override = m
		add_child(mi)

func _build_center_line() -> void:
	# dashed yellow center line down the road
	var n := track.waypoints.size()
	for i in range(n):
		if i % 2 != 0:
			continue
		var a := track.waypoints[i]
		var b := track.waypoints[(i + 1) % n]
		var mid := a.lerp(b, 0.5)
		var dir := (b - a)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.8, 0.06, (dir.length() * 0.55) * WORLD_SCALE)
		mi.mesh = bm
		var m := StandardMaterial3D.new()
		m.albedo_color = Color("#ffe14d")
		m.emission_enabled = true; m.emission = Color("#ffe14d"); m.emission_energy_multiplier = 0.4
		mi.material_override = m
		add_child(mi)                        # in-tree before look_at
		mi.position = _v3(mid, ROAD_Y + 0.04)
		mi.look_at(_v3(b, ROAD_Y + 0.04), Vector3.UP)

func _build_scenery() -> void:
	# Cute low-poly 3D scenery, themed per biome: a dense near row lining the rails,
	# a sparser row of big trees further out, and a ring of background hills.
	var n := track.waypoints.size()
	var half := track.width * 0.5
	# dense near row
	var i := 0
	var idx := 0
	while i < n:
		var dir := track.heading_at(i)
		var nrm := Vector2(-dir.y, dir.x)
		for side: float in [-1.0, 1.0]:
			var base := track.waypoints[i] + nrm * side * (half + 78.0)
			_scenery_at(base, 0.7 + 0.3 * float(idx % 3), idx)
			idx += 1
		i += maxi(2, n / 40)
	# big outer trees further out
	var j := 0
	while j < n:
		var d2 := track.heading_at(j)
		var nrm2 := Vector2(-d2.y, d2.x)
		for side2: float in [-1.0, 1.0]:
			var fb := track.waypoints[j] + nrm2 * side2 * (half + 240.0 + float((j * 7) % 5) * 55.0)
			_scenery_at(fb, 1.5 + 0.6 * float(j % 3), j)
		j += maxi(6, n / 12)
	_build_hills()
	_build_landmarks()

func _build_hills() -> void:
	var b := track.bounds()
	var c := b.get_center()
	var r := maxf(b.size.x, b.size.y) * 0.6 + 500.0
	var base_col: Color = theme_set.get("ground_col", Color("#4a9a3f"))
	for k in range(12):
		var a := TAU * float(k) / 12.0
		var p := c + Vector2(cos(a), sin(a)) * r
		var mi := MeshInstance3D.new()
		var sm := SphereMesh.new(); sm.radius = 20.0; sm.height = 22.0
		mi.mesh = sm
		mi.material_override = _smat(base_col.darkened(0.1).lightened(0.05 * float(k % 3)))
		add_child(mi)
		mi.position = _v3(p, 0.0) - Vector3.UP * 9.0    # half-buried dome
		mi.scale = Vector3(1.5, 0.45, 1.5)

# ---- themed landmark structures (towns, castles, dojos...) -------------------
func _pyr(r: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.0; m.bottom_radius = r; m.height = h; m.radial_segments = 4
	return m

func _build_landmarks() -> void:
	var n := track.waypoints.size()
	var half := track.width * 0.5
	var lm: Array = theme_set.get("landmarks", [])
	for m in range(5):
		var i := (n * m) / 5
		var dir := track.heading_at(i)
		var nrm := Vector2(-dir.y, dir.x)
		var side := 1.0 if m % 2 == 0 else -1.0
		var base := track.waypoints[i] + nrm * side * (half + 430.0 + float(m % 3) * 120.0)
		var world_h := 14.0 + 3.0 * float(m % 3)
		# prefer a generated billboard landmark; fall back to the procedural mesh
		var placed := false
		if lm.size() > 0:
			placed = _place_billboard("landmarks", str(lm[m % lm.size()]), base, world_h)
		if placed:
			continue
		var root := Node3D.new()
		add_child(root)
		root.position = _v3(base, 0.0)
		var to_track := track.waypoints[i] - base
		root.rotation.y = atan2(to_track.x, to_track.y)
		_landmark(root, 1.5 + 0.4 * float(m % 2))

func _place_billboard(subdir: String, asset: String, p: Vector2, world_h: float) -> bool:
	var tex := _tex(subdir, asset)
	if tex == null:
		return false
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	spr.shaded = false
	spr.transparent = true
	spr.pixel_size = world_h / float(maxi(tex.get_height(), 1))
	spr.position = _v3(p, world_h * 0.5)   # bottom sits on the ground
	add_child(spr)
	_ground_shadow(p, world_h * 0.24)      # contact shadow -> reads as grounded, intentional
	return true

var _shadow_tex_cache: Texture2D = null
func _soft_shadow_tex() -> Texture2D:
	if _shadow_tex_cache != null:
		return _shadow_tex_cache
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.45))
	g.set_color(1, Color(0, 0, 0, 0.0))
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 64
	t.height = 64
	t.fill = GradientTexture2D.FILL_RADIAL
	t.fill_from = Vector2(0.5, 0.5)
	t.fill_to = Vector2(1.0, 0.5)
	_shadow_tex_cache = t
	return t

## Soft round contact shadow lying flat on the ground under a billboard.
func _ground_shadow(p: Vector2, radius: float) -> void:
	var mi := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(radius * 2.0, radius * 1.4)     # slightly squashed oval
	mi.mesh = q
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = _soft_shadow_tex()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mi.material_override = mat
	mi.rotation.x = -PI / 2.0                          # lay flat on the ground
	mi.position = _v3(p, 0.03)                         # just above the grass, no z-fight
	add_child(mi)

func _landmark(root: Node3D, sc: float) -> void:
	match track.theme:
		"cherry": _pagoda(root, sc)
		"grass": _windmill(root, sc)
		"volcano": _castle(root, sc)
		"beach": _lighthouse(root, sc)
		"desert": _pyramid(root, sc)
		"moon": _dome_base(root, sc)
		"snow": _cabin(root, sc)
		"city": _skyscraper(root, sc)
		_: _house(root, sc)

func _pagoda(root: Node3D, sc: float) -> void:
	for k in range(3):
		var w := (2.2 - 0.5 * k) * sc
		_put(_box(Vector3(w, 1.1 * sc, w)), _smat(Color("#efe6d8")), Vector3(0, (1.0 + 1.9 * k) * sc, 0), root)
		_put(_pyr(w * 0.9, 1.0 * sc), _smat(Color("#b23a2e")), Vector3(0, (1.9 + 1.9 * k) * sc, 0), root)

func _windmill(root: Node3D, sc: float) -> void:
	_put(_cyl(1.3 * sc, 1.7 * sc, 5.0 * sc), _smat(Color("#eae2d0")), Vector3(0, 2.5 * sc, 0), root)
	_put(_pyr(1.9 * sc, 1.6 * sc), _smat(Color("#a23b2e")), Vector3(0, 5.8 * sc, 0), root)
	for b in range(4):
		var blade := MeshInstance3D.new()
		blade.mesh = _box(Vector3(0.4 * sc, 3.4 * sc, 0.2 * sc))
		blade.material_override = _smat(Color("#d8cbb0"))
		blade.position = Vector3(0, 4.6 * sc, 1.4 * sc)
		blade.rotation.z = deg_to_rad(90.0 * b)
		root.add_child(blade)

func _castle(root: Node3D, sc: float) -> void:
	_put(_box(Vector3(5.0 * sc, 4.5 * sc, 5.0 * sc)), _smat(Color("#8f8a80")), Vector3(0, 2.2 * sc, 0), root)
	for cx: float in [-1.0, 1.0]:
		for cz: float in [-1.0, 1.0]:
			var p := Vector3(cx * 2.6 * sc, 0.0, cz * 2.6 * sc)
			_put(_cyl(1.0 * sc, 1.1 * sc, 6.0 * sc), _smat(Color("#9a948a")), p + Vector3(0, 3.0 * sc, 0), root)
			_put(_pyr(1.3 * sc, 1.6 * sc), _smat(Color("#7a2f2a")), p + Vector3(0, 6.6 * sc, 0), root)

func _lighthouse(root: Node3D, sc: float) -> void:
	_put(_cyl(1.0 * sc, 1.4 * sc, 6.0 * sc), _smat(Color("#f2f2f2")), Vector3(0, 3.0 * sc, 0), root)
	_put(_cyl(1.05 * sc, 1.05 * sc, 1.2 * sc), _smat(Color("#d63a3a")), Vector3(0, 4.2 * sc, 0), root)
	_put(_sphere(0.9 * sc), _smat(Color("#fff2a8"), 0.4, Color("#ffe14d")), Vector3(0, 6.6 * sc, 0), root)

func _pyramid(root: Node3D, sc: float) -> void:
	_put(_pyr(4.5 * sc, 5.0 * sc), _smat(Color("#d9b56a")), Vector3(0, 2.5 * sc, 0), root)

func _dome_base(root: Node3D, sc: float) -> void:
	var d := MeshInstance3D.new()
	d.mesh = _sphere(3.0 * sc)
	d.material_override = _smat(Color("#b8c0cc"), 0.4)
	d.position = Vector3(0, 0.3 * sc, 0)
	d.scale = Vector3(1.0, 0.6, 1.0)
	root.add_child(d)
	_put(_cyl(0.12 * sc, 0.12 * sc, 3.0 * sc), _smat(Color("#88ffff"), 0.3, Color("#39d0ff")), Vector3(0, 3.0 * sc, 0), root)

func _cabin(root: Node3D, sc: float) -> void:
	_put(_box(Vector3(3.4 * sc, 2.2 * sc, 3.0 * sc)), _smat(Color("#8a5a34")), Vector3(0, 1.1 * sc, 0), root)
	_put(_pyr(2.6 * sc, 1.6 * sc), _smat(Color("#f2f6fa")), Vector3(0, 3.0 * sc, 0), root)

func _skyscraper(root: Node3D, sc: float) -> void:
	var h := 10.0 * sc
	_put(_box(Vector3(3.0 * sc, h, 3.0 * sc)), _smat(Color("#39406a"), 0.4, Color("#2a3a6a")), Vector3(0, h * 0.5, 0), root)
	_put(_box(Vector3(2.0 * sc, h * 0.5, 2.0 * sc)), _smat(Color("#4a5290"), 0.4, Color("#3a4a80")), Vector3(0, h + h * 0.25, 0), root)

func _house(root: Node3D, sc: float) -> void:
	_put(_box(Vector3(3.2 * sc, 2.0 * sc, 3.0 * sc)), _smat(Color("#e0d2b0")), Vector3(0, 1.0 * sc, 0), root)
	_put(_pyr(2.4 * sc, 1.5 * sc), _smat(Color("#b23a2e")), Vector3(0, 2.7 * sc, 0), root)

# ---- cute low-poly scenery meshes -------------------------------------------
func _smat(c: Color, rough: float = 0.85, emis: Color = Color(0, 0, 0, 0)) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = rough
	if emis.a > 0.0:
		m.emission_enabled = true; m.emission = emis; m.emission_energy_multiplier = 1.6
	return m

func _cyl(top: float, bot: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new(); m.top_radius = top; m.bottom_radius = bot; m.height = h; return m

func _cone(r: float, h: float) -> CylinderMesh:
	var m := CylinderMesh.new(); m.top_radius = 0.0; m.bottom_radius = r; m.height = h; return m

func _sphere(r: float) -> SphereMesh:
	var m := SphereMesh.new(); m.radius = r; m.height = r * 2.0; return m

func _box(s: Vector3) -> BoxMesh:
	var m := BoxMesh.new(); m.size = s; return m

func _put(mesh: Mesh, mat: StandardMaterial3D, pos: Vector3, parent: Node3D) -> void:
	var mi := MeshInstance3D.new(); mi.mesh = mesh; mi.material_override = mat; mi.position = pos
	parent.add_child(mi)

func _scenery_mesh(base: Vector2, sc: float) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = _v3(base, 0.0)
	match track.theme:
		"snow":
			_put(_cyl(0.18 * sc, 0.22 * sc, 1.2 * sc), _smat(Color("#6b4a2a")), Vector3(0, 0.6 * sc, 0), root)
			for k in range(3):
				_put(_cone((1.05 - 0.28 * k) * sc, 1.2 * sc), _smat(Color("#eaf2f8")), Vector3(0, (1.5 + 0.85 * k) * sc, 0), root)
		"desert":
			_put(_cyl(0.3 * sc, 0.34 * sc, 2.4 * sc), _smat(Color("#3f9a52")), Vector3(0, 1.2 * sc, 0), root)
			_put(_cyl(0.16 * sc, 0.18 * sc, 1.0 * sc), _smat(Color("#3f9a52")), Vector3(-0.5 * sc, 1.7 * sc, 0), root)
		"volcano":
			_put(_sphere(1.1 * sc), _smat(Color("#3a2b28"), 0.9, Color("#e0521a")), Vector3(0, 0.6 * sc, 0), root)
		"beach":
			_put(_cyl(0.16 * sc, 0.2 * sc, 2.6 * sc), _smat(Color("#b98a4a")), Vector3(0, 1.3 * sc, 0), root)
			for a in range(5):
				var ang := deg_to_rad(a * 72.0)
				_put(_sphere(0.5 * sc), _smat(Color("#3faa5a")), Vector3(cos(ang) * 0.5 * sc, 2.6 * sc, sin(ang) * 0.5 * sc), root)
		"moon":
			_put(_cone(0.5 * sc, 2.2 * sc), _smat(Color("#7fd8ff"), 0.3, Color("#39d0ff")), Vector3(0, 1.1 * sc, 0), root)
		"city":
			var hgt := (4.0 + 2.0 * float(int(abs(base.x)) % 3)) * sc
			_put(_box(Vector3(2.0 * sc, hgt, 2.0 * sc)), _smat(Color("#3a3f60"), 0.6), Vector3(0, hgt * 0.5, 0), root)
		"cherry":
			_put(_cyl(0.2 * sc, 0.24 * sc, 1.4 * sc), _smat(Color("#7a5230")), Vector3(0, 0.7 * sc, 0), root)
			_put(_sphere(1.3 * sc), _smat(Color("#ff9ec4")), Vector3(0, 2.3 * sc, 0), root)
		_:
			_put(_cyl(0.2 * sc, 0.24 * sc, 1.4 * sc), _smat(Color("#6b4a2a")), Vector3(0, 0.7 * sc, 0), root)
			_put(_sphere(1.35 * sc), _smat(Color("#4fae57")), Vector3(0, 2.3 * sc, 0), root)

func _scenery_billboard(asset: String, p: Vector2, world_h: float) -> bool:
	var tex := _tex("scenery", asset)
	if tex == null:
		return false
	var spr := Sprite3D.new()
	spr.texture = tex
	spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y   # stays upright, faces camera
	spr.shaded = false
	spr.transparent = true
	spr.pixel_size = world_h / float(maxi(tex.get_height(), 1))
	spr.position = _v3(p, world_h * 0.5)               # bottom sits on the ground
	add_child(spr)
	_ground_shadow(p, world_h * 0.22)
	return true

## Cute low-poly 3D scenery (kept 3D on purpose — reads closer to Mario Kart 8
## than flat sprites would). Landmarks stay as grounded billboards with shadows.
func _scenery_at(base: Vector2, sc: float, idx: int) -> void:
	_scenery_mesh(base, sc)

func _tree(p: Vector2, sc: float) -> void:
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.18 * sc; tm.bottom_radius = 0.22 * sc; tm.height = 1.2 * sc
	trunk.mesh = tm
	var tmat := StandardMaterial3D.new(); tmat.albedo_color = Color("#6b4a2a")
	trunk.material_override = tmat
	trunk.position = _v3(p, 0.6 * sc)
	add_child(trunk)
	for k in range(2):
		var foliage := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0; cm.bottom_radius = (1.1 - 0.35 * k) * sc; cm.height = 1.4 * sc
		foliage.mesh = cm
		var fmat := StandardMaterial3D.new()
		fmat.albedo_color = Color("#2f7a34").lightened(0.08 * k)
		foliage.material_override = fmat
		foliage.position = _v3(p, (1.5 + 0.8 * k) * sc)
		add_child(foliage)

func _build_banners() -> void:
	# a START/FINISH arch over the start line + a couple of colored checkpoint arches
	_arch(track.start_index, Color("#e23b3b"))
	var n := track.waypoints.size()
	_arch((track.start_index + n / 3) % n, Color("#3aa0e8"))
	_arch((track.start_index + 2 * n / 3) % n, Color("#39c56a"))

func _arch(i: int, col: Color) -> void:
	var p := track.waypoints[i]
	var dir := track.heading_at(i)
	var nrm := Vector2(-dir.y, dir.x)
	var half := track.width * 0.5 + 10.0
	var post_h := 5.5
	for side: float in [-1.0, 1.0]:
		var base := p + nrm * side * half
		var post := MeshInstance3D.new()
		var pm := BoxMesh.new(); pm.size = Vector3(0.5, post_h, 0.5)
		post.mesh = pm
		post.material_override = _flat(Color("#dddddd"))
		post.position = _v3(base, post_h * 0.5)
		add_child(post)
	# top banner bar spanning the road
	var bar := MeshInstance3D.new()
	var bw := (half * 2.0) * WORLD_SCALE
	var bm := BoxMesh.new(); bm.size = Vector3(bw, 1.3, 0.4)
	bar.mesh = bm
	bar.material_override = _flat(col)
	add_child(bar)                           # in-tree before look_at
	bar.position = _v3(p, post_h + 0.3)
	bar.look_at(_v3(p + dir, post_h + 0.3), Vector3.UP)

func _flat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	return m

func _build_props() -> void:
	for d in track.props:
		var type := str(d.get("type", "boost"))
		var p: Vector2 = d.get("pos", Vector2.ZERO)
		var mi := MeshInstance3D.new()
		var m := StandardMaterial3D.new()
		match type:
			"boost":
				var cyl := CylinderMesh.new(); cyl.top_radius = 30 * WORLD_SCALE; cyl.bottom_radius = 30 * WORLD_SCALE; cyl.height = 0.08
				mi.mesh = cyl
				m.albedo_color = Color("#39d0ff"); m.emission_enabled = true; m.emission = Color("#39d0ff"); m.emission_energy_multiplier = 1.5
				mi.position = _v3(p, ROAD_Y + 0.04)
			"coin":
				var sp := SphereMesh.new(); sp.radius = 10 * WORLD_SCALE; sp.height = 20 * WORLD_SCALE
				mi.mesh = sp
				m.albedo_color = Color("#f4d24a"); m.metallic = 0.8; m.roughness = 0.2
				mi.position = _v3(p, ROAD_Y + 0.9)
			"obstacle":
				var bx := BoxMesh.new(); bx.size = Vector3(1.4, 1.4, 1.4)
				mi.mesh = bx
				m.albedo_color = Color("#8a5a2a")
				mi.position = _v3(p, ROAD_Y + 0.7)
			_:
				var cyl2 := CylinderMesh.new(); cyl2.top_radius = 22 * WORLD_SCALE; cyl2.bottom_radius = 22 * WORLD_SCALE; cyl2.height = 0.05
				mi.mesh = cyl2
				m.albedo_color = Color("#20202a")
				mi.position = _v3(p, ROAD_Y + 0.04)
		mi.material_override = m
		add_child(mi)

# ------------------------------------------------------------------ karts
func _spawn_karts() -> void:
	var gs := get_node_or_null("/root/GameState")
	var grid := 0
	player = KartScript.new()
	player.is_ai = false
	player.racer_name = gs.selected_boshi_name if gs else "You"
	player.boshi_traits = gs.selected_boshi if gs else {}
	player.color = gs.KART_COLORS[0] if gs else Color("#e8503a")
	player.set_stats(gs.selected_stats if gs else {})
	_add_kart(player, grid); grid += 1

	var roster: Array = gs.ROSTER if gs else []
	var ai_count := 0 if (gs and gs.mode == "tt") else 3     # Time Trial = solo
	for i in range(ai_count):
		var k := KartScript.new()
		k.is_ai = true
		k.ai_skill = 0.9 + 0.06 * i
		var entry: Dictionary = roster[(i + 1) % roster.size()] if roster.size() > 0 else {}
		k.racer_name = AI_NAMES[i % AI_NAMES.size()]
		k.boshi_traits = entry.get("traits", {})
		k.color = gs.KART_COLORS[(i + 1) % gs.KART_COLORS.size()] if gs else Color("#3a8ee8")
		k.set_stats(gs.stats_for(entry) if gs else {})
		_add_kart(k, grid); grid += 1

func _add_kart(k: Kart3D, grid_slot: int) -> void:
	var lane := (grid_slot % 2) * 2 - 1
	add_child(k)
	k.setup(track, lane * 55.0)
	var f := track.start_forward()
	k.pos2d -= f * (grid_slot * 46.0)
	k._sync_transform()
	k.lap_completed.connect(_on_lap)
	k.finished_race.connect(_on_finished)
	karts.append(k)

func _build_camera() -> void:
	camera = Camera3D.new()
	camera.fov = 70.0
	camera.far = 2000.0
	add_child(camera)
	camera.make_current()
	_snap_camera()

func _snap_camera() -> void:
	var fwd := Vector2.RIGHT.rotated(player.heading)
	var fwd3 := Vector3(fwd.x, 0, fwd.y)
	_cam_pos = player.global_position - fwd3 * CAM_DIST + Vector3.UP * CAM_HEIGHT
	camera.global_position = _cam_pos
	camera.look_at(player.global_position + fwd3 * CAM_LOOKAHEAD + Vector3.UP * 1.0, Vector3.UP)

# ------------------------------------------------------------------ loop
func _process(dt: float) -> void:
	if player and camera:
		var fwd := Vector2.RIGHT.rotated(player.heading)
		var fwd3 := Vector3(fwd.x, 0, fwd.y)
		var right3 := Vector3(-fwd.y, 0, fwd.x)
		var target := player.global_position - fwd3 * CAM_DIST + Vector3.UP * CAM_HEIGHT
		_cam_pos = _cam_pos.lerp(target, clampf(dt * 5.0, 0.0, 1.0))
		camera.global_position = _cam_pos
		# look-ahead biased into the turn, plus a subtle dutch-roll lean
		var look := player.global_position + fwd3 * CAM_LOOKAHEAD + Vector3.UP * 1.0 + right3 * (player.body_lean * 3.0)
		camera.look_at(look, Vector3.UP)
		camera.rotate_object_local(Vector3(0, 0, 1), clampf(player.body_lean, -0.5, 0.5) * 0.42)
	_update_fx(dt)

	if not race_started:
		countdown -= dt
		if countdown <= 0.0:
			_start_race()
		else:
			var cd := int(ceil(countdown))
			if cd != _last_beep:
				_last_beep = cd
				AudioManager.play_sfx("beep")
			_update_center(str(cd))
		return
	if _bump_cd > 0.0:
		_bump_cd -= dt
	if race_over:
		if Input.is_action_just_pressed("ui_accept") or Input.is_action_just_pressed("ui_cancel"):
			_advance_after_results()
		return
	race_time += dt
	_update_hud()
	_update_items(dt)
	_resolve_collisions()
	_update_catchup()
	if Input.is_action_just_pressed("ui_cancel"):
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _start_race() -> void:
	race_started = true
	for k in karts:
		k.race_active = true
	_update_center("GO!")
	AudioManager.play_sfx("go")
	get_tree().create_timer(0.8).timeout.connect(_hide_center)

func _hide_center() -> void:
	if is_instance_valid(lbl_center):
		lbl_center.visible = false

# ------------------------------------------------------------------ standings
func _resolve_collisions() -> void:
	# bump physics: the FASTER kart shoves the other one (transfers momentum), so the
	# player can knock rivals around. Both still separate by mass so nobody overlaps.
	var bump := 40.0
	for i in range(karts.size()):
		for j in range(i + 1, karts.size()):
			var a: Kart3D = karts[i]
			var b: Kart3D = karts[j]
			var d := a.pos2d - b.pos2d
			var dist := d.length()
			if dist < bump and dist > 0.5:
				var nrm := d / dist
				var tot := a.mass + b.mass
				var overlap := bump - dist
				a.pos2d += nrm * overlap * (b.mass / tot)     # heavier kart is shoved less
				b.pos2d -= nrm * overlap * (a.mass / tot)
				# momentum shove: whoever is faster knocks the other forward + sideways
				var aggressor: Kart3D = a if a.speed >= b.speed else b
				var victim: Kart3D = b if aggressor == a else a
				var shove := (victim.pos2d - aggressor.pos2d)
				shove = shove.normalized() if shove.length() > 0.001 else nrm
				var force := clampf(absf(a.speed - b.speed) * 0.35 + aggressor.speed * 0.12, 10.0, 46.0)
				victim.pos2d += shove * force * (aggressor.mass / tot)
				victim.speed *= 0.80          # the one who got shoved loses more speed
				aggressor.speed *= 0.97       # the rammer barely slows -> satisfying push
				if (a == player or b == player) and _bump_cd <= 0.0:
					_bump_cd = 0.2
					AudioManager.play_sfx("bump")

func _update_catchup() -> void:
	# gentle rubber-band: trailing karts get up to +8% top speed, leader gets none.
	var s := _standings()
	if s.size() < 2:
		return
	var lead := _progress_score(s[0])
	var last := _progress_score(s[s.size() - 1])
	var span := maxf(lead - last, 1.0)
	for k in karts:
		var behind := clampf((lead - _progress_score(k)) / span, 0.0, 1.0)
		k.catchup = 1.0 + behind * 0.08

func _update_fx(dt: float) -> void:
	_fx_t += dt
	if player == null:
		return
	var boosting := player.boost_time > 0.0
	if _speed_mat:
		var spd := absf(player.speed) / player.MAX_SPEED
		var inten := clampf((spd - 0.72) / 0.28, 0.0, 1.0) * 0.5
		if boosting:
			inten = maxf(inten, 0.9)
		_speed_mat.set_shader_parameter("intensity", inten)
		_speed_mat.set_shader_parameter("time", _fx_t)
	if _item_mat:
		_item_mat.set_shader_parameter("time", _fx_t)
	if camera:
		camera.fov = lerp(camera.fov, CAM_FOV_BOOST if boosting else CAM_FOV_BASE, clampf(dt * 6.0, 0.0, 1.0))
	if _env:
		_env.glow_intensity = lerp(_env.glow_intensity, 0.55 if boosting else 0.28, clampf(dt * 4.0, 0.0, 1.0))

func _progress_score(k: Kart3D) -> float:
	var done := k.lap * k._num_cp + k._cps_passed
	var dist := k.pos2d.distance_to(track.waypoints[k.next_cp])
	return float(done) * 100000.0 - dist

func _standings() -> Array:
	var arr := karts.duplicate()
	arr.sort_custom(func(a, b): return _progress_score(a) > _progress_score(b))
	return arr

func _player_position() -> int:
	return _standings().find(player) + 1

func _on_lap(k, lap: int) -> void:
	if k == player:
		var split := race_time - _last_lap_t          # lap split -> track best
		_last_lap_t = race_time
		if split > 0.5 and (_best_lap == 0.0 or split < _best_lap):
			_best_lap = split
		if lap < track.laps:
			_update_center("LAP %d/%d" % [lap + 1, track.laps])
			AudioManager.play_sfx("lap")
			get_tree().create_timer(1.0).timeout.connect(_hide_center)

func _on_finished(k) -> void:
	if not _finish_order.has(k):
		_finish_order.append(k)
		k.finish_place = _finish_order.size()
		_finish_times[k] = race_time
	if k == player:
		_end_race()

func _end_race() -> void:
	race_over = true
	for k in karts:
		k.race_active = false
	AudioManager.play_sfx("finish")
	AudioManager.engine_stop()
	_show_results()

# ------------------------------------------------------------------ HUD
func _build_hud() -> void:
	hud = CanvasLayer.new()
	add_child(hud)
	# full-screen speed-lines overlay (added first so HUD text draws on top)
	_speed_mat = KartFX.speed_lines()
	var sl := ColorRect.new()
	sl.set_anchors_preset(Control.PRESET_FULL_RECT)
	sl.material = _speed_mat
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(sl)
	# translucent backing panels behind the info clusters (drawn under the labels)
	_hud_panel(Vector2(14, 12), Vector2(228, 156))
	_hud_panel(Vector2(946, 12), Vector2(310, 52))
	lbl_lap = _mk_label(Vector2(24, 18), 30)
	lbl_pos = _mk_label(Vector2(24, 56), 30)
	lbl_time = _mk_label(Vector2(24, 96), 24)
	lbl_best = _mk_label(Vector2(24, 128), 20)
	lbl_speed = _mk_label(Vector2(1080, 660), 24)
	lbl_item = _mk_label(Vector2(958, 20), 26)
	lbl_center = _mk_label(Vector2(520, 290), 90)
	lbl_center.size = Vector2(240, 120)
	lbl_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	# minimap (bottom-left) so the track layout + racers are always readable
	var mm := preload("res://scripts/minimap.gd").new()
	mm.position = Vector2(24, 476)
	mm.size = Vector2(240, 200)
	mm.track = track
	mm.karts = karts
	mm.player = player
	hud.add_child(mm)

func _hud_panel(pos: Vector2, sz: Vector2) -> void:
	var p := Panel.new()
	p.position = pos; p.size = sz
	p.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.03, 0.12, 0.5)
	sb.set_corner_radius_all(12)
	sb.border_color = Color(0.95, 0.72, 0.26, 0.55)
	sb.set_border_width_all(2)
	p.add_theme_stylebox_override("panel", sb)
	hud.add_child(p)

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
	lbl_best.text = "BEST %s" % _fmt_time(_best_lap) if _best_lap > 0.0 else "BEST --:--"
	lbl_speed.text = "%d km/h" % int(absf(player.speed) * 0.35)

func _update_center(txt: String) -> void:
	if lbl_center:
		lbl_center.visible = true
		lbl_center.text = txt

func _show_results() -> void:
	var standings := _standings()
	for k in standings:
		if not _finish_order.has(k):
			_finish_order.append(k)
			k.finish_place = _finish_order.size()
	var panel := Panel.new()
	panel.position = Vector2(340, 120)
	panel.size = Vector2(600, 480)
	hud.add_child(panel)
	var v := VBoxContainer.new()
	v.position = Vector2(30, 24)
	v.custom_minimum_size = Vector2(540, 420)
	panel.add_child(v)
	var gs := get_node_or_null("/root/GameState")
	var is_gp: bool = gs != null and gs.mode == "gp"
	if is_gp:
		var order: Array = []
		for k in _finish_order:
			order.append(k.racer_name)
		gs.gp_award(order)

	var title := Label.new()
	title.add_theme_font_size_override("font_size", 40)
	title.text = ("%s — Race %d/%d" % [gs.gp_cup, gs.gp_index + 1, gs.gp_tracks.size()]) if is_gp else ("RESULTS — %s" % track.name)
	v.add_child(title)
	var yt := Label.new()
	yt.add_theme_font_size_override("font_size", 22)
	yt.text = "Your time: %s" % _fmt_time(race_time)
	v.add_child(yt)
	for i in range(_finish_order.size()):
		var k: Kart3D = _finish_order[i]
		var row := Label.new()
		row.add_theme_font_size_override("font_size", 24)
		var tag := "  (You)" if k == player else ""
		var tstr := _fmt_time(_finish_times[k]) if _finish_times.has(k) else "--:--"
		row.text = "%d.  %-10s %s%s" % [i + 1, k.racer_name, tstr, tag]
		row.add_theme_color_override("font_color", Color("#ffd23a") if k == player else Color.WHITE)
		v.add_child(row)

	var hint := Label.new()
	hint.add_theme_font_size_override("font_size", 20)
	if is_gp:
		var cup_head := Label.new()
		cup_head.add_theme_font_size_override("font_size", 22)
		cup_head.text = "\nCup standings:"
		cup_head.add_theme_color_override("font_color", Color("#c9b8ff"))
		v.add_child(cup_head)
		for e in gs.gp_standings():
			var sr := Label.new()
			sr.add_theme_font_size_override("font_size", 20)
			sr.text = "   %s — %d pts" % [e["name"], e["points"]]
			v.add_child(sr)
		var more: bool = gs.gp_index < gs.gp_tracks.size() - 1
		hint.text = "\nEnter — next race" if more else "\nEnter — cup complete! back to menu"
	else:
		hint.text = "\nEnter / Esc — back to menu"
	v.add_child(hint)

func _advance_after_results() -> void:
	var gs := get_node_or_null("/root/GameState")
	if gs and gs.mode == "gp" and gs.gp_next():
		get_tree().reload_current_scene()      # next GP race, same scene
		return
	if gs and gs.mode == "gp":
		gs.mode = "vs"                          # cup finished; reset so quick races are normal
		gs.theme_override = ""
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")

func _fmt_time(t: float) -> String:
	var m := int(t) / 60
	var s := int(t) % 60
	var ms := int((t - floor(t)) * 100)
	return "%d:%02d.%02d" % [m, s, ms]

# ================================================================ items / combat
func _build_item_boxes() -> void:
	var n := track.waypoints.size()
	var step := maxi(4, n / 4)
	var i := 0
	while i < n:
		var dir := track.heading_at(i)
		var nrm := Vector2(-dir.y, dir.x)
		for lane in [-0.28, 0.0, 0.28]:
			_spawn_item_box(track.waypoints[i] + nrm * (track.width * lane))
		i += step

func _spawn_item_box(p: Vector2) -> void:
	var node := Node3D.new()
	var vis: Node3D
	var tex := _tex("props", "item_box")
	if tex:
		var spr := Sprite3D.new()
		spr.texture = tex
		spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		spr.shaded = false; spr.transparent = true
		spr.pixel_size = 2.4 / float(maxi(tex.get_height(), 1))
		vis = spr
	else:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new(); bm.size = Vector3(1.5, 1.5, 1.5)
		mi.mesh = bm
		if _item_mat == null:
			_item_mat = KartFX.item_shimmer()
		mi.material_override = _item_mat          # rainbow shimmer + bloom
		vis = mi
	node.add_child(vis)
	add_child(node)
	node.position = _v3(p, ROAD_Y + 1.3)
	item_boxes.append({ "pos": p, "cd": 0.0, "node": node, "vis": vis })

func _update_items(dt: float) -> void:
	# item boxes: spin, cooldown, pickup
	for b in item_boxes:
		b["vis"].rotate_y(dt * 2.2)
		if b["cd"] > 0.0:
			b["cd"] -= dt
			b["node"].visible = false
			continue
		b["node"].visible = true
		for k in karts:
			if k.held_item == "" and k.pos2d.distance_to(b["pos"]) < track.width * 0.16 + 34.0:
				_roll_item(k)
				b["cd"] = 5.0
				break
	# player uses item on E (edge-triggered)
	var e := Input.is_key_pressed(KEY_E)
	if e and not _item_key_down and player.held_item != "" and not player.finished:
		_use_item(player)
	_item_key_down = e
	# AI use their item after a short random delay
	for k in karts:
		if k.is_ai and k.held_item != "" and randf() < dt * 0.8:
			_use_item(k)
	_update_shells(dt)
	_update_hazards(dt)
	_update_item_hud()

func _standing_of(k) -> int:
	return _standings().find(k) + 1

func _roll_item(k) -> void:
	var frac := float(_standing_of(k) - 1) / float(maxi(1, karts.size() - 1))
	var pool: Array
	if frac < 0.34:
		pool = ["bone", "banana", "oil", "bone"]
	elif frac < 0.67:
		pool = ["bone", "shell", "banana", "shield", "triple_bone"]
	else:
		pool = ["shell", "lightning", "triple_bone", "shield", "ghost"]
	k.held_item = pool[randi() % pool.size()]
	k.item_charges = 3 if k.held_item == "triple_bone" else 1
	if k == player:
		AudioManager.play_sfx("item_pickup")

func _use_item(k) -> void:
	var it: String = k.held_item
	if it == "":
		return
	if k == player:
		AudioManager.play_sfx(ITEM_SFX.get(it, "item_pickup"))
	if it == "triple_bone":
		k.add_boost(0.9)
		k.item_charges -= 1
		if k.item_charges <= 0:
			k.held_item = ""
		return
	match it:
		"bone": k.add_boost(0.95)
		"banana": _drop_hazard("banana", k)
		"oil": _drop_hazard("oil", k)
		"shell": _spawn_shell(k)
		"shield": k.give_shield(6.0)
		"lightning": _lightning(k)
		"ghost":
			k.add_boost(0.6); k.give_shield(2.5)
	k.held_item = ""
	k.item_charges = 0

func _drop_hazard(kind: String, k) -> void:
	var f := Vector2.RIGHT.rotated(k.heading)
	var p: Vector2 = k.pos2d - f * 48.0
	var node := MeshInstance3D.new()
	var m := StandardMaterial3D.new()
	if kind == "banana":
		var sp := SphereMesh.new(); sp.radius = 0.5; sp.height = 1.0; node.mesh = sp
		m.albedo_color = Color("#e6c800")
		node.position = _v3(p, 0.5)
	else:
		var cy := CylinderMesh.new(); cy.top_radius = 1.1; cy.bottom_radius = 1.1; cy.height = 0.06
		node.mesh = cy
		m.albedo_color = Color("#141414"); m.metallic = 0.5
		node.position = _v3(p, 0.05)
	node.material_override = m
	add_child(node)
	hazards.append({ "kind": kind, "pos": p, "node": node, "owner": k, "life": 22.0 })

func _update_hazards(dt: float) -> void:
	for h in hazards.duplicate():
		h["life"] -= dt
		var struck := false
		for k in karts:
			if k.pos2d.distance_to(h["pos"]) < 26.0:
				k.hit("spin")
				struck = true
		if struck or h["life"] <= 0.0:
			h["node"].queue_free()
			hazards.erase(h)

func _spawn_shell(k) -> void:
	var s := _standings()
	var idx := s.find(k)
	var target = s[idx - 1] if idx > 0 else null
	var node := MeshInstance3D.new()
	var sp := SphereMesh.new(); sp.radius = 0.55; sp.height = 1.1
	node.mesh = sp
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#e23b3b"); m.emission_enabled = true; m.emission = Color("#ff6a3a")
	node.material_override = m
	var f := Vector2.RIGHT.rotated(k.heading)
	var p: Vector2 = k.pos2d + f * 44.0
	node.position = _v3(p, 1.0)
	add_child(node)
	shells.append({ "node": node, "pos": p, "heading": k.heading, "target": target, "life": 6.0, "owner": k })

func _update_shells(dt: float) -> void:
	for sh in shells.duplicate():
		sh["life"] -= dt
		var aim: Vector2
		var tgt = sh["target"]
		if tgt != null and is_instance_valid(tgt) and not tgt.finished:
			aim = tgt.pos2d - sh["pos"]
		else:
			aim = Vector2.RIGHT.rotated(sh["heading"])
		sh["heading"] = lerp_angle(sh["heading"], aim.angle(), dt * 3.0)
		sh["pos"] += Vector2.RIGHT.rotated(sh["heading"]) * 720.0 * dt
		sh["node"].position = _v3(sh["pos"], 1.0)
		var struck := false
		for k in karts:
			if k != sh["owner"] and k.pos2d.distance_to(sh["pos"]) < 28.0:
				k.hit("spin")
				struck = true
		if struck or sh["life"] <= 0.0 or not track.is_on_road(sh["pos"], 70.0):
			sh["node"].queue_free()
			shells.erase(sh)

func _lightning(user) -> void:
	var us := _progress_score(user)
	for other in karts:
		if other != user and _progress_score(other) > us:
			other.apply_squish(3.0)

func _update_item_hud() -> void:
	if lbl_item == null:
		return
	if player.held_item == "":
		lbl_item.text = "ITEM  [ - ]"
	else:
		var extra := "  x%d" % player.item_charges if player.item_charges > 1 else ""
		lbl_item.text = "ITEM  [ %s ]%s   (E)" % [player.held_item.to_upper(), extra]


# ---- painted road-edge lines + roadside sponsor boards (Mario-Kart track dressing) ----
func _lat(i: int, off_m: float, y: float) -> Vector3:
	# a point offset laterally from centreline waypoint i by off_m METRES
	var dir := track.heading_at(i)
	var right := Vector2(-dir.y, dir.x)
	var pt := track.waypoints[i] + right * (off_m / WORLD_SCALE)
	return _v3(pt, y)

func _ribbon(off_a: float, off_b: float, y: float, col: Color, emis: float = 0.0) -> void:
	var n := track.waypoints.size()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in range(n):
		var j := (i + 1) % n
		var ra := _lat(i, off_a, y)
		var rb := _lat(i, off_b, y)
		var rc := _lat(j, off_b, y)
		var rd := _lat(j, off_a, y)
		for v in [ra, rd, rc, ra, rc, rb]:
			st.add_vertex(v)
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if emis > 0.0:
		m.emission_enabled = true
		m.emission = col
		m.emission_energy_multiplier = emis
	mi.material_override = m
	add_child(mi)

func _build_edge_lines() -> void:
	# a crisp white line just inside each road edge -> instantly reads as a race track
	var half_m := track.width * 0.5 * WORLD_SCALE
	_ribbon(half_m - 1.25, half_m - 0.70, ROAD_Y + 0.02, Color(1, 1, 1), 0.3)
	_ribbon(-(half_m - 0.70), -(half_m - 1.25), ROAD_Y + 0.02, Color(1, 1, 1), 0.3)

func _build_roadside_boards() -> void:
	# colourful sponsor-style signboards on posts, lining the track, alternating sides
	var n := track.waypoints.size()
	var half := track.width * 0.5
	var cols := [Color("#e8503a"), Color("#3aa0e8"), Color("#39c56a"), Color("#ffcf3a"), Color("#a05ad6")]
	var step := maxi(4, n / 22)
	var k := 0
	var i := 0
	while i < n:
		var dir := track.heading_at(i)
		var nrm := Vector2(-dir.y, dir.x)
		var side := 1.0 if (k % 2 == 0) else -1.0
		var base := track.waypoints[i] + nrm * side * (half + 20.0)
		var post := MeshInstance3D.new()
		post.mesh = _box(Vector3(0.25, 3.0, 0.25))
		post.material_override = _flat(Color("#c8c8c8"))
		add_child(post)
		post.position = _v3(base, 1.5)
		var board := MeshInstance3D.new()
		board.mesh = _box(Vector3(4.2, 1.7, 0.22))
		var c: Color = cols[k % cols.size()]
		var m := _flat(c)
		var bt := _tex("decor", "banner_a" if k % 2 == 0 else "banner_b")
		if bt != null:
			m.albedo_texture = bt
			m.albedo_color = Color.WHITE
		else:
			m.emission_enabled = true
			m.emission = c
			m.emission_energy_multiplier = 0.28
		board.material_override = m
		add_child(board)
		board.position = _v3(base, 3.5)
		var toward := track.waypoints[i] - base
		board.rotation.y = atan2(toward.x, toward.y)
		k += 1
		i += step


# ---- corner hazard signs, horizon backdrop, sky clouds (Mario-Kart world feel) ----
func _build_corner_signs() -> void:
	# bright yellow/red hazard boards on the outside of sharp corners
	var n := track.waypoints.size()
	var half := track.width * 0.5
	var i := 0
	while i < n:
		var a := track.waypoints[(i - 3 + n) % n]
		var b := track.waypoints[(i + 3) % n]
		var c := track.waypoints[i]
		var d0 := (c - a)
		var d1 := (b - c)
		d0 = d0.normalized() if d0.length() > 0.001 else Vector2.RIGHT
		d1 = d1.normalized() if d1.length() > 0.001 else Vector2.RIGHT
		var crossz := d0.x * d1.y - d0.y * d1.x
		if absf(crossz) < 0.25:
			i += 2
			continue
		var dir := track.heading_at(i)
		var nrm := Vector2(-dir.y, dir.x)
		var side := -signf(crossz)              # outside of the bend
		var base := c + nrm * side * (half + 16.0)
		var post := MeshInstance3D.new()
		post.mesh = _box(Vector3(0.3, 3.4, 0.3))
		post.material_override = _flat(Color("#4a4a4a"))
		add_child(post)
		post.position = _v3(base, 1.7)
		var board := MeshInstance3D.new()
		board.mesh = _box(Vector3(3.4, 2.2, 0.28))
		var ym := _flat(Color("#ffd21e"))
		ym.emission_enabled = true
		ym.emission = Color("#ffd21e")
		ym.emission_energy_multiplier = 0.45
		board.material_override = ym
		add_child(board)
		board.position = _v3(base, 3.7)
		var toward := c - base
		board.rotation.y = atan2(toward.x, toward.y)
		for sx: float in [-0.7, 0.7]:
			var stripe := MeshInstance3D.new()
			stripe.mesh = _box(Vector3(0.55, 2.7, 0.06))
			var sm := _flat(Color("#e23b3b"))
			sm.emission_enabled = true
			sm.emission = Color("#e23b3b")
			sm.emission_energy_multiplier = 0.4
			stripe.material_override = sm
			board.add_child(stripe)
			stripe.position = Vector3(sx, 0, 0.17)
			stripe.rotation = Vector3(0, 0, deg_to_rad(35))
		i += maxi(3, n / 12)

func _build_backdrop() -> void:
	# DISABLED: the generated hills/mesa art is near-opaque (fills the frame) and made a
	# green wall you could drive through. Distant _build_hills domes cover the horizon.
	return
	var asset := ""
	match track.theme:
		"grass", "cherry": asset = "hills_far"
		"desert", "beach", "volcano": asset = "mesa_far"
		_: return
	var tex := _tex("decor", asset)
	if tex == null:
		return
	var b := track.bounds()
	var c := b.get_center()
	var r := maxf(b.size.x, b.size.y) * 0.6 + 650.0
	var cnt := 12
	for k in range(cnt):
		var ang := TAU * float(k) / float(cnt)
		var p := c + Vector2(cos(ang), sin(ang)) * r
		var spr := Sprite3D.new()
		spr.texture = tex
		spr.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		spr.shaded = false
		spr.transparent = true
		var world_h := 95.0
		spr.pixel_size = world_h / float(maxi(tex.get_height(), 1))
		spr.position = _v3(p, world_h * 0.42)
		add_child(spr)

func _build_clouds() -> void:
	if track.theme == "moon":
		return
	var tex := _tex("decor", "cloud")
	if tex == null:
		return
	var b := track.bounds()
	var c := b.get_center()
	var r := maxf(b.size.x, b.size.y) * 0.55 + 380.0
	var cnt := 11
	for k in range(cnt):
		var ang := TAU * float(k) / float(cnt) + 0.3
		var rr := r * (0.8 + 0.08 * float((k * 7) % 5))
		var p := c + Vector2(cos(ang), sin(ang)) * rr
		var spr := Sprite3D.new()
		spr.texture = tex
		spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		spr.shaded = false
		spr.transparent = true
		var world_h := 55.0 + 20.0 * float(k % 3)
		spr.pixel_size = world_h / float(maxi(tex.get_height(), 1))
		spr.position = _v3(p, 60.0 + 14.0 * float(k % 4))
		add_child(spr)
