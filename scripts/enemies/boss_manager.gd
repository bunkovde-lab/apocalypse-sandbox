class_name BossManager
extends Node2D
## Вызов и бой с боссами. Босс вызывается сознательно: алтарь + предмет-приманка (клавиша E).
## Победа даёт награду, открывает рецепты и двигает прогресс кампании.

signal message(text: String)
signal boss_changed(boss_name: String, hp: float, max_hp: float)

const LEASH := 70.0 * 16.0        # дальше игрок уходит — бой сбрасывается

# Алтарь -> описание босса. id флага прогресса и рецепт открываются при победе.
const ALTARS := {
	BlockDB.ALTAR_RAIDER: {"item": "raider_beacon", "boss": "boss_raider_chief", "flag": "boss_1",
		"name": "Главарь мародёров", "win": "Главарь мародёров повержен. Открыт армированный бетон."},
	BlockDB.ALTAR_HIVE: {"item": "spore_lure", "boss": "boss_hive_queen", "flag": "boss_2",
		"name": "Королева-матка", "win": "Королева-матка мертва. Открыт фильтр-очиститель."},
}

var world: WorldData
var player: Player
var combat: EnemyManager
var boss: Boss
var current: Dictionary = {}
var altar_tile := Vector2i.ZERO
var defeats := 0


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
	var id := world.get_block(t.x, t.y)
	if not ALTARS.has(id):
		return ""
	if not p.tile_in_reach(t):
		return ""
	var info: Dictionary = ALTARS[id]
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
	var def: Dictionary = EnemyDB.defs[str(info["boss"])]
	var side := 1 if player.center().x < altar.x * 16.0 else -1
	var pos := Vector2((altar.x + side * 14) * 16.0, 0.0)
	# босс появляется на полу арены рядом с алтарём
	var floor_y := altar.y + 1
	while not world.is_solid(floori(pos.x / 16.0), floor_y) and floor_y < altar.y + 20:
		floor_y += 1
	boss = combat.spawn_at(def, pos, 1, floor_y * 16.0) as Boss
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
