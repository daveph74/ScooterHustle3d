# Scooter Hustle — Developer Handover

> A complete, working **Godot 4.7** arcade endless-runner prototype (think
> Temple Run / Subway Surfers) where you ride a scooter through Philippine
> traffic. This document is written so a new developer **or AI agent** can pick
> the project up cold and be productive immediately.

---

## 0. TL;DR / Current State

- **Engine:** Godot **4.7** stable. GDScript only. No C#. No external Godot plugins required to run.
- **Status:** Playable vertical slice. Menu → gameplay → game over → garage all work. Audio, 3D models, hills/bends, fair traffic, persistence all implemented and tested in-editor by the project owner.
- **Platform target:** Mobile (Android), **portrait** 1080×1920, touch swipe controls (keyboard for desktop testing).
- **Repo branch:** `claude/elegant-lamport-nv40yn`. There is a **draft PR #1** into `main` (which is an empty root commit). Everything is committed and pushed.
- **Main scene:** `res://ui/MainMenu.tscn`.
- **Not run-verified in CI** — there is no `godot` binary in the cloud dev container it was built in; verification was done by the owner running the editor locally and sending screenshots.

### How to run
1. Install Godot 4.7+ (standard, not .NET).
2. Open `project.godot` in Godot.
3. Press **F5**. Test with `←/→` or `A/D`, or click-drag the mouse to simulate a swipe.

---

## 1. Core Design & The Two Non-Obvious Tricks

Understanding these two tricks is the key to the whole codebase.

### Trick 1 — The "treadmill"
The player **never moves forward**. The scooter sits at world `z = 0` and only
slides left/right between 3 lanes (`x = -2.5, 0, +2.5`). Everything else (road
tiles, traffic, coins, scenery) **scrolls toward the player** along +Z and is
recycled once it passes behind. This keeps math simple and avoids float
precision issues over an "endless" distance.

- "Ahead" = negative Z. Objects spawn at `SPAWN_Z = -150` and are freed past `DESPAWN_Z = 14`.
- `distance` (metres travelled) only ever increases and drives the score and difficulty.

### Trick 2 — The "curvy world" (fake hills & bends)
The **logical track stays straight and flat**, so lanes and collisions are
trivial and always correct. Hills and bends are a pure **visual displacement**:

```
Game.gd:
  _path_x(w)  -> sideways offset at world-position w   (bends)
  _path_y(w)  -> vertical offset at world-position w    (hills)
  _path_offset(z) = ( _path_x(distance - z) - _path_x(distance),
                      _path_y(distance - z) - _path_y(distance) )
```

Every scrolling object is displaced by `_path_offset(its z)`, added on top of
its base lane position (stored per-object in the `"bx"`/`"by"` metadata). The
crucial detail: **we subtract the value at the player (`distance`)**, so the
offset is **zero at `z = 0`**. That means:
- The road bends/rolls in the distance but is flat & centred right at the scooter.
- Collisions only ever matter near `z ≈ 0`, where the offset ≈ 0, so traffic in
  lane *N* still lines up with the player in lane *N*. **Bends/hills never affect fairness.**

Road tiles are additionally **pitched and yawed** to the path tangent (see
`_scroll_road`) so they join into a smooth ribbon instead of staircasing. The
grass is baked into each tile and overlaps generously so no seam can reveal it.

`HILL_DIR` / `BEND_DIR` constants (1.0 / -1.0) flip direction if a hill or bend
ever looks inverted. Amplitudes live in `_path_x` / `_path_y`.

---

## 2. Folder / File Map

