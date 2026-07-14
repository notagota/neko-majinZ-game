class_name MatchManager
extends Node

# ============================================================================
# Direttore della partita ONLINE con NETCODE PREDITTIVO (creato da game.gd
# quando NetworkManager.is_online()). Regge la perdita di pacchetti delle RPC
# unreliable senza mai bloccare o rallentare il gioco:
#
#  1. INPUT BUFFERING - ogni frame fisico ha un numero (tick); gli input
#     locali e quelli remoti vengono memorizzati in dizionari indicizzati
#     per tick, cosi' arrivi in ritardo/disordine si sistemano da soli.
#  2. PREDIZIONE LINEARE - se l'input remoto del tick corrente non e' ancora
#     arrivato, si assume che l'avversario stia RIPETENDO l'ultimo input
#     valido ricevuto: il gioco non aspetta mai la rete.
#  3. RIDONDANZA - ogni pacchetto contiene gli input degli ultimi
#     REDUNDANCY (5) frame: un pacchetto perso e' coperto dai successivi
#     senza ritrasmissioni ne' stalli.
#  4. RICONCILIAZIONE - quando un pacchetto rivela che una predizione
#     passata era sbagliata, il fighter remoto viene riportato allo
#     snapshot precedente all'errore e risimulato fino a oggi con gli
#     input veri ("dove dovrebbe essere"), in modalita' silenziosa:
#     game.reconciling e sfx.muted sopprimono danni, effetti e suoni doppi.
#  5. SINCRONIZZAZIONE DEI TICK - all'avvio i due lati fanno un handshake
#     (ping finche' l'altro MatchManager esiste, poi START affidabile
#     dall'host): l'ospite parte gia' avanti di mezzo RTT in tick, cosi' i
#     due contatori corrono allineati al tempo reale. Senza questo, ogni
#     tick di scarto tra i clock diventava LAG PERCEPITO COSTANTE (~17 ms
#     l'uno) o riconciliazioni continue. Il contatore non si ferma mai
#     durante i round, quindi l'allineamento non deriva. Il ping resta
#     misurato per tutta la partita e mostrato nella HUD.
#
# DOVE STA LA LOGICA DI MOVIMENTO: NON qui. Il movimento resta interamente
# in fighter.gd (_tick_move e gli altri _tick_*): questo script decide solo
# QUALE input alimentare a fighter.execute_inputs() e QUANDO risimulare.
# Se aggiungi nuove mosse, basta che dipendano solo dallo stato del Fighter
# e dall'input (niente Input.* o randf() nel gameplay) e il netcode le
# gestisce gratis; aggiungi i nuovi campi di stato a _snap_remote/_restore.
#
# PERFORMANCE (_physics_process a 60 Hz): niente allocazioni superflue
# (bitmask int al posto di dizionari sul filo, PackedInt32Array per la
# finestra), buffer a finestra fissa con potatura O(1) per frame, replay
# raro e lungo al massimo HISTORY tick.
# ============================================================================

const NetC := preload("res://scripts/net_controller.gd")

const REDUNDANCY := 10   # input degli ultimi 10 frame in ogni pacchetto (~166 ms
						 # di packet loss coperti; il pacchetto resta minuscolo)
const HISTORY := 120     # storia tenuta in memoria: 2 s a 60 Hz
const TICK_DT := 1.0 / 60.0
const START_TIMEOUT := 6.0   # se l'handshake non arriva, si parte comunque

var game: Node2D
var local_slot := 1          # 1 = host/P1, 2 = ospite/P2
var remote_peer := 2         # peer id dell'avversario (= autorita' del suo fighter)
var local_f: Fighter
var remote_f: Fighter

