class_name DummyController
extends RefCounted

# Bersaglio d'allenamento: nessun input, resta fermo e incassa.


func poll(_f, _dt: float) -> Dictionary:
	return {"move": Vector2.ZERO, "attack": false, "blast": false, "beam": false,
		"dash": false, "roll": false, "guard": false, "charge": false}
