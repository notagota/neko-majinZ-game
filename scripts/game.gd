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
const MatchScript := preload("res://scripts/match_manager.gd")
const TreeScene := preload("res://scenes/albero_interattivo.tscn")
const DecoyScript := preload("res://scripts/decoy.gd")
const DesertPerspectiveScript := preload("res://scripts/desert_perspective.gd")

const MAPS := ["desert", "lake", "forest"]
const FLOOR_Y := 400.0
# mappa "lake": la costa rocciosa a sinistra scende a gradoni dolci nel lago,
# che occupa tutto il lato destro dell'arena (fondale visibile sott'acqua)
const LAKE_X0 := -80.0      # da qui il terreno scende sotto il pelo dell'acqua
const STEP_W := 150.0       # larghezza di ogni gradone
const STEP_H := 60.0        # dislivello tra i gradoni
const WATER_Y := 402.0      # pelo dell'acqua
const LAKE_BOTTOM := 640.0  # fondale piatto piu' profondo
# mappa "forest": si combatte a terra tra i tronchi delle sequoie giganti e
# in volo sopra le chiome, dove restano solo cielo e nuvole (soffitto alzato).
# E' anche la mappa piu' LARGA (FOREST_ARENA_X): c'e' spazio per un bosco vero,
# con dieci sequoie interattive dietro cui sparire.
const FOREST_CEIL := -1050.0     # quota massima di volo nella foresta
const FOREST_ARENA_X := 1800.0   # semilarghezza dell'arena (le altre: 1150)
const FOREST_TREE_XS := [-1640.0, -1280.0, -980.0, -620.0, -260.0,
	180.0, 560.0, 920.0, 1280.0, 1640.0]
const FOREST_TREE_SC := [0.92, 1.08, 1.0, 1.12, 0.95, 1.06, 0.9, 1.1, 0.98, 1.04]
# livelli di profondita' della foresta: i lottatori stanno a z 0 come le
# sequoie interattive, ma chi si NASCONDE scende a Z_HIDDEN e finisce dietro
# al fusto pur restando davanti al suolo e agli sfondi
const Z_CLOUDS := -30
const Z_FAR := -25
const Z_MID := -20
const Z_GROUND := -10
const Z_HIDDEN := -5
const Z_FRONT := 45   # fronde in primo piano: davanti a lottatori e sequoie

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
var tree_root: Node2D        # contenitore delle sequoie interattive (forest)
var trees: Array = []        # AlberoInterattivo vivi, tickati dal game
var decoys := {}             # Fighter -> immagine-esca viva (vedi spawn_decoy)
var desert_perspective       # controller delle due prospettive 2D del deserto

var flash_layer: CanvasLayer
var menu_stream: AudioStream
var battle_streams := {}
var phase := "intro1"
var phase_t := 0.0
var mode := "versus"
var online := false
var match_mgr: Node = null  # MatchManager della partita online (ping per la HUD)
var reconciling := false  # replay del netcode in corso: sopprimi effetti e danni
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
var dbg_beamtest_cpu := false
var dbg_dinohit := false
var dbg_fastko := false
var dbg_divetest := false
var dbg_hidetest := false
var dbg_treetest := false
var dbg_decoytest := false
var dbg_skytest := false
var dbg_widetest := false
var dbg_tree: Node = null      # albero del --treetest da abbattere
var dbg_treekill_t := -1.0     # countdown prima dell'abbattimento di test
var dbg_decoy_t := -1.0        # countdown del --decoytest prima di nascondersi


