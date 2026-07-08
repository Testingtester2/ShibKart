extends Node2D
class_name Kart
## One racer — player or AI — sharing the same arcade physics and lap tracking.
## Node2D.rotation stays 0; the kart body is drawn manually rotated by `heading`
## so the BoshiCore driver (a child compositor) stays an upright billboard.

signal lap_completed(kart: Kart, lap: int)
signal finished_race(kart: Kart)

# ---- identity ----
var racer_name: String = "Boshi"
var color: Color = Color("#e8503a")
var boshi_traits: Dictionary = {}
var is_ai: bool = false
var ai_skill: float = 1.0                     # 0.8 slow .. 1.1 fast (rubber-banding)

# ---- tuning (pixels / second) ----
const MAX_SPEED := 520.0
const BOOST_MULT := 1.5
const ACCEL := 640.0
const BRAKE := 900.0
const REVERSE_MAX := -150.0
const COAST_FRICTION := 260.0
const TURN_SPEED := 2.7                        # rad/s at full lock, full speed
const DRIFT_TURN_MULT := 1.6
const OFFROAD_MAX := 190.0
const OFFROAD_DRAG := 520.0
const DRIFT_MIN_SPEED := 150.0
const DRIFT_CHARGE_FOR_BOOST := 0.9            # seconds of drift -> mini-turbo
const BOOST_TIME := 0.85

# ---- state ----
var heading: float = 0.0                       # facing angle, radians
var speed: float = 0.0
var boost_time: float = 0.0
var drift_dir: int = 0
var drift_charge: float = 0.0
var body_lean: float = 0.0                     # visual drift lean
var on_road: bool = true

# ---- race progress ----
var track: Track = null
var next_cp: int = 0
var lap: int = 0
var total_laps: int = 3
var finished: bool = false
var finish_place: int = 0
var race_active: bool = false
var _coins: int = 0
var _boosted_props: Dictionary = {}            # prop index -> cooldown

var _boshi: Node2D = null
var _kart_tex: Texture2D = null

const KART_TEX_PATH := "res://assets/karts/kart_body.png"

func _ready() -> void:
	# Optional generated art: a top-down kart body PNG (tinted per racer). Drawn
	# rotated by heading in _draw(). Absent -> the procedural kart shape is used.
	if ResourceLoader.exists(KART_TEX_PATH):
		_kart_tex = load(KART_TEX_PATH)

func setup(t: Track, start_offset: float = 0.0) -> void:
	track = t
	total_laps = t.laps
	heading = t.start_forward().angle()
	next_cp = (t.start_index + 1) % t.waypoints.size()
	# stagger grid position slightly perpendicular to the start line
	var f := t.start_forward()
	var n := Vector2(-f.y, f.x)
	position = t.start_position() + n * start_offset - f * 40.0

func attach_boshi() -> void:
	var bc := get_node_or_null("/root/BoshiCore")
	if bc != null:
		_boshi = bc.spawn(boshi_traits, self)
		# center the side-view billboard over the kart, feet near the seat
		if _boshi != null:
			_boshi.position = Vector2(-24.0, -78.0)
			if _boshi.has_method("play"):
				_boshi.play("idle")

func _physics_process(dt: float) -> void:
	if track == null:
		return
	var throttle := 0.0
	var steer := 0.0
	var want_drift := false
	if finished or not race_active:
		# ease to a stop after finishing / before countdown
		speed = move_toward(speed, 0.0, COAST_FRICTION * dt)
	elif is_ai:
		var cmd := _ai_command()
		throttle = cmd.x
		steer = cmd.y
		want_drift = cmd.z > 0.5
	else:
		throttle = Input.get_action_strength("accelerate") - Input.get_action_strength("brake")
		steer = Input.get_action_strength("steer_right") - Input.get_action_strength("steer_left")
		want_drift = Input.is_action_pressed("drift")

	_integrate(dt, throttle, steer, want_drift)
	if race_active and not finished:
		_update_progress()
		_check_props()
	_update_boshi_anim()
	queue_redraw()

func _integrate(dt: float, throttle: float, steer: float, want_drift: bool) -> void:
	on_road = track.is_on_road(position)
	var top := MAX_SPEED * (BOOST_MULT if boost_time > 0.0 else 1.0)
	if not on_road:
		top = min(top, OFFROAD_MAX)

	if throttle > 0.01:
		speed = move_toward(speed, top, ACCEL * throttle * dt)
	elif throttle < -0.01:
		speed = move_toward(speed, REVERSE_MAX, BRAKE * dt)
	else:
		speed = move_toward(speed, 0.0, COAST_FRICTION * dt)
	if not on_road and speed > OFFROAD_MAX:
		speed = move_toward(speed, OFFROAD_MAX, OFFROAD_DRAG * dt)

	# steering — scales with speed so a parked kart doesn't spin
	var grip := clampf(absf(speed) / 120.0, 0.0, 1.0)
	var turn := steer * TURN_SPEED * grip
	var drifting := want_drift and absf(speed) > DRIFT_MIN_SPEED and absf(steer) > 0.1
	if drifting:
		if drift_dir == 0:
			drift_dir = signi(int(sign(steer)))
		turn *= DRIFT_TURN_MULT
		drift_charge += dt
		body_lean = lerp(body_lean, float(drift_dir) * 0.35, dt * 8.0)
	else:
		if drift_dir != 0 and drift_charge >= DRIFT_CHARGE_FOR_BOOST:
			add_boost(BOOST_TIME)          # release a charged drift -> mini-turbo
		drift_dir = 0
		drift_charge = 0.0
		body_lean = lerp(body_lean, 0.0, dt * 8.0)
	if speed < 0.0:
		turn = -turn                        # reverse steering
	heading += turn * dt

	boost_time = max(0.0, boost_time - dt)
	position += Vector2.RIGHT.rotated(heading) * speed * dt

