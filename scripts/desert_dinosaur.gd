class_name DesertDinosaur
extends Node2D

# Creatura ambientale della Fase 2 del deserto. Vive nello sfondo ma puo'
# colpire i Fighter e, durante il proprio attacco, essere scacciata da loro.

enum State { ENTERING, ROAMING, ATTACKING, RESENTMENT }

const VISUAL_SCALE := 1.75
const BACKGROUND_Y := 365.0
const ENTER_SPEED := 105.0
const ROAM_SPEED := 62.0
const ESCAPE_SPEED := 265.0
const ATTACK_INTERVAL := 2.0
const ATTACK_IMPACT_TIME := 0.30
const ATTACK_DURATION := 0.62
const RESENTMENT_DURATION := 1.25
const ROAM_MIN_X := -285.0
const ROAM_MAX_X := 265.0
const OFFSCREEN_X := 540.0

var game: Node2D
var sprite: AnimatedSprite2D
var state: State = State.ENTERING
var state_time := 0.0
var attack_timer := ATTACK_INTERVAL
var roam_target_x := 0.0
var attack_target: CharacterBody2D
var warned_position := Vector2.ZERO
var strike_done := false
var escape_dir := 1.0
var dead := false
var rng := RandomNumberGenerator.new()


func setup(owner_game: Node2D) -> void:
	game = owner_game
	name = "DesertDinosaur"
	z_index = -5  # davanti alle mesas, dietro a Fighter, colpi ed effetti
	position = Vector2(OFFSCREEN_X, BACKGROUND_Y)
	scale = Vector2.ONE * VISUAL_SCALE
	# Seed identico sui due peer: percorso e bersagli restano sincronizzati.
	rng.seed = 0xD10A5000 + int(game.round_num) * 97
	sprite = AnimatedSprite2D.new()
	sprite.name = "DinosaurSprite"
	sprite.sprite_frames = _build_frames()
	sprite.centered = false
	sprite.offset = Vector2(-32.0, -65.0)
	add_child(sprite)
	roam_target_x = rng.randf_range(40.0, 190.0)
	sprite.play("movement")
	print("[dinosaur] entra nello sfondo della Fase 2")


func _build_frames() -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	_add_animation(frames, "movement", 0, 6, 8.0, true)
	_add_animation(frames, "attack", 7, 9, 9.0, false)
	_add_animation(frames, "resentment", 14, 20, 9.0, true)
	_add_animation(frames, "flee", 27, 30, 8.0, true)
	return frames


func _add_animation(frames: SpriteFrames, animation: String, first: int,
		last: int, fps: float, looped: bool) -> void:
	frames.add_animation(animation)
	frames.set_animation_speed(animation, fps)
	frames.set_animation_loop(animation, looped)
	for index in range(first, last + 1):
		frames.add_frame(animation,
			load("res://assets/sprites/dinosaur/dinosaur_%02d.png" % index))


func tick(dt: float) -> void:
	if dead:
		return
	state_time += dt
	match state:
		State.ENTERING:
			_tick_entering(dt)
		State.ROAMING:
			_tick_roaming(dt)
		State.ATTACKING:
			_tick_attacking()
		State.RESENTMENT:
			_tick_resentment(dt)


func _tick_entering(dt: float) -> void:
	position.x = move_toward(position.x, roam_target_x, ENTER_SPEED * dt)
	if is_equal_approx(position.x, roam_target_x):
		state = State.ROAMING
		state_time = 0.0
		attack_timer = ATTACK_INTERVAL
		_choose_roam_target()
		sprite.play("flee")


func _tick_roaming(dt: float) -> void:
	attack_timer -= dt
	var direction := signf(roam_target_x - position.x)
	if direction == 0.0:
		_choose_roam_target()
		direction = signf(roam_target_x - position.x)
	sprite.flip_h = direction > 0.0  # i frame 27-30 guardano nativamente a sinistra
	position.x = move_toward(position.x, roam_target_x, ROAM_SPEED * dt)
	if absf(position.x - roam_target_x) < 1.0:
		_choose_roam_target()
	if attack_timer <= 0.0:
		_start_attack()


func _choose_roam_target() -> void:
	var next := rng.randf_range(ROAM_MIN_X, ROAM_MAX_X)
	if absf(next - position.x) < 90.0:
		next = ROAM_MIN_X if position.x > 0.0 else ROAM_MAX_X
	roam_target_x = next


