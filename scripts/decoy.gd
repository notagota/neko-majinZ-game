class_name Decoy
extends Sprite2D

# IMMAGINE-ESCA lasciata da chi si nasconde dietro una sequoia (vedi
# Fighter._enter_hide): e' la posa che il lottatore aveva DECOY_LAG frame
# prima di sparire, cioe' l'ultimo punto in cui l'avversario lo ha visto.
#
# Non e' solo un effetto: finche' vive, l'esca INGANNA davvero: l'IA la
# insegue e la attacca (ai_controller), scatto homing e sfere di ki la
# puntano al posto tuo (game.aim_point). Chi la colpisce la fa svanire in
# uno sbuffo e capisce di essere stato beffato (game.try_hit -> "decoy").
#
# Come tutte le entita' dinamiche ha tick(dt) e dead: la lista game.actors
# la fa vivere col tempo di gioco (hitstop e slow-mo compresi).

const LIFE := 2.6      # quanto regge l'inganno
const FADE := 0.5      # ultimo tratto: svanisce sfarfallando

var game: Node2D
var owner_f: Fighter
var t := 0.0
var dead := false


func setup(f: Fighter, pose: Dictionary) -> void:
	game = f.game
	owner_f = f
	# stesso fotogramma (e stesso verso) della posa registrata
	var anim: String = pose.get("anim", "idle")
	if f.spr.sprite_frames.has_animation(anim):
		var idx: int = mini(pose.get("frame", 0), f.spr.sprite_frames.get_frame_count(anim) - 1)
		texture = f.spr.sprite_frames.get_frame_texture(anim, maxi(idx, 0))
	centered = false
	offset = Vector2(-32, -56)   # stesso ancoraggio ai piedi del lottatore
	position = pose.get("pos", f.position)
	flip_h = int(pose.get("facing", 1)) < 0 and anim != "punch" and anim != "punch_l"
	z_index = 0                  # sullo stesso piano dei lottatori
	modulate = Color(1, 1, 1, 0.85)


func center() -> Vector2:
	return position + Vector2(0, -28)


func hurt_rect() -> Rect2:
	return Rect2(position + Vector2(-16, -50), Vector2(32, 50))


func tick(dt: float) -> void:
	t += dt
	# resta credibile quasi fino alla fine, poi sfarfalla e svanisce
	var left := LIFE - t
	if left <= FADE:
		var a: float = clampf(left / FADE, 0.0, 1.0)
		modulate.a = a * (0.6 + 0.4 * sin(t * 30.0))
	if t >= LIFE:
		dead = true


# colpita: l'inganno e' scoperto, l'immagine si dissolve in uno sbuffo
func pop() -> void:
	if dead:
		return
	dead = true
	game.spawn_fx("burst", center(), {"life": 0.3, "add": true, "scale": 0.5,
		"mod": Color(0.75, 0.9, 1.0)})
	for i in range(5):
		game.spawn_fx("spark_1", center(), {"life": 0.3, "add": true,
			"mod": Color(0.8, 0.9, 1.0), "grow": 0.6,
			"vel": Vector2(randf_range(-130.0, 130.0), randf_range(-130.0, 60.0))})
	game.sfx.play("guard", 1.4, -4.0)
	print("[tree] esca colpita: %s ha ingannato l'avversario!" % owner_f.fighter_name)
