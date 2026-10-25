class_name BossManager
extends Node2D
## Вызов и бой с боссами. Босс вызывается сознательно: алтарь + предмет-приманка (клавиша E).
## Победа даёт награду, открывает рецепты и двигает прогресс кампании.

signal message(text: String)
signal boss_changed(boss_name: String, hp: float, max_hp: float)
signal won(flag: String)

const LEASH := 70.0 * 16.0        # дальше игрок уходит — бой сбрасывается

# Боссы и их приманки лежат в data/bosses.json. Старые блоки-алтари связаны с боссами напрямую.
const LEGACY_ALTARS := {BlockDB.ALTAR_RAIDER: "chief", BlockDB.ALTAR_HIVE: "queen"}

static var _defs := {}

var world: WorldData
var player: Player
var combat: EnemyManager
var boss: Boss
var current: Dictionary = {}
var altar_tile := Vector2i.ZERO
var defeats := 0


static func boss_info(id: String) -> Dictionary:
	if _defs.is_empty():
		var file := FileAccess.open("res://data/bosses.json", FileAccess.READ)
		for e in JSON.parse_string(file.get_as_text()):
			_defs[str(e["id"])] = e
	return _defs.get(id, {})


static func all_bosses() -> Array:
	boss_info("chief")
	return _defs.values()


## id босса, чей алтарь стоит на клетке, или "".
func boss_at(t: Vector2i) -> String:
	if world.altars.has(t):
		return str(world.altars[t])
	var id := world.get_block(t.x, t.y)
	return str(LEGACY_ALTARS.get(id, ""))


func setup(w: WorldData, p: Player, c: EnemyManager) -> void:
	world = w
	player = p
	combat = c
	p.bosses = self
	p.died.connect(_on_player_died)


func _physics_process(delta: float) -> void:
	update(delta)


func is_active() -> bool:
	return boss != null and is_instance_valid(boss) and not boss.dead


## E на алтаре: тратит приманку и вызывает босса.
func interact(t: Vector2i, p: Player) -> String:
	var boss_id := boss_at(t)
	if boss_id == "" or not p.tile_in_reach(t):
		return ""
	var info := boss_info(boss_id)
	if Progress.has(str(info["flag"])):
		return "Здесь уже всё кончено."
	if is_active():
		return "Босс уже здесь."
	if p.inv.count(str(info["item"])) <= 0:
		return "Нужен предмет: %s." % ItemDB.title(str(info["item"]))
	p.inv.remove(str(info["item"]), 1)
	summon(info, t)
	return "%s пришёл!" % info["name"]


func summon(info: Dictionary, altar: Vector2i) -> Boss:
	current = info
	altar_tile = altar
	var def: Dictionary = EnemyDB.defs[str(info["def"])]
	var side := 1 if player.center().x < altar.x * 16.0 else -1
	var pos := Vector2((altar.x + side * 14) * 16.0, 0.0)
	# босс появляется на полу арены рядом с алтарём
	var floor_y := altar.y + 1
	while not world.is_solid(floori(pos.x / 16.0), floor_y) and floor_y < altar.y + 20:
		floor_y += 1
	boss = combat.spawn_at(def, pos, 1, floor_y * 16.0) as Boss
	boss.arena_center = Vector2(altar.x * 16.0 + 8.0, altar.y * 16.0)
	boss.died.connect(_on_boss_died)
	boss_changed.emit(str(info["name"]), boss.hp, boss.max_hp)
	return boss


func update(delta: float) -> void:
	if not is_active():
		return
	boss_changed.emit(str(current["name"]), boss.hp, boss.max_hp)
	if boss.center().distance_to(player.center()) > LEASH:
		reset_fight("Бой прерван: босс ушёл обратно.")


func _on_boss_died(e: Enemy) -> void:
	if e != boss:
		return
	var info := current
	Progress.unlock(str(info["flag"]))
	defeats += 1
	for m in boss.minions:
		if is_instance_valid(m) and not m.dead:
			m.take_damage(9999.0, 1)
	boss_changed.emit("", 0.0, 1.0)
	message.emit(str(info["win"]))
	won.emit(str(info["flag"]))
	boss = null
	current = {}


func _on_player_died() -> void:
	if is_active():
		reset_fight("Герой пал. Босс отступил.")


## Убирает босса и его помощников, приманку возвращает.
func reset_fight(text: String) -> void:
	if boss != null and is_instance_valid(boss):
		for m in boss.minions:
			if is_instance_valid(m):
				combat._remove(m)
		combat._remove(boss)
	if not current.is_empty():
		player.inv.add(str(current["item"]), 1)
	boss = null
	current = {}
	boss_changed.emit("", 0.0, 1.0)
	message.emit(text)
