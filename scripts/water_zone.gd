class_name WaterZone
extends Node2D

# Lago della mappa "lake", disegnato in due strati:
#  - front=false (dietro ai lottatori): la costa rocciosa che scende a gradoni
#    dolci verso destra, con il fondale visibile sotto il pelo dell'acqua
#  - front=true (davanti ai lottatori): velo d'acqua traslucido con superficie
#    ondulata (linea continua) e luccichii, cosi' chi si immerge appare
#    "dentro" l'acqua.

const X_RIGHT := 1330.0

var game: Node2D
var front := false
var t := 0.0


func _ready() -> void:
	if front:
		z_index = 40


func _process(dt: float) -> void:
	t += dt
	queue_redraw()


func _slabs() -> Array:
	# [x0, x1, quota del pavimento] della costa a gradoni
	var x0: float = game.LAKE_X0
	var sw: float = game.STEP_W
	var fl: float = game.FLOOR_Y
	var sh: float = game.STEP_H
	return [
		[-270.0, x0, fl],
		[x0, x0 + sw, fl + sh],
		[x0 + sw, x0 + sw * 2.0, fl + sh * 2.0],
		[x0 + sw * 2.0, x0 + sw * 3.0, fl + sh * 3.0],
		[x0 + sw * 3.0, X_RIGHT, game.LAKE_BOTTOM],
	]


func _draw() -> void:
	var wy: float = game.WATER_Y
	var by: float = game.LAKE_BOTTOM
	if not front:
		# colonna d'acqua dietro ai lottatori, sempre piu' scura in profondita'
		var wx0: float = game.LAKE_X0
		var deep_h: float = by + 100.0 - wy
		var bands := 10
		for i in range(bands):
			var yy: float = wy + deep_h * i / bands
			var c := Color(0.12, 0.37, 0.58).lerp(Color(0.02, 0.11, 0.22), float(i) / bands)
			draw_rect(Rect2(wx0, yy, X_RIGHT - wx0, deep_h / bands + 1.0), c)
		_draw_coast(by)
	else:
		var x0: float = game.LAKE_X0
		# velo d'acqua sopra lottatori e fondale
		draw_rect(Rect2(x0, wy, X_RIGHT - x0, by + 100.0 - wy), Color(0.15, 0.45, 0.75, 0.26))
		# superficie: linea ondulata continua (niente tasselli)
		var pts := PackedVector2Array()
		var n := 48
		for i in range(n + 1):
			var sx: float = x0 + (X_RIGHT - x0) * i / n
			pts.append(Vector2(sx, wy + sin(t * 2.1 + i * 0.55) * 1.6))
		draw_polyline(pts, Color(0.92, 0.98, 1.0, 0.5), 1.6)
		# schiuma dove l'acqua tocca la riva
		var foam := 0.5 + 0.3 * sin(t * 3.0)
		draw_circle(Vector2(x0 + 3.0, wy + 1.0), 2.2, Color(1, 1, 1, foam))
		draw_circle(Vector2(x0 + 9.0, wy + 2.0), 1.4, Color(1, 1, 1, foam * 0.7))
		# luccichii che scorrono sott'acqua
		for i in range(7):
			var gx: float = x0 + fmod(i * 197.7 + t * 40.0 * (1.0 + i * 0.11), X_RIGHT - x0)
			var gy: float = wy + 14.0 + fmod(i * 83.3 + t * 16.0, by - wy - 20.0)
			if gy < game.floor_at(gx):
				draw_rect(Rect2(gx, gy, 2, 2), Color(0.8, 0.95, 1.0, 0.16 + 0.14 * sin(t * 6.0 + i)))


func _draw_coast(by: float) -> void:
	var rim := Color(0.87, 0.79, 0.60)
	var face := Color(0.42, 0.35, 0.26)
	var prev_fy: float = game.FLOOR_Y - 8.0
	for s in _slabs():
		var x0: float = s[0]
		var x1: float = s[1]
		var fy: float = s[2]
		# corpo del gradone, piu' scuro e freddo con la profondita'
		var depth: float = clampf((fy - game.FLOOR_Y) / (by - game.FLOOR_Y), 0.0, 1.0)
		var body := Color(0.70, 0.60, 0.44).lerp(Color(0.24, 0.31, 0.36), depth)
		draw_rect(Rect2(x0, fy - 8.0, x1 - x0, by + 110.0 - fy), body)
		# bordo superiore illuminato del gradone
		draw_rect(Rect2(x0, fy - 8.0, x1 - x0, 3.0), rim.lerp(body, depth * 0.55))
		# parete verticale del dislivello (lato sinistro del gradone)
		if fy - 8.0 > prev_fy:
			draw_rect(Rect2(x0 - 3.0, prev_fy, 6.0, fy - 8.0 - prev_fy + 3.0), face)
		prev_fy = fy - 8.0
		# qualche crepa orizzontale per dare consistenza rocciosa
		var seed := int(x0)
		for c in range(3):
			var cx: float = x0 + fposmod(seed * 37.7 + c * 61.3, maxf(x1 - x0 - 30.0, 8.0))
			var cy: float = fy + 14.0 + fposmod(seed * 17.3 + c * 43.9, maxf(by + 70.0 - fy - 20.0, 8.0))
			draw_rect(Rect2(cx, cy, 14.0 + 8.0 * (c % 2), 2.0), body.darkened(0.25))
