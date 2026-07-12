class_name Fighter
extends Node2D

# Lottatore stile Super Sonic Warriors 2: volo libero, combo, ki.
# Le pose native guardano a DESTRA: flip_h quando facing == -1 (sinistra).
# Fanno eccezione i pugni, che hanno un frame dedicato per direzione.

enum St { INTRO, MOVE, ATTACK, BLAST, BEAM_CHARGE, BEAM_FIRE, DASH, ROLL, GUARD, CHARGE, HURT, LAUNCHED, DOWN, KO, WIN, LAND }

const FLOOR_Y := 400.0
const ARENA_X := 1150.0
const CEIL_Y := -420.0
const SEP_X := 760.0
const SEP_Y := 400.0
const SPEED := 225.0

const ANIM_DEFS := {
	"idle": {"frames": ["idle_0", "idle_1"], "fps": 3.0},
	"walk": {"frames": ["walk_01", "walk_02", "walk_03", "walk_04"], "fps": 8.0},
	"fly": {"frames": ["fly_01"], "fps": 5.0},
	"fall": {"frames": ["hurt2_0"], "fps": 5.0},
	"hurt": {"frames": ["hurt2_0"], "fps": 5.0},
	"guard": {"frames": ["guard_0"], "fps": 5.0},
	"windup": {"frames": ["windup_0"], "fps": 5.0},
	"punch": {"frames": ["punch_01"], "fps": 5.0},
	"punch_l": {"frames": ["punch_02"], "fps": 5.0},
	"shove": {"frames": ["beam_08"], "fps": 5.0},
	"blast": {"frames": ["beam_08"], "fps": 5.0},
	"ball": {"frames": ["hurt2_0"], "fps": 5.0},
	"rush": {"frames": ["fly_01"], "fps": 5.0},
	"charge": {"frames": ["beam_05", "beam_06"], "fps": 8.0},
	"tumble": {"frames": ["hurt2_0"], "fps": 9.0},
	"taunt": {"frames": ["taunt_0", "taunt_1"], "fps": 3.0},
	"landing": {"frames": ["landing_01", "landing_02"], "fps": 10.0, "loop": false},
	"beamcast": {"frames": ["beam_01", "beam_02", "beam_03", "beam_04",
		"beam_05", "beam_06", "beam_07", "beam_08"], "fps": 10.7, "loop": false},
}

# catena di attacchi corpo a corpo (J J J): pugno, pugno forte, spinta a due palmi che lancia
const ATTACKS := [
	{"wind_anim": "windup", "hit_anim": "punch", "wind": 0.09, "active": 0.12, "rec": 0.12, "dmg": 7.0, "launch": false},
	{"wind_anim": "windup", "hit_anim": "punch", "wind": 0.07, "active": 0.12, "rec": 0.13, "dmg": 9.0, "launch": false},
	{"wind_anim": "windup", "hit_anim": "shove", "wind": 0.09, "active": 0.13, "rec": 0.20, "dmg": 14.0, "launch": true},
]

var game: Node2D
var enemy: Fighter
var controller
var fighter_name := ""
var palette := "z1"
var is_cpu := false

var hp := 300.0
var hp_max := 300.0
var hp_lag := 300.0
var lag_delay := 0.0
var ki := 100.0
var ki_max := 300.0
var vel := Vector2.ZERO
var facing := 1
var state: int = St.INTRO
var st := 0.0
var invuln := 0.0
var blast_cd := 0.0
var roll_cd := 0.0
var guard_stun := 0.0
var hurt_t := 0.3
var chain_n := 0
var chain_t := 0.0
var attack_stage := 0
var attack_buf := false
var stage_hit := false
var did_spawn := false
var dash_dir := Vector2.ZERO
var after_t := 0.0
var sfx_t := 0.0
var ko_rest := false
var in_water := false
var bubble_t := 0.0
var spr: AnimatedSprite2D
var aura: Sprite2D
var cur_anim := ""


func setup(g: Node2D, pal: String, disp_name: String, ctrl) -> void:
	game = g
	palette = pal
	fighter_name = disp_name
	controller = ctrl
	aura = Sprite2D.new()
	aura.texture = load("res://assets/sprites/fx/aura.png")
	aura.position = Vector2(0, -28)
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	aura.material = mat
	aura.visible = false
	add_child(aura)
	spr = AnimatedSprite2D.new()
	spr.sprite_frames = _build_frames(pal)
	spr.centered = false
	add_child(spr)
	_pivot_feet()
	play_anim("idle")


