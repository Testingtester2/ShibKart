extends RefCounted
class_name Track
## ShibKart track model + (de)serialization + geometry helpers.
##
## A track is a CLOSED LOOP centerline (a list of waypoints) with a road WIDTH,
## a lap count, an optional list of props (boost pads / obstacles / coins), and a
## start_index marking which waypoint carries the start/finish line.
##
## Save format is plain JSON — see docs/TRACK_FORMAT.md. Tracks live under
## user://tracks/*.track.json (player-made) and res://assets/tracks/*.track.json
## (bundled). Keeping the model tiny and text-based makes tracks trivially
## shareable: copy the .track.json file.

const FORMAT_ID := "shibkart_track"
const FORMAT_VERSION := 1

var name: String = "Untitled"
var theme: String = "grass"          # biome: grass/city/desert/moon/cherry/snow/volcano/beach
var weather: String = "clear"        # clear / rain / snow / fog
var width: float = 220.0
var laps: int = 3
var waypoints: PackedVector2Array = PackedVector2Array()   # closed loop centerline
var props: Array = []                                       # [{type,pos:Vector2,rot}]
var start_index: int = 0                                    # waypoint with start line

# ------------------------------------------------------------------ serialization
func to_dict() -> Dictionary:
	var pts: Array = []
	for p in waypoints:
		pts.append([snappedf(p.x, 0.01), snappedf(p.y, 0.01)])
	var pr: Array = []
	for d in props:
		var pos: Vector2 = d.get("pos", Vector2.ZERO)
		pr.append({
			"type": d.get("type", "boost"),
			"pos": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)],
			"rot": snappedf(d.get("rot", 0.0), 0.001),
		})
	return {
		"format": FORMAT_ID,
		"version": FORMAT_VERSION,
		"name": name,
		"theme": theme,
		"weather": weather,
		"width": width,
		"laps": laps,
		"start_index": start_index,
		"waypoints": pts,
		"props": pr,
	}

func to_json() -> String:
	return JSON.stringify(to_dict(), "  ")

static func from_dict(d: Dictionary) -> Track:
	var t := Track.new()
	t.name = str(d.get("name", "Untitled"))
	t.theme = str(d.get("theme", "grass"))
	t.weather = str(d.get("weather", "clear"))
	t.width = float(d.get("width", 220.0))
	t.laps = int(d.get("laps", 3))
	t.start_index = int(d.get("start_index", 0))
	var pts := PackedVector2Array()
	for p in d.get("waypoints", []):
		if p is Array and p.size() >= 2:
			pts.append(Vector2(float(p[0]), float(p[1])))
	t.waypoints = pts
	var pr: Array = []
	for e in d.get("props", []):
		if e is Dictionary:
			var pos: Variant = e.get("pos", [0, 0])
			var v := Vector2.ZERO
			if pos is Array and pos.size() >= 2:
				v = Vector2(float(pos[0]), float(pos[1]))
			pr.append({ "type": str(e.get("type", "boost")), "pos": v, "rot": float(e.get("rot", 0.0)) })
	t.props = pr
	if t.start_index < 0 or t.start_index >= t.waypoints.size():
		t.start_index = 0
	return t

## Load from a res:// or user:// path. Returns null on any failure.
static func load_from(path: String) -> Track:
	if not FileAccess.file_exists(path):
		push_warning("Track.load_from: no file at %s" % path)
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var txt := f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(txt)
	if not (parsed is Dictionary):
		push_warning("Track.load_from: %s is not valid JSON" % path)
		return null
	if str(parsed.get("format", "")) != FORMAT_ID:
		push_warning("Track.load_from: %s is not a %s file" % [path, FORMAT_ID])
		return null
	return from_dict(parsed)

## Save to user://tracks/<slug>.track.json (creates the dir). Returns the path or "".
func save_to_user() -> String:
	DirAccess.make_dir_recursive_absolute("user://tracks")
	var path := "user://tracks/%s.track.json" % _slug(name)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_warning("Track.save_to_user: cannot open %s for write" % path)
		return ""
	f.store_string(to_json())
	f.close()
	return path

static func list_user_tracks() -> Array:
	var out: Array = []
	DirAccess.make_dir_recursive_absolute("user://tracks")
	var d := DirAccess.open("user://tracks")
	if d:
		for fn in d.get_files():
			if fn.ends_with(".track.json"):
				out.append("user://tracks/" + fn)
	return out

static func list_bundled_tracks() -> Array:
	var out: Array = []
	var d := DirAccess.open("res://assets/tracks")
	if d:
		for fn in d.get_files():
			# .import files show up for res:// text too; only take the json
			if fn.ends_with(".track.json"):
				out.append("res://assets/tracks/" + fn)
	return out

# ------------------------------------------------------------------ geometry
func is_valid() -> bool:
	return waypoints.size() >= 3

## Perpendicular (screen) direction of the loop at waypoint i, pointing "forward".
func heading_at(i: int) -> Vector2:
	var n := waypoints.size()
	if n < 2:
		return Vector2.RIGHT
	var a := waypoints[(i - 1 + n) % n]
	var b := waypoints[(i + 1) % n]
	var dir := (b - a)
	return dir.normalized() if dir.length() > 0.001 else Vector2.RIGHT

## Start transform: position at start waypoint, rotation facing along the loop.
func start_position() -> Vector2:
	return waypoints[start_index] if is_valid() else Vector2.ZERO

