class_name SimItem
extends RefCounted
## Pure data. A generated piece of equipment: a slot, a rarity, and 1–3 affixes drawn from the
## slot's pool. `mods` is derived from the affixes in the SimStats format ({stat, pct}) and is
## applied to the player under source = item id while the item is equipped.
##
## Rarity = affix count (common 1, rare 2, epic 3). Each affix has a tier drawn 50/35/15 whose
## pct comes from the tuning (affix_t1/t2/t3: 0.08 / 0.15 / 0.25). The point of a tier is a
## breakpoint: 22 damage against 80 hp is 4 shots, and only a T3 +25 % brings it to 3.
## Stats where lower is better (NEGATIVE_IS_GOOD) get -pct.

const SLOTS: Array[StringName] = [&"weapon", &"armor", &"module"]
const RARITIES: Array[StringName] = [&"common", &"rare", &"epic"]
const AFFIX_COUNT := {&"common": 1, &"rare": 2, &"epic": 3}
# Chance of each tier, in order T1, T2, T3 (sums to 1).
const TIER_WEIGHTS := [0.50, 0.35, 0.15]
# Distinct stats an item of a slot can carry. A stat in two pools (fire_rate, proj_damage,
# player_speed) stacks additively across slots: weapon T1 + module T1 fire_rate = +16 %.
const POOLS := {
	&"weapon": ["fire_rate", "proj_damage", "knockback", "proj_speed"],
	&"armor": ["player_hp", "damage_taken", "player_speed"],
	&"module": ["fire_rate", "proj_damage", "dash_cooldown", "player_speed"],
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

## Seeded roll: AFFIX_COUNT[rarity] distinct stats from the slot's pool, each with a tier from
## TIER_WEIGHTS and the tuning's pct for it. Same rng state, same item. The caller sets id/pos.
static func roll(rng: RandomNumberGenerator, p_rarity: StringName, p_slot: StringName, tuning: SimTuning) -> SimItem:
	var pool: Array = POOLS[p_slot].duplicate()
	var picks: Array = []
	for i in int(AFFIX_COUNT[p_rarity]):
		if pool.is_empty():
			break
		var stat: String = pool.pop_at(rng.randi_range(0, pool.size() - 1))
		var r := rng.randf()
		var tier := 1
		var acc := 0.0
		for t in TIER_WEIGHTS.size():
			acc += TIER_WEIGHTS[t]
			if r < acc:
				tier = t + 1
				break
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