func _ready() -> void:
	randomize()
	_setup_input()
	desert_perspective = DesertPerspectiveScript.new()
	desert_perspective.setup(self)
	add_child(desert_perspective)
	_build_world("desert")
	_build_fighters()
	cam = Camera2D.new()
	cam.position = Vector2(0, 250)
	cam.zoom = Vector2(0.9, 0.9)
	add_child(cam)
	cam.make_current()
	sfx = SfxScript.new()
	add_child(sfx)
	# musiche in loop: canzone del menu + tracce chiptune di battaglia
	# (tools/BattleGen.cs), una per mappa; un solo player le alterna
	menu_stream = _load_loop("res://assets/music/menu.wav")
	battle_streams = {
		"desert": _load_loop("res://assets/music/battle_desert.wav"),
		"lake": _load_loop("res://assets/music/battle_lake.wav"),
		"forest": _load_loop("res://assets/music/battle_forest.wav"),
	}
	music = AudioStreamPlayer.new()
	music.volume_db = -8.0
	add_child(music)
	# strato per i flash a tutto schermo (burst/lines), sotto la HUD (layer 10)
	flash_layer = CanvasLayer.new()
	flash_layer.layer = 5
	add_child(flash_layer)
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	hud = HUDScript.new()
	hud.game = self
	layer.add_child(hud)
	# argomenti di debug: --demo (IA vs IA), --shot=percorso (screenshot e chiudi)
	var skip_menu := false
	var dbg_mapsel := false
	var goto_netmenu := false
	for a in OS.get_cmdline_user_args():
		if a == "--demo":
			p1.controller = AIC.new()
			skip_menu = true
		elif a == "--beamtest":
			dbg_beamtest = true
			skip_menu = true
		elif a == "--perspectivecpu":
			# test speculare: e' P2 a spedire il Player contro mesa_1
			dbg_beamtest_cpu = true
			skip_menu = true
		elif a == "--dinohit":
			# flusso completo: entra in Fase 2 e scaccia il dinosauro
			dbg_beamtest = true
			dbg_dinohit = true
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
		elif a == "--forest":
			_build_world("forest")
			skip_menu = true
		elif a == "--treetest":
			# e2e copertura: P1 si nasconde, l'albero viene abbattuto, P1 riappare
			_build_world("forest")
			dbg_treetest = true
			skip_menu = true
		elif a == "--decoytest":
			# e2e inganno: P1 si nasconde e lascia l'esca; la CPU deve
			# abboccare e attaccarla ("[tree] esca colpita")
			_build_world("forest")
			dbg_decoytest = true
			skip_menu = true
		elif a == "--skytest":
			# entrambi in volo sopra le chiome: verifica di cielo e parallasse
			_build_world("forest")
			dbg_skytest = true
			skip_menu = true
		elif a == "--widetest":
			# lottatori alla massima distanza a terra: e' il caso peggiore per
			# l'inquadratura (zoom-out massimo), dove gli strati di parallasse
			# rischiano di scoprirsi
			_build_world("forest")
			dbg_widetest = true
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
		elif a.begins_with("--nethost=") or a.begins_with("--netjoin="):
			goto_netmenu = true  # test online: vai dritto al menu multiplayer
	if goto_netmenu and not NetworkManager.is_online():
		# solo al primo avvio: quando l'arena viene ricaricata a connessione
		# avvenuta il flag e' ancora negli argomenti e va ignorato.
		# deferred: dentro _ready l'albero e' occupato e il cambio diretto fallisce
		get_tree().change_scene_to_file.call_deferred("res://scenes/multiplayer_menu.tscn")
		return
	if NetworkManager.is_online():
		# arena caricata dal menu online: partita 1v1 tra persone, il
		# MatchManager assegna autorita' e controller di rete ai lottatori
		online = true
		skip_menu = true
		# la mappa l'ha scelta l'host e ha viaggiato nel codice-offerta: i due
		# giochi costruiscono cosi' la STESSA arena (deserto o lago)
		var net_map: String = NetworkManager.map
		if net_map != map:
			_build_world(net_map)
		print("[net] arena online: %s (io sono il player %d)"
			% [map, NetworkManager.local_player()])
		var mm := MatchScript.new()
		mm.name = "Match"
		match_mgr = mm
		add_child(mm)
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
	if desert_perspective != null:
		desert_perspective.clear_stage()
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
	tree_root = null
	trees = []
	world_root = Node2D.new()
	add_child(world_root)
	move_child(world_root, 0)  # sempre dietro a lottatori ed effetti
	# cielo fisso a schermo
	sky_layer = CanvasLayer.new()
	sky_layer.layer = -5
	add_child(sky_layer)
	var sky := TextureRect.new()
	var sky_tex := "res://assets/bg/sky.png"
	if m == "lake":
		sky_tex = "res://assets/bg/bg2_sky.png"
	elif m == "forest":
		sky_tex = "res://assets/bg/bg3_sky.png"
	sky.texture = load(sky_tex)
	sky.stretch_mode = TextureRect.STRETCH_SCALE
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	sky_layer.add_child(sky)
	if m != "forest":
		# nuvole a parallasse manuale (deserto e lago; la foresta usa Parallax2D)
		lay_clouds = Node2D.new()
		if m == "desert":
			lay_clouds.z_index = -30
		world_root.add_child(lay_clouds)
		var ct: Texture2D = load("res://assets/bg/clouds.png")
		for i in range(3):
			var s := Sprite2D.new()
			s.texture = ct
			s.centered = false
			s.position = Vector2(-1700 + i * 1280, -240)
			lay_clouds.add_child(s)
	else:
		_build_forest_layers()
	if m == "desert":
		# montagne lontane
		lay_mount = Node2D.new()
		lay_mount.z_index = -20
		world_root.add_child(lay_mount)
		var mt: Texture2D = load("res://assets/bg/mountains.png")
		for i in range(3):
			var s := Sprite2D.new()
			s.texture = mt
			s.centered = false
			s.position = Vector2(-1850 + i * 1280, FLOOR_Y - 148)
			lay_mount.add_child(s)
		# Le due composizioni delle mesas vengono gestite da un controller
		# dedicato: Fase 1 frontale e Fase 2 laterale restano entrambe Node2D.
		desert_perspective.build_desert(world_root)
	# terreno: sul lago i tile coprono solo la riva alta a sinistra,
	# i gradoni e il fondale li disegna la WaterZone
	var gt_path := "res://assets/bg/ground.png"
	if m == "lake":
		gt_path = "res://assets/bg/bg2_ground.png"
	elif m == "forest":
		gt_path = "res://assets/bg/bg3_ground.png"
	var gt: Texture2D = load(gt_path)
	var gr := Node2D.new()
	if m == "forest":
		gr.z_index = Z_GROUND  # sopra gli sfondi, sotto chi si nasconde
	world_root.add_child(gr)
	# la foresta e' larga il doppio: servono piu' tessere di terreno
	var tiles := 11 if m == "forest" else 8
	for i in range(-tiles, tiles + 1):
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
	elif m == "forest":
		# sequoie interattive: stesso piano dei lottatori ma leggermente
		# dietro (ordine dell'albero di scena), davanti agli strati Parallax2D
		tree_root = Node2D.new()
		world_root.add_child(tree_root)
		_reset_trees()


