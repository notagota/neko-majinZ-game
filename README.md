# Neko Majin Z — Supersonic Clash

Picchiaduro 2D in stile **Dragon Ball FighterZ / DBZ Supersonic Warriors 2**, realizzato con
**Godot 4.6.3**. Il personaggio è Z (Neko Majin Z) con gli sprite originali del gioco DS
*Dragon Ball Z: Supersonic Warriors 2* (file `Z.png`, rip di Grim — spritedatabase.net).

Si combatte contro una CPU (Neko Majin giallo, palette swap generata via script) in un match
al meglio dei 3 round, con **volo libero** in tutta l'arena e **attacchi energetici**.

All'avvio un **menù** (con musica in loop) permette di scegliere tra:

- **COMBATTIMENTO 1v1** — match al meglio dei 3 round contro la CPU;
- **ALLENAMENTO** — bersaglio fermo, niente timer né round, HP e ki di entrambi si
  rigenerano poco dopo ogni scambio: perfetto per provare le mosse;
- **ONLINE 1v1** — sfida un'altra persona in P2P via WebRTC, senza server dedicati
  (vedi la sezione *Online 1v1*).

Scelta la modalità, una seconda schermata permette di **scegliere la mappa**:

- **DESERTO ROCCIOSO** — l'arena classica tra le mesas. Il raggio caricato del Player
  o dell'avversario che colpisce nella prima prospettiva scaglia la vittima contro la
  `mesa_1.png` lontana usando il relativo sprite `z1|z2/hurt2_0.png`:
  scala, posizione, camera e due composizioni `Node2D` dello stage vengono interpolate
  via Tween, senza asset o nodi 3D. Dopo l'impatto si passa a una seconda arena laterale,
  con l'attaccante a sinistra e `mesa_1.png` come muro destro; in questa fase torna il
  volo verticale con W/S. Per 3 secondi effettivi dopo il recupero la vittima — Player,
  CPU o secondo giocatore online — ha entrambi gli assi invertiti e tutti gli attacchi
  bloccati. Il cambio si azzera a ogni round;
  appena la vittima si riprende entra nello sfondo un **dinosauro interattivo**, più
  grande dei lottatori. Usa `dinosaur_00..06` per l'ingresso, `07..09` per un attacco
  telegrafato ogni 2 secondi, `27..30` per vagare orizzontalmente (specchiati andando a
  destra) e `14..20` per fuggire risentito. Può essere colpito soltanto durante il suo
  attacco; il colpo ambientale può essere schivato uscendo dal punto segnalato o parato;
- **LAGO DELLA COSTA** — una spiaggia (sfondo rippato da `sshaohmarubg.gif`): la costa
  rocciosa a sinistra **scende a gradoni dolci** dentro un **lago profondo** che occupa
  tutto il lato destro, con il **fondale visibile** attraverso l'acqua. Chi si immerge
  **sparisce completamente dalla vista** e **non può essere rilevato** dall'avversario,
  a meno che anche quest'ultimo non entri in acqua: la CPU perde il bersaglio ("!!"),
  smette di attaccare e pattuglia l'ultima posizione nota; sfere di ki e scatti smettono
  di puntarti. In acqua ci si muove più lenti, da fermi si galleggia verso l'alto,
  i colpi subiti affondano piano (attrito), e immergersi/riemergere produce splash e
  bollicine. Le **sfere di ki attraversano la superficie** (in entrambe le direzioni)
  sollevando uno schizzo: anche chi è nascosto sott'acqua **si tradisce sparando**.
  I gradoni della costa sono rivestiti con la texture della spiaggia, sfumata da un
  gradino all'altro.
- **FORESTA DI SEQUOIE** — la mappa **più larga** (arena ±1800 invece di ±1150): un bosco
  vero, con **dieci sequoie giganti interattive**, e il **soffitto di volo molto più alto**
  delle altre mappe: salendo si bucano le chiome e si duella **sopra la foresta**, tra cielo,
  nuvole e una cresta di conifere all'orizzonte. Accanto a un tronco — **a qualsiasi quota**,
  anche in volo a mezz'altezza dell'albero — **SPAZIO ti nasconde dietro l'albero**: passi
  dietro al fusto (che si vela per non perderti di vista) ed **esci dal radar** — scatto
  homing e sfere a ricerca non ti puntano più e la CPU perde il bersaglio.
  **INGANNO**: sparendo lasci indietro un'**immagine-esca** di com'eri un attimo prima, cioè
  dove l'avversario ti ha visto per l'ultima volta. L'esca **inganna davvero**: la CPU le vola
  incontro e la prende a pugni, e anche scatto homing e sfere di ki puntano lei al posto tuo.
  Chi la colpisce la fa svanire in uno sbuffo (e capisce di essere stato beffato), poi si
  insospettisce e va a **prendere a legnate il tronco** dove sei sparito.
  Le sequoie **si possono abbattere**, ma sono **molto robuste** (500 PV: servono una
  quindicina di combo piene o una decina di raggi) — quando il fusto cede, si spezza e cade, e
  chi ci si nascondeva dietro viene **scoperto all'istante**. Basta muoversi, attaccare o
  ripremere SPAZIO per uscire; gli alberi abbattuti **ricrescono a ogni round**.