```
res://
├── project.godot              Engine config: main scene, autoloads, input map, portrait, mobile renderer
├── icon.svg                   App icon
├── README.md                  Player-facing: run, controls, Android export, scene/script summaries
├── TODO.md                    Deliberately-unbuilt future features + design guardrails
├── CREDITS.md                 Asset attribution (Kenney MIT models; audio is original/procedural)
├── HANDOVER.md                ← this file
│
├── resources/
│   ├── ScooterData.gd         class_name ScooterData (Resource): id, display_name, speed, handling, price, description
│   ├── rusty_scooter.tres     speed 1.0  handling 1.0  price 0
│   ├── daily_commuter.tres    speed 1.3  handling 1.15 price 250
│   ├── 125cc_bike.tres        speed 1.7  handling 1.3  price 750
│   └── sport_bike.tres        speed 2.2  handling 1.5  price 1800
│
├── systems/
│   ├── GameData.gd            AUTOLOAD. Persistent state + save/load (JSON). Scooter catalogue.
│   ├── AudioManager.gd        AUTOLOAD. Music loops + pooled SFX. Reads/writes settings in GameData.
│   └── ModelUtil.gd           class_name ModelUtil. Auto-fits imported .glb models to a target size.
│
├── vehicles/
│   ├── Player.tscn            Area3D + empty "Model" node + collision box
│   └── Player.gd              class_name Player. Input (swipe+keyboard), lane lerp, collisions. Signals: crashed, coin_collected.
│
├── traffic/
│   ├── TrafficVehicle.tscn    Area3D + empty "Model" node + collision box
│   └── TrafficVehicle.gd      class_name TrafficVehicle. setup(type) builds the model; drive_speed field.
│
├── scenes/
│   ├── Coin.tscn / Coin.gd    class_name Coin. Spins, pickup "pop" tween. Signal: collected.
│   └── Game.tscn              The 3D gameplay scene (see node tree below).
│
├── scripts/
│   └── Game.gd                THE MAIN CONTROLLER. Road, spawning, scrolling, difficulty, scoring, camera, game over.
│
├── ui/
│   ├── MainMenu.tscn/.gd      Title, coins, Play, Garage, + audio options (music on/off, track, sfx on/off)
│   ├── Garage.tscn/.gd        Buy/select scooters; star-rated stats
│   ├── HUD.tscn/.gd           CanvasLayer overlay: run coins / score / total coins + "NEAR MISS!" flash
│   └── GameOver.tscn/.gd      CanvasLayer dim panel: results + Retry / Main Menu
│
├── models/                    Kenney starter-kit models (MIT). IMPORTANT: each kit needs its own colormap.
│   ├── racing/                vehicle-motorcycle, vehicle-truck-{red,yellow,green}.glb
│   │   └── Textures/colormap.png
│   └── city/                  building-small-{a..d}, building-garage, grass-trees, grass-trees-tall.glb
│       └── Textures/colormap.png
│
├── audio/                     Procedurally generated (original) WAVs
│   ├── music/                 track1_cruise, track2_rush, track3_chill (.wav, looped in code)
│   └── sfx/                   coin, crash, near_miss, click (.wav)
│
└── .claude/                   Installed Godot dev-tooling skill (loads in Claude Code sessions on this repo)
    ├── skills/godot/          SKILL.md + references/ + scripts/ (GdUnit4, exports, CI, deploy)
    └── commands/godot.md      /godot slash command
```

---

## 3. Scene: `Game.tscn` Node Tree

```
Game (Node3D)                  ← scripts/Game.gd
├── Sun (DirectionalLight3D)   rotation set in code; shadows on
├── WorldEnvironment           procedural sky; fog DISABLED; ambient from sky
├── Camera3D                   behind+above; rotation/fov driven by Game.gd
├── RoadContainer (Node3D)     holds the 44 recycled road tiles
├── TrafficContainer (Node3D)  holds spawned TrafficVehicle instances
├── CoinContainer (Node3D)     holds spawned Coin instances
├── SceneryContainer (Node3D)  holds buildings/trees
├── Player (instance)          Player.tscn
├── HUD (instance)             ui/HUD.tscn
└── GameOverLayer (instance)   ui/GameOver.tscn
```

There is **no static ground plane** — grass is baked into each scrolling road
tile so it rolls with the hills.

---

## 4. Collision Layers (Area3D overlap, no physics bodies)

| Object   | collision_layer | collision_mask | monitoring |
|----------|-----------------|----------------|------------|
| Player   | 1               | 6 (layers 2+3) | true       |
| Traffic  | 2               | 0              | false      |
| Coin     | 4 (layer 3)     | 0              | false      |

The Player is the only monitor. `Player._on_area_entered`:
- area in group `"traffic"` → `crashed` signal → game over.
- area in group `"coin"`   → `coin.collect()` + `coin_collected(1)` signal.

---

## 5. Signal / Control Flow

