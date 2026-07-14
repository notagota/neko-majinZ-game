class_name DesertPerspective
extends Node2D

# Regia della transizione "falso 3D" del deserto.
# Non esiste alcun asse Z: due composizioni Node2D, una Camera2D e uno sprite
# cinematografico 2D costruiscono l'illusione del lancio in profondita'.

const FXScript := preload("res://scripts/one_shot_fx.gd")
const DinosaurScript := preload("res://scripts/desert_dinosaur.gd")

enum StagePhase { FRONT, HIT_HOLD, THROW_TO_MESA, TURNING, SIDE }

const FRONT_HALF_WIDTH := 1150.0
const SIDE_HALF_WIDTH := 420.0
const SIDE_ATTACKER_POS := Vector2(-330.0, 400.0)
const SIDE_VICTIM_POS := Vector2(330.0, 400.0)
const HIT_HOLD_TIME := 0.18
const THROW_TIME := 0.78
const IMPACT_HOLD_TIME := 0.24
const TURN_OUT_TIME := 0.34
const TURN_IN_TIME := 0.58
const FAR_SCALE := 0.30
const MALUS_TIME := 3.0
const OFFENSIVE_INPUTS := ["attack", "blast", "beam", "dash", "roll", "charge", "attack_held"]

var game: Node2D
var stage_phase: StagePhase = StagePhase.FRONT
var transition_active := false
var phase_1_root: Node2D
var phase_2_root: Node2D
var impact_mesa: Sprite2D
var right_wall_mesa: Sprite2D
var boundary_root: Node2D
var transition_tween: Tween
var trail_tween: Tween
var cinematic_body: Node2D
var cinematic_sprite: Sprite2D
var cinematic_victim: CharacterBody2D
var impact_target := Vector2.ZERO
var confused_fighter: CharacterBody2D
var confused_time := 0.0
var dinosaur_spawn_pending := false
var desert_dinosaur: Node2D


func setup(owner_game: Node2D) -> void:
	game = owner_game


# Le due versioni grafiche convivono nello stesso livello. La seconda rimane
# nascosta finche' la prima non viene "chiusa" come una pagina 2D.
func build_desert(stage_parent: Node2D) -> void:
	clear_stage()
	phase_1_root = Node2D.new()
	phase_1_root.name = "DesertPhase1Front"
	phase_1_root.z_index = -10
	stage_parent.add_child(phase_1_root)
	_add_mesa(phase_1_root, "Mesa0Foreground", "res://assets/bg/mesa_0.png",
		Vector2(-760.0, 400.0), 1.05)
	_add_mesa(phase_1_root, "Mesa0Middle", "res://assets/bg/mesa_0.png",
		Vector2(-90.0, 400.0), 0.62)
	impact_mesa = _add_mesa(phase_1_root, "Mesa1ImpactFar",
		"res://assets/bg/mesa_1.png", Vector2(520.0, 315.0), 0.34)

	phase_2_root = Node2D.new()
	phase_2_root.name = "DesertPhase2Side"
	phase_2_root.z_index = -10
	phase_2_root.visible = false
	stage_parent.add_child(phase_2_root)
	_add_mesa(phase_2_root, "Mesa0NewBackground", "res://assets/bg/mesa_0.png",
		Vector2(-330.0, 400.0), 0.48)
	right_wall_mesa = _add_mesa(phase_2_root, "Mesa1RightWall",
		"res://assets/bg/mesa_1.png", Vector2(SIDE_HALF_WIDTH - 72.0, 400.0), 1.38)
	_build_boundaries(stage_parent)
	reset_stage()


func clear_stage() -> void:
	_kill_tweens()
	_dispose_cinematic()
	transition_active = false
	confused_fighter = null
	confused_time = 0.0
	dinosaur_spawn_pending = false
	desert_dinosaur = null
	phase_1_root = null
	phase_2_root = null
	impact_mesa = null
	right_wall_mesa = null
	boundary_root = null


func _kill_tweens() -> void:
	if transition_tween != null and transition_tween.is_valid():
		transition_tween.kill()
	if trail_tween != null and trail_tween.is_valid():
		trail_tween.kill()
	transition_tween = null
	trail_tween = null


