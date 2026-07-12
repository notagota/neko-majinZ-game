extends Node2D

# Direttore di gioco: costruisce arena, lottatori, camera e HUD; gestisce
# round, colpi, hitstop, slow motion e tutti gli effetti dinamici.

const FighterScript := preload("res://scripts/fighter.gd")
const HumanC := preload("res://scripts/human_controller.gd")
const AIC := preload("res://scripts/ai_controller.gd")
const DummyC := preload("res://scripts/dummy_controller.gd")
const KiBlastScript := preload("res://scripts/ki_blast.gd")
const BeamScript := preload("res://scripts/energy_beam.gd")
const FXScript := preload("res://scripts/one_shot_fx.gd")
const HUDScript := preload("res://scripts/hud.gd")
const SfxScript := preload("res://scripts/sfx_bank.gd")
const WaterScript := preload("res://scripts/water_zone.gd")

const FLOOR_Y := 400.0
# mappa "lake": la costa rocciosa a sinistra scende a gradoni dolci nel lago,
# che occupa tutto il lato destro dell'arena (fondale visibile sott'acqua)
const LAKE_X0 := -80.0      # da qui il terreno scende sotto il pelo dell'acqua
const STEP_W := 150.0       # larghezza di ogni gradone
const STEP_H := 60.0        # dislivello tra i gradoni
const WATER_Y := 402.0      # pelo dell'acqua
const LAKE_BOTTOM := 640.0  # fondale piatto piu' profondo

var p1: Fighter
var p2: Fighter
var cam: Camera2D
var hud
var sfx
var actors: Array = []
var actor_root: Node2D
var map := "desert"
var map_sel := 0
var world_root: Node2D
var sky_layer: CanvasLayer
var water_front: Node2D
var lay_clouds: Node2D
var lay_mount: Node2D
var lay_mesa: Node2D

var phase := "intro1"
var phase_t := 0.0
var mode := "versus"
var menu_sel := 0
var music: AudioStreamPlayer
var volume := 1.0
var round_num := 1
var round_time := 99.0
var round_winner := -1
var wins := [0, 0]
var msg := ""
var msg_t := 0.0
var msg_life := 1.2
var msg_sub := ""
var hint_a := 1.0
var paused := false
var freeze_t := 0.0
var slow := 1.0
var slow_target := 1.0
var shake_amp := 0.0
var shot_path := ""
var shot_t := -1.0
var dbg_beamtest := false
var dbg_fastko := false
var dbg_divetest := false
var dbg_hidetest := false


func _ready() -> void:
	randomize()
	_setup_input()
	_build_world("desert")
	_build_fighters()
	cam = Camera2D.new()
	cam.position = Vector2(0, 250)
	cam.zoom = Vector2(0.9, 0.9)
	add_child(cam)
	cam.make_current()
	sfx = SfxScript.new()
	add_child(sfx)
	# musichetta del menu (loop impostato a runtime sul WAV importato)
	var ms = load("res://assets/music/menu.wav")
	if ms is AudioStreamWAV:
		ms.loop_mode = AudioStreamWAV.LOOP_FORWARD
		ms.loop_begin = 0
		ms.loop_end = ms.data.size() / 2
	music = AudioStreamPlayer.new()
	music.stream = ms
	music.volume_db = -8.0
	add_child(music)
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	hud = HUDScript.new()
	hud.game = self
	layer.add_child(hud)
	# argomenti di debug: --demo (IA vs IA), --shot=percorso (screenshot e chiudi)
	var skip_menu := false
	var dbg_mapsel := false
	for a in OS.get_cmdline_user_args():
		if a == "--demo":
			p1.controller = AIC.new()
			skip_menu = true
		elif a == "--beamtest":
			dbg_beamtest = true
			skip_menu = true
		elif a == "--fastko":
			dbg_fastko = true
			skip_menu = true
		elif a == "--training":
			mode = "training"
			skip_menu = true
		elif a == "--lake":
			_build_world("lake")
			skip_menu = true
		elif a == "--divetest":
			dbg_divetest = true
			skip_menu = true
		elif a == "--hidetest":
			dbg_hidetest = true
			skip_menu = true
		elif a == "--mapsel":
			dbg_mapsel = true
		elif a.begins_with("--shot="):
			shot_path = a.substr(7)
			if shot_t < 0.0:
				shot_t = 3.0
		elif a.begins_with("--shotdelay="):
			shot_t = float(a.substr(12))
	if skip_menu:
		_start_match()
	else:
		_enter_menu()
		if dbg_mapsel:
			phase = "mapsel"