# --- input buffer indicizzati per tick (numero di frame fisico) ---
var tick := 0                # frame corrente della simulazione locale
var local_inputs := {}       # tick -> bitmask input locale
var remote_inputs := {}      # tick -> bitmask REALE ricevuta dall'avversario
var used_inputs := {}        # tick -> bitmask APPLICATA al fighter remoto (reale o predetta)
var last_remote_bits := 0    # ultimo input reale conosciuto: base della predizione
var latest_remote_tick := 0  # tick piu' recente ricevuto

# --- storia per la riconciliazione ---
var remote_snaps := {}       # tick -> stato del fighter remoto PRIMA di quel tick
var tick_meta := {}          # tick -> {dt, froze}: come la partita ha simulato quel frame

var corrections := 0         # riconciliazioni eseguite (diagnostica)
var rx_logged := false
var probe := false           # --netprobe: input sintetici per collaudare predizione/correzioni

# --- avvio sincronizzato e misura della latenza ---
var started := false         # handshake completato: la simulazione corre
var start_wait := 0.0        # da quanto aspettiamo l'handshake (per il fallback)
var hello_t := 0.0           # timer di reinvio di ping/handshake
var remote_alive := false    # il MatchManager dell'avversario esiste e risponde
var ping_ms := 0.0           # RTT levigato in millisecondi (mostrato dalla HUD)
var barrier_tick := 0        # ultimo tick fuori da "fight": mai riconciliare prima
							 # (nei cambi round i fighter vengono riposizionati)


func _ready() -> void:
	game = get_parent()
	# priorita' negativa: input catturati e applicati PRIMA che game.gd
	# (priorita' 0) ticki i lottatori in questo stesso frame fisico
	process_physics_priority = -10
	# convenzione: peer id di WebRTCMultiplayerPeer == slot del giocatore
	# (host = 1, ospite = 2), quindi get_unique_id() e' il nostro slot
	local_slot = multiplayer.get_unique_id()
	remote_peer = 2 if local_slot == 1 else 1
	# autorita' di rete sui personaggi: ognuno comanda solo il proprio
	game.p1.set_multiplayer_authority(NetworkManager.HOST_ID)
	game.p2.set_multiplayer_authority(NetworkManager.GUEST_ID)
	local_f = game.p1 if local_slot == 1 else game.p2
	remote_f = game.p2 if local_slot == 1 else game.p1
	# entrambi i lottatori diventano passivi: i comandi arrivano solo da
	# execute_inputs(), mai da Input
	game.p1.controller = NetC.new()
	game.p2.controller = NetC.new()
	game.p2.is_cpu = false
	game.p1.fighter_name = "NEKO MAJIN Z" + (" (TU)" if local_slot == 1 else "")
	game.p2.fighter_name = "NEKO MAJIN 2" + (" (TU)" if local_slot == 2 else "")
	NetworkManager.match_disconnected.connect(_on_opponent_left)
	probe = "--netprobe" in OS.get_cmdline_user_args()


