class_name Enemy
extends Node2D
## Враг ближнего боя. position = левый верхний угол. Логику ведёт update(), ею управляет EnemyManager.

signal died(enemy: Enemy)

const TILE := 16
const GRAVITY := 1400.0
const MAX_FALL := 700.0
const AGGRO_RANGE := 260.0       # днём враг замечает игрока с такого расстояния
const ATTACK_COOLDOWN := 0.8
const BREAK_RATE := 0.5          # урон по блоку в секунду (блок ломается, если его прочность <= break_max)

var def: Dictionary
var world: WorldData
var max_hp := 1.0
var hp := 1.0
var damage := 1.0
var speed := 50.0
var jump_speed := 470.0
var ranged := false
var shot_cd := 2.0
var shot_range := 220.0
var shot_damage := 8.0
var shoot_timer := 1.0
var keep_dist := 0.0             # дальний бой: не подходит ближе этого расстояния
var retreat := false             # отступает, если игрок ближе 70% keep_dist
var break_max := 0.0             # самый прочный блок, который враг может сгрызть
var size := Vector2(14, 30)
var color := Color.WHITE

var vel := Vector2.ZERO
var on_floor := false
var hit_wall := false
var facing := 1
var attack_cd := 0.0
var hit_flash := 0.0
var knock_time := 0.0
var dead := false
var wander_dir := 0
var wander_timer := 0.0


func setup(d: Dictionary, w: WorldData, night: int = 1) -> void:
	def = d
	world = w
	max_hp = float(d["hp"]) * (1.0 + 0.15 * (night - 1))
	hp = max_hp
	damage = float(d["damage"]) * (1.0 + 0.1 * (night - 1))
	speed = float(d["speed"])
	jump_speed = float(d.get("jump", 470.0))
	break_max = float(d.get("break", 0.0))
	ranged = bool(d.get("ranged", false))
	shot_cd = float(d.get("shot_cd", 2.0))
	shot_range = float(d.get("shot_range", 220.0))
	shot_damage = float(d.get("shot_damage", 8.0))
	keep_dist = float(d.get("keep", 0.0))
	shoot_timer = randf_range(0.5, shot_cd)
	size = Vector2(d["size"][0], d["size"][1])
	color = Color.html(str(d["color"]))


func rect() -> Rect2:
	return Rect2(position, size)


func center() -> Vector2:
	return position + size * 0.5


## Один шаг ИИ и физики. horde = true ночью: орда знает, где игрок, с любого расстояния.
## Возвращает true, если враг касается цели.
func update(delta: float, target: Rect2, horde: bool) -> bool:
	delta = minf(delta, 0.05)
	attack_cd = maxf(0.0, attack_cd - delta)
	shoot_timer = maxf(0.0, shoot_timer - delta)
	hit_flash = maxf(0.0, hit_flash - delta)
	var to := target.get_center() - center()
	var move_dir := 0.0
	var jump := false
	if knock_time > 0.0:
		knock_time -= delta
	elif horde or to.length() < AGGRO_RANGE:
		if absf(to.x) > 4.0:
			move_dir = 1.0 if to.x > 0.0 else -1.0
		if keep_dist > 0.0:
			if retreat and absf(to.x) < keep_dist * 0.7:
				move_dir = -move_dir
			elif absf(to.x) < keep_dist:
				move_dir = 0.0
				facing = 1 if to.x > 0.0 else -1
		if on_floor and (hit_wall or (to.y < -24.0 and absf(to.x) < 48.0)):
			jump = true
	else:
		wander_timer -= delta
		if wander_timer <= 0.0:
			wander_dir = [-1, 0, 0, 1][randi() % 4]
			wander_timer = randf_range(1.5, 3.5)
		move_dir = wander_dir * 0.4
	if move_dir != 0.0:
		facing = 1 if move_dir > 0.0 else -1
	if knock_time <= 0.0:
		vel.x = move_dir * speed
	if jump:
		vel.y = -jump_speed
	vel.y = minf(vel.y + GRAVITY * delta, MAX_FALL)
	var r := TileCollider.move(world, position, size, vel, delta)
	position = r["pos"]
	vel = r["vel"]
	on_floor = r["on_floor"]
	hit_wall = r["hit_wall"]
	if hit_wall and move_dir != 0.0 and break_max > 0.0:
		gnaw(delta)
	queue_redraw()
	return rect().grow(2.0).intersects(target)


## Грызёт слабый блок перед собой (самый нижний твёрдый на высоте тела). Возвращает true, если блок разрушен.
func gnaw(delta: float) -> bool:
	var fx := floori((position.x + (size.x + 1.0 if facing > 0 else -1.0)) / TILE)
	var foot := floori((position.y + size.y - 1.0) / TILE)
	var head := floori(position.y / TILE)
	for ty in range(foot, head - 1, -1):
		if not world.is_solid(fx, ty):
			continue
		var id := world.get_block(fx, ty)
		var h := BlockDB.hardness[id]
		if h < 0.0 or h > break_max or BlockDB.mob_breakable[id] == 0:
			return false
		return world.damage_block(fx, ty, BREAK_RATE * delta)
	return false


## Получить урон. dir = направление удара (1 вправо, -1 влево). Возвращает true, если враг погиб.
func take_damage(amount: float, dir: int) -> bool:
	if dead:
		return false
	hp -= amount
	hit_flash = 0.12
	knock_time = 0.2
	vel = Vector2(dir * 150.0, -170.0)
	if hp <= 0.0:
		dead = true
		died.emit(self)
		return true
	return false


func _draw() -> void:
	var c := Color.WHITE if hit_flash > 0.0 else color
	draw_rect(Rect2(Vector2.ZERO, size), c)
	draw_rect(Rect2(Vector2(size.x * 0.5 + facing * 3.0 - 1.5, 6), Vector2(3, 3)), Color("2a2a30"))
	if hp < max_hp:
		draw_rect(Rect2(Vector2(0, -6), Vector2(size.x, 3)), Color(0.2, 0.0, 0.0))
		draw_rect(Rect2(Vector2(0, -6), Vector2(size.x * hp / max_hp, 3)), Color(0.9, 0.2, 0.2))
