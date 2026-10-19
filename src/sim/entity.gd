class_name SimEntity
extends RefCounted
## Pure data. No Node. Position lives on the XZ plane (Vector2 = x, z).

var id: int
var kind: StringName          # &"player", &"grunt", ...
var pos: Vector2
var vel: Vector2 = Vector2.ZERO
var facing: Vector2 = Vector2.DOWN
var radius: float = 0.4       # body: separation and walls
var hit_radius: float = 0.4   # what a projectile has to touch
var hp: float = 100.0
var hp_max: float = 100.0
var alive: bool = true

# AI / combat state (grunts). Player uses the world-level dash fields.
var state: StringName = &"idle"   # &"idle" | &"chase" | &"windup" | &"recover" | &"return" | &"dead"
var state_t: float = 0.0          # seconds left in the current timed state
var attack_cd: float = 0.0
var spawn_pos: Vector2 = Vector2.ZERO
var aggro_delay: float = 0.0      # > 0: woken by a packmate, will chase when it hits 0
var provoked_t: float = 0.0       # > 0: recently hit, ignores the leash
var pack: int = -1                # wave pack index, -1 for hand-placed grunts

# Elites: a grunt that changes the rule of engagement. Each affix has a counter the starter
# already owns (placement, dash, distance); see SimWorld.AFFIXES.
var elite: bool = false
var affixes: Array[StringName] = []
var fuse_t: float = -1.0          # volatile: >= 0 while the dead body counts down to its blast

func _init(p_id: int, p_kind: StringName, p_pos: Vector2) -> void:
	id = p_id
	kind = p_kind
	pos = p_pos

func has_affix(a: StringName) -> bool:
	return affixes.has(a)

func to_dict() -> Dictionary:
	var d := {
		"id": id, "kind": String(kind),
		"pos": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)],
		"facing": [snappedf(facing.x, 0.01), snappedf(facing.y, 0.01)],
		"radius": radius, "hit_radius": hit_radius,
		"hp": hp, "alive": alive, "state": String(state), "pack": pack,
	}
	if elite:
		d["elite"] = true
		d["affixes"] = affixes.map(func(a: StringName): return String(a))
		d["hp_max"] = hp_max
		d["fuse_t"] = snappedf(fuse_t, 0.001)
	return d
