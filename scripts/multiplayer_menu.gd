class_name MultiplayerMenu
extends Control

# Menu di connessione per la partita online 1v1 (WebRTC via NetworkManager).
#
# Flusso HOST:  OSPITA -> il codice-offerta appare nel riquadro 1 (COPIA e
#               invialo all'avversario) -> incolla la sua risposta nel
#               riquadro 2 -> CONNETTI.
# Flusso JOIN:  PARTECIPA -> incolla il codice dell'host nel riquadro 1 ->
#               GENERA RISPOSTA -> il codice-risposta appare nel riquadro 2
#               (COPIA e rimandalo all'host). La connessione parte da sola
#               quando l'host preme CONNETTI.
# A connessione avvenuta (match_connected) si carica l'arena con
# change_scene_to_file(): game.gd rileva NetworkManager.is_online() e avvia
# la partita online al posto del menu locale.
#
# TEST AUTOMATICO in locale (due istanze headless che si scambiano i codici
# tramite una cartella condivisa):
#   istanza A: --nethost=DIR   scrive DIR/offer.json e attende DIR/answer.json
#   istanza B: --netjoin=DIR   attende DIR/offer.json e scrive DIR/answer.json

const ARENA_SCENE := "res://scenes/main.tscn"

var role := ""              # "", "host" oppure "join"
var status: Label
var mode_row: HBoxContainer
var panel_host: VBoxContainer
var panel_join: VBoxContainer
var offer_out: TextEdit     # host: offerta generata da inviare
var answer_in: TextEdit     # host: risposta incollata
var offer_in: TextEdit      # join: offerta incollata
var answer_out: TextEdit    # join: risposta generata da rimandare

var auto_dir := ""          # cartella condivisa del test automatico
var auto_role := ""
var auto_poll := 0.0
var auto_offer_applied := false
var auto_answer_applied := false


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color(0.03, 0.05, 0.12)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var title := _mk_label("PARTITA ONLINE 1v1", 14, Color(1, 0.82, 0.15))
	title.position = Vector2(0, 4)
	title.size = Vector2(480, 20)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title)
	mode_row = HBoxContainer.new()
	mode_row.alignment = BoxContainer.ALIGNMENT_CENTER
	mode_row.add_theme_constant_override("separation", 16)
	mode_row.position = Vector2(0, 26)
	mode_row.size = Vector2(480, 22)
	mode_row.add_child(_mk_btn("OSPITA (HOST)", _on_host_pressed))
	mode_row.add_child(_mk_btn("PARTECIPA (JOIN)", _on_join_pressed))
	add_child(mode_row)
	panel_host = _build_host_panel()
	panel_join = _build_join_panel()
	status = _mk_label("scegli se ospitare o partecipare  -  ESC: torna al menu", 8, Color(0.8, 0.9, 1.0))
	status.position = Vector2(0, 252)
	status.size = Vector2(480, 14)
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(status)
	# collegamento ai segnali del NetworkManager (autoload): il menu reagisce
	# al bundle di signaling pronto e all'esito della connessione
	NetworkManager.signaling_ready.connect(_on_signaling_ready)
	NetworkManager.match_connected.connect(_on_connected)
	NetworkManager.connection_failed.connect(_on_failed)
	# argomenti del test automatico (vedi intestazione)
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--nethost="):
			auto_dir = a.substr(10)
			auto_role = "host"
		elif a.begins_with("--netjoin="):
			auto_dir = a.substr(10)
			auto_role = "join"
	if auto_role == "host":
		_on_host_pressed()
	elif auto_role == "join":
		_on_join_pressed()


func _process(dt: float) -> void:
	# ESC: chiudi l'eventuale connessione in corso e torna al menu del gioco
	# (l'azione p_menu e' creata da game.gd, che gira sempre prima di questa scena)
	if InputMap.has_action("p_menu") and Input.is_action_just_pressed("p_menu"):
		NetworkManager.close()
		get_tree().change_scene_to_file(ARENA_SCENE)
		return
	if auto_dir.is_empty():
		return
	# test automatico: scambio dei codici tramite file nella cartella condivisa
	auto_poll -= dt
	if auto_poll > 0.0:
		return
	auto_poll = 0.25
	if auto_role == "join" and not auto_offer_applied:
		var p := auto_dir.path_join("offer.json")
		if FileAccess.file_exists(p):
			auto_offer_applied = true
			offer_in.text = FileAccess.get_file_as_string(p)
			print("[nettest] offerta letta da file")
			_make_answer()
	elif auto_role == "host" and not auto_answer_applied:
		var p := auto_dir.path_join("answer.json")
		if FileAccess.file_exists(p):
			auto_answer_applied = true
			answer_in.text = FileAccess.get_file_as_string(p)
			print("[nettest] risposta letta da file")
			_connect_answer()


# --- azioni dei pulsanti -------------------------------------------------------

func _on_host_pressed() -> void:
	NetworkManager.close()
	role = "host"
	panel_host.visible = true
	panel_join.visible = false
	offer_out.text = ""
	answer_in.text = ""
	var err := NetworkManager.host_start()
	if err != OK:
		_set_status("ERRORE %d: WebRTC non disponibile: la DLL webrtc_native deve stare accanto all'exe (riestrai TUTTO lo zip)" % err)
		return
	_set_status("genero il codice offerta...")


func _on_join_pressed() -> void:
	NetworkManager.close()
	role = "join"
	panel_join.visible = true
	panel_host.visible = false
	offer_in.text = ""
	answer_out.text = ""
	_set_status("incolla il codice dell'host e premi GENERA RISPOSTA")


