extends Resource
class_name ScooterData
## A simple data container that describes one scooter.
##
## We store each scooter as a Godot Resource (.tres file). Resources are a
## clean, code-free way to keep game data, and the editor can edit the values
## in a nice inspector. Adding a new scooter later is just a matter of creating
## another .tres file - no new code required.

## A short unique id used in save files (e.g. "rusty").
@export var id: String = ""

## The name shown to the player in menus.
@export var display_name: String = "Scooter"

## The .glb model for this bike (resolved via ModelUtil.hd_load, so the PC
## build can use a models/pc/ HD version). Leave empty to use the default
## scooter model.
@export var model_path: String = ""

## Speed multiplier. 1.0 = slow starter, higher = faster top speed.
@export var speed: float = 1.0

## Handling multiplier. Higher = snappier lane changes.
@export var handling: float = 1.0

## How many total coins are needed to unlock it. 0 = free.
@export var price: int = 0

## One-line flavour description for the garage.
@export var description: String = ""
