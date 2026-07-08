extends Node3D
class_name Kart3D
## A racer in the 3D race view. Logic (position, heading, checkpoints) runs in the
## SAME 2D pixel space as the Track model, so all tuning / AI / lap code matches the
## editor and the track file. The 3D transform is derived each frame by scaling that
## 2D position onto the ground plane (x, 0, y). The kart is a small low-poly model;
## the driver is a Boshi billboard (BoshiCore rendered into a SubViewport → Sprite3D).

signal lap_completed(kart, lap)
signal finished_race(kart)

const WORLD_SCALE := 0.06                       # pixels -> metres for the 3D view

# ---- identity ----
var racer_name: String = "Boshi"
var color: Color = Color("#e8503a")
var boshi_traits: Dictionary = {}
var is_ai: bool = false
var ai_skill: float = 1.0

# stat-driven physics multipliers (set from the Boshi's stats)
var spd_mul: float = 1.0
var acc_mul: float = 1.0
var turn_mul: float = 1.0
var mass: float = 1.0
var catchup: float = 1.0        # rubber-band top-speed bonus, set by race each frame

func set_stats(stats: Dictionary) -> void:
	var sp := float(stats.get("speed", 3))
	var ac := float(stats.get("accel", 3))
	var hd := float(stats.get("handling", 3))
	var wt := float(stats.get("weight", 3))
	spd_mul = 0.9 + 0.05 * sp       # 0.95 .. 1.15
	acc_mul = 0.8 + 0.09 * ac       # 0.89 .. 1.25
	turn_mul = 0.86 + 0.06 * hd     # 0.92 .. 1.16
	mass = 0.6 + 0.18 * wt          # 0.78 .. 1.5

# ---- tuning (pixels / second) — same numbers as the 2D prototype ----
const MAX_SPEED := 560.0
const BOOST_MULT := 1.55
const ACCEL := 780.0
const BRAKE := 1000.0
const REVERSE_MAX := -160.0
const COAST_FRICTION := 300.0
const TURN_SPEED := 3.0
const DRIFT_TURN_MULT := 1.9
const OFFROAD_MAX := 230.0     # grass slows you but doesn't strand you
const OFFROAD_DRAG := 450.0
const DRIFT_MIN_SPEED := 140.0
const DRIFT_CHARGE_FOR_BOOST := 0.8
const BOOST_TIME := 0.9

# ---- state (2D logic space) ----
var pos2d: Vector2 = Vector2.ZERO
var heading: float = 0.0
var speed: float = 0.0
var boost_time: float = 0.0
var drift_dir: int = 0
var drift_charge: float = 0.0
var body_lean: float = 0.0
var on_road: bool = true
var _wall_cd: float = 0.0        # cooldown so the wall-bonk sound doesn't machine-gun

# ---- race progress ----
var track: Track = null
var next_cp: int = 0
var cp_stride: int = 1
var _cps_passed: int = 0
var _num_cp: int = 1
var lap: int = 0
var total_laps: int = 3
var finished: bool = false
var finish_place: int = 0
var race_active: bool = false
var _boosted_props: Dictionary = {}

# items / combat
var held_item: String = ""
var item_charges: int = 0
var spinout_time: float = 0.0
var shield_time: float = 0.0
var squish_time: float = 0.0

var _model: Node3D = null                       # yawed to heading
var _boshi: Node2D = null
var _boost_particles: Node3D = null
var _sparks: Array = []                          # rear drift-spark emitters
var _was_drifting := false                       # for drift-start sfx

func setup(t: Track, start_offset: float = 0.0) -> void:
	track = t
	total_laps = t.laps
	heading = t.start_forward().angle()
	# checkpoints are a sparse subset of the (dense) centerline so they don't race
	# ahead of the kart: ~22 gates around the loop regardless of point density.
	var wn := t.waypoints.size()
	cp_stride = maxi(1, int(round(float(wn) / 22.0)))
	_num_cp = maxi(1, int(round(float(wn) / float(cp_stride))))
	_cps_passed = 0
	next_cp = (t.start_index + cp_stride) % wn
	var f := t.start_forward()
	var n := Vector2(-f.y, f.x)
	pos2d = t.start_position() + n * start_offset - f * 40.0
	_sync_transform()

