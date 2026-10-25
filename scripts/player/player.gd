class_name Player
extends Node2D
## Игрок. position = левый верхний угол прямоугольника столкновений.
## Логика (physics_step, mine_tick, place_block) отделена от чтения ввода, чтобы её можно было тестировать.

const TILE := 16
const SIZE := Vector2(14, 30)
const GRAVITY := 1400.0
const MOVE_SPEED := 170.0
const JUMP_SPEED := 520.0
const MAX_FALL := 700.0
const REACH := 80.0          # дальность копания и стройки, пиксели (5 блоков)
const MINE_POWER := 1.0      # урон по блоку в секунду

var world: WorldData
var vel := Vector2.ZERO
var on_floor := false
var facing := 1
var target_tile := Vector2i.ZERO

# Временный инвентарь этапа 1: имя предмета -> количество. На этапе 2 заменяется настоящим.
var inventory := {}
var hotbar: PackedStringArray = ["dirt", "stone", "sand", "concrete", "scrap", "wood"]
var selected := 0


func physics_step(delta: float, move_dir: float, jump_pressed: bool) -> void:
	delta = minf(delta, 0.05)
	vel.x = move_dir * MOVE_SPEED
	if move_dir != 0.0:
		facing = 1 if move_dir > 0.0 else -1
	if jump_pressed and on_floor:
		vel.y = -JUMP_SPEED
	vel.y = minf(vel.y + GRAVITY * delta, MAX_FALL)
	var r := TileCollider.move(world, position, SIZE, vel, delta)
	position = r["pos"]
	vel = r["vel"]
	on_floor = r["on_floor"]


func center() -> Vector2:
	return position + SIZE * 0.5


func tile_pos() -> Vector2i:
	var c := center()
	return Vector2i(floori(c.x / TILE), floori(c.y / TILE))


func tile_in_reach(t: Vector2i) -> bool:
	var tc := Vector2(t.x * TILE + TILE * 0.5, t.y * TILE + TILE * 0.5)
	return center().distance_to(tc) <= REACH


## Копает блок. Возвращает true, когда блок разрушен.
func mine_tick(t: Vector2i, delta: float) -> bool:
	if not world.in_bounds(t.x, t.y) or not tile_in_reach(t):
		return false
	var id := world.get_block(t.x, t.y)
	if id == BlockDB.AIR:
		return false
	if world.damage_block(t.x, t.y, MINE_POWER * delta):
		var drop := BlockDB.drops[id]
		if drop != "":
			add_item(drop, 1)
		return true
	return false


func place_block(t: Vector2i, block_name: String) -> bool:
	if not world.in_bounds(t.x, t.y) or not tile_in_reach(t):
		return false
	if world.get_block(t.x, t.y) != BlockDB.AIR:
		return false
	if item_count(block_name) <= 0:
		return false
	var id: int = BlockDB.name_to_id.get(block_name, -1)
	if id <= 0 or BlockDB.placeable[id] == 0:
		return false
	if Rect2(t.x * TILE, t.y * TILE, TILE, TILE).intersects(Rect2(position, SIZE)):
		return false
	var supported := world.get_bg(t.x, t.y) != 0 \
		or world.is_solid(t.x - 1, t.y) or world.is_solid(t.x + 1, t.y) \
		or world.is_solid(t.x, t.y - 1) or world.is_solid(t.x, t.y + 1)
	if not supported:
		return false
	remove_item(block_name, 1)
	world.set_block(t.x, t.y, id)
	return true


func place_selected(t: Vector2i) -> bool:
	return place_block(t, hotbar[selected])


func add_item(item: String, n: int) -> void:
	inventory[item] = item_count(item) + n


func remove_item(item: String, n: int) -> bool:
	if item_count(item) < n:
		return false
	inventory[item] = item_count(item) - n
	return true


func item_count(item: String) -> int:
	return inventory.get(item, 0)


func hotbar_text() -> String:
	var parts := PackedStringArray()
	for i in hotbar.size():
		var title := BlockDB.titles[BlockDB.name_to_id[hotbar[i]]]
		var mark := ">" if i == selected else " "
		parts.append("%s%d %s:%d" % [mark, i + 1, title, item_count(hotbar[i])])
	return "  ".join(parts)


func _physics_process(delta: float) -> void:
	if world == null:
		return
	physics_step(delta, Input.get_axis("move_left", "move_right"), Input.is_action_pressed("jump"))
	var m := get_global_mouse_position()
	target_tile = Vector2i(floori(m.x / TILE), floori(m.y / TILE))
	if Input.is_action_pressed("mine"):
		mine_tick(target_tile, delta)
	if Input.is_action_pressed("place"):
		place_selected(target_tile)
	queue_redraw()


func _unhandled_input(event: InputEvent) -> void:
	for i in hotbar.size():
		if event.is_action_pressed("hotbar_%d" % (i + 1)):
			selected = i
	if event.is_action_pressed("hotbar_next"):
		selected = (selected + 1) % hotbar.size()
	elif event.is_action_pressed("hotbar_prev"):
		selected = (selected + hotbar.size() - 1) % hotbar.size()


func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, SIZE), Color("d8c9a0"))
	draw_rect(Rect2(Vector2(SIZE.x * 0.5 + facing * 3.0 - 1.5, 6), Vector2(3, 3)), Color("2a2a30"))
	if world == null:
		return
	var origin := Vector2(target_tile.x * TILE, target_tile.y * TILE) - position
	var color := Color(1, 1, 1, 0.9) if tile_in_reach(target_tile) else Color(1, 0.3, 0.3, 0.5)
	draw_rect(Rect2(origin, Vector2(TILE, TILE)), color, false, 1.0)
	var frac := world.damage_fraction(target_tile.x, target_tile.y)
	if frac > 0.0:
		draw_rect(Rect2(origin, Vector2(TILE, TILE)), Color(0, 0, 0, 0.6 * frac))