# Sfondi della foresta con il nodo Parallax2D (il successore di
# ParallaxBackground): ogni strato scorre a una frazione della camera.
# Dal lontano al vicino, con i z_index della mappa (vedi Z_* qui sotto):
#   PxClouds (0.12): nuvole quasi fisse, si scoprono solo volando in alto
#   PxFar    (0.30, 0.85): cresta di conifere nella foschia
#   PxMid    (0.60, 0.93): sequoie scure di media distanza con varchi
#   PxFront  (1.30, 1.12, z 45): fronde DAVANTI ai lottatori, spariscono
#            in fretta salendo (fattore > 1 = primo piano)
# Le sequoie interattive stanno nel mondo vero (tree_root, fattore 1) a z 0,
# cioe' allo stesso livello dei lottatori: chi si nasconde scende a Z_HIDDEN
# e finisce DIETRO al fusto (che a sua volta diventa semitrasparente).
func _build_forest_layers() -> void:
	var clouds := _parallax_layer(Vector2(0.12, 0.10), Vector2(1280, 0), 4, Z_CLOUDS)
	var ct: Texture2D = load("res://assets/bg/clouds.png")
	var cs := Sprite2D.new()
	cs.texture = ct
	cs.centered = false
	cs.position = Vector2(-640, -140)
	clouds.add_child(cs)
	var far := _parallax_layer(Vector2(0.3, 0.85), Vector2(512, 0), 8, Z_FAR)
	var fs := Sprite2D.new()
	fs.texture = load("res://assets/bg/forest_far.png")
	fs.centered = false
	fs.position = Vector2(-256, -560)
	fs.scale = Vector2(1.0, 1.15)  # allungata: nessuno spiraglio sopra il suolo
	far.add_child(fs)
	var mid := _parallax_layer(Vector2(0.6, 0.93), Vector2(512, 0), 8, Z_MID)
	var ms := Sprite2D.new()
	ms.texture = load("res://assets/bg/forest_mid.png")
	ms.centered = false
	ms.position = Vector2(-256, -433)
	mid.add_child(ms)
	var front := _parallax_layer(Vector2(1.3, 1.35), Vector2(512, 0), 10, Z_FRONT)
	var fr := Sprite2D.new()
	fr.texture = load("res://assets/bg/forest_front.png")
	fr.centered = false
	# Parallax2D mette il figlio a  y + (scroll.y - 1) * (135 - camera.y):
	# a terra (camera ~300) la frangia resta appena sopra il bordo alto e ci
	# penzola dentro; appena si sale in volo scorre giu' ed esce dallo schermo
	# (con scroll.y 1.35 sparisce del tutto gia' a mezz'aria, come deve essere
	# per un primo piano: non si vedono rami sopra le chiome)
	fr.position = Vector2(-256, 170)
	front.add_child(fr)


func _parallax_layer(scroll: Vector2, rep: Vector2, times: int, z: int) -> Parallax2D:
	var px := Parallax2D.new()
	px.scroll_scale = scroll
	px.repeat_size = rep
	px.repeat_times = times
	px.z_index = z
	world_root.add_child(px)
	return px


# Ripianta le sequoie interattive (a inizio round gli alberi abbattuti
# ricrescono): posizioni fisse, taglie leggermente diverse.
func _reset_trees() -> void:
	for tr in trees:
		if is_instance_valid(tr):
			tr.queue_free()
	trees = []
	if map != "forest" or tree_root == null:
		return
	for i in range(FOREST_TREE_XS.size()):
		var tr: Node2D = TreeScene.instantiate()
		tr.game = self
		tr.position = Vector2(FOREST_TREE_XS[i], FLOOR_Y)
		tr.scale = Vector2.ONE * FOREST_TREE_SC[i]
		tree_root.add_child(tr)
		trees.append(tr)


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


# bersagliabile = visibile E nel gruppo "targetable": chi e' in copertura
# dietro una sequoia resta semitrasparente sullo schermo ma sparisce da
# lock-on, homing e sensori dell'IA (requisito della mappa foresta)
func can_target(viewer: Fighter, target: Fighter) -> bool:
	return can_see(viewer, target) and target.is_in_group("targetable")


