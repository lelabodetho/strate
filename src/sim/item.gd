class_name SimItem
extends RefCounted
## Pure data. A generated piece of equipment: a slot, a rarity, and 1–3 affixes drawn from the
## slot's pool. `mods` is derived from the affixes in the SimStats format ({stat, pct}) and is
## applied to the player under source = item id while the item is equipped.
##
## Rarity = affix count (common 1, rare 2, epic 3) and tier range: common T1–T2, rare T1–T3,
## epic T2–T3 (TIER_WEIGHTS). The pct of a tier comes from the tuning (affix_t1/t2/t3:
## 0.08 / 0.15 / 0.25). The point of a tier is a breakpoint: 22 damage against 80 hp is 4
## shots, and only a T3 +25 % brings it to 3. Stats where lower is better (NEGATIVE_IS_GOOD)
## get -pct.
## Three rules keep a drop from being a dud: no pool carries a stat that does not change the
## fight (knockback, proj_speed are weapon identity, not loot); a rare or epic weapon always
## rolls damage or fire rate first, a rare or epic armor hp or damage taken (ROLE); modules
## are unconstrained.

const SLOTS: Array[StringName] = [&"weapon", &"armor", &"module"]
const RARITIES: Array[StringName] = [&"common", &"rare", &"epic"]
const AFFIX_COUNT := {&"common": 1, &"rare": 2, &"epic": 3}
# Chance of each tier by rarity, in order T1, T2, T3 (each row sums to 1). Common never
# reaches T3, epic never falls to T1.
const TIER_WEIGHTS := {
	&"common": [0.60, 0.40, 0.0],
	&"rare": [0.50, 0.35, 0.15],
	&"epic": [0.0, 0.60, 0.40],
}
# Distinct stats an item of a slot can carry. A stat in two pools (fire_rate, proj_damage,
# player_speed, player_hp, dash_cooldown) stacks additively across slots: weapon T1 + module
# T1 fire_rate = +16 %.
const POOLS := {
	&"weapon": ["proj_damage", "fire_rate", "player_speed"],
	&"armor": ["player_hp", "damage_taken", "player_speed", "dash_cooldown"],
	&"module": ["fire_rate", "proj_damage", "dash_cooldown", "player_hp"],
}
# Role guarantee: the first affix of a rare or epic item of these slots comes from here.
const ROLE := {
	&"weapon": ["proj_damage", "fire_rate"],
	&"armor": ["player_hp", "damage_taken"],
}
const NEGATIVE_IS_GOOD := ["dash_cooldown", "damage_taken"]

var id: int = 0              # assigned by the world when the item enters it
var pos: Vector2
var slot: StringName
var rarity: StringName
var affixes: Array = []      # [{stat: String, tier: int (1–3), pct: float}], signed
var mods: Array = []         # [{stat, pct}] for SimStats, derived from affixes
var name_key: String = ""    # "<slot>_<stat of the highest-tier affix>", for a view-side name table
var armed := true            # false for an item dropped under the player's feet by a swap: it is
                             # picked up again only after the player has stepped off it

func _init(p_slot: StringName = &"weapon", p_rarity: StringName = &"common") -> void:
	slot = p_slot
	rarity = p_rarity

## Seeded roll: AFFIX_COUNT[rarity] distinct stats from the slot's pool (the first one from
## ROLE for a rare or epic weapon / armor), each with a tier from TIER_WEIGHTS[rarity] and the
## tuning's pct for it. Same rng state, same item. The caller sets id/pos.
static func roll(rng: RandomNumberGenerator, p_rarity: StringName, p_slot: StringName, tuning: SimTuning) -> SimItem:
	var pool: Array = POOLS[p_slot].duplicate()
	var weights: Array = TIER_WEIGHTS[p_rarity]
	var picks: Array = []
	for i in int(AFFIX_COUNT[p_rarity]):
		if pool.is_empty():
			break
		var stat: String
		if i == 0 and p_rarity != &"common" and ROLE.has(p_slot):
			var role: Array = ROLE[p_slot]
			stat = role[rng.randi_range(0, role.size() - 1)]
			pool.erase(stat)
		else:
			stat = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		var r := rng.randf()
		var tier := 1
		var acc := 0.0
		for t in weights.size():
			acc += weights[t]
			if r < acc:
				tier = t + 1
				break
			if weights[t] > 0.0:
				tier = t + 1
		picks.append({"stat": stat, "tier": tier})
	return make(p_slot, p_rarity, picks, tuning)

## Build an item from explicit {stat, tier} affixes (tests, hand-placed loot).
static func make(p_slot: StringName, p_rarity: StringName, picks: Array, tuning: SimTuning) -> SimItem:
	var it := SimItem.new(p_slot, p_rarity)
	var best_tier := 0
	for a in picks:
		var stat := String(a.stat)
		var tier := clampi(int(a.tier), 1, 3)
		var pct := tier_pct(tier, tuning)
		if NEGATIVE_IS_GOOD.has(stat):
			pct = -pct
		it.affixes.append({"stat": stat, "tier": tier, "pct": pct})
		it.mods.append({"stat": stat, "pct": pct})
		if tier > best_tier:
			best_tier = tier
			it.name_key = "%s_%s" % [p_slot, stat]
	return it

static func tier_pct(tier: int, tuning: SimTuning) -> float:
	match tier:
		1: return tuning.affix_t1
		2: return tuning.affix_t2
		_: return tuning.affix_t3

func to_dict() -> Dictionary:
	return {
		"id": id, "slot": String(slot), "rarity": String(rarity), "name_key": name_key,
		"pos": [snappedf(pos.x, 0.01), snappedf(pos.y, 0.01)],
		"affixes": affixes.duplicate(true),
		"mods": mods.duplicate(true),
	}

## The inverse of to_dict() for the character save: affixes keep their saved pct (the tuning
## of the moment they rolled), mods are rebuilt from them. null when the slot or rarity is
## unknown.
static func from_dict(d: Dictionary) -> SimItem:
	var p_slot := StringName(String(d.get("slot", "")))
	var p_rarity := StringName(String(d.get("rarity", "")))
	if not SLOTS.has(p_slot) or not RARITIES.has(p_rarity):
		return null
	var it := SimItem.new(p_slot, p_rarity)
	it.id = int(d.get("id", 0))
	it.name_key = String(d.get("name_key", ""))
	var p = d.get("pos")
	if p is Array and p.size() == 2:
		it.pos = Vector2(float(p[0]), float(p[1]))
	for a in d.get("affixes", []):
		var stat := String(a.get("stat", ""))
		if stat.is_empty():
			continue
		var pct := float(a.get("pct", 0.0))
		it.affixes.append({"stat": stat, "tier": clampi(int(a.get("tier", 1)), 1, 3), "pct": pct})
		it.mods.append({"stat": stat, "pct": pct})
	return it
