class_name PlayerInput
extends Node
## Turns Godot Input into a Command. Needs the camera to project the mouse onto the ground plane
## and to find the floor item under the cursor (hovered_item_id, read by the scene for the view).

# Where a floor item sits for the cursor: the gem floats at this height, the pick sphere wraps it.
const ITEM_PICK_HEIGHT := 0.75
const ITEM_PICK_RADIUS := 0.6

@export var camera: Camera3D
## Set by the scene while a UI panel is open: movement still works, attack, dash, E and click
## pickup are ignored.
var combat_locked: bool = false
## Floor item under the cursor this tick, 0 if none. Computed by read().
var hovered_item_id: int = 0
var _press_on_item := false   # the current mouse press started on an item: it never fires

func read() -> Command:
	var c := Command.new()
	c.move = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	c.aim = _mouse_on_ground()
	hovered_item_id = _item_under_mouse(GameState.world)
	var pressed := Input.is_action_pressed("attack") and not combat_locked
	var just := Input.is_action_just_pressed("attack") and not combat_locked
	if just:
		_press_on_item = hovered_item_id != 0
	elif not pressed:
		_press_on_item = false
	# A press on an item is a pickup, and holding that press never shoots; a held fire button
	# sweeping over an item picks nothing up.
	c.pickup_id = hovered_item_id if just and _press_on_item else 0
	c.attack = pressed and not _press_on_item
	c.dash = Input.is_action_just_pressed("dash") and not combat_locked
	c.interact = Input.is_action_just_pressed("interact") and not combat_locked
	return c

func _mouse_on_ground() -> Vector2:
	if camera == null:
		return Vector2.ZERO
	var from := camera.project_ray_origin(_mouse())
	var dir := camera.project_ray_normal(_mouse())
	var plane := Plane(Vector3.UP, 0.0)
	var hit = plane.intersects_ray(from, dir)
	if hit == null:
		return Vector2.ZERO
	return Vector2(hit.x, hit.z)

## The floor item whose pick sphere the mouse ray passes closest to, 0 if none.
func _item_under_mouse(world: SimWorld) -> int:
	if camera == null or world == null:
		return 0
	var from := camera.project_ray_origin(_mouse())
	var dir := camera.project_ray_normal(_mouse())
	var best := 0
	var best_d := ITEM_PICK_RADIUS
	for it in world.items.values():
		var center := Vector3(it.pos.x, ITEM_PICK_HEIGHT, it.pos.y)
		var t := (center - from).dot(dir)
		if t < 0.0:
			continue
		var d := (from + dir * t).distance_to(center)
		if d <= best_d:
			best = it.id
			best_d = d
	return best

func _mouse() -> Vector2:
	# The camera's own viewport: a SubViewport maps the mouse through its container.
	return camera.get_viewport().get_mouse_position()
