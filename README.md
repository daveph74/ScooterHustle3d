# Scooter Hustle 🛵

An **arcade endless runner** built in **Godot 4.x** with **GDScript**, inspired by
Temple Run and Subway Surfers. You ride a scooter through chaotic Philippine
traffic. The scooter drives forward automatically — your only job is to dodge
left and right between **three lanes**, grab coins, and survive as long as you
can.

This repository is a **polished vertical slice** (a playable prototype), not a
finished game. It is intentionally simple, heavily commented, and easy to extend.

> **What this is NOT:** a driving simulator, an open-world game, or a realistic
> motorcycle game. It is a fast, snappy, mobile-first arcade runner.

---

## How to run the game

1. Install **Godot 4.3** (or any 4.x) from <https://godotengine.org/download>.
   You only need the **standard** version — no C#/.NET, no plugins.
2. Open Godot, click **Import**, and select the `project.godot` file in this
   folder.
3. Press **F5** (or the ▶ Play button, top-right) to run.

### Controls

| Action      | Keyboard (testing)   | Touch (phone)        |
|-------------|----------------------|----------------------|
| Move left   | `←` or `A`           | Swipe left           |
| Move right  | `→` or `D`           | Swipe right          |

On a PC you can also **click-and-drag** the mouse left/right to simulate a
swipe (mouse-to-touch emulation is enabled in the project settings).

---

## Project structure

```
res://
├── project.godot              # engine config: main scene, autoload, input, portrait
├── icon.svg                   # app icon
├── scenes/
│   ├── Game.tscn / Game is in scripts/  # the gameplay world
│   ├── Coin.tscn              # collectible coin
│   └── Coin.gd
├── scripts/
│   └── Game.gd                # the main gameplay controller (spawning, scrolling, scoring)
├── vehicles/
│   ├── Player.tscn            # the scooter the player controls
│   └── Player.gd
├── traffic/
│   ├── TrafficVehicle.tscn    # one reusable obstacle (jeepney/bus/tricycle/car)
│   └── TrafficVehicle.gd
├── ui/
│   ├── MainMenu.tscn / .gd     # title screen
│   ├── Garage.tscn / .gd       # buy & select scooters
│   ├── HUD.tscn / .gd          # in-game score / coins overlay
│   └── GameOver.tscn / .gd     # crash results screen
├── systems/
│   └── GameData.gd            # global singleton: coins, unlocks, save/load
└── resources/
    ├── ScooterData.gd         # the Resource type describing a scooter
    ├── rusty_scooter.tres
    ├── daily_commuter.tres
    ├── 125cc_bike.tres
    └── sport_bike.tres
```

---

## Every scene explained

- **`ui/MainMenu.tscn`** — The first screen (set as the main scene). A `Control`
  whose UI (title, coin total, Play / Garage buttons) is built in code. Play
  loads the game; Garage loads the garage.

- **`ui/Garage.tscn`** — A `Control` that lists all four scooters as cards. Each
  card shows name, description, star-rated stats, and a Select/Buy/Selected
  button. Lets the player spend coins to unlock faster scooters.

- **`scenes/Game.tscn`** — The 3D gameplay world. Contains:
  - `Sun` (DirectionalLight3D) — lighting and shadows.
  - `WorldEnvironment` — a procedural sky and light distance fog.
  - `Ground` — a big green plane under the road.
  - `Camera3D` — the third-person camera behind the scooter.
  - `RoadContainer`, `TrafficContainer`, `CoinContainer` — empty `Node3D`s that
    hold the road tiles, traffic and coins created at runtime.
  - `Player` — an instance of `Player.tscn`.
  - `HUD` and `GameOverLayer` — instances of the UI overlays.

- **`vehicles/Player.tscn`** — The scooter. An `Area3D` (so it can detect
  overlaps) with a collision box and an empty `Model` node. On ready it drops in
  the Kenney motorcycle model, auto-fitted to size. It sits on collision
  **layer 1** and watches **layers 2 & 3** (traffic & coins).

- **`traffic/TrafficVehicle.tscn`** — One reusable obstacle. An `Area3D` with a
  collision box and an empty `Model` node. `setup(type)` fills it in: the
  jeepney, bus and car use auto-fitted Kenney truck models (different size +
  colour); the tricycle is still hand-built from primitives. Sits on **layer 2**.

- **3D models (`res://models/`)** — Kenney "Racing" and "City Builder" starter
  kits (MIT licensed — see `CREDITS.md`). Used for the player, most traffic, and
  the roadside buildings/trees.

- **`scenes/Coin.tscn`** — A spinning gold coin. An `Area3D` with a cylinder
  mesh (stood on its edge) and a sphere collision shape. Sits on **layer 3**.

- **`ui/HUD.tscn`** — A `CanvasLayer` overlay showing run coins, score and total
  coins, plus the "NEAR MISS!" flash. Built in code.