func _physics_process(dt: float) -> void:
	if not NetworkManager.is_online():
		return
	if not started:
		# HANDSHAKE DI AVVIO: ping ripetuto finche' il MatchManager remoto
		# non risponde (la scena puo' caricarsi in momenti diversi sulle due
		# macchine), poi l'host manda lo START affidabile e parte dal tick 0;
		# l'ospite partira' avanti di mezzo RTT (vedi _net_start). Cosi' i due
		# contatori corrono allineati e nessuno "vive nel passato" dell'altro.
		start_wait += dt
		hello_t -= dt
		if hello_t <= 0.0:
			hello_t = 0.2
			_net_ping.rpc(Time.get_ticks_msec())
		if local_slot == 1 and remote_alive and (ping_ms > 0.0 or start_wait >= 2.0):
			_net_start.rpc(ping_ms)
			_begin(0)
		elif start_wait >= START_TIMEOUT:
			_begin(0)  # l'altro lato non risponde: meglio partire che bloccare
		return
	# ping periodico anche in partita: alimenta la HUD e la diagnostica
	hello_t -= dt
	if hello_t <= 0.0:
		hello_t = 1.0
		_net_ping.rpc(Time.get_ticks_msec())
	# La cinematica falso 3D viene risolta deterministicamente su entrambi i
	# peer. Durante i Tween fermiamo anche il clock del rollback: nessuno dei
	# due lati deve accumulare input o risimulare il Fighter nascosto dallo
	# sprite cinematografico. Ping e rilevamento disconnessione restano attivi.
	if game.desert_perspective != null and game.desert_perspective.transition_active:
		return
	tick += 1
	if game.phase != "fight":
		barrier_tick = tick  # storia precedente non confrontabile (round nuovi ecc.)

	# ------ 1) input locale: cattura, memorizza nel buffer, applica subito ------
	# (il lottatore locale non aspetta MAI la rete: zero lag aggiunto)
	var bits := _probe_bits(tick) if probe else _poll_local_bits()
	local_inputs[tick] = bits
	local_f.execute_inputs(NetworkManager.decode_input(bits, local_inputs.get(tick - 1, 0)))

	# ------ 2) invio con ridondanza: gli ultimi REDUNDANCY tick in un colpo ------
	# pacchetto minuscolo (un int di partenza + 10 int32): se si perde, il
	# successivo ricopre gli stessi tick e nessuno se ne accorge
	var start := maxi(1, tick - REDUNDANCY + 1)
	var window := PackedInt32Array()
	for t in range(start, tick + 1):
		window.append(local_inputs.get(t, 0))
	_rx_inputs.rpc(start, window)

	# ------ 3) fighter remoto: snapshot pre-tick, poi input reale o predetto ------
	# lo snapshot fotografa lo stato PRIMA di consumare l'input del tick:
	# per correggere il tick T bastera' ripartire da snap[T] e risimulare
	remote_snaps[tick] = _snap_remote()
	tick_meta[tick] = {"dt": TICK_DT * game.slow, "froze": game.freeze_t > 0.0}
	var rbits: int
	if remote_inputs.has(tick):
		rbits = remote_inputs[tick]   # gia' arrivato: nessuna predizione
	else:
		rbits = last_remote_bits      # PREDIZIONE LINEARE: ripeti l'ultimo valido
	used_inputs[tick] = rbits
	remote_f.execute_inputs(NetworkManager.decode_input(rbits, used_inputs.get(tick - 1, 0)))
	# (da qui in poi game.gd tichera' i fighter: la logica di movimento vive la')

	# ------ 4) potatura O(1): un solo tick vecchio rimosso per frame ------
	var old := tick - HISTORY
	local_inputs.erase(old)
	remote_inputs.erase(old)
	used_inputs.erase(old)
	remote_snaps.erase(old)
	tick_meta.erase(old)

	if probe and tick % 300 == 0:
		print("[net] riconciliazioni: %d (tick %d, ping %d ms, offset %+d tick)"
			% [corrections, tick, int(ping_ms), latest_remote_tick - tick])


# ============================================================================
# HANDSHAKE DI AVVIO + MISURA DEL PING (RTT)
# ============================================================================
func _begin(t0: int) -> void:
	started = true
	tick = t0
	barrier_tick = t0
	print("[net] simulazione avviata dal tick %d (ping %d ms)" % [t0, int(ping_ms)])


# Unreliable ma reinviato a intervallo fisso: fa da "hello" dell'handshake e
# da sonda del ping per tutta la partita.
@rpc("any_peer", "call_remote", "unreliable")
func _net_ping(ms: int) -> void:
	if multiplayer.get_remote_sender_id() != remote_peer:
		return
	remote_alive = true
	_net_pong.rpc(ms)


@rpc("any_peer", "call_remote", "unreliable")
func _net_pong(ms: int) -> void:
	if multiplayer.get_remote_sender_id() != remote_peer:
		return
	remote_alive = true
	var rtt := float(Time.get_ticks_msec() - ms)
	ping_ms = rtt if ping_ms <= 0.0 else lerpf(ping_ms, rtt, 0.2)