func _start_attack() -> void:
	state = State.ATTACKING
	state_time = 0.0
	strike_done = false
	attack_target = _choose_attack_target()
	if attack_target == null:
		_finish_attack()
		return
	warned_position = attack_target.center()
	sprite.flip_h = attack_target.position.x > position.x
	sprite.play("attack")
	# Il punto resta fisso: allontanarsi dall'icona e' il modo per schivare.
	game.spawn_fx("alert", warned_position + Vector2(0.0, -38.0),
		{"life": ATTACK_IMPACT_TIME + 0.18, "scale": 0.58})
	game.sfx.play("charge", 0.55, -7.0)
	print("[dinosaur] attacco telegrafato contro %s" % attack_target.fighter_name)


func _choose_attack_target() -> CharacterBody2D:
	var candidates: Array = []
	for fighter in [game.p1, game.p2]:
		if fighter != null and fighter.state not in [fighter.St.KO, fighter.St.DOWN]:
			candidates.append(fighter)
	if candidates.is_empty():
		return null
	return candidates[rng.randi_range(0, candidates.size() - 1)]


func _tick_attacking() -> void:
	if not strike_done and state_time >= ATTACK_IMPACT_TIME:
		strike_done = true
		if game.online:
			# L'host decide l'esito sullo stato autorevole e lo replica in modo
			# affidabile; evita che una predizione remota produca due risultati.
			if multiplayer.get_unique_id() == NetworkManager.HOST_ID:
				var slot := 1 if attack_target == game.p1 else 2
				game.net_dinosaur_strike.rpc(slot, warned_position, position)
		else:
			game.dinosaur_strike(attack_target, warned_position, position)
	if state_time >= ATTACK_DURATION:
		_finish_attack()


func _finish_attack() -> void:
	state = State.ROAMING
	state_time = 0.0
	attack_timer = ATTACK_INTERVAL
	attack_target = null
	_choose_roam_target()
	sprite.play("flee")


# Rettangolo della creatura gia' scalato in coordinate mondo. E' consultato
# da game.try_hit per melee, sfere, scatti e raggi.
func hurt_rect() -> Rect2:
	return Rect2(position + Vector2(-29.0, -62.0) * VISUAL_SCALE,
		Vector2(58.0, 62.0) * VISUAL_SCALE)


func is_attacking() -> bool:
	return state == State.ATTACKING


# Qualunque colpo basta a scacciarla, ma solo mentre ATTACKING. Negli altri
# stati gli attacchi attraversano lo sfondo senza interagire.
func hit_by(hitbox: Rect2, _damage: float, attacker_x: float) -> bool:
	if state != State.ATTACKING or not hitbox.intersects(hurt_rect()):
		return false
	if game.online and multiplayer.get_unique_id() != NetworkManager.HOST_ID:
		return true  # feedback predittivo; l'host replichera' la fuga reale
	_begin_resentment(attacker_x)
	if game.online:
		_net_begin_resentment.rpc(escape_dir)
	return true


func _begin_resentment(attacker_x: float) -> void:
	state = State.RESENTMENT
	state_time = 0.0
	attack_target = null
	escape_dir = signf(position.x - attacker_x)
	if escape_dir == 0.0:
		escape_dir = -1.0 if rng.randf() < 0.5 else 1.0
	sprite.flip_h = escape_dir > 0.0
	sprite.play("resentment")
	game.spawn_fx("burst", position + Vector2(0.0, -55.0),
		{"life": 0.34, "add": true, "grow": 0.8, "scale": 0.65})
	game.spawn_fx("alert", position + Vector2(0.0, -120.0),
		{"life": 0.5, "scale": 0.62})
	game.sfx.play("kick", 0.62)
	game.shake(3.0)
	print("[dinosaur] colpito durante l'attacco: fugge risentito")


@rpc("authority", "call_remote", "reliable")
func _net_begin_resentment(direction: float) -> void:
	if dead:
		return
	# Un punto virtuale dal lato opposto produce esattamente la direzione
	# stabilita dall'host senza dipendere dalla predizione locale.
	_begin_resentment(position.x - direction)


func _tick_resentment(dt: float) -> void:
	position.x += escape_dir * ESCAPE_SPEED * dt
	if state_time >= RESENTMENT_DURATION or absf(position.x) > OFFSCREEN_X + 80.0:
		dead = true
		print("[dinosaur] ha abbandonato lo stage")
