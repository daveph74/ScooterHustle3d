# models/pc/ — high-res asset overrides (PC build)

Drop a higher-resolution `.glb` here with the **same filename** as the standard
model and the game will automatically use it **in place of** the one in
`models/custom/` (or `models/city/`). If no override exists, the standard model
is used — so this folder is optional and can hold just the few models you care
about.

How it works: every model is loaded through `ModelUtil.hd_load(path)` /
`ModelUtil.hd_path(path)` (see `systems/ModelUtil.gd`), which checks
`res://models/pc/<filename>` first.

Examples — to ship a sharper scooter and rider on PC, export them from Meshy at
2K textures and save as:

    models/pc/scooter.glb
    models/pc/rider.glb

Other names the game looks for: `jeepney.glb`, `bus.glb`, `taxi.glb`,
`tricycle.glb`, `coin.glb`, `man.glb`, the landmark storefronts
(`jollibee.glb`, `church.glb`, `petron.glb`, …), power-ups
(`magnet/shield/multiplier/speed.glb`), and props (`bench.glb`,
`construction-barrier.glb`, …).

This folder is for the **pc-landscape** branch; the mobile build on `main`
ignores it (its models stay the lighter, optimised versions).
