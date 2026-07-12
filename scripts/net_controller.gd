class_name NetController
extends RefCounted

# Controller passivo per la partita online: non legge mai Input.
# Restituisce l'ultimo comando consegnato a fighter.execute_inputs() dal
# MatchManager (input locale o pacchetto RPC dell'avversario). Se per
# qualche tick non arrivano pacchetti nuovi, i tasti "tenuti" (move, guard,
# charge) restano attivi mentre i fronti (attack, blast...) non si ripetono.


func poll(f, _dt: float) -> Dictionary:
	if f.net_cmd.is_empty():
		return Fighter._empty_input()
	var cmd: Dictionary = f.net_cmd
	# consuma i just-pressed: senza un pacchetto nuovo restano solo i tenuti
	var held := cmd.duplicate()
	for k in ["attack", "blast", "beam", "dash", "roll"]:
		held[k] = false
	f.net_cmd = held
	return cmd