func _build_frames(pal: String) -> SpriteFrames:
	var sf := SpriteFrames.new()
	for anim_name in ANIM_DEFS:
		var def: Dictionary = ANIM_DEFS[anim_name]
		sf.add_animation(anim_name)
		sf.set_animation_speed(anim_name, def.fps)
		sf.set_animation_loop(anim_name, def.get("loop", true))
		for f in def.frames:
			sf.add_frame(anim_name, load("res://assets/sprites/%s/%s.png" % [pal, f]))
	if sf.has_animation("default"):
		sf.remove_animation("default")
	return sf


func reset(pos: Vector2, face: int) -> void:
	position = pos
	facing = face
	hp = hp_max
	hp_lag = hp_max
	ki = 100.0
	vel = Vector2.ZERO
	state = St.INTRO
	st = 0.0
	invuln = 0.0
	guard_stun = 0.0
	chain_n = 0
	blast_cd = 0.0
	roll_cd = 0.0
	ko_rest = false
	in_water = false
	bubble_t = 0.0
	spr.modulate = Color(1, 1, 1, 1)
	aura.visible = false
	cur_anim = ""
	play_anim("taunt")


# --- helper geometrici -------------------------------------------------

func center() -> Vector2:
	return position + Vector2(0, -28)


func hurt_rect() -> Rect2:
	return Rect2(position + Vector2(-16, -50), Vector2(32, 50))


func _floor() -> float:
	return game.floor_at(position.x)


func grounded() -> bool:
	return position.y >= _floor() - 0.5


func _pivot_feet() -> void:
	spr.position = Vector2.ZERO
	spr.offset = Vector2(-32, -56)


func _face_enemy() -> void:
	# non ci si puo' orientare verso un nemico immerso e non rilevabile
	if enemy != null and game.can_see(self, enemy) and abs(enemy.position.x - position.x) > 4.0:
		facing = 1 if enemy.position.x > position.x else -1


static func _empty_input() -> Dictionary:
	return {"move": Vector2.ZERO, "attack": false, "blast": false, "beam": false,
		"dash": false, "roll": false, "guard": false, "charge": false}


# --- ciclo principale ---------------------------------------------------

func tick(dt: float) -> void:
	st += dt
	invuln = max(0.0, invuln - dt)
	blast_cd -= dt
	roll_cd -= dt
	sfx_t -= dt
	chain_t -= dt
	if chain_t <= 0.0:
		chain_n = 0
	# barra HP ritardata (danno arancione che scende)
	if lag_delay > 0.0:
		lag_delay -= dt
	elif hp_lag > hp:
		hp_lag = max(hp, hp_lag - hp_max * 0.55 * dt)
	# rigenerazione ki passiva
	if state != St.KO and state != St.CHARGE:
		ki = min(ki_max, ki + 6.0 * dt)

	var inp := _empty_input()
	if controller != null and state not in [St.INTRO, St.KO, St.WIN]:
		inp = controller.poll(self, dt)

	var was_air := not grounded()
	match state:
		St.MOVE: _tick_move(dt, inp)
		St.LAND: _tick_land(dt)
		St.ATTACK: _tick_attack(dt, inp)
		St.BLAST: _tick_blast(dt)
		St.BEAM_CHARGE: _tick_beam_charge(dt)
		St.BEAM_FIRE: _tick_beam_fire(dt)
		St.DASH: _tick_dash(dt)
		St.ROLL: _tick_roll(dt)
		St.GUARD: _tick_guard(dt, inp)
		St.CHARGE: _tick_charge(dt, inp)
		St.HURT: _tick_hurt(dt)
		St.LAUNCHED: _tick_launched(dt, false)
		St.KO: _tick_launched(dt, true)
		St.DOWN: _tick_down(dt)
		_: pass

	# limiti arena (sul lago il fondale scende sotto la riva)
	position.x = clamp(position.x, -ARENA_X, ARENA_X)
	position.y = clamp(position.y, CEIL_Y, _floor())
	# distanza massima tra i lottatori (stile SSW2)
	if enemy != null and state in [St.MOVE, St.GUARD, St.CHARGE, St.ATTACK]:
		position.x = clamp(position.x, enemy.position.x - SEP_X, enemy.position.x + SEP_X)
		position.y = clamp(position.y, enemy.position.y - SEP_Y, enemy.position.y + SEP_Y)

	# atterraggio: dal volo al terreno si passa per una breve animazione dedicata
	if state == St.MOVE and was_air and grounded():
		state = St.LAND
		st = 0.0
		vel = Vector2.ZERO
		game.spawn_fx("burst", position + Vector2(0, -6), {"life": 0.2, "add": true, "scale": 0.35})
		game.sfx.play("bounce", 1.7)

	# fisica dei liquidi: schizzo attraversando la superficie, bolle da immersi
	var wet: bool = game.in_water_point(center())
	if wet != in_water:
		in_water = wet
		if state != St.INTRO:
			game.splash_at(position.x,
				vel.length() > 220.0 or state in [St.LAUNCHED, St.KO, St.DASH])
		bubble_t = 0.25
	if in_water:
		bubble_t -= dt
		if bubble_t <= 0.0:
			bubble_t = randf_range(0.35, 0.7)
			# niente bolle rivelatrici per chi e' nascosto alla vista del giocatore
			if self == game.p1 or game.can_see(game.p1, self):
				game.spawn_bubble(center() + Vector2(randf_range(-8.0, 8.0), randf_range(-14.0, 4.0)))

	_update_visual()
	queue_redraw()