func _setup_input() -> void:
	var keys := {
		"p_left": [KEY_A, KEY_LEFT],
		"p_right": [KEY_D, KEY_RIGHT],
		"p_up": [KEY_W, KEY_UP],
		"p_down": [KEY_S, KEY_DOWN],
		"p_attack": [KEY_J],
		"p_blast": [KEY_K],
		"p_beam": [KEY_L],
		"p_dash": [KEY_I],
		"p_roll": [KEY_U],
		"p_guard": [KEY_SPACE],
		"p_charge": [KEY_H],
		"p_pause": [KEY_1],
		"p_restart": [KEY_R],
		"p_accept": [KEY_ENTER],
		"p_menu": [KEY_ESCAPE],
		"p_voldown": [KEY_2],
		"p_volup": [KEY_3],
	}
	for action in keys:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
		for k in keys[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			InputMap.action_add_event(action, ev)
	var joy := {
		"p_attack": JOY_BUTTON_A, "p_roll": JOY_BUTTON_B, "p_blast": JOY_BUTTON_X,
		"p_beam": JOY_BUTTON_Y, "p_guard": JOY_BUTTON_LEFT_SHOULDER,
		"p_dash": JOY_BUTTON_RIGHT_SHOULDER, "p_pause": JOY_BUTTON_START,
		"p_accept": JOY_BUTTON_START, "p_menu": JOY_BUTTON_BACK,
	}
	for action in joy:
		var ev := InputEventJoypadButton.new()
		ev.button_index = joy[action]
		InputMap.action_add_event(action, ev)
	var axes := {
		"p_left": [JOY_AXIS_LEFT_X, -1.0], "p_right": [JOY_AXIS_LEFT_X, 1.0],
		"p_up": [JOY_AXIS_LEFT_Y, -1.0], "p_down": [JOY_AXIS_LEFT_Y, 1.0],
	}
	for action in axes:
		var ev := InputEventJoypadMotion.new()
		ev.axis = axes[action][0]
		ev.axis_value = axes[action][1]
		InputMap.action_add_event(action, ev)
	var dpad := {
		"p_left": JOY_BUTTON_DPAD_LEFT, "p_right": JOY_BUTTON_DPAD_RIGHT,
		"p_up": JOY_BUTTON_DPAD_UP, "p_down": JOY_BUTTON_DPAD_DOWN,
	}
	for action in dpad:
		var ev := InputEventJoypadButton.new()
		ev.button_index = dpad[action]
		InputMap.action_add_event(action, ev)
	var trig := InputEventJoypadMotion.new()
	trig.axis = JOY_AXIS_TRIGGER_RIGHT
	trig.axis_value = 1.0
	InputMap.action_add_event("p_charge", trig)


func _build_world(m: String) -> void:
	map = m
	if world_root != null:
		world_root.queue_free()
	if sky_layer != null:
		sky_layer.queue_free()
	if water_front != null:
		water_front.queue_free()
		water_front = null
	lay_clouds = null
	lay_mount = null
	lay_mesa = null
	world_root = Node2D.new()
	add_child(world_root)
	move_child(world_root, 0)  # sempre dietro a lottatori ed effetti
	# cielo fisso a schermo
	sky_layer = CanvasLayer.new()
	sky_layer.layer = -5
	add_child(sky_layer)
	var sky := TextureRect.new()
	sky.texture = load("res://assets/bg/sky.png" if m == "desert" else "res://assets/bg/bg2_sky.png")
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	sky_layer.add_child(sky)
	# nuvole (su entrambe le mappe)
	lay_clouds = Node2D.new()
	world_root.add_child(lay_clouds)
	var ct: Texture2D = load("res://assets/bg/clouds.png")
	for i in range(3):
		var s := Sprite2D.new()
		s.texture = ct
		s.centered = false
		s.position = Vector2(-1700 + i * 1280, -240)
		lay_clouds.add_child(s)
	if m == "desert":
		# montagne lontane
		lay_mount = Node2D.new()
		world_root.add_child(lay_mount)
		var mt: Texture2D = load("res://assets/bg/mountains.png")
		for i in range(3):
			var s := Sprite2D.new()
			s.texture = mt
			s.centered = false
			s.position = Vector2(-1850 + i * 1280, FLOOR_Y - 148)
			lay_mount.add_child(s)
		# mesas di media distanza
		lay_mesa = Node2D.new()
		world_root.add_child(lay_mesa)
		var mesa_xs := [-1120, -680, -330, 340, 760, 1210]
		for i in range(mesa_xs.size()):
			var s := Sprite2D.new()
			s.texture = load("res://assets/bg/mesa_%d.png" % (i % 2))
			s.centered = false
			s.scale = Vector2(0.9, 0.9)
			s.position = Vector2(mesa_xs[i], FLOOR_Y + 4 - s.texture.get_height() * 0.9)
			lay_mesa.add_child(s)
	# terreno: sul lago i tile coprono solo la riva alta a sinistra,
	# i gradoni e il fondale li disegna la WaterZone
	var gt: Texture2D = load("res://assets/bg/ground.png" if m == "desert" else "res://assets/bg/bg2_ground.png")
	var gr := Node2D.new()
	world_root.add_child(gr)
	for i in range(-8, 9):
		if m == "lake" and (i + 1) * 256.0 > -256.0:
			continue
		var s := Sprite2D.new()
		s.texture = gt
		s.centered = false
		s.position = Vector2(i * 256, FLOOR_Y - 8.0)
		gr.add_child(s)
	if m == "lake":
		# fossa d'acqua: strato dietro (pareti e profondita') e velo davanti
		var pit: Node2D = WaterScript.new()
		pit.game = self
		pit.front = false
		world_root.add_child(pit)
		water_front = WaterScript.new()
		water_front.game = self
		water_front.front = true
		add_child(water_front)


# --- acqua e visibilita' ------------------------------------------------------

func floor_at(x: float) -> float:
	if map != "lake" or x < LAKE_X0:
		return FLOOR_Y
	var i := int(floor((x - LAKE_X0) / STEP_W))
	return minf(FLOOR_Y + (i + 1) * STEP_H, LAKE_BOTTOM)


func in_water_point(p: Vector2) -> bool:
	return map == "lake" and p.x > LAKE_X0 and p.y > WATER_Y


func submerged(f: Fighter) -> bool:
	return in_water_point(f.center())


# chi e' sott'acqua non puo' essere rilevato da chi sta fuori
func can_see(viewer: Fighter, target: Fighter) -> bool:
	return not submerged(target) or submerged(viewer)


func splash_at(x: float, big: bool) -> void:
	if map != "lake":
		return
	var p := Vector2(x, WATER_Y - 4.0)
	spawn_fx("burst", p, {"life": 0.28, "add": true, "grow": 1.4 if big else 0.8,
		"scale": 0.55 if big else 0.32, "mod": Color(0.65, 0.85, 1.0)})
	for i in range(4 if big else 2):
		spawn_fx("spark_1", p, {"life": 0.35, "add": true, "mod": Color(0.7, 0.9, 1.0),
			"vel": Vector2(randf_range(-70.0, 70.0), randf_range(-160.0, -60.0)), "grow": 0.5})
	sfx.play("splash", 0.95 if big else 1.25, -4.0)
	if big:
		shake(2.0)


func spawn_bubble(pos: Vector2) -> void:
	spawn_fx("beam_head", pos, {"life": 0.7, "scale": 0.07, "add": true, "grow": 0.05,
		"vel": Vector2(randf_range(-8.0, 8.0), -46.0), "mod": Color(0.75, 0.95, 1.0, 0.7)})


func _build_fighters() -> void:
	p1 = FighterScript.new()
	p1.setup(self, "z1", "NEKO MAJIN Z", HumanC.new())
	add_child(p1)
	p2 = FighterScript.new()
	p2.setup(self, "z2", "NEKO MAJIN (CPU)", AIC.new())
	p2.is_cpu = true
	add_child(p2)
	p1.enemy = p2
	p2.enemy = p1
	actor_root = Node2D.new()
	add_child(actor_root)


# --- menu -------------------------------------------------------------------

func _apply_volume() -> void:
	AudioServer.set_bus_mute(0, volume <= 0.01)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(volume, 0.01)))


