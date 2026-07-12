class_name OneShotFX
extends Sprite2D

# Effetto usa e getta: svanisce, cresce, ruota, si muove. Usato anche per
# le immagini residue (afterimage) di scatti e rotolate.

var life := 0.3
var t := 0.0
var grow := 0.0
var spin := 0.0
var vel := Vector2.ZERO
var start_a := 1.0
var dead := false


func tick(dt: float) -> void:
	t += dt
	if t >= life:
		dead = true
		return
	modulate.a = start_a * (1.0 - t / life)
	scale += Vector2.ONE * grow * dt
	rotation += spin * dt
	position += vel * dt
