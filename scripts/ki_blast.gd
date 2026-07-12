class_name KiBlast
extends Sprite2D

# Sfera di energia: viaggia verso il bersaglio con una leggera ricerca iniziale.

var owner_f: Fighter
var vel := Vector2.ZERO
var t := 0.0
var dead := false
var trail_t := 0.0
var wet := false


func setup(f: Fighter) -> void:
	owner_f = f
	texture = load("res://assets/sprites/fx/beam_head.png")
	scale = Vector2(0.26, 0.26)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	# parte dai palmi della posa beam_08 (~23 px sopra i piedi)
	position = f.position + Vector2(f.facing * 28.0, -23.0)
	wet = f.game.in_water_point(position)
	var target := position + Vector2(f.facing * 100.0, 0.0)
	if f.enemy != null and f.game.can_see(f, f.enemy):
		target = f.enemy.center()
	vel = (target - position).normalized() * 430.0


func tick(dt: float) -> void:
	t += dt
	# leggera ricerca del bersaglio nei primi istanti (solo se rilevabile)
	if t < 0.35 and owner_f.enemy != null and owner_f.game.can_see(owner_f, owner_f.enemy):
		var des := (owner_f.enemy.center() - position).normalized() * 430.0
		vel = vel.rotated(clamp(vel.angle_to(des), -2.4 * dt, 2.4 * dt))
	position += vel * dt
	# l'energia si spegne sfrigolando quando attraversa la superficie dell'acqua
	var w2: bool = owner_f.game.in_water_point(position)
	if w2 != wet:
		owner_f.game.splash_at(position.x, false)
		dead = true
		return
	rotation += 6.0 * dt
	trail_t -= dt
	if trail_t <= 0.0:
		trail_t = 0.035
		owner_f.game.spawn_fx_tex(texture, position,
			{"life": 0.18, "scale": scale.x * 0.85, "add": true, "mod": modulate * Color(1, 1, 1, 0.4)})
	if t >= 2.2 or abs(position.x) > 1350.0 or position.y > 500.0 or position.y < -650.0:
		dead = true
		return
	var r := Rect2(position - Vector2(9, 9), Vector2(18, 18))
	var res = owner_f.game.try_hit(owner_f, r, 6.0,
		{"stun": 0.24, "push": Vector2(owner_f.facing * 70.0, -10.0)})
	if res != "miss":
		dead = true
