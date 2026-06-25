# Scooter Hustle — Future Features (NOT yet implemented)

This prototype is intentionally small. The features below are **out of scope**
for the vertical slice and were deliberately left unbuilt. They are listed here
as a roadmap so the architecture can grow toward them.

## Gameplay systems
- [ ] **Fuel / stamina** — a depleting resource that ends the run.
- [ ] **Passengers** — pick up and drop off riders for bonus coins.
- [ ] **Police chase** — a pursuer that ramps pressure.
- [ ] **Power-ups** — magnet (auto-collect coins), shield, coin multiplier, boost.
- [ ] **Missions / daily challenges** — "collect 100 coins", "travel 1km", etc.

## World & content
- [ ] **Weather** — rain, night, fog as visual + difficulty variations.
- [ ] **Maps / districts** — multiple themed environments (city, province, highway).
- [ ] **A real city skyline** instead of the simple road + sky.
- [ ] **Audio** — engine loop, coin chime, crash thud, music (hook points already
      exist: `Coin.collected`, `Player.crashed`, `Player.coin_collected`).
- [ ] **Particles** — coin sparkle, exhaust smoke, crash debris.
- [ ] **Real art** — replace placeholder box meshes with proper models.

## Vehicles & progression
- [ ] **Scooter part upgrades** — upgrade speed/handling per scooter with coins.
- [ ] **More scooters** — easy to add via new `.tres` files in `resources/`.
- [ ] **Cosmetics / skins**.

## Simulation (explicitly avoided for now)
- [ ] **Traffic AI** — lane changing, braking, overtaking.
- [ ] **Real driving physics** — currently arcade lane-snapping only.
- [ ] **Multiplayer** — leaderboards, ghosts, races.

## Polish & infrastructure
- [ ] **Settings menu** — volume, control sensitivity, haptics.
- [ ] **High-score / stats screen** (best distance, total coins, runs played).
- [ ] **Localization**.
- [ ] **Analytics-free, offline-first** (keep it that way: no backend, no ads,
      no microtransactions).

---

### Design guardrails (keep these true as the game grows)
- Stays an **arcade** runner — fast, snappy, readable. Never a sim.
- Exactly **3 lanes**; the player only moves **left/right**.
- **Mobile-first**, portrait, one-thumb playable.
- No plugins, no backend, no multiplayer, no ads, no microtransactions.