# quota massima di volo: nella foresta si sale fin sopra le chiome
func ceiling_y() -> float:
	return FOREST_CEIL if map == "forest" else Fighter.CEIL_Y


# semilarghezza dell'arena: la foresta e' piu' larga delle altre mappe
func arena_x() -> float:
	if map == "desert" and desert_perspective != null:
		return desert_perspective.arena_half_width()
	return FOREST_ARENA_X if map == "forest" else Fighter.ARENA_X


# Un solo punto filtra i comandi prima che entrino nella macchina a stati:
# nel deserto blocca l'asse Y e applica il breve malus della Fase 2.
func filter_fighter_input(f: Fighter, input_state: Dictionary) -> Dictionary:
	if desert_perspective != null:
		return desert_perspective.filter_input(f, input_state)
	return input_state


# --- immagini-esca (inganno della copertura) ---------------------------------

# Punto verso cui puntare `target`: il bersaglio vero se lo si rileva, la sua
# immagine-esca se e' in copertura e ne ha lasciata una, altrimenti niente
# (null = nessun aggancio). Lo usano lo scatto homing e le sfere di ki.
func aim_point(viewer: Fighter, target: Fighter) -> Variant:
	if target == null:
		return null
	if can_target(viewer, target):
		return target.center()
	var d = decoy_of(target)
	return d.center() if d != null else null


# l'immagine-esca ancora viva lasciata da `f` (null se non c'e')
func decoy_of(f: Fighter) -> Node:
	var d = decoys.get(f)
	if d == null or not is_instance_valid(d) or d.dead:
		return null
	return d


func spawn_decoy(f: Fighter, pose: Dictionary) -> void:
	if reconciling:
		return  # nel replay l'esca originale esiste gia'
	var old = decoys.get(f)
	if old != null and is_instance_valid(old):
		old.dead = true  # una sola esca per lottatore
	var d := DecoyScript.new()
	d.setup(f, pose)
	actor_root.add_child(d)
	actors.append(d)
	decoys[f] = d


# --- sequoie interattive (mappa "forest") ------------------------------------

# la sequoia nella cui zona di copertura (Area2D) si trova il lottatore
func tree_at(f: Fighter) -> Node:
	for tr in trees:
		if not tr.destroyed and tr.hide_rect().has_point(f.center()):
			return tr
	return null


# la sequoia ancora in piedi piu' vicina a un punto (entro max_dx): l'IA la usa
# per andare ad abbattere il tronco dove ha perso di vista il bersaglio
func tree_near(pos: Vector2, max_dx: float = 150.0) -> Node:
	var best: Node = null
	var bd := max_dx
	for tr in trees:
		if tr.destroyed:
			continue
		var d: float = absf(tr.global_position.x - pos.x)
		if d < bd:
			bd = d
			best = tr
	return best


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


# --- musica -------------------------------------------------------------------

# carica un WAV impostandone il loop sull'intera durata: loop_end e' in
# campioni-frame (durata x frequenza) — data.size()/2 vale solo per PCM mono
func _load_loop(path: String) -> AudioStream:
	var ms = load(path)
	if ms is AudioStreamWAV:
		ms.loop_mode = AudioStreamWAV.LOOP_FORWARD
		ms.loop_begin = 0
		ms.loop_end = int(ms.get_length() * ms.mix_rate)
	return ms


# cambia traccia solo se serve: rivincite e riavvii non fanno ripartire il brano
func _play_music(stream: AudioStream, db := -8.0) -> void:
	music.volume_db = db
	if music.stream == stream and music.playing:
		return
	music.stream = stream
	music.play()


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
	if desert_perspective != null:
		desert_perspective.reset_stage()
	# i lottatori esultano sull'arena come sfondo del menu
	if map == "desert":
		p1.reset(Vector2(-130, FLOOR_Y), 1)
		p2.reset(Vector2(130, FLOOR_Y), -1)
	else:
		p1.reset(Vector2(-400, FLOOR_Y), 1)
		p2.reset(Vector2(-160, FLOOR_Y), -1)
	_play_music(menu_stream)


func _tick_menu() -> void:
	if Input.is_action_just_pressed("p_up"):
		menu_sel = (menu_sel + 3) % 4
		sfx.play("select")
	if Input.is_action_just_pressed("p_down"):
		menu_sel = (menu_sel + 1) % 4
		sfx.play("select")
	# sulla voce VOLUME sinistra/destra regolano il livello
	if menu_sel == 3:
		if Input.is_action_just_pressed("p_left"):
			_change_volume(-0.1)
		if Input.is_action_just_pressed("p_right"):
			_change_volume(0.1)
	if Input.is_action_just_pressed("p_accept") or Input.is_action_just_pressed("p_attack"):
		if menu_sel == 3:
			# INVIO sul volume: muta / ripristina
			volume = 1.0 if volume <= 0.01 else 0.0
			_apply_volume()
			sfx.play("select")
			return
		if menu_sel == 2:
			# partita online: menu di connessione in una scena dedicata
			sfx.play("select", 1.2)
			get_tree().change_scene_to_file("res://scenes/multiplayer_menu.tscn")
			return
		mode = "versus" if menu_sel == 0 else "training"
		map_sel = maxi(0, MAPS.find(map))
		phase = "mapsel"
		phase_t = 0.0
		sfx.play("select", 1.2)


