class_name Player
extends Node2D
## Игрок. position = левый верхний угол прямоугольника столкновений.
## Логика (physics_step, mine_tick, place_block, try_attack, take_damage) отделена от чтения ввода,
## чтобы её можно было тестировать без окна.

signal selected_changed
signal damaged
signal died
signal message(text: String)

const TILE := 16
const SIZE := Vector2(14, 30)
const GRAVITY := 1400.0
const MOVE_SPEED := 170.0
const JUMP_SPEED := 520.0
const MAX_FALL := 700.0
const REACH := 80.0           # дальность копания и стройки, пиксели (5 блоков)
const HAND_POWER := 1.0       # урон по блоку в секунду голыми руками
const MAX_HP := 100.0
const INVULN_TIME := 0.7
const REGEN_DELAY := 5.0      # секунд без урона до начала лечения
const REGEN_RATE := 2.0       # здоровья в секунду
const HAMMER_REPAIR := 2.0    # прочности блока в секунду

var world: WorldData
var combat: EnemyManager
var shelter: ShelterManager
var vel := Vector2.ZERO
var on_floor := false
var facing := 1
var target_tile := Vector2i.ZERO
var inv := Inventory.new()
var selected := 0:
	set(value):
		selected = clampi(value, 0, Inventory.HOTBAR - 1)
		selected_changed.emit()

var max_hp := MAX_HP
var hp := MAX_HP
var invuln := 0.0
var since_damage := 99.0
var knock_time := 0.0
var attack_cd := 0.0
var spawn_pos := Vector2.ZERO
var swing_time := 0.0         # для отрисовки взмаха
var deaths := 0
var home_state := 0           # 1 = бафф «Дом» (стабильность 80+), -1 = «Тревога» (кризис)
var survivors: SurvivorManager
var bosses: BossManager
var mouse_world := Vector2.ZERO


func physics_step(delta: float, move_dir: float, jump_pressed: bool) -> void:
	delta = minf(delta, 0.05)
	_tick_timers(delta)
	if knock_time <= 0.0:
		vel.x = move_dir * MOVE_SPEED * (1.1 if home_state > 0 else 1.0)
	if move_dir != 0.0:
		facing = 1 if move_dir > 0.0 else -1
	if jump_pressed and on_floor:
		vel.y = -JUMP_SPEED
	vel.y = minf(vel.y + GRAVITY * delta, MAX_FALL)
	var r := TileCollider.move(world, position, SIZE, vel, delta)
	position = r["pos"]
	vel = r["vel"]
	on_floor = r["on_floor"]


func _tick_timers(delta: float) -> void:
	invuln = maxf(0.0, invuln - delta)
	attack_cd = maxf(0.0, attack_cd - delta)
	knock_time = maxf(0.0, knock_time - delta)
	swing_time = maxf(0.0, swing_time - delta)
	since_damage += delta
	if since_damage >= REGEN_DELAY and hp < max_hp:
		hp = minf(max_hp, hp + REGEN_RATE * (2.0 if home_state > 0 else (0.5 if home_state < 0 else 1.0)) * delta)


func center() -> Vector2:
	return position + SIZE * 0.5


func tile_pos() -> Vector2i:
	var c := center()
	return Vector2i(floori(c.x / TILE), floori(c.y / TILE))


func tile_in_reach(t: Vector2i) -> bool:
	var tc := Vector2(t.x * TILE + TILE * 0.5, t.y * TILE + TILE * 0.5)
	return center().distance_to(tc) <= REACH


func selected_item() -> String:
	return inv.slot_item(selected)


## Сила копания: голые руки или кирка в выбранной ячейке.
func mine_power() -> float:
	return maxf(HAND_POWER, ItemDB.tool_power(selected_item()))


func is_weapon_selected() -> bool:
	var k := ItemDB.kind(selected_item())
	return k == "weapon" or k == "gun"


# ---------- Копание и стройка ----------

## Копает блок. Возвращает true, когда блок разрушен.
func mine_tick(t: Vector2i, delta: float) -> bool:
	if not world.in_bounds(t.x, t.y) or not tile_in_reach(t):
		return false
	var id := world.get_block(t.x, t.y)
	if id == BlockDB.AIR:
		return false
	if id == BlockDB.TOMBSTONE or id == BlockDB.LOOT:
		return _mine_tombstone(t, delta, id)
	if BlockDB.hardness[id] < 0.0:
		return false
	var drop := BlockDB.drops[id]
	if drop != "" and not inv.can_add(drop, 1):
		return false   # некуда класть добычу, блок не ломаем
	if world.damage_block(t.x, t.y, mine_power() * delta):
		if drop != "":
			inv.add(drop, 1)
		return true
	return false


