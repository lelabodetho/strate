class_name SimLevel
extends RefCounted
## Static geometry on the XZ plane (Vector2 = x, z). Pure data, no Node.
## Walkable area = union of floors minus walls. Walls are axis-aligned rects.
## A level comes from code (arena(), the tuning arena) or from data/levels/<name>.json through
## from_dict(): floors, walls (auto_walls() around the floors when absent), player_spawn,
## hand-placed packs, an exit rect (strate -> hub), a descend rect (hub -> strate). The loader
## validates (kind, spawn, pack centers and exit on a floor) and returns null, with an error,
## on anything else.

const WALL_HEIGHT := 2.5
const WALL_THICKNESS := 1.0
const KINDS := ["arena", "hub", "strate"]
const DIR := "res://data/levels"

var name: String = "arena"
var kind: String = "arena"
var bounds: Rect2                 # union of floors
var floors: Array[Rect2] = []     # walkable rects
var walls: Array[Rect2] = []
var player_spawn: Vector2 = Vector2.ZERO
# Hand-placed packs: [{pos: Vector2, size: int, elite: bool, affixes: Array[StringName]}].
# Empty = the wave arena (SimWorld.start_wave) runs instead.
var packs: Array[Dictionary] = []
var exit: Rect2 = Rect2()         # zero size = no exit
var descend: Rect2 = Rect2()      # zero size = no descend pad

static func path(level_name: String) -> String:
	return DIR.path_join(level_name + ".json")

## null (and an error) when the file is missing, not JSON, or fails validation.
static func load_file(p: String) -> SimLevel:
	if not FileAccess.file_exists(p):
		push_error("SimLevel: no such level file: " + p)
		return null
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
	if not parsed is Dictionary:
		push_error("SimLevel: not a JSON object: " + p)
		return null
	return from_dict(parsed)

## Build and validate a level from its dictionary (the JSON shape, see data/levels/*.json).
static func from_dict(d: Dictionary) -> SimLevel:
	var l := SimLevel.new()
	l.name = String(d.get("name", "level"))
	l.kind = String(d.get("kind", "strate"))
	if not KINDS.has(l.kind):
		return _reject(l, "kind must be one of %s, got '%s'" % [KINDS, l.kind])
	for f in d.get("floors", []):
		var r: Variant = _rect(f)
		if r == null or not (r as Rect2).has_area():
			return _reject(l, "every floor must be [x, z, w, h] with w, h > 0")
		l.floors.append(r)
	if l.floors.is_empty():
		return _reject(l, "a level needs at least one floor")
	l.bounds = l.floors[0]
	for f in l.floors:
		l.bounds = l.bounds.merge(f)
	if d.has("walls"):
		for w in d.walls:
			var r: Variant = _rect(w)
			if r == null:
				return _reject(l, "every wall must be [x, z, w, h]")
			l.walls.append(r)
	else:
		l.walls = auto_walls(l.floors)
	var sp = d.get("player_spawn")
	if not (sp is Array and sp.size() == 2):
		return _reject(l, "player_spawn must be [x, z]")
	l.player_spawn = Vector2(float(sp[0]), float(sp[1]))
	if not l.on_floor(l.player_spawn):
		return _reject(l, "player_spawn %s is off the floor" % l.player_spawn)
	for entry in d.get("packs", []):
		if not (entry is Dictionary and entry.get("pos") is Array and entry.pos.size() == 2):
			return _reject(l, "every pack needs pos: [x, z]")
		var pack := {
			"pos": Vector2(float(entry.pos[0]), float(entry.pos[1])),
			"size": maxi(1, int(entry.get("size", 3))),
			"elite": bool(entry.get("elite", false)),
			"affixes": [] as Array[StringName],
		}
		for a in entry.get("affixes", []):
			pack.affixes.append(StringName(String(a)))   # names checked by SimWorld.make_elite
		if not l.on_floor(pack.pos):
			return _reject(l, "pack center %s is off the floor" % pack.pos)
		l.packs.append(pack)
	for key in ["exit", "descend"]:
		if d.get(key) == null:
			continue
		var r: Variant = _rect(d[key])
		if r == null or not (r as Rect2).has_area():
			return _reject(l, "%s must be [x, z, w, h] with w, h > 0" % key)
		if not l.on_floor((r as Rect2).get_center()):
			return _reject(l, "%s %s is off the floor" % [key, r])
		l.set(key, r)
	return l

