extends Node

# ============================================================================
# NetworkManager - multiplayer P2P per 2 giocatori via WebRTC, senza server
# dedicati (autoload: NetworkManager). La connessione e' diretta e a bassa
# latenza; il server STUN pubblico serve solo a scoprire il proprio indirizzo.
#
# SIGNALING: offer, answer e candidati ICE sono impacchettati in UNA stringa
# JSON per lato, da scambiare a mano (copia/incolla, chat...) o tramite una
# futura API (per lo scambio "trickle" in tempo reale ci sono anche i segnali
# granulari local_sdp_created / local_ice_created).
#
# PREREQUISITO (solo build desktop): l'estensione GDExtension "webrtc-native"
# (github.com/godotengine/webrtc-native, release per Godot 4.x) scompattata
# nella cartella del progetto. Nell'export Web WebRTC e' fornito dal browser.
# Se manca, initialize() fallisce con errore chiaro ma il gioco parte lo stesso.
#
# FLUSSO DI CONNESSIONE:
#   Host:   NetworkManager.host_start()
#             -> segnale signaling_ready(json)   ==> invia il JSON all'ospite
#   Ospite: NetworkManager.guest_start(json_dell_host)
#             -> segnale signaling_ready(json)   ==> rimanda il JSON all'host
#   Host:   NetworkManager.host_finish(json_dell_ospite)
#   Quando i canali dati si aprono, multiplayer.peer_connected scatta su
#   entrambi i lati e qui viene rilanciato come match_connected.
#
# COME TESTARLO IN LOCALE (stessa macchina o LAN):
#   1) avvia due istanze del gioco (due volte l'exe, oppure `godot --path .`
#      in due terminali);
#   2) istanza A: chiama host_start() e copia il JSON di signaling_ready;
#   3) istanza B: chiama guest_start(<json di A>) e copia il JSON di risposta;
#   4) istanza A: chiama host_finish(<json di B>).
#   In locale bastano i candidati "host": si connette anche senza internet.
#   In attesa di una UI dedicata si puo' usare un pannellino di debug che
#   stampa/incolla le due stringhe.
#
# PREDISPOSIZIONE ROLLBACK NETCODE (motore da scrivere in rollback_engine.gd):
#   1. la simulazione avanza a tick fissi (60 Hz in _physics_process);
#   2. ogni tick il controller locale codifica l'input in una bitmask
#      (encode_input) e la passa a send_local_input(tick, bits): viene
#      bufferizzata e spedita via RPC UNRELIABLE con ridondanza (gli ultimi
#      INPUT_REDUNDANCY tick), cosi' i pacchetti persi non vanno ritrasmessi;
#   3. se l'input remoto del tick corrente non e' ancora arrivato, il motore
#      usa predicted_remote_input() (ripete l'ultimo noto) e simula comunque;
#   4. prima di simulare il tick T il motore chiama capture_state(T), che
#      salva lo snapshot restituito dalla callback save_state_cb;
#   5. quando arriva un input remoto per un tick passato diverso da quello
#      predetto, il motore chiama restore_state(tick) (che invoca
#      load_state_cb con lo snapshot) e risimula fino al presente.
#   REQUISITO: simulazione deterministica — niente randf() nel gameplay (o
#   seed condiviso), niente dipendenze da delta variabile o da Input diretto:
#   i Fighter devono ricevere SOLO il dizionario prodotto da decode_input().
# ============================================================================

# --- segnali di signaling (requisito 1) -------------------------------------
signal signaling_ready(payload_json: String)               # bundle SDP+ICE completo
signal local_sdp_created(type: String, sdp: String)        # per una futura API trickle
signal local_ice_created(media: String, index: int, name: String)

# --- segnali di stato della partita online ----------------------------------
signal match_connected(peer_id: int)      # canali aperti: si puo' iniziare
signal match_disconnected(peer_id: int)   # l'avversario e' caduto
signal connection_failed                  # handshake ICE fallito

# --- segnali per il rollback -------------------------------------------------
signal remote_input_received(tick: int, bits: int)

const HOST_ID := 1     # l'host e' sempre il player 1
const GUEST_ID := 2

