extends Node
## Autoload "GameState". Holds the SimWorld, drives the sim tick, and serves the test harness.
##
## CLI flags (after `--`):
##   --screenshot=<path>   capture the viewport after N frames, then quit
##   --state=<path>        dump GameState.to_dict() as JSON, then quit
##   --frames=<n>          how many frames to run before capture (default 30)
##   --seed=<n>            world seed (default 1)
##   --debug               view draws body radius and hit radius on the ground
##   --panel               open the tuning panel at start
## In capture mode live input is ignored; the command comes from these flags instead:
##   --move=x,z            held move vector
##   --aim=x,z             world point under the cursor (default: straight down the corridor)
##   --hold=attack         hold the attack button
##   --dash=t1,t2,...      ticks on which dash is pressed

const TUNING_PATH := "res://tools/out/tuning.json"

var world: SimWorld
var debug: bool = false
var _args: Dictionary = {}
var _frames_left: int = -1
var _scripted: bool = false
var _dash_ticks: Array = []
var _recent_events: Array = []   # capture mode: [{tick, events}] for the last RECENT_TICKS ticks
const RECENT_TICKS := 120

func _ready() -> void:
	_args = _parse_args()
	var seed := int(_args.get("seed", "1"))
	debug = _args.has("debug")
	# Reference gameplay values live in tools/out/tuning.json; defaults otherwise.
	world = SimWorld.new(seed, null, SimTuning.load_file(TUNING_PATH))
	if _args.has("screenshot") or _args.has("state"):
		_frames_left = int(_args.get("frames", "30"))
		_scripted = true
		for t in String(_args.get("dash", "")).split(",", false):
			_dash_ticks.append(int(t))

func step(dt: float, cmd: Command) -> void:
	if _scripted:
		cmd = _scripted_command()
	world.step(dt, cmd)
	if _scripted and not world.events.is_empty():
		_recent_events.append({"tick": world.tick, "events": world.to_dict()["events"]})
		while _recent_events.size() > 0 and _recent_events[0].tick < world.tick - RECENT_TICKS:
			_recent_events.pop_front()
	if _frames_left > 0:
		_frames_left -= 1
		if _frames_left == 0:
			_harness_capture.call_deferred()

func to_dict() -> Dictionary:
	var d := world.to_dict()
	if _scripted:
		d["recent_events"] = _recent_events
	return d

func has_arg(key: String) -> bool:
	return _args.has(key)

# Tuning panel entry points: the UI never touches the sim directly.
func set_tuning(key: String, value: float) -> void:
	world.tuning.apply({key: value})

func save_tuning() -> bool:
	return world.tuning.save_file(TUNING_PATH)

func load_tuning() -> void:
	world.tuning = SimTuning.load_file(TUNING_PATH)

func reset_tuning() -> void:
	world.tuning = SimTuning.new()

func _scripted_command() -> Command:
	var c := Command.new()
	c.move = _vec_arg("move", Vector2.ZERO)
	c.aim = _vec_arg("aim", Vector2(0, -20))
	c.attack = String(_args.get("hold", "")).split(",").has("attack")
	c.dash = _dash_ticks.has(world.tick + 1)
	return c

func _vec_arg(key: String, fallback: Vector2) -> Vector2:
	if not _args.has(key):
		return fallback
	var parts: PackedStringArray = String(_args[key]).split(",")
	if parts.size() != 2:
		return fallback
	return Vector2(float(parts[0]), float(parts[1]))

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