static func _reject(l: SimLevel, why: String) -> SimLevel:
	push_error("SimLevel '%s': %s" % [l.name, why])
	return null

static func _rect(v) -> Variant:
	if v is Array and v.size() == 4:
		return Rect2(float(v[0]), float(v[1]), float(v[2]), float(v[3]))
	return null

## Walls of WALL_THICKNESS around every floor, open where two floors touch edge to edge. The
## strips along x (north and south) run a thickness past both corners so the corners close.
static func auto_walls(fl: Array[Rect2]) -> Array[Rect2]:
	var out: Array[Rect2] = []
	var t := WALL_THICKNESS
	for f in fl:
		# north (z-) and south (z+): openings are the x-overlap of a floor touching that edge
		for side in [[f.position.y - t, f.position.y, true], [f.end.y, f.end.y, false]]:
			var z: float = side[0]
			var open: Array = []
			for g in fl:
				if g == f:
					continue
				var touches: bool = (is_equal_approx(g.end.y, f.position.y) if side[2] else is_equal_approx(g.position.y, f.end.y))
				if touches:
					var a := maxf(f.position.x, g.position.x)
					var b := minf(f.end.x, g.end.x)
					if b > a:
						open.append([a, b])
			for piece in _cut([f.position.x - t, f.end.x + t], open):
				out.append(Rect2(piece[0], z, piece[1] - piece[0], t))
		# west (x-) and east (x+)
		for side in [[f.position.x - t, true], [f.end.x, false]]:
			var x: float = side[0]
			var open: Array = []
			for g in fl:
				if g == f:
					continue
				var touches: bool = (is_equal_approx(g.end.x, f.position.x) if side[1] else is_equal_approx(g.position.x, f.end.x))
				if touches:
					var a := maxf(f.position.y, g.position.y)
					var b := minf(f.end.y, g.end.y)
					if b > a:
						open.append([a, b])
			for piece in _cut([f.position.y, f.end.y], open):
				out.append(Rect2(x, piece[0], t, piece[1] - piece[0]))
	# A corner extension that lands inside a neighbouring floor (the jambs of a doorway) goes.
	return out.filter(func(w: Rect2) -> bool:
		for g in fl:
			if g.encloses(w):
				return false
		return true)

## The parts of [lo, hi] outside every [a, b] of `open`.
static func _cut(span: Array, open: Array) -> Array:
	var pieces := [span]
	for o in open:
		var next := []
		for p in pieces:
			if o[1] <= p[0] or o[0] >= p[1]:
				next.append(p)
				continue
			if o[0] > p[0]:
				next.append([p[0], o[0]])
			if o[1] < p[1]:
				next.append([o[1], p[1]])
		pieces = next
	return pieces.filter(func(p): return p[1] - p[0] > 0.001)

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

static func _rect_or_null(r: Rect2) -> Variant:
	return [r.position.x, r.position.y, r.size.x, r.size.y] if r.has_area() else null

## The JSON shape: from_dict(to_dict()) gives the same level.
func to_dict() -> Dictionary:
	var pk := []
	for p in packs:
		pk.append({"pos": [p.pos.x, p.pos.y], "size": p.size, "elite": p.elite,
			"affixes": p.affixes.map(func(a: StringName): return String(a))})
	return {
		"name": name, "kind": kind,
		"bounds": [bounds.position.x, bounds.position.y, bounds.size.x, bounds.size.y],
		"player_spawn": [player_spawn.x, player_spawn.y],
		"floors": _rects(floors),
		"walls": _rects(walls),
		"packs": pk,
		"exit": _rect_or_null(exit),
		"descend": _rect_or_null(descend),
	}
