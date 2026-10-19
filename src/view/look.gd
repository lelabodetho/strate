class_name Look
extends RefCounted
## The render test's look: post filter, lighting and camera parameters. View-side only, nothing
## here touches the sim. Edited from the "rendu" block of the tuning panel, saved as
## tools/presets/look_<name>.json; render_test loads look_default.json at startup if present.

const MODES := ["pixel", "dither", "mix"]
# [key, min, max, step] — numeric sliders of the panel; also clamps loaded files.
const SPECS := [
	["dither", 0.0, 1.0, 0.05],
	["scanlines", 0.0, 1.0, 0.05],
	["viewport_scale", 2.0, 4.0, 1.0],
	["player_light_energy", 0.0, 6.0, 0.1],
	["cold_light_energy", 0.0, 6.0, 0.1],
	["camera_pitch", 30.0, 65.0, 1.0],
	["camera_size", 14.0, 34.0, 1.0],
]
const DIR := "res://tools/presets"
const DEFAULT_NAME := "default"

var mode: String = "mix"
var dither := 0.5             # Bayer threshold spread (dither) / jitter amplitude (mix)
var scanlines := 0.5          # 0 = none, 1 = every third screen row at 72 %
var viewport_scale := 2       # the 3D viewports render at 1/scale of the window
var player_light_color := Color(1.0, 0.84, 0.64)
var player_light_energy := 2.0
var cold_light_energy := 2.0
var camera_pitch := 50.0      # degrees above the ground plane; the yaw stays the 45-degree iso
var camera_size := 24.0       # orthographic height of the view, in world units

static func path(name: String) -> String:
	return DIR.path_join("look_" + name + ".json")

func mode_index() -> int:
	return maxi(0, MODES.find(mode))

func to_dict() -> Dictionary:
	var d := {"mode": mode, "player_light_color": player_light_color.to_html(false)}
	for s in SPECS:
		d[s[0]] = get(s[0])
	return d

## Known keys only, numbers clamped to their spec range.
func apply(d: Dictionary) -> void:
	if d.has("mode") and MODES.has(String(d.mode)):
		mode = String(d.mode)
	if d.has("player_light_color") and Color.html_is_valid(String(d.player_light_color)):
		player_light_color = Color.html(String(d.player_light_color))
	for s in SPECS:
		if d.has(s[0]):
			var v := clampf(float(d[s[0]]), s[1], s[2])
			set(s[0], int(v) if s[0] == "viewport_scale" else v)

func save_file(p: String) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIR))
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict(), "  "))
	f.close()
	return true

## True if the file existed and parsed; the look is left untouched otherwise.
func load_file(p: String) -> bool:
	if not FileAccess.file_exists(p):
		return false
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(p))
	if not parsed is Dictionary:
		return false
	apply(parsed)
	return true