func _change_volume(d: float) -> void:
	volume = clampf(snappedf(volume + d, 0.1), 0.0, 1.0)
	_apply_volume()
	sfx.play("select")
	if phase != "menu" and phase != "mapsel":
		_set_msg("VOLUME: MUTO" if volume <= 0.01 else "VOLUME %d%%" % int(volume * 100.0 + 0.5), "", 0.7)


func _enter_menu() -> void:
	phase = "menu"
	phase_t = 0.0
	paused = false
	msg = ""
	msg_sub = ""
	menu_sel = 0
	round_num = 1
	wins = [0, 0]
	round_time = 99.0
	slow = 1.0
	slow_target = 1.0
	freeze_t = 0.0
	_clear_actors()
	# i lottatori esultano sull'arena come sfondo del menu
	if map == "desert":
		p1.reset(Vector2(-130, FLOOR_Y), 1)
		p2.reset(Vector2(130, FLOOR_Y), -1)
	else:
		p1.reset(Vector2(-400, FLOOR_Y), 1)
		p2.reset(Vector2(-160, FLOOR_Y), -1)
	if music != null and not music.playing:
		music.play()


func _tick_menu() -> void:
	if Input.is_action_just_pressed("p_up"):
		menu_sel = (menu_sel + 2) % 3
		sfx.play("select")
	if Input.is_action_just_pressed("p_down"):
		menu_sel = (menu_sel + 1) % 3
		sfx.play("select")
	# sulla voce VOLUME sinistra/destra regolano il livello
	if menu_sel == 2:
		if Input.is_action_just_pressed("p_left"):
			_change_volume(-0.1)
		if Input.is_action_just_pressed("p_right"):
			_change_volume(0.1)
	if Input.is_action_just_pressed("p_accept") or Input.is_action_just_pressed("p_attack"):
		if menu_sel == 2:
			# INVIO sul volume: muta / ripristina
			volume = 1.0 if volume <= 0.01 else 0.0
			_apply_volume()
			sfx.play("select")
			return
		mode = "versus" if menu_sel == 0 else "training"
		map_sel = 0 if map == "desert" else 1
		phase = "mapsel"
		phase_t = 0.0
		sfx.play("select", 1.2)