func _make_answer() -> void:
	var txt := offer_in.text.strip_edges()
	if txt.is_empty():
		_set_status("prima incolla il codice dell'host!")
		return
	var err := NetworkManager.guest_start(txt)
	if err != OK:
		if err == ERR_INVALID_DATA:
			_set_status("codice dell'host non valido (errore %d)" % err)
		else:
			_set_status("ERRORE %d: WebRTC non disponibile: la DLL webrtc_native deve stare accanto all'exe (riestrai TUTTO lo zip)" % err)
		return
	_set_status("genero la risposta...")


func _connect_answer() -> void:
	var txt := answer_in.text.strip_edges()
	if txt.is_empty():
		_set_status("prima incolla la risposta dell'avversario!")
		return
	var err := NetworkManager.host_finish(txt)
	if err != OK:
		_set_status("risposta non valida (errore %d)" % err)
		return
	_set_status("connessione in corso...")


func _copy_offer() -> void:
	DisplayServer.clipboard_set(offer_out.text)
	_set_status("codice copiato negli appunti: incollalo all'avversario")


func _copy_answer() -> void:
	DisplayServer.clipboard_set(answer_out.text)
	_set_status("risposta copiata negli appunti: incollala all'host")


func _paste_offer() -> void:
	offer_in.text = DisplayServer.clipboard_get()


func _paste_answer() -> void:
	answer_in.text = DisplayServer.clipboard_get()


# --- reazioni al NetworkManager ------------------------------------------------

func _on_signaling_ready(payload: String) -> void:
	if role == "host":
		offer_out.text = payload
		_set_status("codice pronto: COPIA, invialo, poi incolla la risposta qui sotto")
		if not auto_dir.is_empty():
			_auto_write("offer.json", payload)
	elif role == "join":
		answer_out.text = payload
		_set_status("risposta pronta: COPIA e inviala all'host, poi attendi")
		if not auto_dir.is_empty():
			_auto_write("answer.json", payload)


func _on_connected(_id: int) -> void:
	_set_status("CONNESSO! carico l'arena...")
	print("[nettest] connesso: carico l'arena")
	# l'arena e' la scena principale: game.gd vede NetworkManager.is_online()
	# e avvia subito la partita online (deferred: siamo dentro un segnale)
	get_tree().change_scene_to_file.call_deferred(ARENA_SCENE)


func _on_failed() -> void:
	_set_status("CONNESSIONE FALLITA: ricontrolla i codici o la rete")


# --- helper --------------------------------------------------------------------

func _set_status(t: String) -> void:
	status.text = t
	print("[netmenu] ", t)


func _auto_write(fname: String, payload: String) -> void:
	# scrittura atomica (tmp + rename) per evitare letture parziali dall'altra istanza
	var tmp := auto_dir.path_join(fname + ".tmp")
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		print("[nettest] ERRORE: impossibile scrivere ", tmp)
		return
	f.store_string(payload)
	f.close()
	DirAccess.rename_absolute(tmp, auto_dir.path_join(fname))
	print("[nettest] scritto ", fname)


func _mk_label(txt: String, fsize: int, col := Color(1, 1, 1)) -> Label:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", fsize)
	l.add_theme_color_override("font_color", col)
	return l


func _mk_btn(txt: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = txt
	b.add_theme_font_size_override("font_size", 9)
	b.pressed.connect(cb)
	return b


func _mk_edit(can_edit: bool) -> TextEdit:
	var te := TextEdit.new()
	te.editable = can_edit
	te.custom_minimum_size = Vector2(0, 46)
	te.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	te.add_theme_font_size_override("font_size", 8)
	return te


func _mk_panel() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.position = Vector2(16, 52)
	v.size = Vector2(448, 196)
	v.add_theme_constant_override("separation", 3)
	v.visible = false
	add_child(v)
	return v


func _build_host_panel() -> VBoxContainer:
	var v := _mk_panel()
	v.add_child(_mk_label("1) invia questo codice all'avversario:", 8))
	offer_out = _mk_edit(false)
	v.add_child(offer_out)
	var r1 := HBoxContainer.new()
	r1.add_child(_mk_btn("COPIA IL CODICE", _copy_offer))
	v.add_child(r1)
	v.add_child(_mk_label("2) incolla la risposta ricevuta e premi CONNETTI:", 8))
	answer_in = _mk_edit(true)
	v.add_child(answer_in)
	var r2 := HBoxContainer.new()
	r2.add_theme_constant_override("separation", 8)
	r2.add_child(_mk_btn("INCOLLA", _paste_answer))
	r2.add_child(_mk_btn("CONNETTI", _connect_answer))
	v.add_child(r2)
	return v


func _build_join_panel() -> VBoxContainer:
	var v := _mk_panel()
	v.add_child(_mk_label("1) incolla il codice dell'host:", 8))
	offer_in = _mk_edit(true)
	v.add_child(offer_in)
	var r1 := HBoxContainer.new()
	r1.add_theme_constant_override("separation", 8)
	r1.add_child(_mk_btn("INCOLLA", _paste_offer))
	r1.add_child(_mk_btn("GENERA RISPOSTA", _make_answer))
	v.add_child(r1)
	v.add_child(_mk_label("2) invia questa risposta all'host e attendi:", 8))
	answer_out = _mk_edit(false)
	v.add_child(answer_out)
	var r2 := HBoxContainer.new()
	r2.add_child(_mk_btn("COPIA LA RISPOSTA", _copy_answer))
	v.add_child(r2)
	return v