func _add_mesa(parent: Node2D, node_name: String, path: String,
		feet_position: Vector2, visual_scale: float) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.name = node_name
	sprite.texture = load(path)
	sprite.centered = false
	sprite.scale = Vector2.ONE * visual_scale
	sprite.position = feet_position - Vector2(0.0, sprite.texture.get_height() * visual_scale)
	parent.add_child(sprite)
	return sprite


# StaticBody2D e clamp dei Fighter condividono la stessa semilarghezza: il
# passaggio di fase non puo' lasciare pareti invisibili nella vecchia posizione.
func _build_boundaries(stage_parent: Node2D) -> void:
	boundary_root = Node2D.new()
	boundary_root.name = "DesertStageBounds"
	stage_parent.add_child(boundary_root)
	_make_boundary("LeftWall", Vector2.ZERO, Vector2(40.0, 1040.0))
	_make_boundary("RightWall", Vector2.ZERO, Vector2(40.0, 1040.0))
	_make_boundary("Floor", Vector2.ZERO, Vector2(FRONT_HALF_WIDTH * 2.0 + 80.0, 80.0))
	_apply_boundary_layout(FRONT_HALF_WIDTH)


func _make_boundary(node_name: String, pos: Vector2, size: Vector2) -> StaticBody2D:
	var body := StaticBody2D.new()
	body.name = node_name
	body.position = pos
	body.collision_layer = 2
	body.collision_mask = 1
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = size
	collision.shape = rectangle
	body.add_child(collision)
	boundary_root.add_child(body)
	return body


func _apply_boundary_layout(half_width: float) -> void:
	if boundary_root == null or not is_instance_valid(boundary_root):
		return
	var left := boundary_root.get_node("LeftWall") as StaticBody2D
	var right := boundary_root.get_node("RightWall") as StaticBody2D
	var floor_body := boundary_root.get_node("Floor") as StaticBody2D
	left.position = Vector2(-half_width - 20.0, -80.0)
	right.position = Vector2(half_width + 20.0, -80.0)
	floor_body.position = Vector2(0.0, game.FLOOR_Y + 40.0)
	var floor_shape := floor_body.get_child(0).shape as RectangleShape2D
	floor_shape.size = Vector2(half_width * 2.0 + 80.0, 80.0)


func reset_stage() -> void:
	_kill_tweens()
	_dispose_cinematic()
	transition_active = false
	stage_phase = StagePhase.FRONT
	confused_fighter = null
	confused_time = 0.0
	dinosaur_spawn_pending = false
	desert_dinosaur = null
	if phase_1_root != null and is_instance_valid(phase_1_root):
		phase_1_root.visible = true
		phase_1_root.position = Vector2.ZERO
		phase_1_root.rotation = 0.0
		phase_1_root.scale = Vector2.ONE
		phase_1_root.modulate = Color.WHITE
	if phase_2_root != null and is_instance_valid(phase_2_root):
		phase_2_root.visible = false
		phase_2_root.position = Vector2.ZERO
		phase_2_root.rotation = 0.0
		phase_2_root.scale = Vector2.ONE
		phase_2_root.modulate = Color.WHITE
	_apply_boundary_layout(FRONT_HALF_WIDTH)
	if game != null and game.cam != null:
		game.cam.rotation = 0.0
		game.cam.offset = Vector2.ZERO
	for fighter in [game.p1, game.p2] if game != null else []:
		if fighter != null:
			fighter.scale = Vector2.ONE
			fighter.visible = true


func arena_half_width() -> float:
	return SIDE_HALF_WIDTH if stage_phase == StagePhase.SIDE else FRONT_HALF_WIDTH


func tick(delta: float) -> void:
	if transition_active and game.cam != null:
		game.shake_amp = move_toward(game.shake_amp, 0.0, 18.0 * delta)
		game.cam.offset = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * game.shake_amp
	if not transition_active and confused_time > 0.0:
		confused_time = maxf(0.0, confused_time - delta)
		if confused_time <= 0.0:
			confused_fighter = null
	# Compare non appena la vittima termina la breve posa HURT. Da quel
	# momento viene tickato insieme agli altri actor dal GameManager.
	if dinosaur_spawn_pending and stage_phase == StagePhase.SIDE \
			and confused_fighter != null and confused_fighter.state != confused_fighter.St.HURT:
		_spawn_dinosaur()


