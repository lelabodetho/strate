extends Node
## Autoload "GameState". Holds the SimWorld, drives the sim tick, and serves the test harness.
##
## CLI flags (after `--`):
##   --screenshot=<path>   capture the viewport after N frames, then quit
##   --state=<path>        dump GameState.to_dict() as JSON, then quit
##   --frames=<n>          how many frames to run before capture (default 30)
##   --seed=<n>            world seed (default 1)

var world: SimWorld
var _args: Dictionary = {}
var _frames_left: int = -1

func _ready() -> void:
	_args = _parse_args()
	var seed := int(_args.get("seed", "1"))
	world = SimWorld.new(seed)
	if _args.has("screenshot") or _args.has("state"):
		_frames_left = int(_args.get("frames", "30"))

func step(dt: float, cmd: Command) -> void:
	world.step(dt, cmd)
	if _frames_left > 0:
		_frames_left -= 1
		if _frames_left == 0:
			_harness_capture.call_deferred()

func to_dict() -> Dictionary:
	return world.to_dict()

func _harness_capture() -> void:
	await RenderingServer.frame_post_draw
	if _args.has("screenshot"):
		var img := get_viewport().get_texture().get_image()
		img.save_png(_args["screenshot"])
		print("[harness] screenshot -> ", _args["screenshot"])
	if _args.has("state"):
		var f := FileAccess.open(_args["state"], FileAccess.WRITE)
		f.store_string(JSON.stringify(to_dict(), "  "))
		f.close()
		print("[harness] state -> ", _args["state"])
	get_tree().quit()

func _parse_args() -> Dictionary:
	var out := {}
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			out[kv[0]] = kv[1] if kv.size() > 1 else "true"
	return out
