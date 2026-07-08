extends Control
class_name Minimap
## Corner minimap: draws the whole track loop + live kart dots so you always know
## the layout and where everyone is. Fed the track + karts by race3d.

var track: Track
var karts: Array = []
var player = null

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _process(_dt: float) -> void:
	queue_redraw()

func _draw() -> void:
	if track == null or not track.is_valid():
		return
	# background panel
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.05, 0.03, 0.12, 0.55), true)
	draw_rect(Rect2(Vector2.ZERO, size), Color("#f4b942"), false, 2.0)

	var r := track.bounds()
	var pad := 14.0
	var area := Vector2(size.x - pad * 2.0, size.y - pad * 2.0)
	var sc := minf(area.x / maxf(r.size.x, 1.0), area.y / maxf(r.size.y, 1.0))
	var off := Vector2(pad, pad) + (area - r.size * sc) * 0.5

	var pts := PackedVector2Array()
	for wp in track.waypoints:
		pts.append(off + (wp - r.position) * sc)
	# track ribbon (thick grey under, thin bright over)
	var n := pts.size()
	for i in range(n):
		draw_line(pts[i], pts[(i + 1) % n], Color(0, 0, 0, 0.6), 6.0)
	for i in range(n):
		draw_line(pts[i], pts[(i + 1) % n], Color("#e8e8ee"), 3.0)
	# start/finish
	draw_circle(pts[track.start_index], 5.0, Color("#39ff88"))
	# kart dots
	for k in karts:
		var p: Vector2 = off + (k.pos2d - r.position) * sc
		if k == player:
			draw_circle(p, 6.0, Color.WHITE)
			draw_circle(p, 6.0, Color("#1a1a2a"), false, 2.0)
		else:
			draw_circle(p, 4.5, k.color)
