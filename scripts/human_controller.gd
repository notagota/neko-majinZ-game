class_name HumanController
extends RefCounted

# Traduce l'input di tastiera/gamepad nel dizionario di comandi del Fighter.


func poll(_f, _dt: float) -> Dictionary:
	return {
		"move": Vector2(Input.get_axis("p_left", "p_right"), Input.get_axis("p_up", "p_down")),
		"attack": Input.is_action_just_pressed("p_attack"),
		"blast": Input.is_action_just_pressed("p_blast"),
		"beam": Input.is_action_just_pressed("p_beam"),
		"dash": Input.is_action_just_pressed("p_dash"),
		"roll": Input.is_action_just_pressed("p_roll"),
		"guard": Input.is_action_pressed("p_guard"),
		"charge": Input.is_action_pressed("p_charge"),
	}