## Надгробие или ящик с припасами: всё содержимое уходит в инвентарь, остаток возвращается в ящик.
func _mine_tombstone(t: Vector2i, delta: float, id: int = BlockDB.TOMBSTONE) -> bool:
	if not world.damage_block(t.x, t.y, mine_power() * delta):
		return false
	var loot: Dictionary = world.tombstones.get(t, {})
	var rest := {}
	for item in loot:
		var left := inv.add(item, int(loot[item]))
		if left > 0:
			rest[item] = left
	world.tombstones.erase(t)
	if not rest.is_empty():
		world.tombstones[t] = rest        # не всё поместилось: надгробие остаётся с остатком
		world.set_block(t.x, t.y, id)
	return true


func is_hammer_selected() -> bool:
	return ItemDB.stat(selected_item(), "hammer") > 0.0


## Молоток: чинит повреждённый блок, иначе снимает поставленную стену (возвращает её в инвентарь).
## Возвращает "repair", "wall" или "".
func hammer_tick(t: Vector2i, delta: float) -> String:
	if not world.in_bounds(t.x, t.y) or not tile_in_reach(t):
		return ""
	if world.damage_fraction(t.x, t.y) > 0.0:
		world.repair_block(t.x, t.y, HAMMER_REPAIR * delta)
		return "repair"
	if attack_cd > 0.0 or not world.has_placed_wall(t.x, t.y):
		return ""
	var item := ItemDB.wall_item_for(world.bg[t.y * world.width + t.x])
	if item != "" and not inv.can_add(item, 1):
		return ""
	if item != "":
		inv.add(item, 1)
	world.set_bg(t.x, t.y, 0)
	attack_cd = 0.15
	return "wall"


func _place_wall(t: Vector2i, item: String, wall: int) -> bool:
	if world.get_bg(t.x, t.y) != 0 or inv.count(item) <= 0:
		return false
	var supported := world.is_solid(t.x, t.y) \
		or world.is_solid(t.x - 1, t.y) or world.is_solid(t.x + 1, t.y) \
		or world.is_solid(t.x, t.y - 1) or world.is_solid(t.x, t.y + 1) \
		or world.get_bg(t.x - 1, t.y) != 0 or world.get_bg(t.x + 1, t.y) != 0 \
		or world.get_bg(t.x, t.y - 1) != 0 or world.get_bg(t.x, t.y + 1) != 0
	if not supported:
		return false
	inv.remove(item, 1)
	world.set_bg(t.x, t.y, wall)
	return true


func place_block(t: Vector2i, item: String) -> bool:
	if not world.in_bounds(t.x, t.y) or not tile_in_reach(t):
		return false
	var wall := ItemDB.wall_id(item)
	if wall >= 0:
		return _place_wall(t, item, wall)
	if world.get_block(t.x, t.y) != BlockDB.AIR:
		return false
	if inv.count(item) <= 0:
		return false
	var id := ItemDB.block_id(item)
	if id < 0:
		return false
	if BlockDB.solid[id] == 1 and Rect2(t.x * TILE, t.y * TILE, TILE, TILE).intersects(Rect2(position, SIZE)):
		return false
	var supported := world.get_bg(t.x, t.y) != 0 \
		or world.is_solid(t.x - 1, t.y) or world.is_solid(t.x + 1, t.y) \
		or world.is_solid(t.x, t.y - 1) or world.is_solid(t.x, t.y + 1)
	if not supported:
		return false
	inv.remove(item, 1)
	world.set_block(t.x, t.y, id)
	return true


func place_selected(t: Vector2i) -> bool:
	var item := selected_item()
	if item == "":
		return false
	if ItemDB.kind(item) == "consumable":
		return use_item(item)
	return place_block(t, item)


## Использует расходник (аптечка). Возвращает true, если предмет израсходован.
func use_item(item: String) -> bool:
	if ItemDB.kind(item) != "consumable" or inv.count(item) <= 0 or attack_cd > 0.0 or hp <= 0.0:
		return false
	var heal := ItemDB.stat(item, "heal")
	if heal <= 0.0 or hp >= max_hp:
		return false
	inv.remove(item, 1)
	hp = minf(max_hp, hp + heal)
	attack_cd = 0.8
	return true


# ---------- Бой ----------

## Атакует выбранным оружием в сторону aim (мировые координаты). Возвращает true, если атака произошла.
func try_attack(aim: Vector2) -> bool:
	var item := selected_item()
	var kind := ItemDB.kind(item)
	if attack_cd > 0.0 or combat == null or hp <= 0.0:
		return false
	var dir := 1 if aim.x >= center().x else -1
	if kind == "weapon":
		facing = dir
		attack_cd = ItemDB.stat(item, "cooldown", 0.5)
		swing_time = 0.12
		var reach := ItemDB.stat(item, "range", 40.0)
		var x0 := center().x if dir > 0 else center().x - reach - SIZE.x * 0.5
		combat.melee_hit(Rect2(x0, center().y - 18.0, reach + SIZE.x * 0.5, 36.0), ItemDB.damage(item), dir)
		return true
	if kind == "gun":
		var ammo := str(ItemDB.items[item].get("ammo", ""))
		if inv.count(ammo) <= 0:
			return false
		inv.remove(ammo, 1)
		attack_cd = ItemDB.stat(item, "cooldown", 0.4)
		facing = dir
		var aim_dir := aim - center()
		if aim_dir.length() < 1.0:
			aim_dir = Vector2(dir, 0)
		combat.fire(center(), aim_dir, ItemDB.damage(item))
		return true
	return false


