class_name AIController
extends RefCounted

# IA della CPU: sceglie un piano ogni ~0.3s in base alla distanza e al ki,
# accoda pressioni di tasti (seq) e reagisce agli attacchi del giocatore.

var think_t := 0.8
var plan := "idle"
var plan_t := 0.0
var seq: Array = []
var hold_guard := 0.0
var strafe_dir := 1.0
var reacted := false
var last_seen := Vector2.ZERO
var lost := false
var esc_roll := -1.0
var smash_tree: Node = null   # sequoia sospetta da abbattere (piano "smash")


func poll(f, dt: float) -> Dictionary:
	var out := {"move": Vector2.ZERO, "attack": false, "blast": false, "beam": false,
		"dash": false, "roll": false, "guard": false, "charge": false, "attack_held": false}
	var e = f.enemy
	if e == null or f.game.phase != "fight":
		return out
	if f.state in [Fighter.St.HURT, Fighter.St.LAUNCHED, Fighter.St.DOWN, Fighter.St.KO]:
		seq.clear()
		plan = "idle"
		# sotto una combo prolungata a volte tiene premuto l'attacco per la
		# fuga (stessa meccanica del giocatore); decide una volta per combo
		if f.chain_n >= Fighter.ESCAPE_HITS:
			if esc_roll < 0.0:
				esc_roll = randf()
			out.attack_held = esc_roll < 0.5
		return out
	esc_roll = -1.0

	hold_guard = max(0.0, hold_guard - dt)

	# esegue le pressioni programmate
	var kept: Array = []
	for a in seq:
		a.t -= dt
		if a.t <= 0.0:
			out[a.act] = true
		else:
			kept.append(a)
	seq = kept

	# rilevamento: chi e' sott'acqua o in copertura dietro una sequoia
	# sparisce dai "sensori" (gruppo "targetable" + visibilita' in acqua)
	var can_see: bool = f.game.can_target(f, e)
	# INGANNO: se il bersaglio e' sparito ma ha lasciato un'immagine-esca, la
	# CPU ci casca e continua a combattere contro di essa come fosse l'avversario
	var dec = f.game.decoy_of(e)
	var fooled: bool = not can_see and dec != null
	# posizione che la CPU CREDE sia quella del nemico
	var tgt_pos: Vector2 = e.position
	if fooled:
		tgt_pos = dec.position
	elif not can_see:
		tgt_pos = last_seen
	var dist: float = f.position.distance_to(tgt_pos)

	if can_see or fooled:
		last_seen = tgt_pos
		lost = false
	elif not lost:
		# bersaglio perso davvero (mai visto sparire, o esca svanita/colpita):
		# dimentica i piani e mettiti a cercarlo
		lost = true
		seq.clear()
		hold_guard = 0.0
		plan = "search"
		plan_t = 2.0
		f.game.spawn_fx("alert", f.position + Vector2(0, -74), {"life": 0.5, "scale": 0.45})

	# reazioni (solo se il nemico e' rilevabile)
	if can_see and e.state == Fighter.St.BEAM_CHARGE and randf() < dt * 2.5:
		if abs(f.position.y - e.position.y) < 80.0:
			plan = "dodge"
			plan_t = 0.7
	if can_see and e.state == Fighter.St.ATTACK and dist < 120.0 and not reacted:
		reacted = true
		if randf() < 0.3:
			hold_guard = 0.45
	if e.state != Fighter.St.ATTACK:
		reacted = false

	think_t -= dt
	plan_t -= dt
	if plan_t <= 0.0 and plan != "idle":
		plan = "idle"
	if think_t <= 0.0:
		think_t = randf_range(0.25, 0.5)
		if can_see or fooled:
			_choose(f, dist)   # ingannata: sceglie i piani contro l'esca
		else:
			_choose_blind(f)

	# tutti i piani ragionano sul bersaglio CREDUTO: se e' l'esca, la CPU le
	# vola incontro e la prende a pugni finche' non si dissolve
	var to_e: Vector2 = tgt_pos - f.position
	match plan:
		"approach":
			out.move = to_e.normalized()
			if dist < 85.0:
				plan = "melee"
				plan_t = 0.8
				_queue_combo()
		"melee":
			out.move = Vector2(signf(to_e.x) * 0.4, clampf(to_e.y * 0.05, -0.5, 0.5))
		"retreat":
			out.move = Vector2(-signf(to_e.x), -0.5).normalized()
		"dodge":
			out.move = Vector2(-signf(to_e.x) * 0.2, -1.0 if f.position.y > -100.0 else 1.0)
		"strafe":
			out.move = Vector2(0, strafe_dir)
		"charge":
			out.charge = true
			if (dist < 170.0 and f.game.can_target(f, e)) or f.ki > f.ki_max - 10.0:
				plan = "idle"
		"search":
			# pattuglia sull'ultima posizione nota, restando fuori dall'acqua
			var tgt := Vector2(last_seen.x, minf(last_seen.y, 375.0))
			var d: Vector2 = tgt - f.position
			if d.length() > 40.0:
				out.move = d.normalized()
			else:
				out.move = Vector2(0.25 * strafe_dir, 0.0)
		"smash":
			# nella foresta il bersaglio sparito e' probabilmente in copertura:
			# si va sotto la sequoia sospetta e la si prende a legnate finche'
			# non cade (chi ci sta dietro viene scoperto)
			if smash_tree == null or not is_instance_valid(smash_tree) or smash_tree.destroyed:
				smash_tree = null
				plan = "idle"
			else:
				var tp: Vector2 = smash_tree.global_position + Vector2(0, -30)
				var d2: Vector2 = tp - f.position
				if absf(d2.x) > 52.0 or absf(d2.y) > 40.0:
					out.move = d2.normalized()
				elif seq.is_empty():
					_queue_combo()
		_:
			pass

	out.guard = hold_guard > 0.0
	return out