func _spawn_dinosaur() -> void:
	dinosaur_spawn_pending = false
	if desert_dinosaur != null and is_instance_valid(desert_dinosaur) and not desert_dinosaur.dead:
		return
	desert_dinosaur = DinosaurScript.new()
	desert_dinosaur.setup(game)
	game.actor_root.add_child(desert_dinosaur)
	game.actors.append(desert_dinosaur)


func hit_dinosaur(hitbox: Rect2, damage: float, attacker: CharacterBody2D) -> bool:
	if desert_dinosaur == null or not is_instance_valid(desert_dinosaur) \
			or desert_dinosaur.dead:
		return false
	return desert_dinosaur.hit_by(hitbox, damage, attacker.position.x)


# Fase 1: piano strettamente orizzontale. Fase 2: torna il volo libero W/S.
# Durante il malus entrambi gli assi sono invertiti e ogni azione offensiva
# viene cancellata prima di entrare nella macchina a stati del Fighter.
func filter_input(fighter: CharacterBody2D, input_state: Dictionary) -> Dictionary:
	if game.map != "desert":
		return input_state
	var filtered := input_state.duplicate()
	var movement: Vector2 = filtered.get("move", Vector2.ZERO)

	if fighter == confused_fighter and confused_time > 0.0:
		movement = -movement
		for action in OFFENSIVE_INPUTS:
			filtered[action] = false
	filtered["move"] = movement
	return filtered


# L'attivazione e' simmetrica: Player, CPU e secondo giocatore online possono
# essere sia attaccante sia vittima. La palette della vittima sceglie lo sprite.
func can_start(attacker: CharacterBody2D, victim: CharacterBody2D) -> bool:
	return game != null and game.map == "desert" and game.phase == "fight" \
		and stage_phase == StagePhase.FRONT and not transition_active \
		and attacker != null and victim != null and attacker != victim \
		and victim.hp > 0.0 and impact_mesa != null


