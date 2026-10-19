class_name SimStats
extends RefCounted
## The player's effective numbers: tuning values bent by a list of modifiers.
## A modifier is {source, stat, mult, pct, flat}. For a stat:
##   value(stat) = base(stat) × Π mult × (1 + Σ pct) + Σ flat
## `mult` is the weapon's identity (cadence, damage, projectile speed) and compounds; `pct` is
## what items and buffs add, so two +30 % items read +60 %, whatever the weapon.
## Base values come from the tuning, except the derived ones below.
##   fire_rate     shots per second, base 1 / tuning.fire_interval. A +30 % cadence bonus raises
##                 fire_rate; SimWorld derives the interval from it.
##   damage_taken  multiplier on every hit the player takes, base 1.
##   attack_iframes  seconds of invulnerability when an attack starts, base 0.

var tuning: SimTuning
var mods: Array[Dictionary] = []   # source is stored as a String ("weapon", "7" for item 7)

func _init(p_tuning: SimTuning) -> void:
	tuning = p_tuning

func add(source: Variant, stat: String, pct: float = 0.0, flat: float = 0.0, mult: float = 1.0) -> void:
	mods.append({"source": str(source), "stat": stat, "mult": mult, "pct": pct, "flat": flat})

## Add a list of {stat, pct?, flat?, mult?} dictionaries under one source.
func add_all(source: Variant, list: Array) -> void:
	for m in list:
		add(source, String(m.stat), float(m.get("pct", 0.0)), float(m.get("flat", 0.0)), float(m.get("mult", 1.0)))

func remove_source(source: Variant) -> void:
	var key := str(source)
	mods = mods.filter(func(m): return m.source != key)

func has_source(source: Variant) -> bool:
	var key := str(source)
	for m in mods:
		if m.source == key:
			return true
	return false

func base(stat: String) -> float:
	match stat:
		"fire_rate":
			return 1.0 / maxf(tuning.fire_interval, 0.001)
		"damage_taken":
			return 1.0
		"attack_iframes":
			return 0.0
		_:
			var v = tuning.get(stat)
			return float(v) if v != null else 0.0

func value(stat: String) -> float:
	var mult := 1.0
	var pct := 0.0
	var flat := 0.0
	for m in mods:
		if m.stat == stat:
			mult *= m.mult
			pct += m.pct
			flat += m.flat
	return base(stat) * mult * (1.0 + pct) + flat

## Seconds between two attacks, derived from fire_rate.
func fire_interval() -> float:
	return 1.0 / maxf(value("fire_rate"), 0.001)

func to_dict() -> Dictionary:
	var list := []
	for m in mods:
		list.append({"source": m.source, "stat": m.stat, "mult": m.mult, "pct": m.pct, "flat": m.flat})
	return {
		"mods": list,
		"fire_rate": snappedf(value("fire_rate"), 0.001),
		"fire_interval": snappedf(fire_interval(), 0.001),
		"player_speed": snappedf(value("player_speed"), 0.001),
		"player_hp": snappedf(value("player_hp"), 0.001),
		"proj_damage": snappedf(value("proj_damage"), 0.001),
		"proj_speed": snappedf(value("proj_speed"), 0.001),
		"damage_taken": snappedf(value("damage_taken"), 0.001),
	}
