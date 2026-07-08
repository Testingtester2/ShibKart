extends Node2D
class_name TrackView
## Draws a Track: grass backdrop, road ribbon, kerb edges, center dashes,
## start/finish line and props. Used by both the race scene and the editor
## (editor draws extra handles on top). Pure _draw() so it needs no art, but it
## will happily sit under generated tile art later.

var track: Track = null
var show_waypoints: bool = false          # editor turns this on
var show_smoothed: bool = false           # editor: preview the smoothed race ribbon
var selected_index: int = -1

const COL_GRASS := Color("#3f7d3a")
const COL_ROAD := Color("#4a4a55")
const COL_KERB_A := Color("#d94f4f")
const COL_KERB_B := Color("#f2f2f2")
const COL_CENTER := Color("#f4d24a")
const PROP_COLORS := {
	"boost": Color("#39d0ff"),
	"coin": Color("#f4d24a"),
	"obstacle": Color("#8a5a2a"),
	"oil": Color("#20202a"),
}

func set_track(t: Track) -> void:
	track = t
	queue_redraw()

func _draw() -> void:
	if track == null or not track.is_valid():
		return
	# geometry source: the smoothed race ribbon (preview) or the raw control loop
	var geo: Track = track
	if show_smoothed and track.waypoints.size() >= 3:
		geo = track.smoothed(5)
	# road surface — per-segment convex quads (a single ring polygon is concave and
	# would triangulate wrong), so the ribbon fills cleanly.
	var e := geo.edge_polygons()
	var left: PackedVector2Array = e["left"]
	var right: PackedVector2Array = e["right"]
	var m := left.size()
	for i in range(m):
		var j := (i + 1) % m
		var quad := PackedVector2Array([left[i], left[j], right[j], right[i]])
		draw_colored_polygon(quad, COL_ROAD)
	# kerb edges (dashed red/white look via alternating segments)
	_draw_kerb(e["left"])
	_draw_kerb(e["right"])
	# center dashes along the smoothed line
	var gn := geo.waypoints.size()
	for i in range(gn):
		var a := geo.waypoints[i]
		var b := geo.waypoints[(i + 1) % gn]
		if i % 2 == 0:
			draw_line(a, b, COL_CENTER, 4.0)
	# start / finish line — a checkered bar across the road at start_index
	_draw_start_line()
	# props
	for d in track.props:
		_draw_prop(d)
	# editor handles (drawn on the RAW control points, which are draggable)
	if show_waypoints:
		for i in range(track.waypoints.size()):
			var p: Vector2 = track.waypoints[i]
			var col := Color("#ffffff") if i != selected_index else Color("#ffd23a")
			draw_circle(p, 9.0, Color(0, 0, 0, 0.5))
			draw_circle(p, 7.0, col)
			if i == track.start_index:
				draw_circle(p, 12.0, Color("#39ff88"), false, 2.0)

func _draw_kerb(edge: PackedVector2Array) -> void:
	var n := edge.size()
	for i in range(n):
		var a := edge[i]
		var b := edge[(i + 1) % n]
		draw_line(a, b, COL_KERB_A if i % 2 == 0 else COL_KERB_B, 8.0)

func _draw_start_line() -> void:
	var i := track.start_index
	var p := track.waypoints[i]
	var dir := track.heading_at(i)
	var normal := Vector2(-dir.y, dir.x)
	var half := track.width * 0.5
	var a := p + normal * half
	var b := p - normal * half
	# checkered bar
	var squares := 10
	for s in range(squares):
		var t0 := float(s) / squares
		var t1 := float(s + 1) / squares
		var q0 := a.lerp(b, t0)
		var q1 := a.lerp(b, t1)
		var col := Color.WHITE if s % 2 == 0 else Color.BLACK
		var w := dir * 10.0
		var quad := PackedVector2Array([q0 - w, q1 - w, q1 + w, q0 + w])
		draw_colored_polygon(quad, col)

func _draw_prop(d: Dictionary) -> void:
	var pos: Vector2 = d.get("pos", Vector2.ZERO)
	var type: String = str(d.get("type", "boost"))
	var col: Color = PROP_COLORS.get(type, Color.MAGENTA)
	match type:
		"boost":
			# chevron pad
			draw_circle(pos, 26.0, Color(col, 0.35))
			var f := track.heading_at(_nearest_wp(pos)) if track else Vector2.RIGHT
			var s := Vector2(-f.y, f.x)
			for k in range(3):
				var base := pos - f * 18.0 + f * (k * 14.0)
				draw_line(base - s * 16.0, base + f * 12.0, col, 4.0)
				draw_line(base + s * 16.0, base + f * 12.0, col, 4.0)
		"coin":
			draw_circle(pos, 12.0, col)
			draw_circle(pos, 12.0, Color("#b8860b"), false, 2.0)
		"obstacle":
			draw_rect(Rect2(pos - Vector2(14, 14), Vector2(28, 28)), col)
		"oil":
			draw_circle(pos, 20.0, col)
		_:
			draw_circle(pos, 12.0, col)

func _nearest_wp(p: Vector2) -> int:
	var best := 0
	var bd := 1e9
	for i in range(track.waypoints.size()):
		var d := p.distance_squared_to(track.waypoints[i])
		if d < bd:
			bd = d
			best = i
	return best
