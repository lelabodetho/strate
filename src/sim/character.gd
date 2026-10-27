class_name SimCharacter
extends RefCounted
## What belongs to the player across levels: the weapon profile name, the worn items (slot ->
## SimItem), the bag, and the item id counter. A SimWorld is one level; it holds a character
## and reads and writes the equipment through it, so a new world for the next level starts
## from the same character. to_dict() / from_dict() round-trip: this is the save format.
## Item ids come from here and start at ITEM_ID_BASE, far above any entity id a level hands
## out, so an item never shares an id with a grunt or a bullet and keeps its id across levels.

const ITEM_ID_BASE := 1_000_000

var weapon_name: String = "hunter"
var equipped: Dictionary = {}          # slot (StringName) -> SimItem
var inventory: Array[SimItem] = []     # the bag, in pickup order
var next_item_id: int = ITEM_ID_BASE

func new_item_id() -> int:
	var id := next_item_id
	next_item_id += 1
	return id

## Push the weapon mods and every worn item's mods onto a fresh SimStats.
func apply_to(stats: SimStats) -> void:
	stats.remove_source("weapon")
	stats.add_all("weapon", WeaponProfile.by_name(weapon_name).mods)
	for it in equipped.values():
		stats.remove_source(it.id)
		stats.add_all(it.id, it.mods)

## Drop everything (the arena's 0 key, a fresh character).
func clear() -> void:
	equipped.clear()
	inventory.clear()

func item_count() -> int:
	return equipped.size() + inventory.size()

func to_dict() -> Dictionary:
	var worn := {}
	for slot in equipped:
		worn[String(slot)] = equipped[slot].to_dict()
	var bag := []
	for it in inventory:
		bag.append(it.to_dict())
	return {"weapon": weapon_name, "next_item_id": next_item_id, "equipped": worn, "inventory": bag}

static func from_dict(d: Dictionary) -> SimCharacter:
	var c := SimCharacter.new()
	if d.has("weapon") and WeaponProfile.NAMES.has(String(d.weapon)):
		c.weapon_name = String(d.weapon)
	c.next_item_id = maxi(ITEM_ID_BASE, int(d.get("next_item_id", ITEM_ID_BASE)))
	var worn: Dictionary = d.get("equipped", {})
	for slot in worn:
		var it := SimItem.from_dict(worn[slot])
		if it != null and String(it.slot) == String(slot):
			c.equipped[it.slot] = it
	for entry in d.get("inventory", []):
		var it := SimItem.from_dict(entry)
		if it != null:
			c.inventory.append(it)
	# Never hand out an id a loaded item already has.
	for it in c.equipped.values() + c.inventory:
		c.next_item_id = maxi(c.next_item_id, it.id + 1)
	return c
