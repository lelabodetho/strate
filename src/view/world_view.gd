class_name WorldView
extends Node3D
## Owns one EntityView per sim entity and keeps them in sync.

var _views: Dictionary = {}  # id -> EntityView

func sync(world: SimWorld) -> void:
	for e in world.entities.values():
		var v: EntityView = _views.get(e.id)
		if v == null:
			v = EntityView.new()
			v.setup(e)
			add_child(v)
			_views[e.id] = v
		v.sync(e, world.is_dashing() and e.id == world.player_id)
