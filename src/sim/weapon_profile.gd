class_name WeaponProfile
extends RefCounted
## How the player's attack button turns into damage. Not a class: a profile the player can
## switch at any time (keys 1/2/3). Its numbers are SimStats modifiers (source "weapon") with
## `mult` on the current tuning, so tuning presets stay comparable across profiles and item
## bonuses (pct) read the same on every profile. Geometry (cone, blast) is absolute.

const NAMES := ["hunter", "brute", "technomancer"]

var name: String = "hunter"
var kind: StringName = &"projectile"   # &"projectile" | &"cone" | &"blast"
var attack_move := true        # tuning.attack_move_mult applies while attacking
var mods: Array = []           # [{stat, mult}|{stat, flat}] applied to the player under source "weapon"

# cone (brute)
var cone_angle_deg := 90.0
var cone_range := 1.6
var swing_time := 0.15
var lunge := 0.8               # distance covered along the aim during swing_time

# blast (technomancer)
var blast_radius := 2.0
var blast_edge_factor := 0.25  # damage at the edge, as a fraction of the center damage

static func hunter() -> WeaponProfile:
	return WeaponProfile.new()

## No projectile: a 90-degree sweep in front of the player, 2.5x damage, 0.5 s cadence,
## double knockback, a short lunge along the aim, a thicker body with i-frames on the swing.
static func brute() -> WeaponProfile:
	var w := WeaponProfile.new()
	w.name = "brute"
	w.kind = &"cone"
	w.mods = [
		{"stat": "proj_damage", "mult": 2.5},
		{"stat": "knockback", "mult": 2.0},
		{"stat": "fire_rate", "mult": 0.15 / 0.5},   # 0.5 s with the default 0.15 s
		{"stat": "player_hp", "mult": 1.6},
		{"stat": "damage_taken", "mult": 0.65},
		{"stat": "attack_iframes", "flat": 0.12},
	]
	return w

## Slow, fat projectile that bursts on contact or at end of life: 2x damage at the center,
## falling off toward a 1.4-unit edge, 0.8 s cadence. Moves freely while firing. Frail.
static func technomancer() -> WeaponProfile:
	var w := WeaponProfile.new()
	w.name = "technomancer"
	w.kind = &"blast"
	w.blast_radius = 1.4
	w.attack_move = false
	w.mods = [
		{"stat": "proj_damage", "mult": 2.0},
		{"stat": "fire_rate", "mult": 0.15 / 0.8},   # 0.8 s with the default 0.15 s
		{"stat": "proj_speed", "mult": 8.0 / 20.0},  # 8 with the default 20
		{"stat": "proj_radius", "mult": 0.35 / 0.25},  # 0.35 with the default 0.25
		{"stat": "player_hp", "mult": 0.85},
		{"stat": "damage_taken", "mult": 1.1},
	]
	return w

static func by_name(n: String) -> WeaponProfile:
	match n:
		"brute":
			return brute()
		"technomancer":
			return technomancer()
		_:
			return hunter()

func to_dict() -> Dictionary:
	return {"name": name, "kind": String(kind)}
