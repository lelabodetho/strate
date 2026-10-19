class_name SimProjectile
extends RefCounted
## Pure data. A bullet on the XZ plane. Hits anything alive that is not on the owner's side.

var id: int
var owner_id: int
var owner_kind: StringName
var pos: Vector2
var vel: Vector2
var radius: float = 0.25
var damage: float = 10.0
var knockback: float = 0.8   # displacement given to whoever it hits
var ttl: float = 1.5
var blast_radius: float = 0.0   # > 0: bursts on contact, wall or end of life instead of a direct hit

func _init(p_id: int, p_owner: SimEntity, p_pos: Vector2, p_vel: Vector2) -> void:
	id = p_id
	owner_id = p_owner.id
	owner_kind = p_owner.kind
	pos = p_pos
	vel = p_vel

func to_dict() -> Dictionary:
	return {
		"id": id, "owner": owner_id,
		"pos": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)],
		"vel": [snappedf(vel.x, 0.01), snappedf(vel.y, 0.01)],
		"radius": radius,
	}