func _ready() -> void:
	_build_model()
	_build_boshi_billboard()

# ------------------------------------------------------------------ 3D visuals
func _build_model() -> void:
	_model = Node3D.new()
	add_child(_model)
	# nose points toward -Z (Godot forward) so look_at aligns it with travel dir
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(1.6, 0.5, 2.6)
	body.mesh = bm
	body.material_override = _mat(color)
	body.position = Vector3(0, 0.45, 0)
	_model.add_child(body)
	# cabin / seat
	var cab := MeshInstance3D.new()
	var cm := BoxMesh.new()
	cm.size = Vector3(1.0, 0.4, 1.0)
	cab.mesh = cm
	cab.material_override = _mat(color.darkened(0.25))
	cab.position = Vector3(0, 0.8, 0.2)
	_model.add_child(cab)
	# nose wedge
	var nose := MeshInstance3D.new()
	var nm := BoxMesh.new()
	nm.size = Vector3(1.2, 0.3, 0.8)
	nose.mesh = nm
	nose.material_override = _mat(color.lightened(0.15))
	nose.position = Vector3(0, 0.35, -1.4)
	_model.add_child(nose)
	# wheels
	for wp in [Vector3(-0.95, 0.35, -0.9), Vector3(0.95, 0.35, -0.9),
			Vector3(-0.95, 0.35, 1.0), Vector3(0.95, 0.35, 1.0)]:
		var wheel := MeshInstance3D.new()
		var wm := CylinderMesh.new()
		wm.top_radius = 0.42; wm.bottom_radius = 0.42; wm.height = 0.35
		wheel.mesh = wm
		wheel.material_override = _mat(Color("#181820"))
		wheel.rotation = Vector3(0, 0, PI / 2)   # lay the cylinder on its side
		wheel.position = wp
		_model.add_child(wheel)
	# windshield (dark, in front of the cabin)
	var wind := MeshInstance3D.new()
	var wsm := BoxMesh.new()
	wsm.size = Vector3(0.9, 0.5, 0.15)
	wind.mesh = wsm
	var wsmat := _mat(Color("#20242e"))
	wsmat.metallic = 0.4; wsmat.roughness = 0.1
	wind.material_override = wsmat
	wind.position = Vector3(0, 0.85, -0.35)
	wind.rotation = Vector3(deg_to_rad(24), 0, 0)
	_model.add_child(wind)
	# rear spoiler (wing on two posts, at the back = +Z)
	var wing := MeshInstance3D.new()
	var wm2 := BoxMesh.new(); wm2.size = Vector3(1.9, 0.12, 0.5)
	wing.mesh = wm2
	wing.material_override = _mat(color.darkened(0.15))
	wing.position = Vector3(0, 1.05, 1.35)
	_model.add_child(wing)
	# a simple driver head so there's always a visible driver, even before art
	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.4; sm.height = 0.8
	head.mesh = sm
	head.material_override = _mat(color.lightened(0.35))
	head.position = Vector3(0, 1.3, 0.3)
	_model.add_child(head)
	# boost flames (shown only while boosting), out the back
	_boost_particles = Node3D.new()
	_model.add_child(_boost_particles)
	for k in range(2):
		var fl := MeshInstance3D.new()
		var fm := CylinderMesh.new()
		fm.top_radius = 0.0; fm.bottom_radius = 0.28 - 0.1 * k; fm.height = 0.9 - 0.3 * k
		fl.mesh = fm
		var flmat := StandardMaterial3D.new()
		flmat.albedo_color = Color("#ff9d2e") if k == 0 else Color("#ffe14d")
		flmat.emission_enabled = true
		flmat.emission = flmat.albedo_color
		flmat.emission_energy_multiplier = 2.5
		fl.mesh = fm
		fl.material_override = flmat
		fl.rotation = Vector3(deg_to_rad(-90), 0, 0)   # point the cone backward (+Z)
		fl.position = Vector3(0, 0.4, 1.7 + 0.2 * k)
		_boost_particles.add_child(fl)
	_boost_particles.visible = false
	# soft round shadow blob under the kart (flat quad, radial-alpha shader)
	var shadow := MeshInstance3D.new()
	var qm := QuadMesh.new(); qm.size = Vector2(3.4, 3.8)
	shadow.mesh = qm
	shadow.material_override = KartFX.shadow_material()
	shadow.rotation_degrees = Vector3(-90, 0, 0)     # lay flat on the ground
	shadow.position = Vector3(0, 0.04, 0)
	add_child(shadow)
	# rear drift-spark emitters (tinted by mini-turbo charge)
	for sx in [-0.95, 0.95]:
		var sp := KartFX.drift_sparks()
		sp.position = Vector3(sx, 0.3, 1.05)
		add_child(sp)
		_sparks.append(sp)