## Получить урон. Возвращает true, если урон прошёл (нет неуязвимости).
func take_damage(amount: float, from_x: float) -> bool:
	if invuln > 0.0 or hp <= 0.0:
		return false
	hp -= amount
	invuln = INVULN_TIME
	since_damage = 0.0
	var dir := 1.0 if center().x >= from_x else -1.0
	vel = Vector2(dir * 140.0, -200.0)
	knock_time = 0.15
	damaged.emit()
	if hp <= 0.0:
		die()
	return true


## Смерть: половина каждой стопки остаётся на надгробии, игрок возвращается на точку старта.
func die() -> void:
	var lost := {}
	for i in Inventory.SIZE:
		var take := inv.counts[i] >> 1
		if take > 0:
			var item := inv.items[i]
			lost[item] = int(lost.get(item, 0)) + take
			inv.counts[i] -= take
	inv.changed.emit()
	if not lost.is_empty():
		var t := tile_pos()
		for dy in 7:
			if world.get_block(t.x, t.y - dy) == BlockDB.AIR:
				var spot := Vector2i(t.x, t.y - dy)
				world.tombstones[spot] = lost
				world.set_block(spot.x, spot.y, BlockDB.TOMBSTONE)
				break
	deaths += 1
	died.emit()
	respawn()


func respawn() -> void:
	position = spawn_pos
	vel = Vector2.ZERO
	hp = max_hp
	invuln = 2.0
	since_damage = 99.0


# ---------- Инвентарь ----------

func add_item(item: String, n: int) -> int:
	return inv.add(item, n)


func remove_item(item: String, n: int) -> bool:
	return inv.remove(item, n)


func item_count(item: String) -> int:
	return inv.count(item)


func nearby_stations() -> Dictionary:
	return RecipeDB.nearby_stations(world, tile_pos())


# ---------- Ввод и отрисовка ----------

func _physics_process(delta: float) -> void:
	if world == null:
		return
	physics_step(delta, Input.get_axis("move_left", "move_right"), Input.is_action_pressed("jump"))
	var m := get_global_mouse_position()
	mouse_world = m
	target_tile = Vector2i(floori(m.x / TILE), floori(m.y / TILE))
	var over_ui := get_viewport().gui_get_hovered_control() != null
	if not over_ui:
		if Input.is_action_pressed("mine"):
			if is_hammer_selected():
				hammer_tick(target_tile, delta)
			elif is_weapon_selected():
				try_attack(m)
			else:
				mine_tick(target_tile, delta)
		if Input.is_action_pressed("place"):
			place_selected(target_tile)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact") and shelter != null:
		var msg := survivors.interact_at(mouse_world, self) if survivors != null else ""
		if msg == "" and bosses != null:
			msg = bosses.interact(target_tile, self)
		if msg == "":
			msg = shelter.interact(target_tile, self)
		if msg != "":
			message.emit(msg)
	for i in Inventory.HOTBAR:
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			selected = i
	if event.is_action_pressed("hotbar_next"):
		selected = (selected + 1) % Inventory.HOTBAR
	elif event.is_action_pressed("hotbar_prev"):
		selected = (selected + Inventory.HOTBAR - 1) % Inventory.HOTBAR


func _draw() -> void:
	var body := Color("d8c9a0")
	if invuln > 0.0 and int(invuln * 20.0) % 2 == 0:
		body = Color(1, 1, 1, 0.5)
	draw_rect(Rect2(Vector2.ZERO, SIZE), body)
	draw_rect(Rect2(Vector2(SIZE.x * 0.5 + facing * 3.0 - 1.5, 6), Vector2(3, 3)), Color("2a2a30"))
	if swing_time > 0.0:
		var reach := ItemDB.stat(selected_item(), "range", 40.0)
		var x0 := SIZE.x if facing > 0 else -reach
		draw_rect(Rect2(Vector2(x0, SIZE.y * 0.5 - 6.0), Vector2(reach, 12)), Color(1, 1, 1, 0.35))
	if world == null:
		return
	var origin := Vector2(target_tile.x * TILE, target_tile.y * TILE) - position
	var color := Color(1, 1, 1, 0.9) if tile_in_reach(target_tile) else Color(1, 0.3, 0.3, 0.5)
	draw_rect(Rect2(origin, Vector2(TILE, TILE)), color, false, 1.0)
	var frac := world.damage_fraction(target_tile.x, target_tile.y)
	if frac > 0.0:
		draw_rect(Rect2(origin, Vector2(TILE, TILE)), Color(0, 0, 0, 0.6 * frac))
