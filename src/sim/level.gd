class_name SimLevel
extends RefCounted
## Static geometry on the XZ plane (Vector2 = x, z). Pure data, no Node.
## Walkable area = union of floors minus walls. Walls are axis-aligned rects.

const WALL_HEIGHT := 2.5

var bounds: Rect2                 # union of floors
var floors: Array[Rect2] = []     # walkable rects
var walls: Array[Rect2] = []
var player_spawn: Vector2 = Vector2.ZERO

## A straight corridor centered on the origin, long axis along z. Player spawns near the z+ end.
static func corridor(width: float, length: float, thickness: float = 1.0) -> SimLevel:
	var l := SimLevel.new()
	var hw := width * 0.5
	var hl := length * 0.5
	l.bounds = Rect2(-hw, -hl, width, length)
	l.floors.append(l.bounds)
	l.player_spawn = Vector2(0, hl - 3.0)
	l.walls.append(Rect2(-hw - thickness, -hl - thickness, thickness, length + 2.0 * thickness))  # west (x-)
	l.walls.append(Rect2(hw, -hl - thickness, thickness, length + 2.0 * thickness))               # east (x+)
	l.walls.append(Rect2(-hw, -hl - thickness, width, thickness))                                  # far  (z-)
	l.walls.append(Rect2(-hw, hl, width, thickness))                                               # near (z+)
	return l

## The tuning arena: the 6x24 corridor opens north (z-) into a 16x20 room holding two 2x2
## pillars with a 4-unit gap between them. Player spawns at the south end of the corridor.
static func arena() -> SimLevel:
	var l := SimLevel.new()
	var corridor := Rect2(-3, -12, 6, 24)
	var room := Rect2(-8, -32, 16, 20)
	l.floors = [corridor, room]
	l.bounds = corridor.merge(room)
	l.player_spawn = Vector2(0, 9)
	l.walls = [
		Rect2(-4, -12, 1, 25),   # corridor west, from the room's south wall down to the near wall
		Rect2(3, -12, 1, 25),    # corridor east
		Rect2(-4, 12, 8, 1),     # near (south) wall
		Rect2(-9, -13, 6, 1),    # room south wall, west of the corridor mouth
		Rect2(3, -13, 6, 1),     # room south wall, east of the corridor mouth
		Rect2(-9, -33, 1, 21),   # room west
		Rect2(8, -33, 1, 21),    # room east
		Rect2(-9, -33, 18, 1),   # room north
		Rect2(-4, -23, 2, 2),    # pillar west
		Rect2(2, -23, 2, 2),     # pillar east  (gap x in [-2, 2])
	]
	return l

## Push a circle out of every wall, then keep it inside bounds.
func resolve_circle(pos: Vector2, radius: float) -> Vector2:
	for w in walls:
		var closest := Vector2(clampf(pos.x, w.position.x, w.end.x), clampf(pos.y, w.position.y, w.end.y))
		var d := pos - closest
		var dist := d.length()
		if dist < radius:
			if dist < 0.0001:
				# Center exactly inside the wall: push toward the level center.
				d = bounds.get_center() - pos
				if d.length() < 0.0001:
					d = Vector2.RIGHT
				pos = closest + d.normalized() * radius
			else:
				pos = closest + d / dist * radius
	var r := Vector2(radius, radius)
	return pos.clamp(bounds.position + r, bounds.end - r)

func on_floor(p: Vector2) -> bool:
	for f in floors:
		if f.has_point(p):
			return true
	return false

## True if a point is inside a wall or off every floor.
func is_blocked(p: Vector2) -> bool:
	if not on_floor(p):
		return true
	for w in walls:
		if w.has_point(p):
			return true
	return false

## True if a circle fits there without touching a wall or leaving the floor.
func circle_fits(p: Vector2, radius: float) -> bool:
	if not on_floor(p):
		return false
	return resolve_circle(p, radius).distance_to(p) < 0.001

static func _rects(list: Array[Rect2]) -> Array:
	var out := []
	for r in list:
		out.append([r.position.x, r.position.y, r.size.x, r.size.y])
	return out

func to_dict() -> Dictionary:
	return {
		"bounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
		"player_spawn": [player_spawn.x, player_spawn.y],
		"floors": _rects(floors),
		"walls": _rects(walls),
	}