func start_transition(attacker: CharacterBody2D, victim: CharacterBody2D) -> bool:
	if not can_start(attacker, victim):
		return false
	transition_active = true
	stage_phase = StagePhase.HIT_HOLD
	confused_fighter = null
	confused_time = 0.0
	attacker.vel = Vector2.ZERO
	victim.vel = Vector2.ZERO
	victim.state = victim.St.HURT
	victim.st = 0.0
	victim.aura.visible = false
	_create_cinematic(victim)
	impact_target = impact_mesa.global_position + Vector2(
		impact_mesa.texture.get_width() * impact_mesa.scale.x * 0.5,
		impact_mesa.texture.get_height() * impact_mesa.scale.y * 0.78)

	var launch_dir := signf(victim.position.x - attacker.position.x)
	if launch_dir == 0.0:
		launch_dir = float(attacker.facing)
	game.spawn_fx("burst", cinematic_body.position + Vector2(0.0, -28.0),
		{"life": 0.28, "add": true, "screen": true})
	game.sfx.play("kick", 0.72)
	game.shake(5.0)
	transition_tween = create_tween()
	transition_tween.set_parallel(true)
	transition_tween.tween_property(cinematic_body, "position",
		cinematic_body.position + Vector2(launch_dir * 34.0, 10.0), HIT_HOLD_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	transition_tween.tween_property(cinematic_body, "scale", Vector2(1.22, 0.86), HIT_HOLD_TIME)
	transition_tween.tween_property(cinematic_body, "rotation", launch_dir * 0.16, HIT_HOLD_TIME)
	transition_tween.tween_property(game.cam, "position", victim.center(), HIT_HOLD_TIME)
	transition_tween.tween_property(game.cam, "zoom", Vector2.ONE * 1.18, HIT_HOLD_TIME)
	transition_tween.finished.connect(_begin_throw.bind(attacker, victim, launch_dir))
	print("[desert-perspective] %s lanciato verso mesa_1 (sprite %s/hurt2_0)"
		% [victim.fighter_name, victim.palette])
	return true


func _create_cinematic(victim: CharacterBody2D) -> void:
	_dispose_cinematic()
	cinematic_victim = victim
	cinematic_body = Node2D.new()
	cinematic_body.name = "CinematicHurtBody"
	cinematic_body.position = victim.position
	cinematic_body.z_index = 35
	add_child(cinematic_body)
	cinematic_sprite = Sprite2D.new()
	cinematic_sprite.name = "Hurt2Sprite"
	cinematic_sprite.texture = load("res://assets/sprites/%s/hurt2_0.png" % victim.palette)
	cinematic_sprite.centered = false
	cinematic_sprite.offset = Vector2(-32.0, -56.0)
	cinematic_sprite.flip_h = victim.facing < 0
	cinematic_body.add_child(cinematic_sprite)
	victim.visible = false


func _dispose_cinematic() -> void:
	if cinematic_victim != null and is_instance_valid(cinematic_victim):
		cinematic_victim.visible = true
	if cinematic_body != null and is_instance_valid(cinematic_body):
		cinematic_body.queue_free()
	cinematic_body = null
	cinematic_sprite = null
	cinematic_victim = null


func _begin_throw(attacker: CharacterBody2D, victim: CharacterBody2D, launch_dir: float) -> void:
	if not transition_active or cinematic_body == null:
		return
	stage_phase = StagePhase.THROW_TO_MESA
	game.spawn_fx("lines", cinematic_body.position, {"life": 0.72, "add": true, "screen": true})
	game.sfx.play("dash", 0.62)
	_schedule_throw_echoes()
	transition_tween = create_tween()
	transition_tween.set_parallel(true)
	transition_tween.tween_property(cinematic_body, "position", impact_target, THROW_TIME) \
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	transition_tween.tween_property(cinematic_body, "scale", Vector2.ONE * FAR_SCALE, THROW_TIME) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	transition_tween.tween_property(cinematic_body, "rotation", launch_dir * TAU * 1.25, THROW_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	transition_tween.tween_property(game.cam, "position", impact_target + Vector2(-24.0, -8.0), THROW_TIME) \
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN_OUT)
	transition_tween.tween_property(game.cam, "zoom", Vector2.ONE * 1.58, THROW_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	transition_tween.finished.connect(_on_mesa_impact.bind(attacker, victim))


func _schedule_throw_echoes() -> void:
	trail_tween = create_tween()
	for alpha in [0.42, 0.34, 0.26, 0.18]:
		trail_tween.tween_interval(THROW_TIME / 5.0)
		trail_tween.tween_callback(_spawn_cinematic_echo.bind(alpha))


func _spawn_cinematic_echo(alpha: float) -> void:
	if cinematic_body == null or cinematic_sprite == null:
		return
	var echo := FXScript.new()
	echo.texture = cinematic_sprite.texture
	echo.centered = false
	echo.offset = Vector2(-32.0, -56.0)
	echo.flip_h = cinematic_sprite.flip_h
	echo.position = cinematic_body.position
	echo.scale = cinematic_body.scale
	echo.rotation = cinematic_body.rotation
	echo.modulate = Color(1.0, 0.72, 0.35, alpha)
	echo.start_a = alpha
	echo.life = 0.34
	game.actor_root.add_child(echo)
	game.actors.append(echo)


func _on_mesa_impact(attacker: CharacterBody2D, victim: CharacterBody2D) -> void:
	if not transition_active or cinematic_body == null:
		return
	cinematic_body.position = impact_target
	cinematic_body.rotation = 0.0
	game.spawn_fx("burst", impact_target, {"life": 0.48, "add": true, "screen": true})
	game.spawn_fx("alert", impact_target + Vector2(0.0, -28.0), {"life": 0.42, "scale": 0.48})
	for i in range(8):
		game.spawn_fx("spark_0" if i % 2 == 0 else "spark_1",
			impact_target + Vector2(randf_range(-12.0, 12.0), randf_range(-22.0, 12.0)),
			{"life": 0.45, "add": true, "grow": 1.4,
			 "vel": Vector2(randf_range(-150.0, 150.0), randf_range(-170.0, 80.0))})
	game.sfx.play("bounce", 0.68)
	game.shake(9.0)
	print("[desert-perspective] impatto su mesa_1 -> zoom ravvicinato")
	transition_tween = create_tween()
	transition_tween.set_parallel(true)
	transition_tween.tween_property(cinematic_body, "scale", Vector2.ONE * 0.38, IMPACT_HOLD_TIME) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)
	transition_tween.tween_property(game.cam, "position", impact_target + Vector2(0.0, -12.0), IMPACT_HOLD_TIME)
	transition_tween.tween_property(game.cam, "zoom", Vector2.ONE * 1.82, IMPACT_HOLD_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	transition_tween.finished.connect(_turn_out_phase_one.bind(attacker, victim))


func _turn_out_phase_one(attacker: CharacterBody2D, victim: CharacterBody2D) -> void:
	stage_phase = StagePhase.TURNING
	phase_2_root.visible = true
	phase_2_root.scale = Vector2(0.04, 1.12)
	phase_2_root.rotation = 0.16
	phase_2_root.modulate = Color(1.0, 1.0, 1.0, 0.12)
	game.cam.rotation = -0.12
	transition_tween = create_tween()
	transition_tween.set_parallel(true)
	transition_tween.tween_property(phase_1_root, "scale", Vector2(0.03, 1.10), TURN_OUT_TIME) \
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	transition_tween.tween_property(phase_1_root, "rotation", -0.18, TURN_OUT_TIME)
	transition_tween.tween_property(phase_1_root, "modulate", Color(1.0, 1.0, 1.0, 0.08), TURN_OUT_TIME)
	transition_tween.tween_property(game.cam, "zoom", Vector2.ONE * 1.94, TURN_OUT_TIME)
	transition_tween.tween_property(game.cam, "rotation", 0.10, TURN_OUT_TIME)
	transition_tween.finished.connect(_turn_in_phase_two.bind(attacker, victim))


func _turn_in_phase_two(attacker: CharacterBody2D, victim: CharacterBody2D) -> void:
	phase_1_root.visible = false
	transition_tween = create_tween()
	transition_tween.set_parallel(true)
	transition_tween.tween_property(phase_2_root, "scale", Vector2.ONE, TURN_IN_TIME) \
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_OUT)
	transition_tween.tween_property(phase_2_root, "rotation", 0.0, TURN_IN_TIME)
	transition_tween.tween_property(phase_2_root, "modulate", Color.WHITE, TURN_IN_TIME)
	transition_tween.tween_property(game.cam, "position", Vector2(0.0, 250.0), TURN_IN_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	transition_tween.tween_property(game.cam, "zoom", Vector2.ONE * 0.62, TURN_IN_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	transition_tween.tween_property(game.cam, "rotation", 0.0, TURN_IN_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	transition_tween.tween_property(attacker, "position", SIDE_ATTACKER_POS, TURN_IN_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	transition_tween.tween_property(cinematic_body, "position", SIDE_VICTIM_POS, TURN_IN_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	transition_tween.tween_property(cinematic_body, "scale", Vector2.ONE, TURN_IN_TIME) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	transition_tween.tween_property(cinematic_body, "rotation", 0.0, TURN_IN_TIME)
	transition_tween.finished.connect(_finish_transition.bind(attacker, victim))


func _finish_transition(attacker: CharacterBody2D, victim: CharacterBody2D) -> void:
	stage_phase = StagePhase.SIDE
	_apply_boundary_layout(SIDE_HALF_WIDTH)
	attacker.position = SIDE_ATTACKER_POS
	victim.position = SIDE_VICTIM_POS
	attacker.scale = Vector2.ONE
	victim.scale = Vector2.ONE
	attacker.facing = 1
	victim.facing = -1
	attacker.vel = Vector2.ZERO
	victim.vel = Vector2.ZERO
	attacker.state = attacker.St.MOVE
	victim.state = victim.St.HURT
	victim.hurt_t = 0.65
	attacker.st = 0.0
	victim.st = 0.0
	_dispose_cinematic()
	confused_fighter = victim
	dinosaur_spawn_pending = true
	# Tre secondi pieni di malus DOPO la posa di recupero.
	confused_time = MALUS_TIME + victim.hurt_t
	transition_active = false
	transition_tween = null
	game.freeze_t = 0.0
	game.cam.rotation = 0.0
	game.cam.offset = Vector2.ZERO
	var who: String = "TU" if victim == game.local_fighter() else String(victim.fighter_name)
	game._set_msg("PROSPETTIVA LATERALE",
		"%s: COMANDI INVERTITI E ATTACCHI BLOCCATI" % who, 3.0)
	print("[desert-perspective] Fase 2; vittima=%s, limiti=+/-%.0f, malus=%.1fs"
		% [victim.fighter_name, SIDE_HALF_WIDTH, MALUS_TIME])
