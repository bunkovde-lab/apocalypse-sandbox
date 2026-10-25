class_name CampManager
extends Node2D
## Охрана лагеря и бункера рейдеров: стража появляется, когда игрок подходит ближе ACTIVATE,
## и возвращается на следующий день, если её перебили.

const ACTIVATE := 65.0 * 16.0

var world: WorldData
var player: Player
var combat: EnemyManager
var clock: DayClock
var guards := {}          # индекс постройки -> Array[Enemy]
var spawned_day := {}     # индекс постройки -> день последнего появления


func setup(w: WorldData, p: Player, c: EnemyManager, clk: DayClock) -> void:
	world = w
	player = p
	combat = c
	clock = clk


func _physics_process(delta: float) -> void:
	update(delta)


func update(_delta: float) -> void:
	if world == null:
		return
	for i in world.structures.size():
		var st: Dictionary = world.structures[i]
		if not (st["type"] == "camp" or st["type"] == "bunker"):
			continue
		var rect: Rect2i = st["rect"]
		var center := Vector2(rect.get_center()) * 16.0
		if center.distance_to(player.center()) > ACTIVATE:
			continue
		var alive: Array = (guards.get(i, []) as Array).filter(func(g) -> bool: return is_instance_valid(g) and not g.dead)
		guards[i] = alive
		if not alive.is_empty() or spawned_day.get(i, -1) == clock.day:
			continue
		spawned_day[i] = clock.day
		for tile in st["spawns"]:
			var def: Dictionary = EnemyDB.defs["raider"]
			var e := combat.spawn_at(def, Vector2(tile.x * 16.0, 0.0), 1, tile.y * 16.0)
			guards[i].append(e)
