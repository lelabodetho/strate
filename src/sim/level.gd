class_name SimLevel
extends RefCounted
## Static geometry on the XZ plane (Vector2 = x, z). Pure data, no Node.
## Walkable area = bounds minus walls. Walls are axis-aligned rects.

const WALL_HEIGHT := 2.5

var bounds: Rect2
var walls: Array[Rect2] = []

## A straight corridor centered on the origin, long axis along z.
static func corridor(width: float, length: float, thickness: float = 1.0) -> SimLevel:
	var l := SimLevel.new()
	var hw := width * 0.5
	var hl := length * 0.5
	l.bounds = Rect2(-hw, -hl, width, length)
	l.walls.append(Rect2(-hw - thickness, -hl - thickness, thickness, length + 2.0 * thickness))  # west (x-)
	l.walls.append(Rect2(hw, -hl - thickness, thickness, length + 2.0 * thickness))               # east (x+)
	l.walls.append(Rect2(-hw, -hl - thickness, width, thickness))                                  # far  (z-)
	l.walls.append(Rect2(-hw, hl, width, thickness))                                               # near (z+)
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

## True if a point is inside a wall or outside the bounds.
func is_blocked(p: Vector2) -> bool:
	if not bounds.has_point(p):
		return true
	for w in walls:
		if w.has_point(p):
			return true
	return false

func to_dict() -> Dictionary:
	var ws := []
	for w in walls:
		ws.append([w.position.x, w.position.y, w.size.x, w.size.y])
	return {
		"bounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
		"walls": ws,
	}
