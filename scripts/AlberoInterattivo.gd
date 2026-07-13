class_name AlberoInterattivo
extends Area2D

# Sequoia interattiva della mappa "forest" (scene/albero_interattivo.tscn):
#
#   AlberoInterattivo (Area2D)          <- questo script, origine ai piedi
#   |-- Tronco (Sprite2D)               fusto colpibile
#   |-- Chioma (Sprite2D)               fogliame in cima (ondeggia)
#   +-- ZonaCopertura (CollisionShape2D) rettangolo in cui premere SPAZIO:
#       corre lungo TUTTO il fusto (120x600), quindi ci si nasconde a
#       qualsiasi quota, anche in volo a mezz'altezza dell'albero
#
# Dietro al tronco ci si puo' NASCONDERE (vedi Fighter._enter_hide): il
# lottatore diventa semitrasparente, lascia un'IMMAGINE-ESCA di dov'era un
# attimo prima (decoy.gd) ed esce dal gruppo "targetable", quindi
# sparisce da homing, sfere a ricerca e sensori dell'IA. L'albero si puo'
# anche ABBATTERE: ogni colpo che tocca il tronco (smistato da game.try_hit)
# scala i PV; a zero il fusto si spezza, cade e l'albero si libera con
# queue_free() — chi ci si nascondeva dietro viene scoperto all'istante.
#
# I lottatori non hanno corpi fisici (tutte le collisioni del gioco sono
# rettangoli testati a mano), percio' la zona dell'Area2D non usa i segnali
# di fisica: il suo RectangleShape2D viene letto da hide_rect() e testato
# come punto-nel-rettangolo, restando regolabile dall'editor della scena.

# PV alti di proposito: una sequoia gigante non cade per due pugni. Servono
# circa 17 combo J-J-J (30 l'una) o una decina di raggi: l'avversario deve
# davvero accanirsi sul tronco per stanare chi ci si nasconde dietro.
const HP_MAX := 500.0
const FALL_T := 0.85     # durata della caduta del tronco spezzato
const HIT_CD := 0.18     # i colpi multi-frame (raggio) non grandinano danni
const HIDE_ALPHA := 0.5  # trasparenza del fusto con qualcuno in copertura

var game: Node2D
var hp := HP_MAX
var destroyed := false   # abbattuto: niente piu' copertura ne' danni
var dead := false        # caduta finita: il game lo rimuove e lo libera
var hurt_cd := 0.0
var flash := 0.0         # lampo bianco quando incassa un colpo
var fall_dir := 1.0      # cade dalla parte opposta a chi lo colpisce
var fall_t := 0.0
var sway_ph := 0.0       # fase dell'ondeggiare (dipende dalla posizione)
var t := 0.0
var trunk_a := 1.0       # opacita' del fusto (scende con qualcuno in copertura)

@onready var tronco: Sprite2D = $Tronco
@onready var chioma: Sprite2D = $Chioma
@onready var zona: CollisionShape2D = $ZonaCopertura


func _ready() -> void:
	sway_ph = position.x * 0.013


# --- geometria -----------------------------------------------------------

# rettangolo GLOBALE della zona di copertura: e' il RectangleShape2D della
# CollisionShape2D, cosi' la si regola dalla scena e il codice la segue
func hide_rect() -> Rect2:
	var size: Vector2 = zona.shape.size * scale
	return Rect2(to_global(zona.position) - size * 0.5, size)


# rettangolo GLOBALE del tronco colpibile (piu' stretto dello sprite)
func trunk_rect() -> Rect2:
	var w := 66.0 * scale.x
	var h := 600.0 * scale.y
	return Rect2(global_position + Vector2(-w * 0.5, -h), Vector2(w, h))


# c'e' un lottatore in copertura dietro questo fusto?
func _covering() -> bool:
	if destroyed or game == null:
		return false
	for f in [game.p1, game.p2]:
		if f != null and f.hide_tree == self:
			return true
	return false


# --- danni ----------------------------------------------------------------