# Server STUN pubblici gratuiti (Google): servono solo a scoprire il proprio
# indirizzo pubblico per l'handshake ICE. Piu' istanze = ridondanza se una
# e' irraggiungibile; bastano per la stragrande maggioranza dei NAT domestici.
const ICE_SERVERS := [
	{"urls": [
		"stun:stun.l.google.com:19302",
		"stun:stun1.l.google.com:19302",
		"stun:stun2.l.google.com:19302",
		"stun:stun3.l.google.com:19302",
		"stun:stun4.l.google.com:19302",
	]},
]

# Server TURN opzionale (relay del traffico): serve SOLO dietro firewall
# aziendali o NAT simmetrici molto restrittivi, dove il collegamento P2P
# diretto e' impossibile. Si ottiene gratis registrandosi ad es. su
# https://www.metered.ca/stun-turn (Open Relay) o https://xirsys.com;
# inserire qui le proprie credenziali e decommentare, insieme alla riga
# `servers.append(TURN_SERVER)` in _setup().
#const TURN_SERVER := {
#	"urls": [
#		"turn:standard.relay.metered.ca:80",
#		"turn:standard.relay.metered.ca:443",
#		"turn:standard.relay.metered.ca:443?transport=tcp",
#	],
#	"username": "IL_TUO_USERNAME",
#	"credential": "LA_TUA_PASSWORD",
#}

# bitmask input: stati "tenuti premuti"; i just-pressed si ricavano in
# decode_input confrontando col tick precedente (deterministico)
const B_LEFT := 1
const B_RIGHT := 2
const B_UP := 4
const B_DOWN := 8
const B_ATTACK := 16
const B_BLAST := 32
const B_BEAM := 64
const B_DASH := 128
const B_ROLL := 256
const B_GUARD := 512
const B_CHARGE := 1024

const INPUT_REDUNDANCY := 8   # ogni pacchetto ripete gli ultimi N tick
const MAX_SNAPSHOTS := 64     # ~1 s di storia a 60 Hz

# Su varie reti webrtc-native non raggiunge MAI GATHERING_STATE_COMPLETE
# (es. uno dei server STUN non risponde): senza un fallback l'host resterebbe
# per sempre su "genero il codice offerta...". Il bundle viene quindi emesso
# anche quando la raccolta si e' assestata (nessun candidato nuovo da
# GATHER_GRACE secondi) o al piu' tardi dopo GATHER_TIMEOUT.
const GATHER_GRACE := 1.5     # s senza candidati nuovi = raccolta considerata finita
const GATHER_TIMEOUT := 6.0   # tetto massimo di attesa dall'SDP locale
const CONNECT_TIMEOUT := 25.0 # dopo host_finish: se ICE non aggancia, e' fallita

# Mappe giocabili online: la simulazione dev'essere deterministica su entrambe
# le macchine (il netcode risimula il fighter remoto). Deserto e lago lo sono:
# il lago aggiunge solo fisica dell'acqua e stealth, entrambi funzione della
# sola posizione. La foresta NO (alberi abbattibili ed esche non stanno negli
# snapshot del MatchManager), quindi resta fuori.
const ONLINE_MAPS := ["desert", "lake"]

var rtc: WebRTCMultiplayerPeer
var pc: WebRTCPeerConnection
var is_host := false
# mappa della partita online: la sceglie l'HOST e viaggia dentro il
# codice-offerta; l'ospite la legge applicando il payload (_apply_remote_payload)
var map := "desert"

var _local_sdp := {}          # {"type": ..., "sdp": ...} in attesa del bundle
var _local_candidates: Array = []
var _signaling_sent := false
var _failed := false
var _gather_t := 0.0          # tempo trascorso da quando esiste l'SDP locale
var _last_cand_t := 0.0       # istante (su _gather_t) dell'ultimo candidato ICE
var _connect_t := -1.0        # >=0: conto alla rovescia dell'handshake ICE (lato host)
var _connected := false

# buffer di input per il rollback: tick -> bitmask
var local_inputs := {}
var remote_inputs := {}
var latest_remote_tick := -1

# hook di salvataggio/ripristino registrati dal gioco (vedi register_rollback)
var save_state_cb := Callable()
var load_state_cb := Callable()
var snapshots := {}           # tick -> stato serializzato dal gioco


func _ready() -> void:
	# Segnali del MultiplayerAPI: peer_connected scatta quando i canali dati
	# WebRTC dell'avversario si aprono, peer_disconnected quando cadono.
	# game.gd non deve collegarsi a questi ma ai nostri match_connected /
	# match_disconnected, che aggiungono la pulizia dello stato di rete.
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)


