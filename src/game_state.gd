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
##   --restart=<frame>     call restart() on that capture frame (tests the death -> R flow)
##   --next=<frame>        call next_wave() on that capture frame
##   --reset=<frame>       call reset_waves() on that capture frame
##   --drop=x,z            put a servo_trigger on the floor at start (tests the pickup flow)
##   --elite=x,z[,affix,...]  hand-placed elite at start (affixes: shielded, volatile, fast)
##   --weapon=<name>       hunter | brute | technomancer
##   --look=<name>         render_test only: load tools/presets/look_<name>.json (default: "default")
##   --mode=<name>         render_test only: pixel | dither | mix (tools/snap.sh picks that scene)
##   --dither=<f>          render_test only: dither strength 0..1
##   --preset=<name>       apply tools/presets/<name>.json at start

const TUNING_PATH := "res://tools/out/tuning.json"
const PRESET_DIR := "res://tools/presets"

var world: SimWorld
var debug: bool = false
var paused: bool = false   # set by the scene while the tuning panel is open; the sim does not step
var preset_name: String = ""   # last preset applied or saved; "" = none
var preset_dirty: bool = false # a slider moved since the preset was applied
# Render test look (not sim tuning): filter, scanlines, viewport scale, lights. The panel
# edits it, F cycles the mode, render_test.gd applies it every frame.
var look := Look.new()
var look_name: String = Look.DEFAULT_NAME
var render_scene: bool = false   # set by render_test.gd so the HUD shows the mode
var _args: Dictionary = {}
var _frames_left: int = -1
var _scripted: bool = false
var _dash_ticks: Array = []
var _recent_events: Array = []   # capture mode: [{tick, events}] for the last RECENT_TICKS ticks
const RECENT_TICKS := 120
var _frame: int = 0
var _frozen: bool = false        # capture mode: the sim stops once the frame budget is spent
var _restart_frame: int = -1
var _next_frame: int = -1
var _reset_frame: int = -1

signal wave_cleared(wave: int)
## Capture mode: emitted right after the main screenshot, before the state dump and quit, so a
## scene can save extra images next to it (render_test dumps its two viewports).
signal capturing(base_path: String)

func _ready() -> void:
	_args = _parse_args()
	var seed := int(_args.get("seed", "1"))
	debug = _args.has("debug")
	look_name = String(_args.get("look", Look.DEFAULT_NAME))
	look.load_file(Look.path(look_name))
	if _args.has("mode"):
		look.apply({"mode": String(_args["mode"])})
	if _args.has("dither"):
		look.apply({"dither": float(_args["dither"])})
	# Reference gameplay values live in tools/out/tuning.json; defaults otherwise.
	world = SimWorld.new(seed, null, SimTuning.load_file(TUNING_PATH))
	if _args.has("preset"):
		apply_preset(String(_args["preset"]))
	if _args.has("weapon"):
		world.set_weapon(String(_args["weapon"]))
	world.begin()
	if _args.has("drop"):
		world.drop_item("servo_trigger", _vec_arg("drop", Vector2.ZERO))
	if _args.has("elite"):
		var parts: PackedStringArray = String(_args["elite"]).split(",")
		if parts.size() >= 2:
			var affixes: Array[StringName] = []
			for i in range(2, parts.size()):
				if SimWorld.AFFIXES.has(StringName(parts[i])):
					affixes.append(StringName(parts[i]))
			world.spawn_elite(Vector2(float(parts[0]), float(parts[1])), affixes)
	if _args.has("screenshot") or _args.has("state"):
		_frames_left = int(_args.get("frames", "30"))
		_scripted = true
		for t in String(_args.get("dash", "")).split(",", false):
			_dash_ticks.append(int(t))
		_restart_frame = int(_args.get("restart", "-1"))
		_next_frame = int(_args.get("next", "-1"))
		_reset_frame = int(_args.get("reset", "-1"))