func _tick_mapsel() -> void:
	if Input.is_action_just_pressed("p_left"):
		map_sel = (map_sel + MAPS.size() - 1) % MAPS.size()
		sfx.play("select")
	if Input.is_action_just_pressed("p_right"):
		map_sel = (map_sel + 1) % MAPS.size()
		sfx.play("select")
	if Input.is_action_just_pressed("p_menu"):
		phase = "menu"
		phase_t = 0.0
		sfx.play("select", 0.8)
		return
	if Input.is_action_just_pressed("p_accept") or Input.is_action_just_pressed("p_attack"):
		var m: String = MAPS[map_sel]
		if m != map:
			_build_world(m)
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
	if not online:  # online i controller di rete li assegna il MatchManager
		p2.controller = DummyC.new() if mode == "training" else AIC.new()
	# musichetta chiptune di battaglia della mappa (un po' sotto gli effetti)
	_play_music(battle_streams[map], -10.0)
	_start_round()


func _start_round() -> void:
	round_time = 99.0
	_clear_actors()
	if desert_perspective != null:
		desert_perspective.reset_stage()
	_reset_trees()  # nella foresta gli alberi abbattuti ricrescono a ogni round
	if map == "desert":
		p1.reset(Vector2(-130, FLOOR_Y), 1)
		p2.reset(Vector2(130, FLOOR_Y), -1)
	elif map == "forest":
		# nella radura centrale, tra le sequoie interattive
		p1.reset(Vector2(-200, FLOOR_Y), 1)
		p2.reset(Vector2(200, FLOOR_Y), -1)
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
	decoys = {}  # le immagini-esca vivono nella lista actors: spariscono con essa


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
	# linee di velocita' a tutto schermo sul colpo decisivo
	spawn_fx("lines", victim.center(), {"life": 0.55, "add": true, "screen": true})


func _end_round() -> void:
	phase = "round_end"
	phase_t = 0.0
	slow_target = 1.0
	# a round finito nessuno resta in copertura (ne' dietro al tronco, ne' fuori
	# dal mirino): posa di vittoria e sconfitta si devono vedere
	for f in [p1, p2]:
		if f.hide_tree != null or f.state == Fighter.St.HIDE:
			f.force_unhide()
	if round_winner >= 0:
		if mode != "training":
			wins[round_winner] += 1
		var w := p1 if round_winner == 0 else p2
		if w.state != Fighter.St.KO:
			w.state = Fighter.St.WIN
			w.st = 0.0
			w.aura.visible = false  # spegni l'aura se stava caricando o fuggendo
	else:
		_set_msg("PAREGGIO", "", 1.5)


func _match_over() -> void:
	phase = "match_end"
	phase_t = 0.0
	var p1_won: bool = wins[0] >= 2
	if online:
		# la vittoria va giudicata dal punto di vista del lottatore locale
		var you_won: bool = p1_won == (local_fighter() == p1)
		_set_msg("HAI VINTO!" if you_won else "HAI PERSO...", "ESC: torna al menu", 9999.0)
	else:
		_set_msg("HAI VINTO!" if p1_won else "VITTORIA DELLA CPU",
			"INVIO: rivincita   R: riavvia   ESC: menu", 9999.0)
	sfx.play("round", 0.8)