func _tick_mapsel() -> void:
	if Input.is_action_just_pressed("p_left") or Input.is_action_just_pressed("p_right"):
		map_sel = 1 - map_sel
		sfx.play("select")
	if Input.is_action_just_pressed("p_menu"):
		phase = "menu"
		phase_t = 0.0
		sfx.play("select", 0.8)
		return
	if Input.is_action_just_pressed("p_accept") or Input.is_action_just_pressed("p_attack"):
		var m := "desert" if map_sel == 0 else "lake"
		if m != map:
			_build_world(m)
		music.stop()
		sfx.play("round")
		_start_match()


# --- gestione round -------------------------------------------------------

func _set_msg(m: String, sub := "", life := 1.2) -> void:
	msg = m
	msg_sub = sub
	msg_t = 0.0
	msg_life = life


func _start_match() -> void:
	wins = [0, 0]
	round_num = 1
	p2.controller = DummyC.new() if mode == "training" else AIC.new()
	_start_round()


func _start_round() -> void:
	round_time = 99.0
	_clear_actors()
	if map == "desert":
		p1.reset(Vector2(-130, FLOOR_Y), 1)
		p2.reset(Vector2(130, FLOOR_Y), -1)
	else:
		# sul lago: P1 sulla riva alta, CPU in volo sopra l'acqua
		p1.reset(Vector2(-400, FLOOR_Y), 1)
		p2.reset(Vector2(340, FLOOR_Y - 40.0), -1)
	if dbg_fastko:
		p2.hp = 20.0
		p2.hp_lag = 20.0
		p1.ki = 300.0
	slow = 1.0
	slow_target = 1.0
	freeze_t = 0.0
	round_winner = -1
	phase = "intro1"
	phase_t = 0.0
	if mode == "training":
		_set_msg("ALLENAMENTO", "colpisci a volonta'  -  ESC: torna al menu", 1.8)
	else:
		_set_msg("ROUND %d" % round_num, "", 1.3)
	sfx.play("round")


