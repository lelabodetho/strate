class_name SimEntity
extends RefCounted
## Pure data. No Node. Position lives on the XZ plane (Vector2 = x, z).

var id: int
var kind: StringName          # &"player", &"grunt", ...
var pos: Vector2
var vel: Vector2 = Vector2.ZERO
var facing: Vector2 = Vector2.DOWN
var hp: float = 100.0
var hp_max: float = 100.0
var alive: bool = true

func _init(p_id: int, p_kind: StringName, p_pos: Vector2) -> void:
	id = p_id
	kind = p_kind
	pos = p_pos

func to_dict() -> Dictionary:
	return {
		"id": id, "kind": String(kind),
		"pos": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)],
		"facing": [snappedf(facing.x, 0.01), snappedf(facing.y, 0.01)],
		"hp": hp, "alive": alive,
	}