- **`ui/GameOver.tscn`** — A `CanvasLayer` with a dimmed panel showing the run
  results and Retry / Main Menu buttons.

---

## Every script explained

- **`systems/GameData.gd`** *(autoload singleton)* — The persistent brain of the
  game. Loads the four scooter resources, tracks `total_coins`, `unlocked_ids`
  and `selected_id`, and saves/loads them to `user://scooterhustle_save.json`.
  Reachable from anywhere as `GameData`.

- **`resources/ScooterData.gd`** — Defines the `ScooterData` resource type with
  `id`, `display_name`, `speed`, `handling`, `price`, `description`. Each `.tres`
  file is one scooter. Adding a scooter = add a `.tres` + one line in GameData.

- **`vehicles/Player.gd`** — Reads input (keyboard actions + touch swipes) and
  smoothly slides the scooter between the three lanes (it never moves forward —
  the world scrolls toward it). Handles collisions: hitting traffic emits
  `crashed`; touching a coin collects it and emits `coin_collected`. Reads the
  selected scooter's `handling` to set how snappy lane changes feel.

- **`traffic/TrafficVehicle.gd`** — No AI at all. Its only job is `setup(type)`,
  which resizes and recolours the box to look like a jeepney, bus, tricycle or
  car. Movement is handled centrally by `Game.gd`.

- **`scenes/Coin.gd`** — Spins the coin and plays a "pop" tween (`collect()`)
  when picked up. Emits `collected`.

- **`scripts/Game.gd`** — The main controller. It:
  - builds and endlessly scrolls a pool of road tiles (the "treadmill" trick);
  - spawns, moves and recycles traffic, coins, and roadside scenery
    (buildings & trees down each side of the road);
  - ramps difficulty gently (traffic speeds up and spawns more often over time);
  - tracks score (distance + near-miss bonus) and coins;
  - detects **near misses**, does **screen shake** on crash, widens the camera
    **FOV** with speed, and tilts the camera into lane changes;
  - banks coins and shows the Game Over screen on a crash.

- **`systems/ModelUtil.gd`** — A small helper that drops an imported `.glb`
  model into the scene and **auto-fits** it: it measures the model's bounding
  box and scales/centres it to a target size, so models work regardless of their
  native units. If a vehicle ever faces the wrong way, flip the `FACES_BACK`
  constant in `Player.gd` / `TrafficVehicle.gd`.

- **`ui/MainMenu.gd`, `ui/Garage.gd`, `ui/HUD.gd`, `ui/GameOver.gd`** — Build
  their respective UIs in code and wire up the buttons / scene changes.

### How it fits together (signals & flow)

```
MainMenu ──Play──▶ Game.tscn
   │
   └─Garage──▶ Garage ──Back──▶ MainMenu

Game.gd
  ├─ instances Player, HUD, GameOver
  ├─ Player.coin_collected ─▶ Game adds a coin + HUD feedback
  └─ Player.crashed ────────▶ Game banks coins (GameData.add_coins) + GameOver

GameOver ──Retry──▶ reloads Game.tscn
GameOver ──Menu───▶ MainMenu.tscn
```

---

## How to export to Android

1. In Godot, install the **Android Build Template** and export templates:
   *Editor → Manage Export Templates → Download and Install*.
2. Install the **Android SDK** + **JDK 17**. The easiest path is to install
   **Android Studio** once, then in Godot go to
   *Editor → Editor Settings → Export → Android* and point it at:
   - **Android SDK Path** (e.g. `~/Android/Sdk`)
   - **Java SDK Path** (JDK 17)
   - **Debug Keystore** (Godot can generate a debug keystore for you).
3. Open *Project → Export…*, click **Add… → Android**.
4. Recommended preset settings:
   - **Architectures:** enable `arm64-v8a` (and `armeabi-v7a` for old devices).
   - The project is already set to **portrait** orientation in
     `project.godot`, so no extra change is needed.
5. Plug in a phone with **USB debugging** on, then click the small Android
   **▶ (one-click deploy)** button in the top-right, **or** press **Export
   Project** to produce an `.apk`.
6. To publish on Google Play later, switch the preset to produce an **`.aab`**
   and sign it with a **release keystore** (not the debug one).

> Tip: test on-device early. Touch swipes only fully behave on a real phone.

---

## Tuning the game

Most "feel" values live as constants/variables at the top of **`scripts/Game.gd`**:

- Per-bike speed: each bike's `speed` stat in `resources/*.tres` sets its start
  and top speed; the global `SPEED_*` consts in `Game.gd` tune the formula.
- `traffic_interval`, `coin_interval` — spawn frequency.
- the difficulty ramp lines inside `_process()` (the `* 0.35`, `* 0.012` numbers).
- `LANE_WIDTH` (also in `Player.gd` — keep them equal!).

Scooter stats live in the **`resources/*.tres`** files and can be edited in the
Godot inspector without touching code.

---

See **`TODO.md`** for the planned-but-deliberately-unbuilt future features.