func _clear_actors() -> void:
	for a in actors:
		a.queue_free()
	actors = []


func _time_up() -> void:
	phase = "timeup"
	phase_t = 0.0
	if abs(p1.hp - p2.hp) < 0.5:
		round_winner = -1
	else:
		round_winner = 0 if p1.hp > p2.hp else 1
	_set_msg("TEMPO SCADUTO", "", 1.8)
	sfx.play("ko")


func on_ko(victim: Fighter) -> void:
	if phase != "fight":
		return
	phase = "ko"
	phase_t = 0.0
	round_winner = 0 if victim == p2 else 1
	victim.set_ko(Vector2(-victim.facing * 380.0, -300.0))
	freeze_t = 0.25
	slow = 0.35
	slow_target = 0.35
	_set_msg("K.O.", "", 2.4)
	sfx.play("ko")
	shake(6.0)


func _end_round() -> void:
	phase = "round_end"
	phase_t = 0.0
	slow_target = 1.0
	if round_winner >= 0:
		if mode != "training":
			wins[round_winner] += 1
		var w := p1 if round_winner == 0 else p2
		if w.state != Fighter.St.KO:
			w.state = Fighter.St.WIN
			w.st = 0.0
	else:
		_set_msg("PAREGGIO", "", 1.5)


func _match_over() -> void:
	phase = "match_end"
	phase_t = 0.0
	var player_won: bool = wins[0] >= 2
	_set_msg("HAI VINTO!" if player_won else "VITTORIA DELLA CPU",
		"INVIO: rivincita   R: riavvia   ESC: menu", 9999.0)
	sfx.play("round", 0.8)


func _tick_phase(dt: float) -> void:
	match phase:
		"intro1":
			if phase_t >= 1.2:
				phase = "intro2"
				phase_t = 0.0
				_set_msg("FIGHT!", "", 0.9)
				sfx.play("round", 1.3)
		"intro2":
			if phase_t >= 0.15 and p1.state == Fighter.St.INTRO:
				p1.state = Fighter.St.MOVE
				p1.st = 0.0
				p2.state = Fighter.St.MOVE
				p2.st = 0.0
			if phase_t >= 0.8:
				phase = "fight"
				phase_t = 0.0
		"fight":
			if mode == "training":
				# HP e ki si rigenerano poco dopo l'ultimo scambio
				for f in [p1, p2]:
					if f.state == Fighter.St.MOVE and f.st > 1.2:
						f.hp = min(f.hp_max, f.hp + 80.0 * dt)
						f.hp_lag = max(f.hp_lag, f.hp)
						f.ki = min(f.ki_max, f.ki + 40.0 * dt)
			else:
				round_time -= dt
			if dbg_beamtest and phase_t >= 0.4 and p1.state == Fighter.St.MOVE:
				dbg_beamtest = false
				p1.ki = 300.0
				p1.state = Fighter.St.BEAM_CHARGE
				p1.st = 0.0
				p1.aura.visible = true
				sfx.play("charge", 0.85)
			if dbg_divetest and phase_t >= 0.4 and p1.state == Fighter.St.MOVE:
				dbg_divetest = false
				p1.position = Vector2(500, 560)  # immerso nel lago
			if dbg_hidetest and phase_t >= 0.4 and p2.state == Fighter.St.MOVE:
				dbg_hidetest = false
				p2.position = Vector2(500, 560)  # CPU immersa: deve sparire
			if round_time <= 0.0:
				round_time = 0.0
				_time_up()
		"ko":
			if phase_t > 0.9:
				slow_target = 1.0
			if phase_t >= 2.6:
				_end_round()
		"timeup":
			if phase_t >= 1.8:
				_end_round()
		"round_end":
			if phase_t >= 2.2:
				if mode == "training":
					_start_round()
				else:
					round_num += 1
					if wins[0] >= 2 or wins[1] >= 2:
						_match_over()
					else:
						_start_round()
		_:
			pass


# --- ciclo principale ------------------------------------------------------