func step(dt: float, cmd: Command) -> void:
	if _frozen:
		return
	_frame += 1
	if _scripted:
		cmd = _scripted_command()
		if _frame == _restart_frame:
			restart()
		if _frame == _next_frame:
			next_wave()
		if _frame == _reset_frame:
			reset_waves()
	if not paused:
		world.step(dt, cmd)
		for ev in world.events:
			if ev.type == "wave_cleared":
				wave_cleared.emit(ev.wave)
		if _scripted and not world.events.is_empty():
			_recent_events.append({"tick": world.tick, "events": world.to_dict()["events"]})
			while _recent_events.size() > 0 and _recent_events[0].tick < world.tick - RECENT_TICKS:
				_recent_events.pop_front()
	if _frames_left > 0:
		_frames_left -= 1
		if _frames_left == 0:
			# Freeze so the state dump and the screenshot describe the same tick.
			_frozen = true
			_harness_capture.call_deferred()

func to_dict() -> Dictionary:
	var d := world.to_dict()
	d["paused"] = paused
	d["preset"] = preset_label()
	if _scripted:
		d["recent_events"] = _recent_events
		d["restarts"] = restarts
	return d

var restarts: int = 0

## R: same wave again, player at full health at the spawn. No scene reload, tuning untouched.
func restart() -> void:
	world.restart_wave()
	restarts += 1

## N: next wave right now, player state kept.
func next_wave() -> void:
	world.start_wave(world.wave + 1)

## 0: back to wave 1 with a fresh player, items dropped. R keeps them.
func reset_waves() -> void:
	world.reset_run()

func has_arg(key: String) -> bool:
	return _args.has(key)

# Tuning panel entry points: the UI never touches the sim directly.
func set_tuning(key: String, value: float) -> void:
	world.tuning.apply({key: value})
	preset_dirty = true

func save_tuning() -> bool:
	return world.tuning.save_file(TUNING_PATH)

func load_tuning() -> void:
	world.tuning = SimTuning.load_file(TUNING_PATH)
	preset_name = ""
	preset_dirty = false

# Presets: named tuning files in tools/presets/. Applying one changes the live tuning only;
# tools/out/tuning.json is untouched until Save.
func list_presets() -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(PRESET_DIR)
	if dir == null:
		return out
	for f in dir.get_files():
		if f.ends_with(".json"):
			out.append(f.trim_suffix(".json"))
	out.sort()
	return out

func preset_path(name: String) -> String:
	return PRESET_DIR.path_join(name + ".json")

func apply_preset(name: String) -> bool:
	var path := preset_path(name)
	if not FileAccess.file_exists(path):
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		return false
	world.tuning.apply(parsed)
	preset_name = name
	preset_dirty = false
	return true

func save_preset(name: String) -> bool:
	name = name.strip_edges().validate_filename()
	if name.is_empty():
		return false
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(PRESET_DIR))
	if not world.tuning.save_file(preset_path(name)):
		return false
	preset_name = name
	preset_dirty = false
	return true

## "name", "name*" when modified since applied, "" when no preset is active.
func preset_label() -> String:
	if preset_name.is_empty():
		return ""
	return preset_name + ("*" if preset_dirty else "")

func set_weapon(name: String) -> void:
	world.set_weapon(name)

func cycle_render_mode() -> void:
	look.mode = Look.MODES[(look.mode_index() + 1) % Look.MODES.size()]

func save_look(name: String) -> bool:
	name = name.strip_edges().validate_filename()
	if name.is_empty():
		return false
	look_name = name
	return look.save_file(Look.path(name))

func load_look(name: String) -> bool:
	name = name.strip_edges().validate_filename()
	if name.is_empty():
		return false
	look_name = name
	return look.load_file(Look.path(name))

func reset_tuning() -> void:
	world.tuning = SimTuning.new()
	preset_name = ""
	preset_dirty = false

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
		capturing.emit(String(_args["screenshot"]).trim_suffix(".png"))
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