# Reliable: l'host lo invia una volta sola quando sa che l'altro lato esiste.
# L'ospite compensa il viaggio del messaggio partendo avanti di mezzo RTT.
@rpc("any_peer", "call_remote", "reliable")
func _net_start(host_rtt_ms: float) -> void:
	if multiplayer.get_remote_sender_id() != remote_peer or started:
		return
	var rtt := maxf(ping_ms, host_rtt_ms)
	_begin(int(roundf(rtt * 0.5 / (TICK_DT * 1000.0))))


# ============================================================================
# RICEZIONE - arriva la finestra ridondante dell'avversario: si integrano i
# buchi e, se una predizione passata si rivela sbagliata, si riconcilia.
# ============================================================================
@rpc("any_peer", "call_remote", "unreliable")
func _rx_inputs(start_tick: int, window: PackedInt32Array) -> void:
	# anti-imbroglio: accetta input solo dal peer proprietario del fighter remoto
	if multiplayer.get_remote_sender_id() != remote_peer:
		return
	if not rx_logged:
		rx_logged = true
		print("[net] input remoti attivi (slot %d)" % remote_peer)
	var first_bad := -1
	for i in range(window.size()):
		var t := start_tick + i
		if remote_inputs.has(t):
			continue  # gia' noto grazie alla ridondanza di un pacchetto precedente
		remote_inputs[t] = window[i]
		# tick gia' simulato con un input diverso da quello vero? (i tick
		# prima della barriera sono di un "mondo" gia' riposizionato: si ignorano)
		if t <= tick and t > barrier_tick and first_bad < 0 \
				and used_inputs.get(t, window[i]) != window[i]:
			first_bad = t
	# la predizione futura riparte sempre dall'input reale piu' recente
	var newest := start_tick + window.size() - 1
	if newest > latest_remote_tick:
		latest_remote_tick = newest
		last_remote_bits = window[window.size() - 1]
	# RICONCILIAZIONE: solo in combattimento (nei cambi round i fighter
	# vengono riposizionati da _start_round e la storia non e' confrontabile)
	if first_bad >= 0 and game.phase == "fight":
		_reconcile(first_bad)


# Riporta il fighter remoto allo stato precedente al primo tick mispredetto e
# lo risimula fino a oggi con gli input veri (o di nuovo predetti dove ancora
# mancano): la "correzione immediata" che lo posiziona dove dovrebbe essere.
func _reconcile(from_tick: int) -> void:
	var snap: Dictionary = remote_snaps.get(from_tick, {})
	if snap.is_empty():
		return  # errore piu' vecchio della storia conservata: lascia perdere
	corrections += 1
	_restore_remote(snap)
	# replay silenzioso: il mondo (danni, proiettili, effetti, suoni, scosse)
	# e' gia' stato prodotto dalla simulazione originale e non va duplicato
	game.reconciling = true
	game.sfx.muted = true
	for rt in range(from_tick, tick + 1):
		remote_snaps[rt] = _snap_remote()  # la storia ora segue il ramo corretto
		var rbits: int = remote_inputs[rt] if remote_inputs.has(rt) else last_remote_bits
		used_inputs[rt] = rbits
		remote_f.execute_inputs(NetworkManager.decode_input(rbits, used_inputs.get(rt - 1, 0)))
		# risimula il frame con lo stesso passo del frame originale (slow-mo
		# compreso); nei frame di hitstop il gioco non aveva tickato nessuno
		var meta: Dictionary = tick_meta.get(rt, {"dt": TICK_DT, "froze": false})
		if not meta.froze:
			remote_f.tick(meta.dt)
	game.sfx.muted = false
	game.reconciling = false