# --- stati --------------------------------------------------------------

func _tick_move(dt: float, inp: Dictionary) -> void:
	_face_enemy()
	var mv: Vector2 = inp.move
	if mv.length() > 1.0:
		mv = mv.normalized()
	# in acqua ci si muove piu' lenti e da fermi si tende a galleggiare su
	vel = mv * SPEED * (0.55 if in_water else 1.0)
	if in_water and mv == Vector2.ZERO:
		vel.y = -16.0
	position += vel * dt
	if inp.attack:
		_start_attack()
	elif inp.blast and ki >= 15.0 and blast_cd <= 0.0:
		ki -= 15.0
		state = St.BLAST
		st = 0.0
		did_spawn = false
		_face_enemy()
	elif inp.beam and ki >= 200.0:
		state = St.BEAM_CHARGE
		st = 0.0
		_face_enemy()
		aura.visible = true
		game.sfx.play("charge", 0.85)
	elif inp.dash and ki >= 25.0 and enemy != null:
		ki -= 25.0
		state = St.DASH
		st = 0.0
		stage_hit = false
		after_t = 0.0
		# lo scatto punta il bersaglio solo se lo si puo' rilevare
		if game.can_see(self, enemy):
			dash_dir = (enemy.center() - center()).normalized()
		else:
			dash_dir = Vector2(facing, 0.0)
		_face_enemy()
		game.sfx.play("dash")
	elif inp.roll and roll_cd <= 0.0:
		state = St.ROLL
		st = 0.0
		stage_hit = false
		after_t = 0.0
		_face_enemy()
		if grounded():
			vel = Vector2(facing * 300.0, -180.0)
		else:
			vel = Vector2(facing * 310.0, 150.0)
		game.sfx.play("dash", 1.3)
	elif inp.guard:
		state = St.GUARD
		st = 0.0
		vel = Vector2.ZERO
	elif inp.charge and ki < ki_max - 1.0:
		state = St.CHARGE
		st = 0.0
		aura.visible = true
		game.sfx.play("charge")
		sfx_t = 0.62


func _start_attack() -> void:
	_face_enemy()
	state = St.ATTACK
	st = 0.0
	attack_stage = 0
	attack_buf = false
	stage_hit = false


func _attack_rect() -> Rect2:
	var hx := position.x + 8.0 if facing > 0 else position.x - 54.0
	return Rect2(Vector2(hx, position.y - 50.0), Vector2(46, 42))


func _tick_attack(dt: float, inp: Dictionary) -> void:
	if inp.attack:
		attack_buf = true
	var atk: Dictionary = ATTACKS[attack_stage]
	var t_wind: float = atk.wind
	var t_active: float = t_wind + atk.active
	var t_end: float = t_active + atk.rec
	if st < t_active:
		position.x += facing * 70.0 * dt
	if st >= t_wind and st < t_active and not stage_hit:
		var opts := {
			"stun": 0.34,
			"push": Vector2(facing * 130.0, -20.0),
			"heavy": atk.launch,
		}
		if atk.launch:
			opts["launch"] = Vector2(facing * 260.0, -270.0)
		var res = game.try_hit(self, _attack_rect(), atk.dmg, opts)
		if res != "miss":
			stage_hit = true
	if st >= t_active and attack_buf and attack_stage < ATTACKS.size() - 1:
		attack_stage += 1
		st = 0.0
		attack_buf = false
		stage_hit = false
		return
	if st >= t_end:
		state = St.MOVE