func _physics_process(delta: float) -> void:
	if Input.is_action_just_pressed("p_voldown"):
		_change_volume(-0.1)
	if Input.is_action_just_pressed("p_volup"):
		_change_volume(0.1)
	if phase == "menu" or phase == "mapsel":
		if phase == "menu":
			_tick_menu()
		else:
			_tick_mapsel()
		if phase == "menu" or phase == "mapsel":  # ancora nei menu
			phase_t += delta
			_tick_shot(delta)
			_tick_camera(delta)
			return
	if Input.is_action_just_pressed("p_menu"):
		paused = false
		_enter_menu()
		return
	if Input.is_action_just_pressed("p_pause"):
		paused = not paused
		sfx.play("select")
	if Input.is_action_just_pressed("p_restart"):
		paused = false
		_start_match()
		return
	if phase == "match_end" and Input.is_action_just_pressed("p_accept"):
		_start_match()
		return
	if paused:
		return
	_tick_shot(delta)
	slow = move_toward(slow, slow_target, delta * 2.0)
	var dt := delta * slow
	msg_t += delta
	if msg != "" and msg_t > msg_life:
		msg = ""
		msg_sub = ""
	phase_t += dt
	_tick_phase(dt)
	if freeze_t > 0.0:
		freeze_t -= delta
	else:
		p1.tick(dt)
		p2.tick(dt)
		_push_apart()
		for a in actors:
			a.tick(dt)
		var alive: Array = []
		for a in actors:
			if a.dead:
				a.queue_free()
			else:
				alive.append(a)
		actors = alive
	_tick_camera(delta)
	if phase == "fight" and round_num == 1 and wins == [0, 0] and phase_t < 7.0:
		hint_a = 1.0
	else:
		hint_a = move_toward(hint_a, 0.0, delta * 1.5)


func _tick_shot(delta: float) -> void:
	if shot_t > 0.0:
		shot_t -= delta
		if shot_t <= 0.0:
			var img := get_viewport().get_texture().get_image()
			img.save_png(shot_path)
			get_tree().quit()


func _push_apart() -> void:
	var pushable := [Fighter.St.MOVE, Fighter.St.GUARD, Fighter.St.CHARGE, Fighter.St.ATTACK, Fighter.St.INTRO, Fighter.St.LAND]
	if p1.state not in pushable or p2.state not in pushable:
		return
	var dx := p2.position.x - p1.position.x
	if absf(dx) < 26.0 and absf(p1.position.y - p2.position.y) < 40.0:
		var push: float = (26.0 - absf(dx)) / 2.0
		var s := 1.0 if dx >= 0.0 else -1.0
		p1.position.x -= s * push
		p2.position.x += s * push


func _tick_camera(delta: float) -> void:
	var mid := (p1.center() + p2.center()) * 0.5
	var dxv: float = abs(p1.position.x - p2.position.x)
	var dyv: float = abs(p1.position.y - p2.position.y)
	var zx := 480.0 / (dxv + 300.0)
	var zy := 270.0 / (dyv + 210.0)
	var z: float = clamp(min(zx, zy), 0.55, 1.0)
	cam.zoom = cam.zoom.lerp(Vector2(z, z), 1.0 - exp(-5.0 * delta))
	var half_w := 240.0 / cam.zoom.x
	var half_h := 135.0 / cam.zoom.x
	mid.y -= 20.0
	mid.x = clamp(mid.x, -1300.0 + half_w, 1300.0 - half_w)
	var y_max := 560.0 if map == "lake" else 470.0
	mid.y = clamp(mid.y, -520.0 + half_h, y_max - half_h)
	cam.position = cam.position.lerp(mid, 1.0 - exp(-7.0 * delta))
	shake_amp = move_toward(shake_amp, 0.0, 18.0 * delta)
	cam.offset = Vector2(randf_range(-1, 1), randf_range(-1, 1)) * shake_amp
	# parallasse manuale (alcuni strati esistono solo su certe mappe)
	var cp := cam.position
	if lay_clouds != null:
		lay_clouds.position = Vector2(cp.x * 0.85, (cp.y - 250.0) * 0.7)
	if lay_mount != null:
		lay_mount.position = Vector2(cp.x * 0.6, (cp.y - 250.0) * 0.45)
	if lay_mesa != null:
		lay_mesa.position = Vector2(cp.x * 0.25, 0)


func shake(a: float) -> void:
	shake_amp = max(shake_amp, a)