# Test della foresta: mette P1 in copertura dietro `tr` (dov'e' gia' stato
# posizionato) e, se richiesto, programma l'abbattimento della sequoia.
func _dbg_hide_p1(tr: Node, kill: bool) -> void:
	if p1.state != Fighter.St.MOVE:
		return
	p1._record_pose()
	p1._enter_hide(tr)
	print("[test] p1 targetable=%s hide=%s aria=%s esca=%s" %
		[p1.is_in_group("targetable"), p1.state == Fighter.St.HIDE,
		not p1.grounded(), decoy_of(p1) != null])
	if kill:
		dbg_tree = tr
		dbg_treekill_t = 1.2


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
			if dbg_beamtest_cpu and phase_t >= 0.4 and p2.state == Fighter.St.MOVE:
				dbg_beamtest_cpu = false
				p2.ki = 300.0
				p2.state = Fighter.St.BEAM_CHARGE
				p2.st = 0.0
				p2.aura.visible = true
				sfx.play("charge", 0.85)
			if dbg_dinohit and desert_perspective.desert_dinosaur != null \
					and is_instance_valid(desert_perspective.desert_dinosaur) \
					and desert_perspective.desert_dinosaur.is_attacking():
				dbg_dinohit = false
				var dino = desert_perspective.desert_dinosaur
				desert_perspective.hit_dinosaur(dino.hurt_rect(), 99.0, p1)
			if dbg_divetest and phase_t >= 0.4 and p1.state == Fighter.St.MOVE:
				dbg_divetest = false
				p1.position = Vector2(500, 560)  # immerso nel lago
			if dbg_hidetest and phase_t >= 0.4 and p2.state == Fighter.St.MOVE:
				dbg_hidetest = false
				p2.position = Vector2(500, 560)  # CPU immersa: deve sparire
			if dbg_skytest and phase_t >= 0.2 and p1.state == Fighter.St.MOVE:
				dbg_skytest = false
				p1.position = Vector2(-140, -560)  # al pelo delle chiome
				p2.position = Vector2(140, -840)   # in alto nel cielo
			# --decoytest: P1 e la CPU si affiancano a mezz'aria accanto a una
			# sequoia; mezzo secondo dopo P1 sparisce dietro il tronco lasciando
			# l'esca sotto il naso della CPU, che deve continuare a picchiare
			# l'immagine ("[tree] esca colpita")
			if dbg_decoytest and phase_t >= 0.4 and dbg_decoy_t < 0.0 and trees.size() > 4:
				var t5 = trees[4]
				p1.position = Vector2(t5.position.x + 40.0, FLOOR_Y - 240.0)
				p2.position = Vector2(t5.position.x + 150.0, FLOOR_Y - 240.0)
				dbg_decoy_t = 0.5
			if dbg_decoy_t > 0.0:
				dbg_decoy_t -= dt
				if dbg_decoy_t <= 0.0:
					dbg_decoytest = false
					_dbg_hide_p1(trees[4], false)
			# --treetest: copertura A MEZZA ALTEZZA del fusto (la zona corre
			# lungo tutto l'albero), poi la sequoia viene abbattuta
			if dbg_treetest and phase_t >= 0.4 and trees.size() > 4:
				dbg_treetest = false
				p1.position = Vector2(trees[4].position.x + 40.0, FLOOR_Y - 240.0)
				_dbg_hide_p1(trees[4], true)
			if dbg_treekill_t > 0.0:
				dbg_treekill_t -= dt
				if dbg_treekill_t <= 0.0 and dbg_tree != null:
					dbg_tree.take_damage(999.0, p2.position.x)
					dbg_tree = null
					print("[test] p1 targetable=%s state=%d" %
						[p1.is_in_group("targetable"), p1.state])
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
			msg_t += delta
			if msg != "" and msg_t > msg_life:
				msg = ""
				msg_sub = ""
			_tick_shot(delta)
			_tick_camera(delta)
			return
	if Input.is_action_just_pressed("p_menu"):
		paused = false
		if online:
			_exit_online()  # chiude la connessione e ripristina i controller
		_enter_menu()
		return
	# online niente pausa/riavvio/rivincita locali: manderebbero fuori sincrono
	if Input.is_action_just_pressed("p_pause") and not online:
		paused = not paused
		sfx.play("select")
	if Input.is_action_just_pressed("p_restart") and not online:
		paused = false
		_start_match()
		return
	if phase == "match_end" and Input.is_action_just_pressed("p_accept") and not online:
		_start_match()
		return
	if paused:
		return
	_tick_shot(delta)
	if desert_perspective != null:
		desert_perspective.tick(delta)
		# La sequenza usa i Tween per camera e lottatori. Fermare qui il clock
		# di gioco impedisce a IA, timer e attacchi di interferire con la regia;
		# gli effetti visivi gia' emessi continuano invece a dissolversi.
		if desert_perspective.transition_active:
			_tick_dynamic_actors(delta)
			msg_t += delta
			return
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
		_tick_dynamic_actors(dt)
		# sequoie della foresta: ondeggiano, incassano e cadono col tempo
		# di gioco (rispettano hitstop e slow-mo come ogni entita')
		var t_alive: Array = []
		for tr in trees:
			tr.tick(dt)
			if tr.dead:
				tr.queue_free()
			else:
				t_alive.append(tr)
		trees = t_alive
	if desert_perspective == null or not desert_perspective.transition_active:
		_tick_camera(delta)
	if phase == "fight" and round_num == 1 and wins == [0, 0] and phase_t < 7.0:
		hint_a = 1.0
	else:
		hint_a = move_toward(hint_a, 0.0, delta * 1.5)


func _tick_dynamic_actors(dt: float) -> void:
	for actor in actors:
		actor.tick(dt)
	var alive: Array = []
	for actor in actors:
		if actor.dead:
			actor.queue_free()
		else:
			alive.append(actor)
	actors = alive


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
	var lim_x := arena_x() + 150.0  # bordo del mondo disegnato (arena + margine)
	mid.x = clamp(mid.x, -lim_x + half_w, lim_x - half_w)
	# sul lago la camera puo' scendere fin sotto il fondale (LAKE_BOTTOM):
	# chi si immerge resta sempre inquadrato, col fondo visibile sotto i piedi;
	# nella foresta invece puo' salire fin sopra le chiome delle sequoie
	var y_max := (LAKE_BOTTOM + 70.0) if map == "lake" else 470.0
	var y_min := (FOREST_CEIL - 100.0) if map == "forest" else -520.0
	mid.y = clamp(mid.y, y_min + half_h, y_max - half_h)
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
	if reconciling:
		return
	shake_amp = max(shake_amp, a)


