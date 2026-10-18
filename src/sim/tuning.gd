class_name SimTuning
extends RefCounted
## Every gameplay number in one place. SimWorld reads these; nothing else owns them.
## Reference values live in tools/out/tuning.json (saved from the in-game panel), not here.

# [key, min, max, step] — drives the tuning panel sliders and validates loaded files.
const SPECS := [
	["player_speed", 2.0, 12.0, 0.1],
	["player_hp", 10.0, 500.0, 10.0],
	["player_radius", 0.1, 1.0, 0.05],
	["dash_speed", 5.0, 50.0, 0.5],
	["dash_time", 0.05, 0.5, 0.01],
	["dash_cooldown", 0.0, 2.0, 0.05],
	["dash_iframes", 0.0, 1.0, 0.01],
	["fire_interval", 0.03, 1.0, 0.01],
	["proj_speed", 5.0, 60.0, 0.5],
	["proj_damage", 1.0, 100.0, 1.0],
	["proj_ttl", 0.2, 5.0, 0.1],
	["proj_radius", 0.05, 1.0, 0.05],
	["muzzle_offset", 0.0, 2.0, 0.05],
	["knockback", 0.0, 3.0, 0.05],
	["attack_move_mult", 0.1, 1.0, 0.05],
	["grunt_hp", 5.0, 300.0, 5.0],
	["grunt_speed", 0.5, 12.0, 0.1],
	["grunt_damage", 0.0, 100.0, 1.0],
	["grunt_radius", 0.1, 1.0, 0.05],
	["grunt_hit_radius", 0.1, 1.5, 0.05],
	["grunt_reach", 0.0, 2.0, 0.05],
	["grunt_hit_slack", 0.0, 2.0, 0.05],
	["grunt_windup", 0.05, 2.0, 0.01],
	["grunt_recover", 0.0, 3.0, 0.05],
	["grunt_aggro", 1.0, 40.0, 1.0],
]

# Player
var player_speed := 6.0
var player_hp := 100.0
var player_radius := 0.4
var dash_speed := 22.0
var dash_time := 0.18
var dash_cooldown := 0.6
var dash_iframes := 0.25      # invulnerability window, starts with the dash, outlasts it a little

# Player weapon: a plain repeater. Three hits per grunt.
var fire_interval := 0.15
var proj_speed := 20.0
var proj_damage := 10.0
var proj_ttl := 1.5
var proj_radius := 0.25
var muzzle_offset := 0.6
var knockback := 0.8          # displacement applied to whoever takes a hit, along the hit direction
var attack_move_mult := 1.0   # move speed while attacking (hunter: fire_cd > 0, brute: during the swing)

# Grunt: walks at the player, telegraphs, hits at contact, recovers.
var grunt_hp := 30.0
var grunt_speed := 3.5
var grunt_damage := 10.0
var grunt_radius := 0.45      # body: separation and walls
var grunt_hit_radius := 0.55  # what a bullet has to touch
var grunt_reach := 0.35       # extra distance beyond the two radii to start an attack
var grunt_hit_slack := 0.5    # extra distance tolerated when the hit lands (lets the player dodge)
var grunt_windup := 0.4
var grunt_recover := 0.7
var grunt_aggro := 30.0

static func keys() -> PackedStringArray:
	var out := PackedStringArray()
	for s in SPECS:
		out.append(s[0])
	return out

func to_dict() -> Dictionary:
	var d := {}
	for k in keys():
		d[k] = get(k)
	return d

## Apply known keys from a dictionary, clamped to their spec range. Unknown keys are ignored.
func apply(d: Dictionary) -> void:
	for s in SPECS:
		if d.has(s[0]):
			set(s[0], clampf(float(d[s[0]]), s[1], s[2]))

func save_file(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(to_dict(), "  "))
	f.close()
	return true

## Defaults overridden by the file's values; defaults alone if the file is missing or invalid.
static func load_file(path: String) -> SimTuning:
	var t := SimTuning.new()
	if not FileAccess.file_exists(path):
		return t
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		t.apply(parsed)
	return t
