class_name GameHUD
extends Control

# HUD disegnata a mano: barre HP/ki, ritratti, timer, pallini round,
# contatore combo, messaggi centrali e schermata di pausa.

const HINT1 := "WASD/frecce: vola e cammina   J: combo   K: sfera ki   L: raggio (2 tacche di ki)"
const HINT2 := "I: scatto   U: palla   SPAZIO: parata   H: carica ki   tieni J sotto combo: FUGA   ESC: menu"

var game: Node2D
var port1: Texture2D
var port2: Texture2D
var logo: Texture2D
var font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	port1 = load("res://assets/sprites/ui/portrait1.png")
	port2 = load("res://assets/sprites/ui/portrait2.png")
	logo = load("res://assets/sprites/ui/logo.png")
	font = ThemeDB.fallback_font


func _process(_dt: float) -> void:
	queue_redraw()


func _text(s: String, pos: Vector2, size: int, col: Color, align := "l") -> void:
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var p := pos
	if align == "c":
		p.x -= w / 2.0
	elif align == "r":
		p.x -= w
	draw_string_outline(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, 3, Color(0, 0, 0, col.a * 0.9))
	draw_string(font, p, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)


func _draw_side(f, right: bool) -> void:
	if right:
		draw_set_transform(Vector2(480, 0), 0.0, Vector2(-1, 1))
	# ritratto
	var ptex := port2 if right else port1
	var pw := 56.0
	var ph := ptex.get_height() * (pw / ptex.get_width())
	draw_rect(Rect2(3, 3, pw + 2, ph + 2), Color(0, 0, 0, 0.85))
	draw_texture_rect(ptex, Rect2(Vector2(4, 4), Vector2(pw, ph)), false)
	# barra HP
	var bx := 66.0
	var bw := 158.0
	var by := 8.0
	var bh := 9.0
	draw_rect(Rect2(bx - 1, by - 1, bw + 2, bh + 2), Color(0, 0, 0, 0.85))
	draw_rect(Rect2(bx, by, bw, bh), Color(0.25, 0.05, 0.05))
	var fr: float = clamp(f.hp / f.hp_max, 0.0, 1.0)
	var lr: float = clamp(f.hp_lag / f.hp_max, 0.0, 1.0)
	draw_rect(Rect2(bx, by, bw * lr, bh), Color(0.95, 0.45, 0.1))
	var hp_col := Color(0.35, 0.9, 0.25) if fr > 0.3 else Color(0.95, 0.8, 0.15)
	draw_rect(Rect2(bx, by, bw * fr, bh), hp_col)
	# barra ki
	var ky := by + bh + 3.0
	draw_rect(Rect2(bx - 1, ky - 1, bw + 2, 7), Color(0, 0, 0, 0.85))
	draw_rect(Rect2(bx, ky, bw, 5), Color(0.05, 0.1, 0.25))
	var kr: float = clamp(f.ki / f.ki_max, 0.0, 1.0)
	var ki_col := Color(0.25, 0.8, 1.0) if f.ki < 200.0 else Color(1.0, 0.9, 0.3)
	draw_rect(Rect2(bx, ky, bw * kr, 5), ki_col)
	for i in [1, 2]:
		draw_rect(Rect2(bx + bw * i / 3.0, ky, 1, 5), Color(0, 0, 0, 0.7))
	if right:
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# nome (non specchiato)
	if right:
		_text(f.fighter_name, Vector2(414, 40), 8, Color(1, 1, 1), "r")
	else:
		_text(f.fighter_name, Vector2(66, 40), 8, Color(1, 1, 1), "l")


