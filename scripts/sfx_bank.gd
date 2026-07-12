class_name SfxBank
extends Node

# Pool di AudioStreamPlayer per gli effetti sonori generati proceduralmente.

const NAMES := ["hit", "kick", "blast", "beam", "charge", "dash", "guard", "ko", "bounce", "round", "select", "splash"]

var streams := {}
var players: Array = []
var muted := false  # silenzia i replay di riconciliazione del netcode


func _ready() -> void:
	for n in NAMES:
		streams[n] = load("res://assets/sfx/%s.wav" % n)
	for i in range(10):
		var p := AudioStreamPlayer.new()
		add_child(p)
		players.append(p)


func play(n: String, pitch: float = 1.0, vol: float = 0.0) -> void:
	if muted or not streams.has(n):
		return
	for p in players:
		if not p.playing:
			p.stream = streams[n]
			p.pitch_scale = pitch * randf_range(0.96, 1.04)
			p.volume_db = vol
			p.play()
			return
	players[0].stream = streams[n]
	players[0].pitch_scale = pitch
	players[0].volume_db = vol
	players[0].play()