func start_forward() -> Vector2:
	return heading_at(start_index)

## Build the left/right road edges for rendering a filled ribbon (closed loop).
func edge_polygons() -> Dictionary:
	var left := PackedVector2Array()
	var right := PackedVector2Array()
	var n := waypoints.size()
	var half := width * 0.5
	for i in range(n):
		var dir := heading_at(i)
		var normal := Vector2(-dir.y, dir.x)
		left.append(waypoints[i] + normal * half)
		right.append(waypoints[i] - normal * half)
	return { "left": left, "right": right }

## One closed polygon covering the road surface (left edge forward + right back).
func road_polygon() -> PackedVector2Array:
	var e := edge_polygons()
	var poly := PackedVector2Array()
	poly.append_array(e["left"])
	var right: PackedVector2Array = e["right"]
	for i in range(right.size() - 1, -1, -1):
		poly.append(right[i])
	return poly

## Shortest distance from p to the closed centerline (for on-track / off-road test).
func distance_to_centerline(p: Vector2) -> float:
	var n := waypoints.size()
	if n < 2:
		return 1e9
	var best := 1e9
	for i in range(n):
		var a := waypoints[i]
		var b := waypoints[(i + 1) % n]
		best = min(best, _seg_dist(p, a, b))
	return best

func is_on_road(p: Vector2, slack: float = 8.0) -> bool:
	return distance_to_centerline(p) <= width * 0.5 + slack

## Closest point on the centerline loop (used to keep karts inside the rails).
func nearest_point(p: Vector2) -> Vector2:
	var n := waypoints.size()
	if n < 2:
		return p
	var best := waypoints[0]
	var bd := 1e20
	for i in range(n):
		var a := waypoints[i]
		var b := waypoints[(i + 1) % n]
		var ab := b - a
		var t := clampf((p - a).dot(ab) / maxf(ab.length_squared(), 0.0001), 0.0, 1.0)
		var q := a + ab * t
		var d := p.distance_squared_to(q)
		if d < bd:
			bd = d
			best = q
	return best

static func _seg_dist(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab := b - a
	var len2 := ab.length_squared()
	if len2 < 0.0001:
		return p.distance_to(a)
	var t := clampf((p - a).dot(ab) / len2, 0.0, 1.0)
	return p.distance_to(a + ab * t)

## Axis-aligned bounds of the whole course (for centering the editor / minimap).
func bounds() -> Rect2:
	if waypoints.is_empty():
		return Rect2(0, 0, 0, 0)
	var r := Rect2(waypoints[0], Vector2.ZERO)
	for p in waypoints:
		r = r.expand(p)
	return r.grow(width)

## A denser, Catmull-Rom-smoothed copy used at RACE time so every track curves
## nicely. The editor keeps sparse control points; this densifies them on load so
## road, kerbs, scenery and AI lines all become smooth with no per-track authoring.
func smoothed(subdiv: int = 6) -> Track:
	var n := waypoints.size()
	if n < 3 or subdiv < 2:
		return self
	var t := Track.new()
	t.name = name; t.theme = theme; t.weather = weather
	t.width = width; t.laps = laps
	t.props = props.duplicate(true)
	var pts := PackedVector2Array()
	for i in range(n):
		var p0 := waypoints[(i - 1 + n) % n]
		var p1 := waypoints[i]
		var p2 := waypoints[(i + 1) % n]
		var p3 := waypoints[(i + 2) % n]
		for s in range(subdiv):
			pts.append(_catmull(p0, p1, p2, p3, float(s) / float(subdiv)))
	t.waypoints = pts
	t.start_index = (start_index * subdiv) % pts.size()
	return t

static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((p1 * 2.0) + (-p0 + p2) * t
		+ (p0 * 2.0 - p1 * 5.0 + p2 * 4.0 - p3) * t2
		+ (-p0 + p1 * 3.0 - p2 * 3.0 + p3) * t3)

static func _slug(s: String) -> String:
	var out := ""
	for c in s.to_lower():
		if (c >= "a" and c <= "z") or (c >= "0" and c <= "9"):
			out += c
		elif c == " " or c == "-" or c == "_":
			out += "_"
	if out.strip_edges() == "":
		out = "track"
	return out

# ------------------------------------------------------------------ defaults
## A ready-to-race oval so the game runs before anyone opens the editor.
static func make_default() -> Track:
	var t := Track.new()
	t.name = "Boshi Speedway"
	t.width = 240.0
	t.laps = 3
	var cx := 640.0
	var cy := 360.0
	var rx := 460.0
	var ry := 240.0
	var pts := PackedVector2Array()
	var steps := 24
	for i in range(steps):
		var ang := TAU * float(i) / float(steps)
		# squash into a rounded rectangle-ish oval
		pts.append(Vector2(cx + cos(ang) * rx, cy + sin(ang) * ry))
	t.waypoints = pts
	t.start_index = 0
	t.props = [
		{ "type": "boost", "pos": Vector2(cx + rx * 0.7, cy - ry * 0.7), "rot": 0.0 },
		{ "type": "boost", "pos": Vector2(cx - rx * 0.7, cy + ry * 0.7), "rot": 0.0 },
		{ "type": "coin",  "pos": Vector2(cx, cy - ry), "rot": 0.0 },
		{ "type": "coin",  "pos": Vector2(cx, cy + ry), "rot": 0.0 },
	]
	return t
