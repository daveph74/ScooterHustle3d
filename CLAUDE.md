# Scooter Hustle — project context for Claude

**This is a PHONE-BASED game. Always design and build for mobile first.**

- **Target:** Android, **portrait** orientation (1080×1920), touch-first.
- **Controls:** swipe left/right only (3 lanes, auto-forward). Keyboard `←/→`/`A`/`D` exists only for desktop testing. Never add controls that assume a keyboard/mouse.
- **Performance:** keep effects lightweight — it must run smoothly on a phone. Be mindful of per-frame node counts, draw calls, and overdraw.
- **UI:** must be clean, large-tap-target, and readable in portrait on a small screen.
- **Engine:** Godot **4.7**, GDScript only. No C#, no external Godot plugins, no backend, no ads, no multiplayer, no microtransactions.

## Working agreement
- Develop on branch `claude/elegant-lamport-nv40yn`; commit + push changes; draft PR #1 targets `main`.
- Read **HANDOVER.md** for full architecture (the "treadmill" + "curvy world" tricks, file map, systems, tuning knobs, gotchas).
- Godot 4.7 is strict about typed arrays / `:=` inference — see HANDOVER §9.

## Scope guardrails
Keep it an arcade 3-lane left/right runner. OUT of scope (see TODO.md): weather,
fuel, passengers, police, maps, multiplayer, real driving physics, traffic AI,
scooter part upgrades.