func _choose_blind(f) -> void:
	# senza bersaglio rilevabile: nella foresta il primo sospetto e' che sia in
	# copertura dietro un tronco, quindi si va ad abbatterlo; altrimenti si
	# cerca, si ricarica il ki o si cambia quota
	var r := randf()
	if f.game.map == "forest" and r < 0.45:
		# raggio generoso: se l'esca ha attirato la CPU lontano dal tronco,
		# il sospetto cade comunque sulla sequoia piu' vicina a dov'era il nemico
		var tr = f.game.tree_near(last_seen, 400.0)
		if tr != null:
			smash_tree = tr
			plan = "smash"
			plan_t = 2.2
			return
	if r < 0.55:
		plan = "search"
		plan_t = 1.2
	elif r < 0.82 and f.ki < 260.0:
		plan = "charge"
		plan_t = 1.3
	else:
		plan = "strafe"
		plan_t = 0.6
		strafe_dir = 1.0 if randf() < 0.5 else -1.0


func _queue_combo() -> void:
	seq.append({"t": 0.05, "act": "attack"})
	seq.append({"t": 0.28, "act": "attack"})
	seq.append({"t": 0.52, "act": "attack"})


func _choose(f, dist: float) -> void:
	var r := randf()
	if dist < 95.0:
		if r < 0.45:
			plan = "melee"
			plan_t = 0.8
			_queue_combo()
		elif r < 0.60:
			hold_guard = 0.5
			plan = "idle"
		elif r < 0.72:
			seq.append({"t": 0.05, "act": "roll"})
			plan = "idle"
		elif r < 0.85:
			plan = "retreat"
			plan_t = 0.6
		else:
			seq.append({"t": 0.05, "act": "blast"})
			plan = "idle"
	elif dist < 280.0:
		if r < 0.35:
			plan = "approach"
			plan_t = 1.2
		elif r < 0.50 and f.ki >= 25.0:
			seq.append({"t": 0.05, "act": "dash"})
			seq.append({"t": 0.35, "act": "attack"})
			seq.append({"t": 0.55, "act": "attack"})
			seq.append({"t": 0.75, "act": "attack"})
			plan = "idle"
		elif r < 0.70:
			seq.append({"t": 0.05, "act": "blast"})
			plan = "idle"
		elif r < 0.78:
			seq.append({"t": 0.05, "act": "roll"})
			plan = "approach"
			plan_t = 0.7
		elif r < 0.90 and f.ki < 220.0:
			plan = "charge"
			plan_t = 1.4
		else:
			plan = "strafe"
			plan_t = 0.7
			strafe_dir = 1.0 if randf() < 0.5 else -1.0
	else:
		if r < 0.30:
			seq.append({"t": 0.05, "act": "blast"})
			if randf() < 0.5:
				seq.append({"t": 0.4, "act": "blast"})
			plan = "idle"
		elif r < 0.50:
			plan = "approach"
			plan_t = 1.5
		elif r < 0.72 and f.ki < 260.0:
			plan = "charge"
			plan_t = 1.8
		elif r < 0.85 and f.ki >= 200.0 and abs(f.position.y - last_seen.y) < 55.0:
			seq.append({"t": 0.05, "act": "beam"})
			plan = "idle"
		else:
			plan = "strafe"
			plan_t = 0.8
			strafe_dir = 1.0 if randf() < 0.5 else -1.0
