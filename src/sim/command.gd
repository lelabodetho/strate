class_name Command
extends RefCounted
## One player intent for one simulation tick. Produced by src/input, consumed by src/sim.
## This is the only thing that will travel over the network in coop.

var move: Vector2 = Vector2.ZERO   # normalized, world XZ plane
var aim: Vector2 = Vector2.ZERO    # world XZ point under the cursor
var attack: bool = false
var dash: bool = false

func to_dict() -> Dictionary:
	return {"move": [move.x, move.y], "aim": [aim.x, aim.y], "attack": attack, "dash": dash}