func _tick_blast(_dt: float) -> void:
	if st >= 0.10 and not did_spawn:
		did_spawn = true
		game.spawn_blast(self)
	if st >= 0.26:
		blast_cd = 0.30
		state = St.MOVE


func _tick_beam_charge(_dt: float) -> void:
	game.shake(0.7)
	if st >= 0.75:
		aura.visible = false
		if ki >= 200.0:
			ki -= 200.0
			state = St.BEAM_FIRE
			st = 0.0
			game.spawn_beam(self)
		else:
			state = St.MOVE


func _tick_beam_fire(_dt: float) -> void:
	if st >= 1.5:
		state = St.MOVE


func _tick_dash(dt: float) -> void:
	vel = dash_dir * 560.0
	position += vel * dt
	after_t -= dt
	if after_t <= 0.0:
		after_t = 0.045
		game.spawn_afterimage(self)
	if not stage_hit:
		var r := Rect2(center() + dash_dir * 26.0 - Vector2(20, 20), Vector2(40, 40))
		var res = game.try_hit(self, r, 8.0, {"stun": 0.34, "push": Vector2(facing * 150.0, -30.0)})
		if res != "miss":
			stage_hit = true
			vel = Vector2.ZERO
			state = St.MOVE
			return
	if st >= 0.42 or (enemy != null and center().distance_to(enemy.center()) < 46.0):
		state = St.MOVE


func _tick_roll(dt: float) -> void:
	vel.y += (190.0 if in_water else 520.0) * dt
	if in_water:
		vel = vel.move_toward(Vector2.ZERO, 260.0 * dt)
	position += vel * dt
	after_t -= dt
	if after_t <= 0.0:
		after_t = 0.06
		game.spawn_afterimage(self)
	if not stage_hit:
		var r := Rect2(center() - Vector2(22, 22), Vector2(44, 44))
		var res = game.try_hit(self, r, 12.0, {"launch": Vector2(facing * 200.0, -190.0), "heavy": true})
		if res != "miss":
			stage_hit = true
	if (st > 0.15 and grounded()) or st >= 0.6:
		roll_cd = 1.4
		state = St.MOVE


func _tick_guard(dt: float, inp: Dictionary) -> void:
	_face_enemy()
	guard_stun -= dt
	vel = vel.move_toward(Vector2.ZERO, 500.0 * dt)
	position += vel * dt
	if guard_stun <= 0.0 and not inp.guard:
		state = St.MOVE


func _tick_charge(dt: float, inp: Dictionary) -> void:
	_face_enemy()
	ki = min(ki_max, ki + 135.0 * dt)
	game.shake(0.5)
	if sfx_t <= 0.0:
		sfx_t = 0.62
		game.sfx.play("charge")
	if not inp.charge or ki >= ki_max - 0.5:
		aura.visible = false
		state = St.MOVE


func _tick_land(_dt: float) -> void:
	if st >= 0.18:
		state = St.MOVE


func _tick_hurt(dt: float) -> void:
	vel = vel.move_toward(Vector2.ZERO, 700.0 * dt)
	position += vel * dt
	if st >= hurt_t:
		state = St.MOVE


func _tick_launched(dt: float, is_ko: bool) -> void:
	if is_ko and ko_rest:
		return
	if in_water:
		# in acqua il colpo viene smorzato: si affonda verso una velocita'
		# terminale (mai in stallo a mezz'acqua) e dopo poco si riprende
		# il controllo galleggiando
		vel.x = move_toward(vel.x, 0.0, 320.0 * dt)
		vel.y = move_toward(vel.y, 130.0, 520.0 * dt)
		if not is_ko and st >= 0.55:
			invuln = 0.6
			state = St.MOVE
	else:
		vel.y += 880.0 * dt
		vel.x = move_toward(vel.x, 0.0, 60.0 * dt)
	position += vel * dt
	if position.x <= -ARENA_X + 1.0 or position.x >= ARENA_X - 1.0:
		vel.x *= -0.55
		position.x = clamp(position.x, -ARENA_X + 1.0, ARENA_X - 1.0)
	var fy := _floor()
	if position.y >= fy:
		position.y = fy
		if abs(vel.y) > 240.0:
			vel.y = -vel.y * 0.42
			vel.x *= 0.75
			game.spawn_fx("burst", position + Vector2(0, -14), {"life": 0.28, "grow": 1.0, "add": true, "scale": 0.6})
			game.sfx.play("bounce")
			game.shake(3.0)
		else:
			vel = Vector2.ZERO
			if is_ko:
				ko_rest = true
			else:
				state = St.DOWN
				st = 0.0