# colpo smistato da game.try_hit: true se il colpo ha toccato il tronco
func hit_by(r: Rect2, dmg: float, from_x: float) -> bool:
	if destroyed or hurt_cd > 0.0:
		return false
	if not trunk_rect().intersects(r):
		return false
	take_damage(dmg, from_x)
	return true


# scala i PV e, a zero, avvia la distruzione (richiesta dal design)
func take_damage(dmg: float, from_x: float = 0.0) -> void:
	if destroyed:
		return
	hp -= dmg
	hurt_cd = HIT_CD
	flash = 1.0
	fall_dir = 1.0 if from_x < global_position.x else -1.0
	if game != null:
		# schegge di corteccia dal punto piu' vivo del tronco
		for i in range(3):
			game.spawn_fx("spark_1", global_position + Vector2(randf_range(-20.0, 20.0), randf_range(-130.0, -30.0)),
				{"life": 0.3, "add": true, "mod": Color(0.78, 0.55, 0.32),
				"vel": Vector2(randf_range(-90.0, 90.0), randf_range(-40.0, 70.0)), "grow": 0.4})
		game.sfx.play("bounce", 0.7, -6.0)
	if hp <= 0.0:
		_start_fall()


# tronco spezzato: PRIMA si scopre chi ci si nascondeva dietro (torna
# visibile, bersagliabile e vulnerabile), poi parte l'animazione di caduta
func _start_fall() -> void:
	destroyed = true
	fall_t = 0.0
	monitoring = false
	monitorable = false
	if game != null:
		for f in [game.p1, game.p2]:
			if f != null and f.hide_tree == self:
				f.force_unhide()
		game.sfx.play("ko", 0.55, -4.0)
		game.shake(3.0)
		# la chioma esplode in una pioggia di fogliame
		for i in range(10):
			game.spawn_fx("spark_0", chioma.global_position + Vector2(randf_range(-90.0, 90.0), randf_range(-60.0, 60.0)),
				{"life": 0.5, "mod": Color(0.25, 0.6, 0.3), "spin": randf_range(-6.0, 6.0),
				"vel": Vector2(randf_range(-120.0, 120.0), randf_range(-30.0, 120.0)), "grow": 0.4})
	print("[tree] albero abbattuto (x=%d)" % int(global_position.x))


# --- animazione (tickata dal game: rispetta hitstop e slow-mo) -------------

func tick(dt: float) -> void:
	t += dt
	hurt_cd = maxf(0.0, hurt_cd - dt)
	flash = maxf(0.0, flash - dt * 6.0)
	var fl := 1.0 + flash * 0.9
	# chi si nasconde passa DIETRO al fusto: il legno si vela, cosi' la sagoma
	# in copertura resta leggibile (convenzione "raggi X" degli occlusori)
	var want: float = HIDE_ALPHA if _covering() else 1.0
	trunk_a = move_toward(trunk_a, want, dt * 3.5)
	tronco.self_modulate = Color(fl, fl, fl, trunk_a)
	chioma.self_modulate = Color(fl, fl, fl)
	if not destroyed:
		# la chioma ondeggia appena, il tronco resta fermo
		chioma.rotation = sin(t * 0.8 + sway_ph) * 0.02
		return
	# caduta: ruota attorno alla base accelerando, poi sfuma e sparisce
	fall_t += dt
	var k := clampf(fall_t / FALL_T, 0.0, 1.0)
	rotation = fall_dir * (PI * 0.5) * k * k
	modulate.a = 1.0 - maxf(0.0, (k - 0.7) / 0.3)
	if k >= 1.0 and not dead:
		if game != null:
			# tonfo a terra dove atterra la cima
			var tip := global_position + Vector2(fall_dir * 480.0 * scale.x, -10.0)
			game.spawn_fx("burst", tip, {"life": 0.3, "add": true, "scale": 0.5,
				"mod": Color(0.7, 0.85, 0.6)})
			game.shake(2.5)
			game.sfx.play("bounce", 0.5)
		dead = true