func _process(dt: float) -> void:
	if pc == null:
		return
	# rtc (e quindi pc) viene gia' pollato ogni frame dal MultiplayerAPI;
	# qui controlliamo solo l'avanzamento del signaling.
	# Il bundle e' pronto quando abbiamo l'SDP locale e la raccolta dei
	# candidati ICE e' terminata: lo emettiamo una volta sola. COMPLETE e' la
	# via maestra, ma se non arriva (vedi GATHER_GRACE) si emette lo stesso
	# con i candidati raccolti fin qui: bastano per la quasi totalita' dei NAT.
	if not _signaling_sent and not _local_sdp.is_empty():
		_gather_t += dt
		var done: bool = pc.get_gathering_state() == WebRTCPeerConnection.GATHERING_STATE_COMPLETE
		if not done and not _local_candidates.is_empty() and _gather_t - _last_cand_t >= GATHER_GRACE:
			done = true
		if not done and _gather_t >= GATHER_TIMEOUT:
			done = true  # anche senza candidati: meglio un errore chiaro che l'attesa infinita
		if done:
			_signaling_sent = true
			signaling_ready.emit(get_local_payload())
	if not _failed and pc.get_connection_state() == WebRTCPeerConnection.STATE_FAILED:
		_failed = true
		connection_failed.emit()
	# dopo host_finish l'handshake ICE deve chiudersi in pochi secondi: se
	# resta appeso in CONNECTING (NAT troppo restrittivo) segnaliamo il
	# fallimento invece di lasciare l'host in attesa per sempre
	if _connect_t >= 0.0 and not _connected and not _failed:
		_connect_t += dt
		if _connect_t >= CONNECT_TIMEOUT:
			_failed = true
			connection_failed.emit()


# --- avvio della connessione (requisito 1) -----------------------------------

# Lato host: prepara la mesh e genera l'offer; il JSON da inviare all'ospite
# arrivera' col segnale signaling_ready.
func host_start() -> Error:
	var err := _setup(HOST_ID, GUEST_ID)
	if err != OK:
		return err
	is_host = true
	return pc.create_offer()


# Lato ospite: applica l'offer ricevuto; Godot genera da solo l'answer
# (session_description_created) e signaling_ready emettera' il JSON di risposta.
func guest_start(offer_json: String) -> Error:
	var err := _setup(GUEST_ID, HOST_ID)
	if err != OK:
		return err
	is_host = false
	return _apply_remote_payload(offer_json)


# Lato host, ultimo passo: applica l'answer dell'ospite.
func host_finish(answer_json: String) -> Error:
	var err := _apply_remote_payload(answer_json)
	if err == OK:
		_connect_t = 0.0  # da qui l'handshake ICE ha CONNECT_TIMEOUT secondi
	return err


func close() -> void:
	if rtc != null and multiplayer.multiplayer_peer == rtc:
		multiplayer.multiplayer_peer = null
	if rtc != null:
		rtc.close()
	if pc != null:
		pc.close()
	rtc = null
	pc = null
	_local_sdp = {}
	_local_candidates = []
	_signaling_sent = false
	_failed = false
	_gather_t = 0.0
	_last_cand_t = 0.0
	_connect_t = -1.0
	_connected = false
	local_inputs.clear()
	remote_inputs.clear()
	snapshots.clear()
	latest_remote_tick = -1


func is_online() -> bool:
	return rtc != null and not multiplayer.get_peers().is_empty()


# slot del giocatore locale nella partita (1 = host, 2 = ospite)
func local_player() -> int:
	return 1 if is_host else 2


func _setup(local_id: int, remote_id: int) -> Error:
	close()
	pc = WebRTCPeerConnection.new()
	var servers: Array = ICE_SERVERS.duplicate()
	# per reti molto restrittive: decommenta TURN_SERVER in cima al file e poi
	#servers.append(TURN_SERVER)
	var err := pc.initialize({"iceServers": servers})
	if err != OK:
		push_error("WebRTC non disponibile (errore %d): sulle build desktop serve l'estensione webrtc-native, vedi intestazione di network_manager.gd" % err)
		pc = null
		return err
	pc.session_description_created.connect(_on_local_sdp)
	pc.ice_candidate_created.connect(_on_local_ice)
	rtc = WebRTCMultiplayerPeer.new()
	err = rtc.create_mesh(local_id)
	if err != OK:
		return err
	err = rtc.add_peer(pc, remote_id)
	if err != OK:
		return err
	# da qui in poi il MultiplayerAPI polla rtc/pc a ogni frame e fara'
	# scattare peer_connected quando l'handshake si completa
	multiplayer.multiplayer_peer = rtc
	return OK