```
MainMenu --Play--> Game.tscn
   └--Garage--> Garage --Back--> MainMenu

Game.gd (in _ready):
   connects Player.coin_collected -> _on_coin_collected (count + HUD + coin SFX)
   connects Player.crashed       -> _on_player_crashed  (bank coins, crash SFX, shake, show GameOver)

GameOver --Retry--> reload Game.tscn
GameOver --Menu---> MainMenu.tscn

AudioManager (autoload) persists across scene changes -> music keeps playing.
```

---

## 6. Key Systems In Detail

### 6.1 Player (`vehicles/Player.gd`)
- 3 lanes; `current_lane` 0/1/2 starting at 1 (middle). `_lane_to_x(l) = (l-1)*2.5`.
- Smoothly lerps `position.x` to the target lane; `lane_change_speed = 7.0 * scooter.handling`.
- **Keyboard:** `Input.is_action_just_pressed("move_left"/"move_right")`.
- **Touch:** `_unhandled_input` tracks a screen touch; a drag of > `SWIPE_MIN_PIXELS` (40px) triggers one lane change (one lane per swipe). Mouse→touch emulation is on in `project.godot`, so click-drag works on desktop.
- Visual model: Kenney motorcycle via `ModelUtil.instance_fitted`. `SCOOTER_FACES_BACK = true` (already corrected for this model).

### 6.2 Traffic & the "always passable" guarantee (`Game.gd` + `TrafficVehicle.gd`)
This is the most important gameplay-correctness system.

