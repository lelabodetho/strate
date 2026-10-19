class_name WeaponProfile
extends RefCounted
## How the player's attack button turns into damage. Not a class: a profile the player can
## switch at any time (keys 1/2/3). Its numbers are SimStats modifiers (source "weapon") with
## `mult` on the current tuning, so tuning presets stay comparable across profiles and item
## bonuses (pct) read the same on every profile. Geometry (cone, blast) and the attack window
## are absolute: they are the weapon's identity, never a multiplier on the tuning.
##
## Attack window, driven by SimWorld: windup (committed: the shot or swing has not landed yet),
## hit (the instant the projectile spawns or the cone resolves), recovery (no new attack yet).
## Holding attack re-queues the next windup at the end of recovery, never earlier. A dash
## cancels both phases (a windup's shot is lost). The player moves at tuning.attack_move_mult
## during windup and recovery. The fire_rate stat (items) scales the whole window:
## window × (1 / fire_rate), so +12 % attack speed shortens windup and recovery alike.

const NAMES := ["hunter", "brute", "technomancer"]

var name: String = "hunter"
var kind: StringName = &"projectile"   # &"projectile" | &"cone" | &"blast"
var windup := 0.12             # seconds from the trigger to the hit
var recovery := 0.30           # seconds after the hit before the next windup may start
var mods: Array = []           # [{stat, mult}|{stat, flat}] applied to the player under source "weapon"

# cone (brute)
var cone_angle_deg := 90.0
var cone_range := 1.6
var swing_time := 0.15         # the lunge plays over the first swing_time seconds of recovery
var lunge := 0.8               # distance covered along the aim during swing_time

# blast (technomancer)
var blast_radius := 2.0
var blast_edge_factor := 0.25  # damage at the edge, as a fraction of the center damage

## Plain repeater: 0.12 s windup, 0.30 s recovery (0.42 s per shot).
static func hunter() -> WeaponProfile:
	return WeaponProfile.new()

## No projectile: a 90-degree sweep in front of the player, 2.5x damage, 0.22 s windup and
## 0.45 s recovery (0.67 s per swing), double knockback, a short lunge along the aim right
## after the hit, a thicker body with i-frames on the swing.
static func brute() -> WeaponProfile:
	var w := WeaponProfile.new()
	w.name = "brute"
	w.kind = &"cone"
	w.windup = 0.22
	w.recovery = 0.45
	w.mods = [
		{"stat": "proj_damage", "mult": 2.5},
		{"stat": "knockback", "mult": 2.0},
		{"stat": "player_hp", "mult": 1.6},
		{"stat": "damage_taken", "mult": 0.65},
		{"stat": "attack_iframes", "flat": 0.12},
	]
	return w

## Slow, fat projectile that bursts on contact or at end of life: 2x damage at the center,
## falling off toward a 1.4-unit edge, 0.30 s windup and 0.55 s recovery (0.85 s per shot). Frail.
static func technomancer() -> WeaponProfile:
	var w := WeaponProfile.new()
	w.name = "technomancer"
	w.kind = &"blast"
	w.blast_radius = 1.4
	w.windup = 0.30
	w.recovery = 0.55
	w.mods = [
		{"stat": "proj_damage", "mult": 2.0},
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
	return {"name": name, "kind": String(kind), "windup": windup, "recovery": recovery}