# --- partita online ------------------------------------------------------------

# il lottatore controllato su QUESTA macchina (per l'ospite online e' p2):
# e' il punto di vista per lo stealth acquatico e per l'esito del match
func local_fighter() -> Fighter:
	if online and NetworkManager.local_player() == 2:
		return p2
	return p1


func _exit_online() -> void:
	online = false
	match_mgr = null
	NetworkManager.close()
	var mm := get_node_or_null("Match")
	if mm != null:
		mm.queue_free()
	# ripristina i controller e i nomi della modalita' locale
	p1.controller = HumanC.new()
	p1.fighter_name = "NEKO MAJIN Z"
	p2.controller = AIC.new()
	p2.is_cpu = true
	p2.fighter_name = "NEKO MAJIN (CPU)"


# chiamata dal MatchManager quando cade la connessione con l'avversario
func net_opponent_left() -> void:
	if not online:
		return
	_exit_online()
	_enter_menu()
	_set_msg("AVVERSARIO DISCONNESSO", "", 2.5)


# scoppio di liberazione dalla combo (vedi Fighter._burst_escape): flash a
# tutto schermo e respinta dell'aggressore vicino, senza danni
func fighter_escaped(f: Fighter) -> void:
	print("[fight] %s si libera dalla combo!" % f.fighter_name)
	spawn_fx("burst", f.center(), {"life": 0.4, "add": true, "screen": true})
	spawn_fx("lines", f.center(), {"life": 0.45, "add": true, "mod": Color(1, 1, 1, 0.9), "screen": true})
	if reconciling:
		return  # nel replay lo scoppio originale ha gia' fatto tutto
	sfx.play("kick", 0.6)
	sfx.play("charge", 1.6, -5.0)
	shake(4.0)
	freeze_t = max(freeze_t, 0.08)
	var e := f.enemy
	if e == null or e.state in [Fighter.St.KO, Fighter.St.DOWN]:
		return
	if f.center().distance_to(e.center()) < 150.0:
		var dir := signf(e.position.x - f.position.x)
		if dir == 0.0:
			dir = float(-f.facing)
		e.state = Fighter.St.LAUNCHED
		e.st = 0.0
		e.vel = Vector2(dir * 300.0, -170.0)
		e.aura.visible = false
		spawn_fx("alert", e.position + Vector2(0, -74), {"life": 0.35, "scale": 0.55})


# --- risoluzione dei colpi ---------------------------------------------------

# Attacco ambientale del dinosauro: il simbolo di preavviso resta nel punto
# scelto, quindi un Fighter che si allontana in tempo schiva il colpo. Parata,
# invulnerabilita' e KO seguono le stesse regole del combattimento normale.
func dinosaur_strike(target: Fighter, warned_pos: Vector2, source_pos: Vector2) -> bool:
	if phase != "fight" or reconciling or target == null or target.invuln > 0.0:
		return false
	if target.state in [Fighter.St.DOWN, Fighter.St.KO]:
		return false
	if target.center().distance_to(warned_pos) > 82.0:
		spawn_fx("spark_1", warned_pos, {"life": 0.28, "add": true, "grow": 1.5})
		print("[dinosaur] attacco schivato da %s" % target.fighter_name)
		return false
	var direction := signf(target.position.x - source_pos.x)
	if direction == 0.0:
		direction = 1.0
	if target.state == Fighter.St.GUARD:
		target.take_block(2.5, Vector2(direction * 150.0, -20.0))
		spawn_fx("spark_1", target.center(), {"life": 0.22, "add": true})
		sfx.play("guard")
		freeze_t = maxf(freeze_t, 0.04)
		print("[dinosaur] attacco parato da %s" % target.fighter_name)
		return true
	target.take_hit(12.0, {"launch": Vector2(direction * 220.0, -175.0), "heavy": true})
	spawn_fx("burst", target.center(), {"life": 0.32, "add": true, "screen": true})
	spawn_fx("spark_0", target.center(), {"life": 0.28, "add": true, "grow": 2.2})
	sfx.play("kick", 0.72)
	freeze_t = maxf(freeze_t, 0.08)
	shake(4.0)
	if target.hp <= 0.0:
		on_ko(target)
	print("[dinosaur] %s colpito dall'attacco dallo sfondo" % target.fighter_name)
	return true


@rpc("authority", "call_local", "reliable")
func net_dinosaur_strike(player_slot: int, warned_pos: Vector2, source_pos: Vector2) -> void:
	if not online:
		return
	var target: Fighter = p1 if player_slot == 1 else p2
	dinosaur_strike(target, warned_pos, source_pos)