func add_boost(t: float) -> void:
	boost_time = max(boost_time, t)
	speed = max(speed, MAX_SPEED * 1.05)

# ---- AI: aim at a lookahead checkpoint, throttle always, drift on sharp turns ----
func _ai_command() -> Vector3:
	var n := track.waypoints.size()
	var target := track.waypoints[next_cp]
	# lookahead: blend toward the following checkpoint for smoother lines
	var ahead := track.waypoints[(next_cp + 1) % n]
	target = target.lerp(ahead, 0.35)
	var to := target - position
	var desired := to.angle()
	var diff := wrapf(desired - heading, -PI, PI)
	var steer := clampf(diff * 2.2, -1.0, 1.0)
	var throttle := 1.0 * clampf(ai_skill, 0.7, 1.15)
	# ease off on very sharp corrections so AI doesn't over-oscillate
	if absf(diff) > 1.2:
		throttle *= 0.7
	var drift := 1.0 if absf(diff) > 0.7 and speed > DRIFT_MIN_SPEED else 0.0
	return Vector3(throttle, steer, drift)

func _update_progress() -> void:
	var n := track.waypoints.size()
	var cp := track.waypoints[next_cp]
	var radius := maxf(track.width * 0.65, 130.0)
	if position.distance_to(cp) <= radius:
		if next_cp == track.start_index:
			lap += 1
			lap_completed.emit(self, lap)
			if lap >= total_laps and not finished:
				finished = true
				finished_race.emit(self)
		next_cp = (next_cp + 1) % n

func _check_props() -> void:
	for i in range(track.props.size()):
		var d: Dictionary = track.props[i]
		var pos: Vector2 = d.get("pos", Vector2.ZERO)
		var cd: float = _boosted_props.get(i, 0.0)
		if cd > 0.0:
			_boosted_props[i] = cd - get_physics_process_delta_time()
			continue
		var type := str(d.get("type", ""))
		if type == "boost" and position.distance_to(pos) < 34.0:
			add_boost(BOOST_TIME)
			_boosted_props[i] = 1.0
		elif type == "coin" and position.distance_to(pos) < 22.0:
			_coins += 1
			speed = min(speed + 30.0, MAX_SPEED * BOOST_MULT)
			_boosted_props[i] = 4.0
		elif type in ["obstacle", "oil"] and position.distance_to(pos) < 26.0:
			speed *= 0.4
			_boosted_props[i] = 0.6

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

# ------------------------------------------------------------------ rendering
func _draw() -> void:
	# shadow
	draw_circle(Vector2(0, 6), 20.0, Color(0, 0, 0, 0.25))
	var ang := heading + body_lean
	var fwd := Vector2.RIGHT.rotated(ang)
	var side := Vector2(-fwd.y, fwd.x)
	# generated art path: draw the kart body texture, tinted by racer color
	if _kart_tex != null:
		draw_set_transform(Vector2.ZERO, ang, Vector2.ONE)
		var sz := _kart_tex.get_size()
		var target_w := 64.0
		var s := target_w / maxf(sz.x, 1.0)
		draw_texture_rect(_kart_tex, Rect2(-sz * s * 0.5, sz * s), false, color)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if boost_time > 0.0:
			draw_circle(-fwd * 30.0, 7.0, Color("#ff9d2e"))
		return
	# kart body (rounded quad), tinted by racer color
	var hl := 22.0
	var hw := 14.0
	var body := PackedVector2Array([
		fwd * hl + side * hw * 0.6,
		fwd * hl - side * hw * 0.6,
		-fwd * hl - side * hw,
		-fwd * hl + side * hw,
	])
	draw_colored_polygon(body, color)
	# wheels
	var wheel := Color("#181820")
	for s in [-1.0, 1.0]:
		draw_circle(fwd * 12.0 + side * hw * 1.05 * s, 6.0, wheel)
		draw_circle(-fwd * 12.0 + side * hw * 1.05 * s, 6.0, wheel)
	# nose accent
	draw_line(fwd * hl, fwd * (hl + 8.0), color.lightened(0.3), 3.0)
	# boost flames
	if boost_time > 0.0:
		var fl := Color("#ff9d2e")
		draw_circle(-fwd * (hl + 6.0), 7.0, fl)
		draw_circle(-fwd * (hl + 14.0), 4.0, Color("#ffe14d"))
	# driver seat bump (so there's always a visible "driver" even without art)
	if _boshi == null:
		draw_circle(Vector2.ZERO - fwd * 2.0, 8.0, color.darkened(0.25))
