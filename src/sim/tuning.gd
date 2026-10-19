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
	["grunt_turn_rate", 60.0, 1080.0, 30.0],
	["elite_shield_turn_rate", 30.0, 720.0, 10.0],
	["aggro_share_radius", 0.0, 10.0, 0.5],
	["aggro_drop_mult", 1.0, 4.0, 0.1],
	["provoke_time", 0.0, 15.0, 0.5],
	["item_drop_chance", 0.0, 1.0, 0.05],
	["wave_delay", 0.5, 15.0, 0.5],
	["wave_cap", 3.0, 24.0, 1.0],
	["pack_spacing", 0.0, 20.0, 1.0],
	["elite_from_wave", 0.0, 20.0, 1.0],
	["elite_every", 1.0, 5.0, 1.0],
	["elite_hp_mult", 1.0, 10.0, 0.5],
	["elite_damage_mult", 1.0, 5.0, 0.1],
	["elite_body_mult", 1.0, 2.0, 0.05],
	["elite_shield_reduction", 0.0, 1.0, 0.05],
	["elite_shield_angle", 30.0, 360.0, 10.0],
	["elite_fuse", 0.1, 3.0, 0.1],
	["elite_blast_radius", 0.5, 6.0, 0.25],
	["elite_blast_damage_mult", 0.0, 5.0, 0.25],
	["elite_fast_mult", 1.0, 3.0, 0.1],
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
var grunt_turn_rate := 720.0   # deg/s the facing may rotate while idle, chasing or returning (≈ a snap)
var elite_shield_turn_rate := 150.0  # a shielded elite turns this slowly instead: dash past it to reach its back
var aggro_share_radius := 4.0  # a waking grunt wakes idle grunts within this distance
var aggro_drop_mult := 1.8     # a chasing grunt farther than grunt_aggro * this gives up and walks home
var provoke_time := 4.0        # a hit grunt ignores the leash for this long, re-armed on every hit

# Loot
var item_drop_chance := 0.2    # chance a dying grunt leaves an item on the floor

# Wave pacing: the arena imitates the rhythm of a zone (packs spread out, one pull at a time,
# a breath between pulls).
var wave_delay := 2.0          # seconds between the last kill and the next wave
var wave_cap := 12.0           # max grunts per wave
var pack_spacing := 0.0        # min distance between two pack centers of a wave; 0 = off

# Elites: one on every elite_every-th wave from elite_from_wave (0 = never), leading a pack.
# Tougher body, and one affix (two from SimWorld.ELITE_SECOND_AFFIX_WAVE) that each have a
# counter the starter owns.
var elite_from_wave := 2.0
var elite_every := 1.0
var elite_hp_mult := 3.0
var elite_damage_mult := 1.5
var elite_body_mult := 1.2          # radius and hit radius
var elite_shield_reduction := 0.7   # shielded: frontal hits lose this fraction of damage and knockback
var elite_shield_angle := 120.0     # shielded: full width of the frontal cone, degrees (counter: flank)
var elite_fuse := 0.6               # volatile: seconds between the kill and the blast (counter: step back, dash)
var elite_blast_radius := 2.0
var elite_blast_damage_mult := 2.0  # volatile: blast damage = grunt_damage × this
var elite_fast_mult := 1.6          # fast: chase speed × this (counter: distance, dash)

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