# --- risoluzione dei colpi ---------------------------------------------------

func try_hit(attacker: Fighter, r: Rect2, dmg: float, opts: Dictionary = {}) -> String:
	if phase != "fight":
		return "miss"
	var victim := attacker.enemy
	if victim == null or victim.invuln > 0.0:
		return "miss"
	if victim.state in [Fighter.St.DOWN, Fighter.St.KO]:
		return "miss"
	if not r.intersects(victim.hurt_rect()):
		return "miss"
	var contact: Vector2 = (r.get_center() + victim.center()) * 0.5
	attacker.ki = min(attacker.ki_max, attacker.ki + 9.0)
	if victim.state == Fighter.St.GUARD:
		var chip: float = opts.get("chip", dmg * 0.2)
		var pdir: float = signf(victim.position.x - attacker.position.x)
		victim.take_block(chip, Vector2(pdir * 120.0, 0))
		spawn_fx("spark_1", contact, {"life": 0.18, "add": true})
		sfx.play("guard")
		freeze_t = max(freeze_t, 0.03)
		if victim.hp <= 0.0:
			on_ko(victim)
		return "blocked"
	victim.take_hit(dmg, opts)
	var heavy: bool = opts.get("heavy", false)
	if heavy:
		spawn_fx("burst", contact, {"life": 0.3, "add": true, "grow": 1.5, "scale": 0.7})
		spawn_fx("alert", victim.position + Vector2(0, -74), {"life": 0.35, "scale": 0.55})
	else:
		spawn_fx("spark_0", contact, {"life": 0.22, "add": true, "grow": 2.0, "spin": 3.0})
	sfx.play("kick" if heavy else "hit")
	freeze_t = max(freeze_t, 0.10 if heavy else 0.05)
	shake(3.0 if heavy else 1.2)
	if victim.hp <= 0.0:
		on_ko(victim)
	return "hit"


# --- spawn di entita dinamiche ------------------------------------------------

func spawn_fx(fx_name: String, pos: Vector2, opts: Dictionary = {}) -> void:
	spawn_fx_tex(load("res://assets/sprites/fx/%s.png" % fx_name), pos, opts)


func spawn_fx_tex(tex: Texture2D, pos: Vector2, opts: Dictionary = {}) -> void:
	var fx := FXScript.new()
	fx.texture = tex
	fx.position = pos
	fx.life = opts.get("life", 0.25)
	fx.grow = opts.get("grow", 0.0)
	fx.spin = opts.get("spin", 0.0)
	fx.vel = opts.get("vel", Vector2.ZERO)
	var s: float = opts.get("scale", 1.0)
	fx.scale = Vector2(s, s)
	if opts.get("add", false):
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		fx.material = mat
	if opts.has("mod"):
		fx.modulate = opts["mod"]
	fx.start_a = fx.modulate.a
	actor_root.add_child(fx)
	actors.append(fx)


func spawn_afterimage(f: Fighter) -> void:
	if f.spr == null or f.spr.sprite_frames == null or not f.visible:
		return
	var tex := f.spr.sprite_frames.get_frame_texture(f.spr.animation, f.spr.frame)
	if tex == null:
		return
	var fx := FXScript.new()
	fx.texture = tex
	fx.centered = false
	fx.offset = Vector2(-32, -56)
	fx.position = f.position
	fx.flip_h = f.spr.flip_h
	fx.modulate = Color(1.0, 0.7, 0.3, 0.5) if f.is_cpu else Color(0.4, 0.7, 1.0, 0.5)
	fx.start_a = 0.5
	fx.life = 0.22
	actor_root.add_child(fx)
	actors.append(fx)


func spawn_blast(f: Fighter) -> void:
	var b := KiBlastScript.new()
	b.setup(f)
	if f.is_cpu:
		b.modulate = Color(1.0, 0.55, 0.35)
	actor_root.add_child(b)
	actors.append(b)
	sfx.play("blast")
	spawn_fx("spark_1", b.position, {"life": 0.15, "add": true})


func spawn_beam(f: Fighter) -> void:
	var b := BeamScript.new()
	b.setup(f)
	actor_root.add_child(b)
	actors.append(b)
	sfx.play("beam")
	shake(4.0)