Nel menù (titolo con logo in stile Dragon Ball): W/S per scegliere, INVIO o J per
confermare, ESC per tornare indietro; l'ultima voce regola il **volume** (A/D, INVIO = muto).
In gioco, **ESC** riporta al menù, **1** mette in pausa, **2/3** abbassano/alzano il volume.

## Come si avvia

Eseguibile standalone (da inviare ad amici): `dist/NekoMajinZ.exe` **insieme a**
`dist/libwebrtc_native.windows.template_release.x86_64.dll` — il gioco è tutto incorporato
nell'exe, ma la DLL (estensione GDExtension, che l'export copia accanto all'eseguibile)
serve per l'**ONLINE 1v1** e deve restare nella stessa cartella. Lo zip delle release le
contiene entrambe: **estrarre tutto**, non solo l'exe.

Dal progetto:

```
"C:\Users\ricca\Godot_v4.6.3-stable_mono_win64\Godot_v4.6.3-stable_mono_win64.exe" --path "C:\Users\ricca\NekoMajin_Game"
```

oppure aprire la cartella come progetto nell'editor Godot e premere F5.

## Comandi (tastiera)

| Tasto | Azione |
|---|---|
| **WASD / frecce** | Movimento e volo libero (in aria si fluttua, stile SSW2); atterrando si esegue una breve animazione di atterraggio |
| **J** | Combo corpo a corpo (J, J, J: pugno → pugno forte → spinta a due palmi che lancia) |
| **J (tieni premuto mentre subisci una combo)** | **Fuga**: dopo 3 colpi subiti di fila, uno scoppio di ki spezza la combo, respinge l'aggressore vicino e ti lascia **invulnerabile per ~2 secondi** (anche la CPU a volte lo usa) |
| **K** | Sfera di ki (costa 15 ki, leggera ricerca del bersaglio) |
| **L** | Raggio energetico (costa 200 ki = 2 tacche, danno enorme): animazione di carica in 8 pose, poi il raggio si estende e colpisce con la punta, con pioggia di scintille sull'impatto |
| **I** | Scatto homing verso l'avversario (costa 25 ki, colpisce al contatto) |
| **U** | Attacco palla rotolante (gratis, con ricarica) |
| **SPAZIO** | Parata (riduce il danno all'80%) — **nella foresta**, accanto a una sequoia (a terra **o in volo**, lungo tutto il fusto): ti **nascondi dietro il tronco** lasciando un'**immagine-esca** al posto tuo (ripremi o muoviti per uscire) |
| **H** (tieni premuto) | Carica ki con aura |
| **R** | Riavvia il match — **1** pausa — **INVIO** rivincita a fine match |
| **ESC** | Torna al menù — **2/3** volume giù/su (muto a zero) |

Supporto gamepad: levetta/croce = movimento, A = combo, X = sfera, Y = raggio,
B = palla, RB = scatto, LB = parata, grilletto destro = carica ki, Start = pausa,
Back/Select = menù.

## Meccaniche

- HP 300, ki 300 (3 tacche). Il ki si rigenera lentamente, si guadagna coi colpi e si carica con H.
- Round da 99 secondi; allo scadere vince chi ha più HP. Vince il match chi conquista 2 round.
- Hitstop, slow-motion sul KO, scossa della camera, contatore combo, barra HP con danno ritardato.
- **Impact frame in stile anime**: i flash d'impatto (`burst`) e le linee di velocità (`lines`)
  si espandono a coprire l'intera scena (1440×810) **solo sui colpi pesanti**: combo che
  lancia, impatto del raggio, KO e fuga dalla combo.
- **Musiche chiptune di battaglia**, una per mappa: incalzante in La minore (160 BPM) nel
  deserto, arpeggi con eco in Re minore (140 BPM) sul lago, riff che si arrampicano in Mi
  minore (150 BPM) nella foresta; in loop per tutto il match.
- **Stealth per mappa**: sott'acqua nel lago, dietro le sequoie nella foresta. In entrambi
  i casi chi è coperto esce dal gruppo `targetable`, cioè sparisce da homing, sfere a
  ricerca e "sensori" della CPU (che passa a cercarti sull'ultima posizione nota).
  Nella foresta si aggiunge l'**immagine-esca** (`decoy.gd`): un falso bersaglio che dura
  ~2,6 s e che l'avversario (CPU, scatto homing e sfere di ki) insegue e attacca al posto tuo.
- La camera inquadra entrambi i lottatori e zooma in/out dinamicamente (stile SSW2).
- La CPU vola, para, schiva i raggi, carica il ki, fa combo, scatti e sfere.

## Online 1v1 (P2P WebRTC)

Connessione **diretta tra i due giocatori** (WebRTC + `WebRTCMultiplayerPeer`), senza
server dedicati: serve solo scambiarsi due codici testuali (per chat/Discord/email).

1. Un giocatore sceglie **OSPITA (HOST)**: il gioco genera un **codice offerta** — COPIA
   e invialo all'avversario. Col pulsante **MAPPA** l'host sceglie l'arena della partita
   (**DESERTO ROCCIOSO** o **LAGO DELLA COSTA**): la scelta viaggia dentro il codice-offerta,
   quindi l'ospite carica la stessa mappa senza doversi accordare (cambiando mappa il codice
   viene rigenerato: invia sempre l'ultimo). La foresta resta fuori dall'online: alberi
   abbattibili ed esche non sono nello snapshot del netcode e potrebbero desincronizzarsi.
2. L'altro sceglie **PARTECIPA (JOIN)**, incolla il codice, preme **GENERA RISPOSTA** e
   rimanda il **codice risposta** all'host.
3. L'host incolla la risposta e preme **CONNETTI**: appena il collegamento si apre
   entrambi entrano nell'arena (host = P1). ESC abbandona la partita.

Note tecniche: l'host comanda P1 e l'ospite P2 (`set_multiplayer_authority`); ogni frame
l'input locale viene compresso in una bitmask e scambiato con RPC *unreliable*
(`match_manager.gd` → `fighter.execute_inputs()`); niente pausa/riavvio in online.
Il netcode è **predittivo**: gli input sono bufferizzati per numero di frame, ogni
pacchetto ripete gli ultimi 10 frame (ridondanza contro il packet loss), se l'input
dell'avversario non è ancora arrivato si assume che ripeta l'ultimo ricevuto e, quando
un pacchetto smentisce una predizione, il personaggio remoto viene riportato allo
snapshot del frame sbagliato e risimulato fino al presente (riconciliazione silenziosa:
niente danni/effetti/suoni doppi). Il gioco non si blocca mai in attesa della rete.
All'avvio della partita i due giochi fanno un **handshake di sincronizzazione**: i
contatori di frame partono allineati (l'ospite compensa il mezzo viaggio del messaggio
di start), così lo scarto tra i clock non diventa lag artificiale; il **ping** è
misurato di continuo e mostrato sotto il timer. Se la raccolta dei candidati ICE non
si conclude (succede su alcune reti), il codice-offerta viene emesso comunque dopo
pochi secondi con i candidati raccolti fin lì, e l'handshake dell'host ha un timeout
chiaro invece dell'attesa infinita. Richiede l'estensione `addons/webrtc_native` (inclusa, build
Windows x86_64; per altre piattaforme scaricare le librerie dalla release GitHub di
`godotengine/webrtc-native`). Il traffico passa in P2P; i server STUN pubblici di Google
(più istanze, per ridondanza) servono solo a scoprire il proprio indirizzo. In LAN funziona
anche senza internet. Dietro firewall aziendali o NAT simmetrici molto restrittivi il P2P
diretto può essere impossibile: in `network_manager.gd` c'è una variabile `TURN_SERVER`
commentata, pronta per le credenziali di un relay TURN gratuito (es. Metered.ca o Xirsys).

## Flag di debug (dopo `--`)

```
godot --path . -- --demo                 # IA contro IA (salta il menu)
godot --path . -- --fastko               # CPU con 20 HP (test flusso KO)
godot --path . -- --beamtest             # P1 spara il raggio subito
godot --path . -- --perspectivecpu       # P2 spara il raggio a P1: test malus speculare
godot --path . -- --dinohit              # Fase 2 + dinosauro colpito durante l'attacco
godot --path . -- --training             # entra direttamente in allenamento
godot --path . -- --lake                 # combattimento sulla mappa del lago
godot --path . -- --divetest             # (col lago) P1 parte immerso: test stealth
godot --path . -- --forest               # combattimento nella foresta di sequoie
godot --path . -- --treetest             # (foresta) P1 si nasconde in volo, l'albero cade, P1 e' scoperto
godot --path . -- --decoytest            # (foresta) P1 lascia l'esca: la CPU ci casca e la attacca
godot --path . -- --skytest              # (foresta) i due partono sopra le chiome
godot --path . -- --widetest             # (foresta) lottatori lontanissimi: zoom-out estremo
godot --path . -- --mapsel               # apre direttamente la scelta mappa
godot --path . -- --shot=out.png --shotdelay=3.5   # screenshot automatico e chiudi
godot --path . -- --nethost=C:/tmp/net           # test online: host automatico via file
godot --path . -- --netjoin=C:/tmp/net           # test online: ospite automatico via file
godot --path . -- --nethost=C:/tmp/net --netmap=lake   # ...online sulla mappa del lago
```

(`--nethost`/`--netjoin` scambiano offerta e risposta tramite `offer.json`/`answer.json`
nella cartella indicata: lanciando due istanze sulla stessa cartella si connettono da sole;
`--netmap=desert|lake` sceglie la mappa lato host, che l'ospite eredita dal codice-offerta.
Aggiungendo `--netprobe` i giocatori generano input sintetici che cambiano di continuo:
serve a collaudare predizione e riconciliazioni, contate nei log ogni 5 secondi.)

## Struttura

- `scripts/game.gd` — direttore: menù, modalità, arena, round, colpi, camera, effetti, input map
- `scripts/desert_perspective.gd` — regia falso 3D del deserto: Fase 1/Fase 2,
  Tween di lancio e camera, `StaticBody2D` dei limiti e malus dei comandi
- `scripts/desert_dinosaur.gd` — dinosauro ambientale della Fase 2: ingresso,
  movimento, attacco telegrafato, vulnerabilità temporanea e fuga
- `scripts/fighter.gd` — macchina a stati del lottatore (16 stati); `execute_inputs()` riceve i comandi di rete
- `scripts/ai_controller.gd` / `human_controller.gd` / `dummy_controller.gd` / `net_controller.gd` — controller intercambiabili
- `scripts/network_manager.gd` (autoload) — P2P WebRTC: signaling offer/answer/ICE in JSON,
  bitmask di input, buffer e snapshot pronti per il rollback netcode
- `scripts/multiplayer_menu.gd` + `scenes/multiplayer_menu.tscn` — schermata di connessione online
- `scripts/match_manager.gd` — nell'arena online: autorità di rete, netcode predittivo
  (buffer per tick, ridondanza 5 frame, predizione e riconciliazione con replay silenziato)
- `addons/webrtc_native/` — estensione GDExtension WebRTC (librerie Windows x86_64)
- `scripts/ki_blast.gd`, `energy_beam.gd`, `one_shot_fx.gd`, `hud.gd`, `sfx_bank.gd`
- `scripts/water_zone.gd` — il lago: fossa scura dietro ai lottatori e velo d'acqua
  animato davanti (superficie ondulata, luccichii, arredo del fondale)
- `scripts/AlberoInterattivo.gd` + `scenes/albero_interattivo.tscn` — la sequoia della
  foresta: zona di copertura (Area2D lungo tutto il fusto), PV del tronco, caduta e scoperta
  di chi si nasconde; gli sfondi della foresta usano nodi `Parallax2D` a più profondità
  (`game._build_forest_layers`)
- `scripts/decoy.gd` — l'immagine-esca lasciata da chi si nasconde: falso bersaglio per
  CPU, scatto homing e sfere di ki (`game.aim_point` / `game.decoy_of`), si dissolve se colpita
- `assets/sprites/z1|z2` — frame del personaggio, rivolti nativamente a destra
  (z2 = palette swap gialla per la CPU, rigenerata da z1 con `tools/PaletteSwapDir.cs`);
  i pugni hanno un frame per direzione: `punch_01` verso destra, `punch_02` verso sinistra
- `assets/sprites/fx|ui`, `assets/bg`, `assets/sfx` — effetti, ritratti, sfondi e suoni generati;
  il raggio è composto da `beam_head` (sfera alle mani), `beam_body1` (tratto tegolabile),
  `beam_body2` (tratto fiammeggiante) e `beam_tail` (punta, dove sta la collisione)
- `assets/music/menu.wav` — canzone del menù (loop sull'intera durata del brano);
  `battle_desert.wav` / `battle_lake.wav` / `battle_forest.wav` — musiche chiptune di
  battaglia (da `tools/BattleGen.cs` e `tools/ForestGen.cs`)
- `tools/*.cs` — script C# (PowerShell `Add-Type`) della pipeline degli asset:
  `SpriteDetect` (bounding box), `Extract` (ritaglio + palette swap da Z.png),
  `PaletteSwapDir` (rigenera z2 da z1), `BgGen` (sfondi deserto), `LakeGen` (sfondo e
  riva del lago da sshaohmarubg.gif + splash.wav), `ForestGen` (sfondi, sequoie e musica
  della foresta), `SfxGen` (WAV sintetizzati), `MusicGen` (musichetta chiptune originale
  del menù), `BattleGen` (musiche di battaglia)