# --- scambio dei dati di signaling -------------------------------------------

func _on_local_sdp(type: String, sdp: String) -> void:
	pc.set_local_description(type, sdp)
	_local_sdp = {"type": type, "sdp": sdp}
	local_sdp_created.emit(type, sdp)


func _on_local_ice(media: String, index: int, name: String) -> void:
	_local_candidates.append({"media": media, "index": index, "name": name})
	_last_cand_t = _gather_t
	local_ice_created.emit(media, index, name)


# Bundle locale corrente (SDP + tutti i candidati ICE) come stringa JSON.
# E' lo stesso payload emesso da signaling_ready.
func get_local_payload() -> String:
	return JSON.stringify({
		"type": _local_sdp.get("type", ""),
		"sdp": _local_sdp.get("sdp", ""),
		"candidates": _local_candidates,
		"map": map,   # scelta dell'host: l'ospite carica la stessa arena
	})


func _apply_remote_payload(payload_json: String) -> Error:
	if pc == null:
		return ERR_UNCONFIGURED
	var data: Variant = JSON.parse_string(payload_json)
	if not (data is Dictionary) or not data.has("sdp") or String(data.get("sdp", "")).is_empty():
		push_error("Payload di signaling non valido")
		return ERR_INVALID_DATA
	# solo l'ospite eredita la mappa: e' l'host a sceglierla (nella sua risposta
	# l'ospite la rimanda indietro, ma l'host ignora il campo)
	if not is_host:
		var m := String(data.get("map", "desert"))
		map = m if m in ONLINE_MAPS else "desert"
	var err := pc.set_remote_description(String(data.get("type", "offer")), String(data["sdp"]))
	if err != OK:
		return err
	for c in data.get("candidates", []):
		pc.add_ice_candidate(String(c.get("media", "")), int(c.get("index", 0)), String(c.get("name", "")))
	return OK


func _on_peer_connected(id: int) -> void:
	_connected = true
	print("[net] peer connesso: %d (io sono il player %d)" % [id, local_player()])
	match_connected.emit(id)


func _on_peer_disconnected(id: int) -> void:
	print("[net] peer disconnesso: %d" % id)
	close()
	match_disconnected.emit(id)


# --- trasporto degli input (requisito 2: rete separata dagli input) -----------
# Il NetworkManager NON legge mai Input: riceve bitmask gia' codificate dal
# futuro controller di rete (net_controller.gd), che a sua volta fara':
#   var bits := NetworkManager.encode_input(stato_tenuto_delle_azioni)
#   NetworkManager.send_local_input(tick, bits)
# e per il fighter remoto leggera' get_remote_input()/predicted_remote_input()
# decodificando con decode_input(bits, bits_del_tick_prima).

# Registra l'input locale del tick e lo spedisce (unreliable + ridondanza).
func send_local_input(tick: int, bits: int) -> void:
	local_inputs[tick] = bits
	if not is_online():
		return
	var start := maxi(0, tick - INPUT_REDUNDANCY + 1)
	var window := PackedInt32Array()
	for t in range(start, tick + 1):
		window.append(local_inputs.get(t, 0))
	_rx_inputs.rpc(start, window)


# Unreliable: un pacchetto perso non blocca nulla, i tick mancanti arrivano
# con la finestra ridondante del pacchetto successivo.
@rpc("any_peer", "call_remote", "unreliable")
func _rx_inputs(start_tick: int, window: PackedInt32Array) -> void:
	for i in range(window.size()):
		var t := start_tick + i
		if not remote_inputs.has(t):
			remote_inputs[t] = window[i]
			latest_remote_tick = maxi(latest_remote_tick, t)
			remote_input_received.emit(t, window[i])


func has_remote_input(tick: int) -> bool:
	return remote_inputs.has(tick)


