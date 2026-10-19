class_name Command
extends RefCounted
## One player intent for one simulation tick. Produced by src/input, consumed by src/sim.
## This is the only thing that will travel over the network in coop.

var move: Vector2 = Vector2.ZERO   # normalized, world XZ plane
var aim: Vector2 = Vector2.ZERO    # world XZ point under the cursor
var attack: bool = false
var dash: bool = false
var interact: bool = false         # pressed this tick: pick up the nearest floor item (E)
var pickup_id: int = 0             # pressed this tick on that floor item (click); 0 = none
var target_id: int = -1            # enemy snapped under the cursor (SimWorld.target_at); -1 = none

func to_dict() -> Dictionary:
	return {"move": [move.x, move.y], "aim": [aim.x, aim.y], "attack": attack, "dash": dash, "interact": interact, "pickup_id": pickup_id, "target_id": target_id}
