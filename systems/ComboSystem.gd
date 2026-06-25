extends RefCounted
class_name ComboSystem
## Tracks the coin-collection streak and the score multiplier it grants.
##
## Kept as a small standalone object (not in Game.gd) so the rules live in one
## place. A fresh instance is made per run, so it resets automatically. The
## "don't break the streak" tension comes from on_miss()/on_crash() zeroing it.
##
## Multiplier tiers: 5 coins -> x2, 15 -> x3, 30 -> x4.

var count := 0


func multiplier() -> int:
	if count >= 30:
		return 4
	if count >= 15:
		return 3
	if count >= 5:
		return 2
	return 1


## Collect a coin. Returns true if this push crossed a new multiplier milestone
## (so the caller can play a louder/higher cue).
func on_coin() -> bool:
	var before := multiplier()
	count += 1
	return multiplier() > before


## Missing a coin breaks the streak.
func on_miss() -> void:
	count = 0


## Crashing breaks the streak.
func on_crash() -> void:
	count = 0
