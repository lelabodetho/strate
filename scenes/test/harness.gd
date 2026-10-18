extends Node3D
## Test harness scene: iso camera, flat arena, one player cube. The agent runs this via tools/snap.sh.

@onready var cam: Camera3D = $Camera3D
@onready var world_view: WorldView = $WorldView
@onready var input: PlayerInput = $PlayerInput

func _ready() -> void:
	input.camera = cam
	var w: SimWorld = GameState.world
	if w.player() == null:
		w.spawn(&"player", Vector2.ZERO)
		w.spawn(&"grunt", Vector2(4, -3))
		w.spawn(&"grunt", Vector2(-5, 2))
		w.spawn(&"grunt", Vector2(3, 5))
	world_view.sync(w)

func _physics_process(dt: float) -> void:
	GameState.step(dt, input.read())
	world_view.sync(GameState.world)
