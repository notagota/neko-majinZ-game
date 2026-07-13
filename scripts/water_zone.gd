class_name WaterZone
extends Node2D

# Lago della mappa "lake", disegnato in due strati:
#  - front=false (dietro ai lottatori): la costa rocciosa che scende a gradoni
#    dolci verso destra, con il fondale visibile sotto il pelo dell'acqua
#  - front=true (davanti ai lottatori): velo d'acqua traslucido con superficie
#    ondulata (linea continua) e luccichii, cosi' chi si immerge appare
#    "dentro" l'acqua.

const X_RIGHT := 1330.0
const GROUND_TEX := preload("res://assets/bg/bg2_ground.png")
const BLEND_W := 56.0   # larghezza del raccordo sfumato tra un gradone e l'altro

var game: Node2D
var front := false
var t := 0.0


func _ready() -> void:
	if front:
		z_index = 40
	# serve per tegolare GROUND_TEX oltre il bordo destro (UV > 1)
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


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
		_draw_bottom(by)
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


# Arredo del fondale (sassi, alghe che ondeggiano, sabbia increspata) posato
# su gradoni e fondo piatto: ora che la camera segue i lottatori in
# profondita', il fondo del lago deve leggersi chiaramente come "pavimento".
# Posizioni deterministiche (MAI randf qui: il disegno non influenza il
# gameplay ma deve restare identico frame dopo frame).
func _draw_bottom(by: float) -> void:
	var x0: float = game.LAKE_X0
	var fl: float = game.FLOOR_Y
	# sassi sparsi, piu' freddi e scuri man mano che si scende
	for i in range(16):
		var gx: float = x0 + 30.0 + fmod(i * 197.3 + 61.0, X_RIGHT - x0 - 60.0)
		var gy: float = game.floor_at(gx)
		if gy <= fl + 4.0:
			continue  # solo sott'acqua
		var depth: float = clampf((gy - fl) / (by - fl), 0.0, 1.0)
		var rs: float = 5.0 + fmod(i * 37.7, 9.0)
		var rc := Color(0.52, 0.47, 0.40).lerp(Color(0.16, 0.22, 0.30), depth)
		draw_circle(Vector2(gx, gy - rs * 0.35), rs, rc)
		draw_circle(Vector2(gx - rs * 0.3, gy - rs * 0.55), rs * 0.55, rc.lightened(0.12))
	# alghe: nastri ancorati al fondo che ondeggiano con la corrente
	for i in range(9):
		var ax: float = x0 + 70.0 + fmod(i * 271.9 + 23.0, X_RIGHT - x0 - 120.0)
		var ay: float = game.floor_at(ax)
		if ay <= fl + 4.0:
			continue
		var depth: float = clampf((ay - fl) / (by - fl), 0.0, 1.0)
		var h: float = 26.0 + fmod(i * 53.1, 26.0)
		var col := Color(0.16, 0.55, 0.34).lerp(Color(0.05, 0.25, 0.20), depth)
		var pts := PackedVector2Array()
		for k in range(6):
			var sway: float = sin(t * 1.6 + i * 1.7 + k * 0.7) * (1.0 + 2.2 * k / 5.0)
			pts.append(Vector2(ax + sway, ay - h * k / 5.0))
		draw_polyline(pts, col, 2.2)
	# increspature di sabbia sul fondo piatto piu' profondo
	var deep_x0: float = x0 + game.STEP_W * 3.0
	for i in range(10):
		var sx: float = deep_x0 + 40.0 + i * (X_RIGHT - deep_x0 - 80.0) / 9.0
		var sw2: float = 14.0 + fmod(i * 31.7, 12.0)
		draw_line(Vector2(sx - sw2, by - 2.0), Vector2(sx + sw2, by - 2.0),
			Color(0.30, 0.36, 0.44, 0.7), 1.5)


func _draw_coast(by: float) -> void:
	# Ogni gradone e' rivestito con bg2_ground.png (bordo roccioso in cima,
	# sabbia sotto) ancorata alla propria sommita', come i tile della riva.
	# Per non dare stacchi tra una texture e l'altra, la texture di ogni
	# gradone "sborda" sul successivo dissolvendosi (quad con alpha sfumato).
	var fl: float = game.FLOOR_Y
	var bot: float = by + 110.0
	var slabs := _slabs()
	var tints: Array = []
	var anchors: Array = []
	for i in range(slabs.size()):
		# tinta: sabbia piena in superficie, sempre piu' fredda e scura in fondo
		var depth: float = clampf((slabs[i][2] - fl) / (by - fl), 0.0, 1.0)
		tints.append(Color(1, 1, 1).lerp(Color(0.38, 0.50, 0.62), depth))
		# il primo lembo e' ancorato al reticolo dei tile della riva (x = -512)
		# cosi' la texture prosegue senza cucitura dal terreno di sinistra
		anchors.append(Vector2(-512.0 if i == 0 else slabs[i][0], slabs[i][2] - 8.0))
	for i in range(slabs.size()):
		var x0: float = anchors[i].x if i == 0 else slabs[i][0]
		_tex_quad(Rect2(x0, anchors[i].y, slabs[i][1] - x0, bot - anchors[i].y),
			anchors[i], tints[i], 1.0, 1.0)
		# raccordo: il gradone precedente si prolunga su questo e sfuma via,
		# coprendo anche la parete del dislivello con una discesa morbida
		if i > 0:
			_tex_quad(Rect2(slabs[i][0], anchors[i - 1].y, BLEND_W, bot - anchors[i - 1].y),
				anchors[i - 1], tints[i - 1], 1.0, 0.0)


# quad texturizzato con UV nel reticolo di `anchor` e alpha che scorre
# da sinistra (a_left) a destra (a_right): il mattone delle sfumature
func _tex_quad(r: Rect2, anchor: Vector2, tint: Color, a_left: float, a_right: float) -> void:
	var tw := float(GROUND_TEX.get_width())
	var th := float(GROUND_TEX.get_height())
	var pts := PackedVector2Array([r.position, Vector2(r.end.x, r.position.y),
		r.end, Vector2(r.position.x, r.end.y)])
	var uvs := PackedVector2Array()
	for p in pts:
		uvs.append(Vector2((p.x - anchor.x) / tw, (p.y - anchor.y) / th))
	var cl := Color(tint.r, tint.g, tint.b, tint.a * a_left)
	var cr := Color(tint.r, tint.g, tint.b, tint.a * a_right)
	draw_polygon(pts, PackedColorArray([cl, cr, cr, cl]), uvs, GROUND_TEX)