func _mat(c: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 0.6
	return m

func _build_boshi_billboard() -> void:
	# render the 2D BoshiCore compositor into a SubViewport, show it as a 3D billboard
	var bc := get_node_or_null("/root/BoshiCore")
	if bc == null:
		return
	var vp := SubViewport.new()
	vp.size = Vector2i(220, 260)
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(vp)
	var old: float = bc.display_height
	bc.display_height = 230.0
	_boshi = bc.spawn(boshi_traits, vp)
	bc.display_height = old
	if _boshi != null:
		_boshi.position = Vector2(110 - 26, 258 - 8)   # center-bottom of the viewport
		if _boshi.has_method("play"):
			_boshi.play("idle")
	var spr := Sprite3D.new()
	spr.texture = vp.get_texture()
	spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	spr.shaded = false
	spr.transparent = true
	spr.pixel_size = 0.011
	spr.position = Vector3(0, 1.6, 0.3)
	add_child(spr)

# ------------------------------------------------------------------ physics
func _physics_process(dt: float) -> void:
	if track == null:
		return
	# combat timers
	if shield_time > 0.0: shield_time -= dt
	if squish_time > 0.0: squish_time -= dt
	# spun out: no control, skid + spin, then recover
	if spinout_time > 0.0:
		spinout_time -= dt
		speed = move_toward(speed, 0.0, 900.0 * dt)
		heading += 15.0 * dt
		boost_time = max(0.0, boost_time - dt)
		pos2d += Vector2.RIGHT.rotated(heading) * speed * dt
		_sync_transform()
		_update_boshi_anim()
		return
	var throttle := 0.0
	var steer := 0.0
	var want_drift := false
	if finished or not race_active:
		speed = move_toward(speed, 0.0, COAST_FRICTION * dt)
	elif is_ai:
		var cmd := _ai_command()
		throttle = cmd.x; steer = cmd.y; want_drift = cmd.z > 0.5
	else:
		throttle = Input.get_action_strength("accelerate") - Input.get_action_strength("brake")
		steer = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
		want_drift = Input.is_action_pressed("drift")

	_integrate(dt, throttle, steer, want_drift)
	if race_active and not finished:
		_update_progress()
		_check_props()
	_update_boshi_anim()
	_sync_transform()
	if not is_ai:
		AudioManager.engine_set(clampf(absf(speed) / MAX_SPEED, 0.0, 1.0))
		AudioManager.offroad(race_active and not on_road and absf(speed) > 60.0)

func _integrate(dt: float, throttle: float, steer: float, want_drift: bool) -> void:
	on_road = track.is_on_road(pos2d)
	var top := MAX_SPEED * spd_mul * catchup * (BOOST_MULT if boost_time > 0.0 else 1.0)
	if not on_road:
		top = min(top, OFFROAD_MAX)
	if squish_time > 0.0:
		top = min(top, MAX_SPEED * 0.5)          # zapped by lightning
	if throttle > 0.01:
		# accel is snappier at low speed and tapers near top for a natural curve
		var curve := 1.0 - 0.35 * clampf(speed / maxf(top, 1.0), 0.0, 1.0)
		speed = move_toward(speed, top, ACCEL * acc_mul * throttle * curve * dt)
	elif throttle < -0.01:
		speed = move_toward(speed, REVERSE_MAX, BRAKE * dt)
	else:
		speed = move_toward(speed, 0.0, COAST_FRICTION * dt)
	if not on_road and speed > OFFROAD_MAX:
		speed = move_toward(speed, OFFROAD_MAX, OFFROAD_DRAG * dt)

	# steering: needs some speed to bite, and eases off a touch at very high speed
	# so the kart stays stable on straights while still turning hard in corners.
	var grip := clampf(absf(speed) / 110.0, 0.0, 1.0)
	var hi_speed := 1.0 - 0.22 * clampf(absf(speed) / MAX_SPEED, 0.0, 1.0)
	var turn := steer * TURN_SPEED * turn_mul * grip * hi_speed
	var drifting := want_drift and absf(speed) > DRIFT_MIN_SPEED and absf(steer) > 0.1
	if not is_ai and drifting and not _was_drifting:
		AudioManager.play_sfx("drift")
	_was_drifting = drifting
	if drifting:
		if drift_dir == 0:
			drift_dir = signi(int(sign(steer)))
		turn *= DRIFT_TURN_MULT
		drift_charge += dt
		body_lean = lerp(body_lean, float(drift_dir) * 0.3, dt * 8.0)
	else:
		if drift_dir != 0 and drift_charge >= DRIFT_CHARGE_FOR_BOOST:
			add_boost(BOOST_TIME)
			if not is_ai:
				AudioManager.play_sfx("turbo")
		drift_dir = 0
		drift_charge = 0.0
		body_lean = lerp(body_lean, 0.0, dt * 8.0)
	if speed < 0.0:
		turn = -turn
	heading += turn * dt
	boost_time = max(0.0, boost_time - dt)
	pos2d += Vector2.RIGHT.rotated(heading) * speed * dt
	_wall_cd = max(0.0, _wall_cd - dt)
	# solid track boundary — the roadside rail/fence is a WALL: you bonk off it and
	# lose speed, instead of sliding through onto the grass. A wheel can still clip
	# the very edge, but drive into the fence and it stops you like Mario Kart.
	var near := track.nearest_point(pos2d)
	var edge := pos2d - near
	var limit := track.width * 0.5 + 24.0
	if edge.length() > limit:
		var n := edge.normalized()
		pos2d = near + n * (limit - 3.0)                     # shoved back inside the wall
		speed *= 0.42                                        # hard bonk: big speed loss
		heading = lerp_angle(heading, (near - pos2d).angle(), 0.18)   # deflect back onto track
		if not is_ai and _wall_cd <= 0.0:
			_wall_cd = 0.3
			AudioManager.play_sfx("bump")
	_update_sparks(drifting)

func _update_sparks(drifting: bool) -> void:
	var active := drifting and absf(speed) > DRIFT_MIN_SPEED
	var col := KartFX.charge_color(drift_charge, DRIFT_CHARGE_FOR_BOOST)
	for sp in _sparks:
		sp.emitting = active
		if active:
			sp.color = col
			if sp.mesh != null and sp.mesh.material != null:
				sp.mesh.material.emission = col

func add_boost(t: float) -> void:
	boost_time = max(boost_time, t)
	speed = max(speed, MAX_SPEED * 1.05)

## Take a hit (shell / banana / oil). A shield absorbs one hit instead.
func hit(kind: String = "spin") -> void:
	if shield_time > 0.0:
		shield_time = 0.0
		return
	if kind == "squish":
		apply_squish(3.0)
	else:
		spinout_time = max(spinout_time, 1.4)

func apply_squish(t: float) -> void:
	if shield_time > 0.0:
		return
	squish_time = max(squish_time, t)
	speed = min(speed, MAX_SPEED * 0.4)

func give_shield(t: float) -> void:
	shield_time = max(shield_time, t)

func _ai_command() -> Vector3:
	var n := track.waypoints.size()
	var target := track.waypoints[next_cp]
	var ahead := track.waypoints[(next_cp + cp_stride) % n]
	target = target.lerp(ahead, 0.4)
	var to := target - pos2d
	var desired := to.angle()
	var diff := wrapf(desired - heading, -PI, PI)
	var steer := clampf(diff * 2.2, -1.0, 1.0)
	var throttle := 1.0 * clampf(ai_skill, 0.7, 1.15)
	if absf(diff) > 1.2:
		throttle *= 0.7
	# look further ahead and slow for an upcoming sharp corner (smoother racing line)
	var g2 := track.waypoints[(next_cp + cp_stride) % n]
	var g3 := track.waypoints[(next_cp + 2 * cp_stride) % n]
	var v1 := (g2 - track.waypoints[next_cp]).normalized()
	var v2 := (g3 - g2).normalized()
	var upcoming := absf(wrapf(v2.angle() - v1.angle(), -PI, PI))   # 0 straight .. PI hairpin
	throttle *= clampf(1.0 - upcoming * 0.5, 0.55, 1.0)
	var drift := 1.0 if absf(diff) > 0.65 and speed > DRIFT_MIN_SPEED else 0.0
	return Vector3(throttle, steer, drift)

func _update_progress() -> void:
	var n := track.waypoints.size()
	var radius := maxf(track.width * 0.7, 150.0)
	if pos2d.distance_to(track.waypoints[next_cp]) <= radius:
		next_cp = (next_cp + cp_stride) % n
		_cps_passed += 1
		if _cps_passed >= _num_cp:            # completed one full loop of gates
			_cps_passed = 0
			lap += 1
			lap_completed.emit(self, lap)
			if lap >= total_laps and not finished:
				finished = true
				finished_race.emit(self)

func _check_props() -> void:
	for i in range(track.props.size()):
		var d: Dictionary = track.props[i]
		var p: Vector2 = d.get("pos", Vector2.ZERO)
		var cd: float = _boosted_props.get(i, 0.0)
		if cd > 0.0:
			_boosted_props[i] = cd - get_physics_process_delta_time()
			continue
		var type := str(d.get("type", ""))
		if type == "boost" and pos2d.distance_to(p) < 34.0:
			add_boost(BOOST_TIME); _boosted_props[i] = 1.0
			if not is_ai: AudioManager.play_sfx("boost")
		elif type == "coin" and pos2d.distance_to(p) < 22.0:
			speed = min(speed + 30.0, MAX_SPEED * BOOST_MULT); _boosted_props[i] = 4.0
			if not is_ai: AudioManager.play_sfx("coin")
		elif type in ["obstacle", "oil"] and pos2d.distance_to(p) < 26.0:
			speed *= 0.4; _boosted_props[i] = 0.6
			if not is_ai: AudioManager.play_sfx("bump")

func _update_boshi_anim() -> void:
	if _boshi == null or not _boshi.has_method("play"):
		return
	var want := "idle"
	if absf(speed) > 380.0:
		want = "run"
	elif absf(speed) > 40.0:
		want = "walk"
	if _boshi.get("_current_anim") != want:
		_boshi.play(want)

# ------------------------------------------------------------------ transform
const ROAD_Y := 0.06    # match race3d road surface height

func _sync_transform() -> void:
	global_position = Vector3(pos2d.x, 0.0, pos2d.y) * WORLD_SCALE + Vector3.UP * ROAD_Y
	var fwd := Vector2.RIGHT.rotated(heading)
	var fwd3 := Vector3(fwd.x, 0.0, fwd.y)
	if fwd3.length() > 0.001:
		look_at(global_position + fwd3, Vector3.UP)
	if _model != null:
		_model.rotation.z = body_lean          # visual drift lean
		_model.scale = Vector3.ONE * (0.55 if squish_time > 0.0 else 1.0)
	if _boost_particles != null:
		_boost_particles.visible = boost_time > 0.0
