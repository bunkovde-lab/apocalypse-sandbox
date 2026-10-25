class_name LayerSpawner
extends Node
## Враги подземных слоёв: пока игрок внутри слоя, рядом с ним в пещерах появляются местные обитатели.

const RANGE_MIN := 16
const RANGE_MAX := 32

var world: WorldData
var player: Player
var combat: EnemyManager
var rng := RandomNumberGenerator.new()
var timer := 1.0
var spawned_total := 0


func setup(w: WorldData, p: Player, c: EnemyManager) -> void:
	Layers.ensure_loaded()
	EnemyDB.ensure_loaded()
	world = w
	player = p
	combat = c
	rng.seed = w.seed_value + 55


func _physics_process(delta: float) -> void:
	update(delta)


func update(delta: float) -> void:
	timer -= delta
	if timer > 0.0:
		return
	timer = 1.5
	var pt := player.tile_pos()
	var layer := Layers.at_y(pt.y)
	if layer.is_empty() or player.hp <= 0.0:
		return
	var near := 0
	for e in combat.enemies:
		if is_instance_valid(e) and not e.dead and e.center().distance_to(player.center()) < 45.0 * 16.0:
			near += 1
	if near >= int(layer["cap"]):
		return
	spawn_one(layer)


## Пробует создать одного обитателя слоя в пещере рядом с игроком. Возвращает врага или null.
func spawn_one(layer: Dictionary) -> Enemy:
	var pt := player.tile_pos()
	var pool: Dictionary = layer["enemies"]
	var name := _pick(pool)
	var def: Dictionary = EnemyDB.defs[name]
	var fly: bool = bool(def.get("fly", false))
	var scale := 1 + Progress.boss_count()
	for _attempt in 40:
		var side := 1 if rng.randf() < 0.5 else -1
		var x := pt.x + side * rng.randi_range(RANGE_MIN, RANGE_MAX)
		var y := pt.y + rng.randi_range(-8, 8)
		if not world.in_bounds(x, y) or y < int(layer["y0"]) or y > int(layer["y1"]):
			continue
		var free := not world.is_solid(x, y) and not world.is_solid(x, y - 1) and not world.is_solid(x, y - 2)
		if not free:
			continue
		if not fly and not world.is_solid(x, y + 1):
			continue
		var e := combat.spawn_at(def, Vector2(x * 16.0, 0.0), scale, (y + 1) * 16.0)
		spawned_total += 1
		return e
	return null


func _pick(pool: Dictionary) -> String:
	var total := 0.0
	for k in pool:
		total += float(pool[k])
	var roll := rng.randf() * total
	for k in pool:
		roll -= float(pool[k])
		if roll <= 0.0:
			return str(k)
	return str(pool.keys()[0])
