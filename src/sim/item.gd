class_name SimItem
extends RefCounted
## Pure data. A thing on the floor the player walks over. Its `mods` are SimStats modifiers
## ({stat, pct, flat}) applied to the player on pickup, under source = item id.

const KINDS := ["servo_trigger"]

var id: int
var kind: String
var pos: Vector2
var mods: Array = []   # [{stat, pct, flat}]

func _init(p_id: int, p_kind: String, p_pos: Vector2) -> void:
	id = p_id
	kind = p_kind
	pos = p_pos
	mods = mods_for(p_kind)

## The modifiers each kind carries. Only one kind for now.
static func mods_for(p_kind: String) -> Array:
	match p_kind:
		"servo_trigger":
			return [{"stat": "fire_rate", "pct": 0.30}]
		_:
			return []

func to_dict() -> Dictionary:
	return {
		"id": id, "kind": kind,
		"pos": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)],
		"mods": mods.duplicate(true),
	}