# -1 se l'input di quel tick non e' (ancora) arrivato
func get_remote_input(tick: int) -> int:
	return remote_inputs.get(tick, -1)


# Predizione standard del rollback: ripeti l'ultimo input remoto conosciuto.
func predicted_remote_input(tick: int) -> int:
	for t in range(mini(tick, latest_remote_tick), -1, -1):
		if remote_inputs.has(t):
			return remote_inputs[t]
	return 0


# Da chiamare quando un tick e' confermato su entrambi i lati: libera i buffer.
func trim_before(tick: int) -> void:
	for d in [local_inputs, remote_inputs, snapshots]:
		for t in d.keys():
			if t < tick:
				d.erase(t)


# --- salvataggio/ripristino dello stato (requisito 2) --------------------------
# Il gioco registra due callback:
#   save_cb: func(tick: int) -> Variant     serializza TUTTO lo stato della
#            simulazione (posizioni, hp, ki, stati, timer, proiettili...)
#   load_cb: func(tick: int, stato) -> void lo ripristina esattamente
# Esempio in game.gd:
#   NetworkManager.register_rollback(_save_sim_state, _load_sim_state)
func register_rollback(save_cb: Callable, load_cb: Callable) -> void:
	save_state_cb = save_cb
	load_state_cb = load_cb


# Fotografa lo stato del tick corrente (chiamata dal motore prima di simulare).
func capture_state(tick: int) -> void:
	if not save_state_cb.is_valid():
		return
	snapshots[tick] = save_state_cb.call(tick)
	if snapshots.size() > MAX_SNAPSHOTS:
		snapshots.erase(snapshots.keys().min())


# Torna allo snapshot del tick indicato; false se non e' disponibile.
func restore_state(tick: int) -> bool:
	if not load_state_cb.is_valid() or not snapshots.has(tick):
		return false
	load_state_cb.call(tick, snapshots[tick])
	return true


# --- codifica deterministica degli input ---------------------------------------

# `held` usa le stesse chiavi del dizionario dei controller, ma con TUTTI i
# tasti come "tenuti premuti" (Input.is_action_pressed), mai just_pressed.
static func encode_input(held: Dictionary) -> int:
	var bits := 0
	var mv: Vector2 = held.get("move", Vector2.ZERO)
	if mv.x < -0.3:
		bits |= B_LEFT
	if mv.x > 0.3:
		bits |= B_RIGHT
	if mv.y < -0.3:
		bits |= B_UP
	if mv.y > 0.3:
		bits |= B_DOWN
	if held.get("attack", false):
		bits |= B_ATTACK
	if held.get("blast", false):
		bits |= B_BLAST
	if held.get("beam", false):
		bits |= B_BEAM
	if held.get("dash", false):
		bits |= B_DASH
	if held.get("roll", false):
		bits |= B_ROLL
	if held.get("guard", false):
		bits |= B_GUARD
	if held.get("charge", false):
		bits |= B_CHARGE
	return bits


# Ricostruisce il dizionario nel formato esatto atteso da fighter.gd
# (vedi human_controller.gd). I just-pressed sono calcolati dal fronte di
# salita rispetto al tick precedente: identico su entrambe le macchine.
# Il movimento e' quantizzato a -1/0/1: niente analogico, per determinismo.
static func decode_input(bits: int, prev_bits: int) -> Dictionary:
	return {
		"move": Vector2(_axis(bits, B_LEFT, B_RIGHT), _axis(bits, B_UP, B_DOWN)),
		"attack": _pressed(bits, prev_bits, B_ATTACK),
		"blast": _pressed(bits, prev_bits, B_BLAST),
		"beam": _pressed(bits, prev_bits, B_BEAM),
		"dash": _pressed(bits, prev_bits, B_DASH),
		"roll": _pressed(bits, prev_bits, B_ROLL),
		"guard": (bits & B_GUARD) != 0,
		"charge": (bits & B_CHARGE) != 0,
		"attack_held": (bits & B_ATTACK) != 0,  # per la fuga dalla combo (J tenuto)
	}


static func _axis(bits: int, neg: int, pos: int) -> float:
	return (1.0 if bits & pos else 0.0) - (1.0 if bits & neg else 0.0)


static func _pressed(bits: int, prev_bits: int, mask: int) -> bool:
	return (bits & mask) != 0 and (prev_bits & mask) == 0
