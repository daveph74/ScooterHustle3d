# Scooter Hustle — Unreal Engine 5.8 Build Brief

> Paste this whole file into a fresh Claude Code session as the opening prompt.
> It is **self-contained**: it describes the game to build from scratch in
> **Unreal Engine 5.8**. There is an existing Godot 4.7 implementation this is
> based on; you do **not** need it, but the design below is the source of truth.

---

## 0. What you are building

**Scooter Hustle** — a 3-lane arcade endless runner (Temple Run / Subway
Surfers style) where you ride a scooter through Philippine traffic, dodging
vehicles, grabbing coins, and going as far as possible.

- **Engine:** Unreal Engine **5.8**.
- **Primary target:** **Android phone, portrait** (1080×1920), **touch swipe**
  controls. Also runnable on PC for testing (keyboard).
- **Feel:** bright, friendly, low-poly arcade. Smooth on a mid-range phone.
- **Single player. No backend, no ads, no microtransactions, no multiplayer.**

Build it **mobile-first**: keep draw calls, triangles, and overdraw low. Assume
a modest phone GPU.

---

## 1. The two non-obvious tricks (read first — this is the whole architecture)

### Trick 1 — The "treadmill"
The player **never moves forward**. The scooter sits at world `Z = 0` (use your
chosen forward axis; in UE that's typically +X — pick one and be consistent)
and only slides **left/right** between 3 lanes. Everything else — road tiles,
traffic, coins, scenery — **scrolls toward the player** and is recycled
(object-pooled) once it passes behind. This keeps the math simple and avoids
floating-point precision problems over an "endless" distance.

- "Ahead" = far spawn distance; objects spawn ~150 units ahead and are recycled
  ~14 units behind the player.
- A single `Distance` value (metres travelled) only ever increases; it drives
  the score and all difficulty ramps.

### Trick 2 — The "curvy world" (fake hills & bends)
The **logical track stays straight and flat** — so lanes and collisions are
trivial and always correct. Hills and bends are a **pure visual displacement**:

```
path_x(w) -> sideways offset at distance-along-track w   (bends)
path_y(w) -> vertical offset at distance-along-track w   (hills)
offset(z) = ( path_x(Distance - z) - path_x(Distance),
              path_y(Distance - z) - path_y(Distance) )
```

Every scrolling object is displaced by `offset(its_z)` **on top of** its logical
lane position. The crucial detail: **subtract the value at the player
(`Distance`)** so the offset is **zero at the player**. Result:
- The road bends and rolls into the distance, but is flat & centred right at the
  scooter.
- Collisions only ever matter near the player, where the offset ≈ 0, so traffic
  in lane *N* always lines up with the player in lane *N*. **Bends/hills never
  affect fairness.**

Road tiles are also **pitched/yawed to the path tangent** so they join into a
smooth ribbon instead of a staircase.

Reference displacement curves (tune freely):
```
path_x(w) = sin(w*0.006)*8.0 + sin(w*0.015)*3.5     // bends
path_y(w) = sin(w*0.020)*2.4 + cos(w*0.045)*1.0     // rolling hills
```

> Implement these two tricks first. Everything else hangs off them.

---

## 2. Core gameplay

- **3 lanes**, centres at local X = **-2.5, 0, +2.5** (lane width 2.5). Player
  starts in the centre lane.
- **Controls:** swipe **left/right** to change lane (one lane per swipe). On PC,
  `Left/Right` arrows or `A/D`. No other controls — never assume keyboard/mouse
  in the shipping design.
- **Lane change:** smooth slide (lerp) to the target lane, not a teleport; the
  bike **leans** into the turn. Slide speed and lean scale with the bike's
  *handling* stat (see §6).
- **Crash:** hitting any traffic vehicle / obstacle ends the run (unless a
  shield power-up is active, which absorbs one hit). On crash, eject the rider
  ragdoll-style for juice, play a scream + crash SFX, show Game Over.
- **Score:** distance travelled in metres, multiplied by an active combo
  multiplier. Persist a **Best** score.
- **Coins:** collectible along lanes; collecting builds a combo; missing a coin
  line breaks the combo.

---

## 3. Spawning & scrolling (the run loop)

Each frame:
1. `speed` ramps up with time (see §6); `Distance += speed * dt`.
2. Scroll every active object toward the player by `speed * dt`, then apply the
   curvy-world `offset(z)` to its transform.
3. Recycle (pool) anything past the despawn point; spawn new rows at the far
   spawn point on timers.
4. Update HUD (score, coins, speedometer), camera, screen shake.

**Spawners (all on independent timers/distance gates):**
- **Traffic rows** — a "row" of 1+ vehicles across lanes, but **never blocks the
  guaranteed-open lane**, so the road is always passable. There is deliberately
  **NO traffic AI**: vehicles don't steer/brake/overtake. Each just drives
  forward slower than the player, so the player overtakes it (that relative
  motion is what makes traffic look alive). 4 vehicle types: jeepney, tricycle,
  bus, car/taxi.
- **Coin lines** — short lines of coins in the safe lane.
- **Power-ups** — rare; magnet, shield, x2-coins (multiplier), speed boost.
- **Pedestrian crossings** — a zebra crossing with a few people walking across,
  leaving the safe lane clear; starts later in the run.
- **Lane closure** — an outer lane dead-ends behind a construction barrier wall
  with dug-up road; the player must merge inward or crash. Centre lane forced
  open.
- **Road split** (signature mechanic) — a raised concrete **median island** with
  a bright warning nose appears in the **centre lane**, forcing the player to
  pick **left or right**. **Both sides are drivable**; one side (random) is
  lined with a coin reward + a power-up, and traffic is steered to the other
  side. Driving into the median crashes you — that's what forces the choice.

---

## 4. Camera, world, presentation

- **Camera:** chase cam behind + above the scooter, looking slightly down the
  road. FOV widens a little with speed for a sense of speed. On a tall portrait
  screen use a wider FOV; on a wide screen pull in / narrow FOV. Add subtle
  **screen shake** on crash / near-miss.
- **Environment:** sunny daytime, warm ambient, soft shadows, light fog for
  depth. Bright low-poly Philippine streetscape: tiled road with lane dashes,
  raised sidewalks + kerbs, a continuous "street wall" of buildings on both
  sides, palm trees, lamp posts, sidewalk clutter (benches/bins/pots), parked
  jeepneys/scooters, ambient pedestrians.
- **Districts:** the run cycles through ~6 themed districts (Downtown, Barangay,
  Residential, Provincial, Beach Road, Fiesta), each with its own building/
  landmark/tree mix and colour palette (ground, ambient, sun, fog) that blends
  smoothly at transitions.
- **Landmarks:** recognisable storefronts that face the road (Jollibee, church,
  sari-sari store, Petron, 7-Eleven, pharmacy, etc.).
- **HUD:** rounded translucent badges — coins (top-left), big score in metres
  (top-centre), Best (top-right), pause button. A **semicircular speedometer**
  gauge bottom-right: tick marks, colour-coded fill (green→yellow→red), a
  redline zone, a needle, and a km/h number. Flash "TOP SPEED!" when the speed
  cap is first reached. Near-miss flash, combo indicator, power-up timer bars,
  and a brief district/event banner.
- **Audio:** looping engine that revs with speed, 2 music tracks, SFX for coin /
  crash / near-miss / UI click / rider scream.

---

## 5. Menus & meta

- **Main Menu:** title, total coins, Play, Garage, (optional) Daily Missions,
  audio options (music on/off + track, SFX on/off). Show a small **build tag**
  in a corner for verifying deployed builds.
- **Garage:** buy/select scooters with coins; show star-rated stats. Cosmetics
  (paint colour, helmet, wheel tint) that are **purely visual** and never change
  stats.
- **Game Over:** results (distance, coins, best), Retry / Main Menu.
- **Persistence:** save to a local save file (SaveGame in UE) — total coins,
  unlocked/selected scooter, equipped cosmetics, best score, settings,
  daily-mission state.

---

## 6. Bikes / vehicles (data-driven)

Four player bikes, each a data asset with: `id`, `display_name`, `model`,
`model_yaw` (facing fix), `speed` multiplier, `handling` multiplier, `price`,
`description`.

| Bike | speed | handling | price |
|---|---|---|---|
| Rusty Scooter | 1.0 | 1.0 | 0 (free) |
| Daily Commuter | 1.3 | 1.15 | 250 |
| 125cc Bike | 1.7 | 1.3 | 750 |
| Sport Bike | 2.2 | 1.5 | 1800 |

**Speed stat drives BOTH ends** (so faster bikes really go faster, not just
start faster):
```
start_speed = 14 + speed*4
top_speed   = max(start_speed + 4, 30 + speed*7)
speed(t)    = min(start_speed + elapsed*0.35, top_speed) + speed_boost_bonus
```
**Handling stat** drives lane-slide rate and lean angle:
```
lane_slide_rate = 8.0 * handling
lean_amount     = 0.25 * handling
```
**Speedometer:** `kmh = round(speed * 2.6)`; dial full-scale 120 km/h; redline
at ~0.84 of the dial.

Other tuning: lane width 2.5; spawn ~150 ahead, despawn ~14 behind; road tile
length ~4 with ~44 pooled tiles; traffic spawn interval ramps from ~1.6s down to
~0.85s with distance.

---

## 7. Engagement systems (port last, after the core loop is fun)

- **Combo / streak:** consecutive coin pickups raise a multiplier; missing coins
  or crashing resets it; milestone pops.
- **Power-ups:** magnet (pulls nearby coins), shield (absorbs one hit),
  multiplier (x2 coins for a duration), speed boost (temporary extra speed). Show
  a timer bar per active power-up.
- **Daily Missions:** a few rotating goals (e.g. "collect N coins", "travel N m",
  "N near-misses") with coin rewards.
- **Random events:** brief themed modifiers (e.g. fiesta = more coins, rush hour
  = denser traffic) announced by a banner.

---

## 8. UE5.8 implementation guidance

- **Blueprints-first** is fine for this scope and iterates fast; drop to **C++**
  for the hot per-frame scroll/curvy-world math if profiling needs it. A clean
  split: a C++ (or BP) **GameMode/Director** actor owns `Distance`, `speed`,
  spawning, scrolling, and the path functions; pooled actors for tiles/traffic/
  coins/power-ups.
- **Treadmill:** keep the player Pawn stationary; move pooled actors. Apply the
  curvy-world offset in each pooled actor's tick (or batched in the Director)
  using the shared `path_x/path_y`.
- **Pooling:** pre-spawn and recycle road tiles, traffic, coins (don't
  Spawn/Destroy every frame) — important for mobile.
- **Collision:** simple box overlaps near the player; logical lane X is exact, so
  overlap tests are trivial. Lanes/collisions use the *logical* (un-displaced)
  positions.
- **Input:** Enhanced Input — a swipe gesture (touch) mapped to lane-left/
  lane-right; keyboard Left/Right/A/D for PC testing.
- **Rendering for mobile:** Forward shading or the Mobile renderer, MSAA,
  keep materials cheap (mostly unlit/▸simple lit, vertex-colour or small
  textures), bake lighting where possible, watch overdraw from transparency
  (particles, fog). Target 60 fps on a mid phone.
- **Assets:** start with primitive/placeholder meshes to prove the loop, then
  swap in low-poly art. **Keep models low-poly (~10–15k tris) and textures
  ≤1K** — the original project's biggest mistake was importing 300k-tri
  AI-generated models that tanked load time and FPS. Budget assets from the
  start.
- **Project settings:** portrait orientation locked; mobile preview; package for
  Android. Set up an Android export early so you can test on device.

---

## 9. Suggested build order (milestones)

1. **Core loop greybox:** player Pawn fixed, pooled road tiles scrolling, swipe
   to change lane between 3 lanes, chase camera. No art.
2. **Curvy world:** add `path_x/path_y` displacement + tile pitch/yaw. Confirm
   collisions stay fair at the player.
3. **Traffic + coins + crash + score:** rows that never block the safe lane;
   coin lines; crash → game over; distance score + Best.
4. **Speed ramp + speedometer + HUD badges.**
5. **Power-ups + combo.**
6. **Lane closure + road split** (the median fork).
7. **Districts + scenery + landmarks + audio.**
8. **Menus, Garage, bikes (data-driven stats), cosmetics, persistence.**
9. **Daily missions + random events.**
10. **Mobile polish:** pooling/perf pass, Android build, on-device testing.

Get steps 1–3 fun before adding anything else.

---

## 10. Scope guardrails (OUT of scope — do not build)

Weather, fuel, passengers, police chases, open maps, multiplayer, real driving
physics, traffic AI, scooter part upgrades. Keep it a tight 3-lane left/right
arcade runner.

---

## 11. First message to give the new session

> "Build *Scooter Hustle* in Unreal Engine 5.8 per this brief, mobile-first
> (Android portrait, swipe controls). Start with milestone 1 (the treadmill core
> loop greybox): a stationary player Pawn, pooled scrolling road tiles, 3-lane
> swipe movement, and a chase camera — no art yet. Then we'll add the curvy-world
> displacement. Confirm your plan before writing code."