# ============================================================================
# Snapshot dello stato del fighter remoto. NON si salvano/ripristinano
# hp/hp_lag/combo: i danni li applica sempre la simulazione originale (i
# colpi sono spenti nel replay) e non devono mai essere annullati.
# ============================================================================
func _snap_remote() -> Dictionary:
	return {
		"pos": remote_f.position, "vel": remote_f.vel, "facing": remote_f.facing,
		"state": remote_f.state, "st": remote_f.st, "invuln": remote_f.invuln,
		"blast_cd": remote_f.blast_cd, "roll_cd": remote_f.roll_cd,
		"guard_stun": remote_f.guard_stun, "hurt_t": remote_f.hurt_t,
		"attack_stage": remote_f.attack_stage, "attack_buf": remote_f.attack_buf,
		"stage_hit": remote_f.stage_hit, "did_spawn": remote_f.did_spawn,
		"dash_dir": remote_f.dash_dir, "after_t": remote_f.after_t,
		"ko_rest": remote_f.ko_rest, "in_water": remote_f.in_water,
		"ki": remote_f.ki, "aura": remote_f.aura.visible, "net_cmd": remote_f.net_cmd,
	}


func _restore_remote(s: Dictionary) -> void:
	remote_f.position = s.pos
	remote_f.vel = s.vel
	remote_f.facing = s.facing
	remote_f.state = s.state
	remote_f.st = s.st
	remote_f.invuln = s.invuln
	remote_f.blast_cd = s.blast_cd
	remote_f.roll_cd = s.roll_cd
	remote_f.guard_stun = s.guard_stun
	remote_f.hurt_t = s.hurt_t
	remote_f.attack_stage = s.attack_stage
	remote_f.attack_buf = s.attack_buf
	remote_f.stage_hit = s.stage_hit
	remote_f.did_spawn = s.did_spawn
	remote_f.dash_dir = s.dash_dir
	remote_f.after_t = s.after_t
	remote_f.ko_rest = s.ko_rest
	remote_f.in_water = s.in_water
	remote_f.ki = s.ki
	remote_f.aura.visible = s.aura
	remote_f.net_cmd = s.net_cmd


# --- input locale -----------------------------------------------------------

# Bitmask costruita direttamente dalle azioni (niente dizionari temporanei):
# SOLO stati "tenuti"; i just-pressed li ricava decode_input dal tick prima.
func _poll_local_bits() -> int:
	var bits := 0
	if Input.is_action_pressed("p_left"):
		bits |= NetworkManager.B_LEFT
	if Input.is_action_pressed("p_right"):
		bits |= NetworkManager.B_RIGHT
	if Input.is_action_pressed("p_up"):
		bits |= NetworkManager.B_UP
	if Input.is_action_pressed("p_down"):
		bits |= NetworkManager.B_DOWN
	if Input.is_action_pressed("p_attack"):
		bits |= NetworkManager.B_ATTACK
	if Input.is_action_pressed("p_blast"):
		bits |= NetworkManager.B_BLAST
	if Input.is_action_pressed("p_beam"):
		bits |= NetworkManager.B_BEAM
	if Input.is_action_pressed("p_dash"):
		bits |= NetworkManager.B_DASH
	if Input.is_action_pressed("p_roll"):
		bits |= NetworkManager.B_ROLL
	if Input.is_action_pressed("p_guard"):
		bits |= NetworkManager.B_GUARD
	if Input.is_action_pressed("p_charge"):
		bits |= NetworkManager.B_CHARGE
	return bits


# Collaudo (--netprobe): direzione che si inverte ogni 20 tick + attacchi
# periodici. Ogni inversione produce una mispredizione sull'altra macchina,
# cosi' il contatore di riconciliazioni deve crescere.
func _probe_bits(t: int) -> int:
	var b := NetworkManager.B_RIGHT if ((t / 20) + local_slot) % 2 == 0 else NetworkManager.B_LEFT
	if t % 50 < 2:
		b |= NetworkManager.B_ATTACK
	return b


func _on_opponent_left(_id: int) -> void:
	game.net_opponent_left()