- **All traffic shares ONE speed**: `drive_speed = TRAFFIC_SPEED_FRACTION (0.45) * base_speed`. Uniform speed means vehicles keep formation and can **never drift into an impossible 3-lane wall**. Each is scrolled by `(speed - drive_speed) * delta`, so the faster player always overtakes traffic.
- Traffic spawns in **rows** (`_spawn_traffic_at`). A row never blocks all three lanes — the current `_safe_lane` is always left open.
- Early game: a row blocks only one of the two non-safe lanes (2 lanes open). After `elapsed > 20s`, a row may block **both** non-safe lanes (only the safe lane open).
- `_safe_lane` drifts by at most **±1 lane, and only on easy (2-open) rows**, so the player can always follow the open path with single swipes and is never forced through a tight diagonal.
- Coin lines spawn **in the safe lane**, gently guiding the player along the open path.
- `TrafficVehicle.setup(type)` swaps the box for a Kenney truck model (jeepney=green, bus=red, car=yellow) or builds a **procedural tricycle** (motorbike + sidecar; no off-the-shelf model). `TRAFFIC_FACES_BACK = true`.
- Vehicle collision box = a per-type `bounds` Vector3 (used regardless of the visual model's exact size).

### 6.3 Coins (`scenes/Coin.gd`)
- Spawned as lines of 3–5 in the safe lane. Spin in place; on `collect()` play a scale-up + float tween, disable collision, then `queue_free`.
- Counting happens via the Player's `coin_collected` signal (not the coin), so there's no double counting.

### 6.4 Near miss (`Game._check_near_miss`)
When a vehicle crosses the player's z without colliding and the lateral distance
is `1.2 < dx < 3.2` (i.e. it was in the adjacent lane), award **+25 score**,
small camera shake, HUD "NEAR MISS!" flash, and the near_miss SFX.

### 6.5 Difficulty ramp (`Game._process`)
- `speed = min(base_speed + elapsed*0.35, MAX_SPEED=42)`, where `base_speed = 14 + scooter.speed*4`.
- `traffic_interval = max(0.85, 1.6 - elapsed*0.012)` (rows get closer).
- Two-lane blocks unlock at `elapsed > 20s` (50% chance per row).
- No sudden spikes — everything ramps with `elapsed`.

### 6.6 Camera (`Game._update_camera`)
- Drifts X partly toward the player's lane and toward the bend ahead.
- **Yaws into bends** and **pitches with hills** by sampling `_path_offset(-22)` (22 m ahead). Base downward tilt is −16°.
- Banks (roll) slightly into lane changes and bends.
- **FOV widens 70°→82°** as speed increases for a sense of speed.
- Screen shake uses the camera's `h_offset`/`v_offset` so it never fights the position lerp. Crash = strong (0.6), near miss = small (0.15), decaying over time.

### 6.7 ModelUtil (`systems/ModelUtil.gd`)
`instance_fitted(parent, packed_scene, target, fit_axis, face_back)`:
- Instantiates the model under a `holder → pivot` pair.
- Measures the model's combined AABB, **scales uniformly** so either its length (`"length"`) or height (`"height"`) matches `target`, centres it horizontally, and drops it to `y=0`.
- The holder is returned at the parent origin so the caller can freely position/rotate it (scenery does).
- `footprint_radius(holder)` returns half the larger horizontal dimension after fitting — used to push scenery far enough off the road that it never overlaps, regardless of model size/rotation.
- This is why dropping in any new `.glb` "just works" at the right size.

### 6.8 Scenery (`Game._spawn_scenery_at`, `_prewarm_scenery`)
Buildings (height 7–16) and tree clumps (height 3–5) from the Kenney City Kit,
placed on alternating sides at `road_edge + gap + footprint_radius`, random yaw,
scrolled and recycled like everything else, and displaced by the same path so
they ride the hills/bends.

### 6.9 Audio (`systems/AudioManager.gd`)
- Autoload, persists across scenes, so music is continuous.
- 3 music loops; looping enabled in code (`AudioStreamWAV.LOOP_FORWARD`, `loop_end` computed from length). Music at −6 dB.
- SFX pool of 6 players (round-robin so overlaps don't cut out), at **−6 dB (50% volume)**.
- Public API: `play_sfx(name)`, `toggle_music()`, `set_music_enabled(bool)`, `next_track()`, `current_track_name()`, `set_sfx_enabled(bool)`.
- Settings (`music_on`, `sfx_on`, `music_track`) live in `GameData` and are saved.
- **Audio is procedurally generated chiptune** (see §9) — placeholder quality, designed to be drop-in replaceable.

### 6.10 Persistence (`systems/GameData.gd`)
- Saves to `user://scooterhustle_save.json`: `total_coins`, `unlocked_ids`, `selected_id`, `music_on`, `sfx_on`, `music_track`.
- Scooter catalogue is `preload`ed from the four `.tres` files. Add a scooter by adding a `.tres` and one line in `_load_scooter_defs()`.
- Rusty Scooter is always owned (enforced on load).

---

## 7. Tuning Knobs (where to change "feel")

Almost everything lives at the top of **`scripts/Game.gd`**:

| Want to change | Edit |
|---|---|
| Lane spacing | `LANE_WIDTH` (also in `Player.gd` — keep equal!) |
| Speed / difficulty | `base_speed` formula, `MAX_SPEED`, the `elapsed*` ramp coefficients |
| How aggressive traffic is | `traffic_interval` floor, the `elapsed > 20` / `randf() < 0.5` two-lane gate |
| Traffic relative speed | `TRAFFIC_SPEED_FRACTION` |
| Hill/bend strength | amplitudes in `_path_x` / `_path_y` |
| Hill/bend direction | `HILL_DIR` / `BEND_DIR` (1.0 ↔ -1.0) |
| Road smoothness | `SEGMENT_LENGTH` (smaller = smoother, more nodes) / `SEGMENT_COUNT` |
| Spawn distance / cull | `SPAWN_Z` / `DESPAWN_Z` |
| Coin frequency | `coin_interval` |
| Scenery density | `scenery_interval` |

Per-scooter feel: the `.tres` files (`speed`, `handling`). Swipe sensitivity:
`SWIPE_MIN_PIXELS` in `Player.gd`. Audio volumes: `volume_db` in `AudioManager.gd`.

---

## 8. Assets

### 3D models — Kenney (MIT)
- From `KenneyNL/Starter-Kit-Racing` (vehicles) and `KenneyNL/Starter-Kit-City-Builder` (buildings/trees).
- **CRITICAL GOTCHA:** Kenney GLBs reference a shared `Textures/colormap.png` **relative to the model file**, and the two kits have **different** palettes. That's why models are split into `models/racing/` and `models/city/`, each with its **own** `Textures/colormap.png`. If you add a Kenney model, put it next to the matching colormap or it will be untextured (you'll see `Can't open file colormap.png` errors).
- Orientation: Kenney racing models import facing one way; the `*_FACES_BACK` flags correct it. New models may need the flag flipped.

### Audio — original / procedural
- Generated by a standalone Python script (pure stdlib `wave`/`math`) — no samples, no third-party licence. The generator is not committed (it lived in scratch), but it's trivial to recreate: sine/triangle/square arpeggios + bass + kick for music; blips/noise bursts for SFX. To replace with real audio, just drop new files into `audio/music/` and `audio/sfx/` with the same names (or update the `preload` paths in `AudioManager.gd`).

---

## 9. Known Limitations & Gotchas

1. **Not verified in CI / no Godot binary** in the build container. Verify changes by running the editor.
2. **Godot 4.7 strict typing**: avoid `:=` type inference where the value's type can't be determined (e.g. `event.position` on a base `InputEvent` — cast first), and don't assign an untyped `Array` literal to an `Array[int]` (use an explicit untyped `var: Array` + `if/else`). Both bit us already.
3. **Curve is visual only.** Far-ahead objects are offset sideways/vertically; this is intentional and does not affect collisions (offset → 0 at the player).
4. **Performance:** ~44 road tiles + scenery + traffic are repositioned every frame. Fine on desktop; profile on a real phone before shipping. Consider fewer/larger tiles or culling if needed.
5. **Audio quality** is placeholder chiptune.
6. **Tricycle** is the only procedurally-built vehicle (no model exists for it).
7. The installed **`/godot` skill** needs a `godot` binary on PATH to actually run its test/export scripts.

---

## 10. Build / Export

- **Run:** open in Godot 4.7, F5.
- **Android:** install export templates + Android SDK/JDK 17, add an Android export preset (project is already portrait), enable `arm64-v8a`, one-click deploy or export APK; use a release keystore + `.aab` for Play Store. Full steps are in `README.md`.
- **Web/desktop & CI:** the installed `/godot` skill (`.claude/skills/godot/`) documents GdUnit4 testing, web/desktop exports, GitHub Actions CI, and deployment to Vercel/GitHub Pages/itch.io. There are no tests yet — adding a GdUnit4 suite is a good first task (the skill walks through it).

---

## 11. Git / PR State

- **Working branch:** `claude/elegant-lamport-nv40yn` (all work here).
- **`main`** is an empty initial commit created so a PR could exist; the branch is reparented onto it.
- **Draft PR #1** → `main`. Mark it ready / merge when you're happy.
- Commit style: descriptive subject + body; each feature is its own commit, so the history reads as a feature log (add prototype → low-poly → Kenney models → fix textures → hills/bends → fix seams → fair traffic → audio → skill, etc.).

---

## 12. Suggested Next Steps

Short term / polish:
- Add a **pause button** and an in-game music/SFX toggle.
- **Particles**: coin sparkle on pickup, debris/dust on crash (hooks already exist via the signals).
- **High score / best distance** on the menu and game-over screen.
- A proper **Settings screen** (currently options are inline on the main menu).

Content:
- Swap placeholder audio for real tracks; swap/extend vehicle & building variety.
- More scooters (just add `.tres` files).

Engineering:
- Add a **GdUnit4 test suite** (use the `/godot` skill) — e.g. test `GameData` save/load, `_safe_lane` never produces an unsolvable row, `ModelUtil` fitting.
- Set up **CI** (GitHub Actions) to headless-export web on every push (skill has a template).

Explicitly OUT of scope for the prototype (see `TODO.md`): weather, fuel,
passengers, police, maps, multiplayer, real driving physics, traffic AI, scooter
part upgrades. Keep it an arcade, 3-lane, left/right runner.

---

## 13. Glossary of the Important Symbols

- `distance` — metres travelled this run; monotonic; drives score & difficulty.
- `_safe_lane` — the lane guaranteed open in the current traffic row.
- `bx` / `by` (node metadata) — an object's base X/Y before path displacement.
- `_path_offset(z)` — the (x,y) visual displacement for an object at local z.
- `drive_speed` — a traffic vehicle's forward speed (uniform across all traffic).
- `*_FACES_BACK` — per-model 180° flip flags for imported vehicle orientation.
- `HILL_DIR` / `BEND_DIR` — sign flips for the hill/bend direction.
- `ModelUtil.instance_fitted` — drop any `.glb` in at the right size automatically.
```