func _tick_down(_dt: float) -> void:
	if st >= 0.5:
		invuln = 0.7
		state = St.MOVE


# --- subire colpi -------------------------------------------------------

func take_hit(dmg: float, opts: Dictionary) -> void:
	hp = max(0.0, hp - dmg)
	lag_delay = 0.55
	ki = min(ki_max, ki + 5.0)
	chain_n += 1
	chain_t = 1.0
	aura.visible = false
	ko_rest = false
	if hp <= 0.0:
		return  # il game gestisce il KO
	var launch: Vector2 = opts.get("launch", Vector2.ZERO)
	if launch != Vector2.ZERO:
		state = St.LAUNCHED
		st = 0.0
		vel = launch
	else:
		state = St.HURT
		st = 0.0
		hurt_t = opts.get("stun", 0.32)
		vel = opts.get("push", Vector2.ZERO)


func take_block(chip: float, push: Vector2) -> void:
	hp = max(0.0, hp - chip)
	lag_delay = 0.55
	guard_stun = 0.2
	vel = push


func set_ko(launch: Vector2) -> void:
	state = St.KO
	st = 0.0
	vel = launch
	invuln = 0.0
	aura.visible = false
	ko_rest = false


# --- aspetto ------------------------------------------------------------

func play_anim(a: String) -> void:
	if a == "punch" and facing < 0:
		a = "punch_l"
	if cur_anim == a:
		return
	cur_anim = a
	spr.play(a)


func _update_visual() -> void:
	# l'avversario immerso sparisce del tutto dalla vista, a meno che anche il
	# giocatore non sia in acqua (fuori dal combattimento resta sempre visibile)
	if game.phase == "fight" and self != game.p1:
		visible = game.can_see(game.p1, self)
	else:
		visible = true
	var vis_a := 1.0
	if state == St.DOWN or (invuln > 0.0 and state == St.MOVE):
		vis_a = 0.55 + 0.3 * sin(st * 40.0)
	# sott'acqua lo sprite prende una velatura azzurra
	if in_water:
		spr.modulate = Color(0.62, 0.80, 1.0, vis_a * 0.92)
	else:
		spr.modulate = Color(1, 1, 1, vis_a)
	if aura.visible:
		aura.modulate = Color(1, 1, 1, 0.45 + 0.35 * randf())
		aura.rotation = randf_range(-0.06, 0.06)
	match state:
		St.MOVE:
			if grounded():
				play_anim("walk" if absf(vel.x) > 10.0 else "idle")
			else:
				play_anim("fly")
		St.LAND:
			play_anim("landing")
		St.ATTACK:
			var atk: Dictionary = ATTACKS[attack_stage]
			play_anim(atk.wind_anim if st < atk.wind else atk.hit_anim)
		St.BLAST:
			play_anim("blast")
		St.BEAM_CHARGE, St.BEAM_FIRE:
			play_anim("beamcast")
		St.CHARGE:
			play_anim("charge")
		St.DASH:
			play_anim("rush")
		St.ROLL:
			play_anim("ball")
		St.GUARD:
			play_anim("guard")
		St.HURT:
			play_anim("hurt")
		St.LAUNCHED:
			play_anim("tumble")
		St.KO:
			play_anim("fall" if ko_rest else "tumble")
		St.DOWN:
			play_anim("fall")
		St.WIN, St.INTRO:
			play_anim("taunt")
	# arte nativa verso destra: si specchia guardando a sinistra, tranne i
	# pugni che sono gia' disegnati nella direzione giusta
	spr.flip_h = facing < 0 and cur_anim != "punch" and cur_anim != "punch_l"


func _draw() -> void:
	# ombra a terra (sul lago cade sul fondale)
	var height: float = game.floor_at(position.x) - position.y
	var a: float = clamp(0.4 - height / 1000.0, 0.08, 0.4)
	var s: float = clamp(1.0 - height / 900.0, 0.45, 1.0)
	draw_set_transform(Vector2(0, height + 2.0), 0.0, Vector2(1.0, 0.3))
	draw_circle(Vector2.ZERO, 15.0 * s, Color(0.12, 0.06, 0.03, a))
