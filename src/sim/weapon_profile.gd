class_name WeaponProfile
extends RefCounted
## How the player's attack button turns into damage. Not a class: a profile the player can
## switch at any time (keys 1/2/3). Every number is a multiplier on the current SimTuning, so
## tuning presets stay comparable across profiles. Geometry (cone, blast) is absolute.

const NAMES := ["hunter", "brute", "technomancer"]

var name: String = "hunter"
var kind: StringName = &"projectile"   # &"projectile" | &"cone" | &"blast"
var damage_mult := 1.0
var knockback_mult := 1.0
var fire_interval_mult := 1.0
var proj_speed_mult := 1.0
var proj_radius_mult := 1.0

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
## double knockback, and a short lunge along the aim.
static func brute() -> WeaponProfile:
	var w := WeaponProfile.new()
	w.name = "brute"
	w.kind = &"cone"
	w.damage_mult = 2.5
	w.knockback_mult = 2.0
	w.fire_interval_mult = 0.5 / 0.15   # 0.5 s with the default 0.15 s
	return w

## Slow, fat projectile that bursts on contact or at end of life: 2x damage at the center,
## falling off toward a 2-unit edge, 0.6 s cadence.
static func technomancer() -> WeaponProfile:
	var w := WeaponProfile.new()
	w.name = "technomancer"
	w.kind = &"blast"
	w.damage_mult = 2.0
	w.fire_interval_mult = 0.6 / 0.15   # 0.6 s with the default 0.15 s
	w.proj_speed_mult = 10.0 / 20.0     # 10 with the default 20
	w.proj_radius_mult = 0.35 / 0.25    # 0.35 with the default 0.25
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
