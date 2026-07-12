# Neko Majin Z — Supersonic Clash

Picchiaduro 2D in stile **Dragon Ball FighterZ / DBZ Supersonic Warriors 2**, realizzato con
**Godot 4.6.3**. Il personaggio è Z (Neko Majin Z) con gli sprite originali del gioco DS
*Dragon Ball Z: Supersonic Warriors 2* (file `Z.png`, rip di Grim — spritedatabase.net).

Si combatte contro una CPU (Neko Majin giallo, palette swap generata via script) in un match
al meglio dei 3 round, con **volo libero** in tutta l'arena e **attacchi energetici**.

All'avvio un **menù** (con musichetta chiptune) permette di scegliere tra:

- **COMBATTIMENTO 1v1** — match al meglio dei 3 round contro la CPU;
- **ALLENAMENTO** — bersaglio fermo, niente timer né round, HP e ki di entrambi si
  rigenerano poco dopo ogni scambio: perfetto per provare le mosse.

Scelta la modalità, una seconda schermata permette di **scegliere la mappa**:

- **DESERTO ROCCIOSO** — l'arena classica tra le mesas;
- **LAGO DELLA COSTA** — una spiaggia (sfondo rippato da `sshaohmarubg.gif`): la costa
  rocciosa a sinistra **scende a gradoni dolci** dentro un **lago profondo** che occupa
  tutto il lato destro, con il **fondale visibile** attraverso l'acqua. Chi si immerge
  **sparisce completamente dalla vista** e **non può essere rilevato** dall'avversario,
  a meno che anche quest'ultimo non entri in acqua: la CPU perde il bersaglio ("!!"),
  smette di attaccare e pattuglia l'ultima posizione nota; sfere di ki e scatti smettono
  di puntarti. In acqua ci si muove più lenti, da fermi si galleggia verso l'alto,
  i colpi subiti affondano piano (attrito), le sfere di ki si spengono in superficie
  con uno schizzo, e immergersi/riemergere produce splash e bollicine.

Nel menù (titolo con logo in stile Dragon Ball): W/S per scegliere, INVIO o J per
confermare, ESC per tornare indietro; la terza voce regola il **volume** (A/D, INVIO = muto).
In gioco, **ESC** riporta al menù, **1** mette in pausa, **2/3** abbassano/alzano il volume.

## Come si avvia

Eseguibile standalone (da inviare ad amici): `dist/NekoMajinZ.exe` — basta il file exe,
il gioco è tutto incorporato.

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
| **K** | Sfera di ki (costa 15 ki, leggera ricerca del bersaglio) |
| **L** | Raggio energetico (costa 200 ki = 2 tacche, danno enorme): animazione di carica in 8 pose, poi il raggio si estende e colpisce con la punta, con pioggia di scintille sull'impatto |
| **I** | Scatto homing verso l'avversario (costa 25 ki, colpisce al contatto) |
| **U** | Attacco palla rotolante (gratis, con ricarica) |
| **SPAZIO** | Parata (riduce il danno all'80%) |
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
- La camera inquadra entrambi i lottatori e zooma in/out dinamicamente (stile SSW2).
- La CPU vola, para, schiva i raggi, carica il ki, fa combo, scatti e sfere.

## Flag di debug (dopo `--`)

```
godot --path . -- --demo                 # IA contro IA (salta il menu)
godot --path . -- --fastko               # CPU con 20 HP (test flusso KO)
godot --path . -- --beamtest             # P1 spara il raggio subito
godot --path . -- --training             # entra direttamente in allenamento
godot --path . -- --lake                 # combattimento sulla mappa del lago
godot --path . -- --divetest             # (col lago) P1 parte immerso: test stealth
godot --path . -- --mapsel               # apre direttamente la scelta mappa
godot --path . -- --shot=out.png --shotdelay=3.5   # screenshot automatico e chiudi
```

## Struttura

- `scripts/game.gd` — direttore: menù, modalità, arena, round, colpi, camera, effetti, input map
- `scripts/fighter.gd` — macchina a stati del lottatore (16 stati)
- `scripts/ai_controller.gd` / `human_controller.gd` / `dummy_controller.gd` — controller intercambiabili
- `scripts/ki_blast.gd`, `energy_beam.gd`, `one_shot_fx.gd`, `hud.gd`, `sfx_bank.gd`
- `scripts/water_zone.gd` — il lago: fossa scura dietro ai lottatori e velo d'acqua
  animato davanti (superficie ondulata, luccichii)
- `assets/sprites/z1|z2` — frame del personaggio, rivolti nativamente a destra
  (z2 = palette swap gialla per la CPU, rigenerata da z1 con `tools/PaletteSwapDir.cs`);
  i pugni hanno un frame per direzione: `punch_01` verso destra, `punch_02` verso sinistra
- `assets/sprites/fx|ui`, `assets/bg`, `assets/sfx` — effetti, ritratti, sfondi e suoni generati;
  il raggio è composto da `beam_head` (sfera alle mani), `beam_body1` (tratto tegolabile),
  `beam_body2` (tratto fiammeggiante) e `beam_tail` (punta, dove sta la collisione)
- `assets/music/menu.wav` — musichetta chiptune del menù (loop, generata via script)
- `tools/*.cs` — script C# (PowerShell `Add-Type`) della pipeline degli asset:
  `SpriteDetect` (bounding box), `Extract` (ritaglio + palette swap da Z.png),
  `PaletteSwapDir` (rigenera z2 da z1), `BgGen` (sfondi deserto), `LakeGen` (sfondo e
  riva del lago da sshaohmarubg.gif + splash.wav), `SfxGen` (WAV sintetizzati),
  `MusicGen` (musichetta del menù)
