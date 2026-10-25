class_name Survivor
extends Node2D
## Выживший. Сначала ждёт спасения (stranded), потом живёт на базе (resident) и работает по роли.
## position = левый верхний угол.

const TILE := 16
const SIZE := Vector2(14, 30)
const GRAVITY := 1400.0
const WALK_SPEED := 60.0
const JUMP_SPEED := 460.0
const ROLES := ["builder", "farmer", "engineer"]
const ROLE_TITLES := {"builder": "Строитель", "farmer": "Фермер", "engineer": "Инженер", "": "Без роли"}
const ROLE_COLORS := {"builder": Color("d9a441"), "farmer": Color("6fbf5a"), "engineer": Color("5aa7d9"), "": Color("b0b0b0")}
const NO_STATION := Vector2i(-1, -1)

var world: WorldData
var survivor_name := ""
var skills := {}                 # роль -> уровень 1..3
var role := ""
var resident := false
var home := NO_STATION           # клетка кровати
var station := NO_STATION        # рабочее место (грядка или очиститель)
var working := false
var deadline := 0.0               # >0: сколько секунд ещё ждёт спасения (сигнал бедствия)
var signal_event := false
var vel := Vector2.ZERO
var on_floor := false
var hit_wall := false
var wander_dir := 0
var wander_timer := 0.0
var _time := 0.0


func rect() -> Rect2:
	return Rect2(position, SIZE)


func center() -> Vector2:
	return position + SIZE * 0.5


func best_role(rng: RandomNumberGenerator) -> String:
	var best := ""
	var best_level := -1
	for r in ROLES:
		var lv: int = skills.get(r, 1)
		if lv > best_level or (lv == best_level and rng.randf() < 0.5):
			best = r
			best_level = lv
	return best


func cycle_role() -> void:
	var i := ROLES.find(role)
	role = ROLES[(i + 1) % ROLES.size()]
	station = NO_STATION
	working = false


## Один шаг жизни жителя: идёт к рабочему месту или слоняется у кровати.
func update(delta: float) -> void:
	delta = minf(delta, 0.05)
	_time += delta
	var target_x := center().x
	working = false
	var has_station := station != NO_STATION
	if has_station:
		target_x = station.x * TILE + TILE * 0.5
	elif home != NO_STATION:
		wander_timer -= delta
		if wander_timer <= 0.0:
			wander_dir = [-1, 0, 0, 1][randi() % 4]
			wander_timer = randf_range(1.5, 4.0)
		target_x = home.x * TILE + TILE * 0.5 + wander_dir * 3.0 * TILE
	var dx := target_x - center().x
	var move := 0.0
	if absf(dx) > 6.0:
		move = 1.0 if dx > 0.0 else -1.0
	elif has_station and on_floor:
		working = true
	vel.x = move * WALK_SPEED
	if hit_wall and on_floor and move != 0.0:
		vel.y = -JUMP_SPEED
	vel.y = minf(vel.y + GRAVITY * delta, 700.0)
	var r := TileCollider.move(world, position, SIZE, vel, delta)
	position = r["pos"]
	vel = r["vel"]
	on_floor = r["on_floor"]
	hit_wall = r["hit_wall"]
	# провалился или застрял далеко от дома — возвращаем к кровати
	if home != NO_STATION and (center().distance_to(Vector2(home.x * TILE, home.y * TILE)) > 40.0 * TILE):
		teleport_home()
	queue_redraw()


func teleport_home() -> void:
	position = Vector2(home.x * TILE + 1, (home.y + 1) * TILE - SIZE.y)
	vel = Vector2.ZERO


func _draw() -> void:
	var c: Color = ROLE_COLORS[role] if resident else Color("e8e0d0")
	draw_rect(Rect2(Vector2.ZERO, SIZE), c)
	draw_rect(Rect2(Vector2(SIZE.x * 0.5 - 1.5, 6), Vector2(3, 3)), Color("2a2a30"))
	var font := ThemeDB.fallback_font
	if resident:
		draw_string(font, Vector2(-14, -6), survivor_name, HORIZONTAL_ALIGNMENT_CENTER, 42, 9, Color(1, 1, 1, 0.9))
		if working:
			draw_circle(Vector2(SIZE.x * 0.5, -14), 2.0, Color(0.4, 1.0, 0.4))
	else:
		var bob := sin(_time * 4.0) * 2.0
		draw_string(font, Vector2(2, -6 + bob), "!", HORIZONTAL_ALIGNMENT_CENTER, 12, 16, Color(1.0, 0.85, 0.2))
