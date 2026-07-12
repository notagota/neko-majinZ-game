class_name EnergyBeam
extends Node2D

# Raggio energetico: sfera (beam_head) alle mani, corpo ondulato tegolabile
# (beam_body1), tratto fiammeggiante (beam_body2) e punta arrotondata
# (beam_tail) che avanza. L'arte punta nativamente verso +x (destra):
# scale.x = -1 quando si spara verso sinistra. La collisione sta solo sulla
# punta, alla fine di beam_tail; all'impatto esplodono scintille.

const GROW := 1500.0

var owner_f: Fighter
var dir := 1
var beam_len := 16.0
var max_len := 900.0
var t := 0.0
var end_t := 1.4
var dead := false
var hit_done := false
var alpha := 1.0
var spark_t := 0.0
var head_tex: Texture2D
var body1_tex: Texture2D
var body2_tex: Texture2D
var tail_tex: Texture2D


func setup(f: Fighter) -> void:
	owner_f = f
	dir = f.facing
	position = f.position + Vector2(f.facing * 30.0, -24.0)
	head_tex = load("res://assets/sprites/fx/beam_head.png")
	body1_tex = load("res://assets/sprites/fx/beam_body1.png")
	body2_tex = load("res://assets/sprites/fx/beam_body2.png")
	tail_tex = load("res://assets/sprites/fx/beam_tail.png")
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	scale.x = -1.0 if dir == -1 else 1.0
	if dir == 1:
		max_len = 1300.0 - position.x
	else:
		max_len = position.x + 1300.0
	max_len = min(max_len, 980.0)
	end_t = max_len / GROW + 0.75


func _tip() -> Vector2:
	return position + Vector2(dir * beam_len, 0.0)


func tick(dt: float) -> void:
	t += dt
	beam_len = min(max_len, beam_len + GROW * dt)
	if t > end_t:
		alpha -= dt / 0.28
		if alpha <= 0.0:
			dead = true
			return
	owner_f.game.shake(1.1)
	# collisione su tutta la lunghezza attiva: chi tocca il raggio (punta
	# compresa) subisce il colpo, anche se ci entra a meta' corpo
	if not hit_done and alpha > 0.9:
		var x0 := position.x if dir == 1 else position.x - beam_len
		var r := Rect2(Vector2(x0, position.y - 27.0), Vector2(beam_len, 54.0))
		var res = owner_f.game.try_hit(owner_f, r, 40.0,
			{"launch": Vector2(dir * 430.0, -140.0), "chip": 10.0, "heavy": true})
		if res != "miss":
			hit_done = true
			# il raggio si ferma sul bersaglio e preme ancora un momento
			var victim := owner_f.enemy
			if victim != null:
				var d := absf(victim.center().x - position.x)
				beam_len = clamp(d, 40.0, beam_len)
			max_len = beam_len
			end_t = min(end_t, t + 0.6)
			_impact_sparks(_tip(), res == "hit")
	# scintille continue finche' il raggio preme sul punto d'impatto
	if hit_done and alpha > 0.5:
		spark_t -= dt
		if spark_t <= 0.0:
			spark_t = 0.07
			var p := _tip() + Vector2(randf_range(-6, 6), randf_range(-20, 20))
			owner_f.game.spawn_fx("spark_0" if randi() % 2 == 0 else "spark_1", p,
				{"life": 0.2, "add": true, "grow": 2.5, "spin": randf_range(-6.0, 6.0),
				"vel": Vector2(-dir * randf_range(40.0, 130.0), randf_range(-90.0, 90.0))})
	queue_redraw()


func _impact_sparks(tip: Vector2, full_hit: bool) -> void:
	var g = owner_f.game
	g.spawn_fx("burst", tip, {"life": 0.32, "add": true, "screen": true})
	for i in range(6):
		var a := randf_range(0.0, TAU)
		g.spawn_fx("spark_0" if i % 2 == 0 else "spark_1", tip,
			{"life": 0.3, "add": true, "grow": 1.5, "spin": randf_range(-8.0, 8.0),
			"vel": Vector2(cos(a), sin(a)) * randf_range(90.0, 240.0)})
	if full_hit:
		g.shake(5.0)


func _draw() -> void:
	var m := Color(1, 1, 1, alpha * (0.85 + 0.15 * sin(t * 30.0)))
	var tip_x := beam_len
	# in successione dalla sfera alla punta: head, body1, body2, tail
	var b2_x := tip_x - 25.0 - 37.0
	if b2_x > 20.0:
		draw_texture_rect(body1_tex, Rect2(20.0, -31.0, b2_x - 20.0, 62.0), true, m)
	if b2_x > 16.0:
		draw_texture_rect(body2_tex, Rect2(b2_x, -31.0, 37.0, 62.0), false, m)
	if tip_x > 42.0:
		draw_texture_rect(tail_tex, Rect2(tip_x - 25.0, -26.0, 25.0, 52.0), false, m)
	draw_texture_rect(head_tex, Rect2(-31.0, -31.0, 62.0, 62.0), false, m)