func _draw_menu() -> void:
	draw_rect(Rect2(0, 0, 480, 270), Color(0.02, 0.03, 0.1, 0.45))
	# logo stile Dragon Ball, pulsante, con i ritratti ai lati
	var sc := 1.0 + 0.04 * sin(game.phase_t * 2.4)
	var lw := 216.0
	var lh := lw * logo.get_height() / logo.get_width()
	draw_set_transform(Vector2(240, 62), 0.0, Vector2(sc, sc))
	draw_texture_rect(logo, Rect2(Vector2(-lw / 2.0, -lh / 2.0), Vector2(lw, lh)), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	_text("SUPERSONIC CLASH", Vector2(240, 116), 13, Color(0.55, 0.85, 1.0), "c")
	var pw := 52.0
	var ph1 := port1.get_height() * (pw / port1.get_width())
	draw_texture_rect(port1, Rect2(Vector2(26, 62 - ph1 / 2), Vector2(pw, ph1)), false)
	draw_set_transform(Vector2(480, 0), 0.0, Vector2(-1, 1))
	var ph2 := port2.get_height() * (pw / port2.get_width())
	draw_texture_rect(port2, Rect2(Vector2(26, 62 - ph2 / 2), Vector2(pw, ph2)), false)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# voci del menu (l'ultima e' il volume, regolabile con A/D)
	var vol_label := "VOLUME: MUTO" if game.volume <= 0.01 else "VOLUME %d%%" % int(game.volume * 100.0 + 0.5)
	var opts := ["COMBATTIMENTO 1v1", "ALLENAMENTO", "ONLINE 1v1", vol_label]
	for i in range(4):
		var y := 142.0 + i * 22.0
		var sel: bool = game.menu_sel == i
		var col := Color(1, 0.82, 0.15) if sel else Color(1, 1, 1, 0.9)
		if sel:
			draw_rect(Rect2(240 - 98, y - 14, 196, 20), Color(0, 0, 0, 0.55))
			_text(">", Vector2(240 - 90 + 3.0 * sin(game.phase_t * 7.0), y), 12, col, "l")
			_text("<", Vector2(240 + 90 - 3.0 * sin(game.phase_t * 7.0), y), 12, col, "r")
		_text(opts[i], Vector2(240, y), 12, col, "c")
		if i == 3:
			# barretta del volume sotto la voce
			var bw := 90.0
			draw_rect(Rect2(240 - bw / 2.0, y + 5.0, bw, 4.0), Color(0, 0, 0, 0.6))
			draw_rect(Rect2(240 - bw / 2.0, y + 5.0, bw * game.volume, 4.0),
				Color(1, 0.82, 0.15) if sel else Color(0.6, 0.75, 0.9))
	# avvisi (es. "AVVERSARIO DISCONNESSO" tornando da una partita online)
	if game.msg != "":
		_text(game.msg, Vector2(240, 232), 8, Color(1, 0.45, 0.3), "c")
	_text("W/S: scegli    A/D: regola    INVIO o J: conferma", Vector2(240, 244), 8, Color(1, 1, 1, 0.85), "c")
	_text("in gioco: ESC menu   1 pausa   2/3 volume", Vector2(240, 253), 7, Color(1, 1, 1, 0.55), "c")


func _draw_mapsel() -> void:
	draw_rect(Rect2(0, 0, 480, 270), Color(0.02, 0.03, 0.1, 0.45))
	_text("SCEGLI LA MAPPA", Vector2(240, 48), 20, Color(1, 0.85, 0.2), "c")
	var names := ["DESERTO ROCCIOSO", "LAGO DELLA COSTA"]
	var descs := [
		"l'arena classica tra le mesas",
		"un lago profondo: chi si immerge non puo' essere rilevato!",
	]
	for i in range(2):
		var cx := 128.0 + i * 224.0
		var sel: bool = game.map_sel == i
		var r := Rect2(cx - 78, 78, 156, 82)
		# cornice (dorata se selezionata)
		draw_rect(Rect2(r.position - Vector2(3, 3), r.size + Vector2(6, 6)),
			Color(1, 0.82, 0.15) if sel else Color(0, 0, 0, 0.6))
		if i == 0:
			# anteprima deserto: cielo, mesas, sabbia
			draw_rect(r, Color(0.42, 0.6, 0.83))
			draw_rect(Rect2(r.position.x, r.position.y + 52, r.size.x, 30), Color(0.79, 0.6, 0.42))
			draw_rect(Rect2(r.position.x + 20, r.position.y + 22, 28, 32), Color(0.66, 0.45, 0.3))
			draw_rect(Rect2(r.position.x + 108, r.position.y + 30, 22, 24), Color(0.62, 0.42, 0.28))
			draw_circle(r.position + Vector2(128, 14), 8, Color(0.99, 0.96, 0.84))
		else:
			# anteprima lago: cielo, sole, riva e specchio d'acqua profondo
			draw_rect(r, Color(0.16, 0.3, 0.85))
			draw_circle(r.position + Vector2(30, 15), 8, Color(0.99, 0.97, 0.86))
			draw_rect(Rect2(r.position.x, r.position.y + 52, r.size.x, 30), Color(0.84, 0.77, 0.57))
			draw_rect(Rect2(r.position.x + 39, r.position.y + 52, 78, 30), Color(0.13, 0.42, 0.72))
			draw_rect(Rect2(r.position.x + 39, r.position.y + 52, 78, 3), Color(0.75, 0.92, 1.0))
		if sel:
			var wob := 3.0 * sin(game.phase_t * 7.0)
			_text(">", Vector2(cx - 88 + wob, 124), 14, Color(1, 0.82, 0.15), "r")
			_text("<", Vector2(cx + 88 - wob, 124), 14, Color(1, 0.82, 0.15), "l")
		_text(names[i], Vector2(cx, 178), 10, Color(1, 0.82, 0.15) if sel else Color(1, 1, 1), "c")
	_text(descs[game.map_sel], Vector2(240, 204), 8, Color(1, 1, 1, 0.9), "c")
	_text("A/D o frecce: scegli    INVIO o J: conferma    ESC: indietro", Vector2(240, 236), 8, Color(1, 1, 1, 0.7), "c")


func _draw() -> void:
	if game == null or game.p1 == null:
		return
	if game.phase == "menu":
		_draw_menu()
		return
	if game.phase == "mapsel":
		_draw_mapsel()
		return
	var p1 = game.p1
	var p2 = game.p2
	_draw_side(p1, false)
	_draw_side(p2, true)
	if game.mode == "training":
		_text("ALLENAMENTO", Vector2(240, 22), 10, Color(1, 1, 1, 0.8), "c")
	else:
		# timer
		_text("%02d" % int(ceil(game.round_time)), Vector2(240, 26), 20, Color(1, 1, 1), "c")
		# pallini round vinti
		for i in range(2):
			var c1 := Color(1, 0.75, 0.1) if game.wins[0] > i else Color(0, 0, 0, 0.45)
			var c2 := Color(1, 0.75, 0.1) if game.wins[1] > i else Color(0, 0, 0, 0.45)
			draw_circle(Vector2(72 + i * 12, 48), 4, c1)
			draw_circle(Vector2(480 - 72 - i * 12, 48), 4, c2)
	# contatori combo
	if p2.chain_n >= 2:
		_text("COMBO x%d" % p2.chain_n, Vector2(70, 64), 12, Color(1, 0.6, 0.1), "l")
	if p1.chain_n >= 2:
		_text("COMBO x%d" % p1.chain_n, Vector2(410, 64), 12, Color(1, 0.3, 0.2), "r")
	# messaggio centrale
	if game.msg != "":
		var sc := 1.0 + 0.9 * exp(-game.msg_t * 9.0)
		draw_set_transform(Vector2(240, 120), 0.0, Vector2(sc, sc))
		_text(game.msg, Vector2(0, 8), 30, Color(1, 0.85, 0.2), "c")
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		if game.msg_sub != "":
			_text(game.msg_sub, Vector2(240, 152), 10, Color(1, 1, 1), "c")
	# suggerimenti comandi
	if game.hint_a > 0.01:
		_text(HINT1, Vector2(240, 248), 7, Color(1, 1, 1, game.hint_a), "c")
		_text(HINT2, Vector2(240, 258), 7, Color(1, 1, 1, game.hint_a), "c")
	# pausa
	if game.paused:
		draw_rect(Rect2(0, 0, 480, 270), Color(0, 0, 0, 0.55))
		_text("PAUSA", Vector2(240, 130), 24, Color(1, 1, 1), "c")
		_text("1 per riprendere - R per riavviare - ESC per il menu - 2/3 volume", Vector2(240, 155), 10, Color(1, 1, 1), "c")