func try_hit(attacker: Fighter, r: Rect2, dmg: float, opts: Dictionary = {}) -> String:
	# durante un replay di riconciliazione i colpi non vengono risolti:
	# il danno reale e' gia' stato applicato dalla simulazione originale
	if phase != "fight" or reconciling:
		return "miss"
	# le sequoie incassano qualsiasi colpo che ne tocca il tronco (anche se
	# l'attacco manca l'avversario): "tree" dice al chiamante che il colpo
	# e' comunque andato a segno, cosi' sfere e raggi si fermano sul legno
	var tree_hit := false
	for tr in trees:
		if tr.hit_by(r, dmg, attacker.position.x):
			tree_hit = true
	# Il dinosauro e' vulnerabile soltanto nei pochi frame del suo ATTACKING.
	var dinosaur_hit := false
	if map == "desert" and desert_perspective != null:
		dinosaur_hit = desert_perspective.hit_dinosaur(r, dmg, attacker)
	var victim := attacker.enemy
	# l'immagine-esca dell'avversario in copertura: colpirla la dissolve (e
	# svela l'inganno) ma non fa alcun danno — vale come colpo andato a vuoto
	var fake_hit := false
	var dec = decoy_of(victim)
	if dec != null and r.intersects(dec.hurt_rect()):
		dec.pop()
		fake_hit = true
	var no_hit := "tree" if tree_hit else ("dinosaur" if dinosaur_hit \
		else ("decoy" if fake_hit else "miss"))
	if victim == null or victim.invuln > 0.0:
		return no_hit
	if victim.state in [Fighter.St.DOWN, Fighter.St.KO]:
		return no_hit
	if not r.intersects(victim.hurt_rect()):
		return no_hit
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
		spawn_fx("burst", contact, {"life": 0.3, "add": true, "screen": true})
		spawn_fx("alert", victim.position + Vector2(0, -74), {"life": 0.35, "scale": 0.55})
	else:
		spawn_fx("spark_0", contact, {"life": 0.22, "add": true, "grow": 2.0, "spin": 3.0})
	sfx.play("kick" if heavy else "hit")
	freeze_t = max(freeze_t, 0.10 if heavy else 0.05)
	shake(3.0 if heavy else 1.2)
	# Il raggio caricato di qualunque lottatore puo' aprire la seconda
	# prospettiva; il controller decide in modo simmetrico attaccante/vittima.
	if opts.get("desert_perspective", false) and desert_perspective != null:
		desert_perspective.start_transition(attacker, victim)
	if victim.hp <= 0.0:
		on_ko(victim)
	return "hit"


# --- spawn di entita dinamiche ------------------------------------------------

func spawn_fx(fx_name: String, pos: Vector2, opts: Dictionary = {}) -> void:
	# con "screen": true burst e lines diventano "impact frame" in stile anime
	# che coprono l'intera scena (1440x810): riservato ai colpi pesanti
	# (combo che lancia, impatto del raggio, KO, fuga dalla combo)
	if opts.get("screen", false) and (fx_name == "burst" or fx_name == "lines"):
		_spawn_screen_fx(fx_name, opts)
		return
	spawn_fx_tex(load("res://assets/sprites/fx/%s.png" % fx_name), pos, opts)


# flash a schermo intero: parte gia' grande al centro dello schermo e si
# espande oltre i bordi mentre svanisce (spazio schermo: ignora la camera)
func _spawn_screen_fx(fx_name: String, opts: Dictionary) -> void:
	if reconciling:
		return
	var tex: Texture2D = load("res://assets/sprites/fx/%s.png" % fx_name)
	var fx := FXScript.new()
	fx.texture = tex
	fx.position = Vector2(240, 135)  # centro del viewport 480x270
	fx.life = opts.get("life", 0.3)
	# scala che copre tutta la scena, raggiunta a meta' vita
	var cover: float = maxf(480.0 / tex.get_width(), 270.0 / tex.get_height())
	fx.scale = Vector2.ONE * cover * 0.55
	fx.grow = cover * 1.1 / fx.life
	if opts.get("add", false):
		var mat := CanvasItemMaterial.new()
		mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		fx.material = mat
	if opts.has("mod"):
		fx.modulate = opts["mod"]
	fx.start_a = fx.modulate.a
	flash_layer.add_child(fx)
	actors.append(fx)


func spawn_fx_tex(tex: Texture2D, pos: Vector2, opts: Dictionary = {}) -> void:
	if reconciling:
		return
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
	if reconciling or f.spr == null or f.spr.sprite_frames == null or not f.visible:
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
	if reconciling:
		return  # nel replay il proiettile originale esiste gia': niente doppioni
	var b := KiBlastScript.new()
	b.setup(f)
	if f.is_cpu:
		b.modulate = Color(1.0, 0.55, 0.35)
	actor_root.add_child(b)
	actors.append(b)
	sfx.play("blast")
	spawn_fx("spark_1", b.position, {"life": 0.15, "add": true})


func spawn_beam(f: Fighter) -> void:
	if reconciling:
		return
	var b := BeamScript.new()
	b.setup(f)
	actor_root.add_child(b)
	actors.append(b)
	sfx.play("beam")
	shake(4.0)
