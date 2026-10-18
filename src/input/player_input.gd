class_name PlayerInput
extends Node
## Turns Godot Input into a Command. Needs the camera to project the mouse onto the ground plane.

@export var camera: Camera3D

func read() -> Command:
	var c := Command.new()
	c.move = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	c.attack = Input.is_action_pressed("attack")
	c.dash = Input.is_action_just_pressed("dash")
	c.aim = _mouse_on_ground()
	return c

func _mouse_on_ground() -> Vector2:
	if camera == null:
		return Vector2.ZERO
	var m := get_viewport().get_mouse_position()
	var from := camera.project_ray_origin(m)
	var dir := camera.project_ray_normal(m)
	var plane := Plane(Vector3.UP, 0.0)
	var hit = plane.intersects_ray(from, dir)
	if hit == null:
		return Vector2.ZERO
	return Vector2(hit.x, hit.z)
