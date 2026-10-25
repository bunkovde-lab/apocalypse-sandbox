class_name ShelterManager
extends Node2D
## Убежище: комнаты, двери, кровать, генератор с топливом, турели на энергии и шипы.
## Устройства регистрируются сами по сигналу block_changed.

const TILE := 16
const POWER_RANGE := 12            # блоков от генератора до потребителя
const GEN_CAPACITY := 12.0
const TURRET_DRAW := 4.0
const FUEL_PER_COAL := 120.0       # секунд работы от одного угля
const FUEL_MAX := 600.0
const TURRET_RANGE := 176.0
const TURRET_DAMAGE := 9.0
const TURRET_COOLDOWN := 0.7
const SPIKE_DAMAGE := 18.0
const SPIKE_COOLDOWN := 0.6
const ROOM_LIMIT := 500            # больше этого — не комната, а открытое пространство

var world: WorldData
var player: Player
var combat: EnemyManager
var devices := {}       # Vector2i -> id блока-устройства
var fuel := {}          # Vector2i генератора -> секунд топлива
var cooldowns := {}     # Vector2i -> секунд до следующего действия
var powered := {}       # Vector2i турели -> есть ли энергия
var gen_load := {}      # Vector2i генератора -> нагрузка
var tracers: Array = [] # [от, до, время жизни]
var power_timer := 0.0


func setup(w: WorldData, p: Player, c: EnemyManager) -> void:
	world = w
	player = p
	combat = c
	world.block_changed.connect(_on_block_changed)
	p.shelter = self


func _on_block_changed(x: int, y: int) -> void:
	var pos := Vector2i(x, y)
	var id := world.get_block(x, y)
	if BlockDB.device[id] == 1:
		devices[pos] = id
	elif devices.erase(pos):
		fuel.erase(pos)
		cooldowns.erase(pos)
		powered.erase(pos)
		gen_load.erase(pos)
	recompute_power()


func count_of(id: int) -> int:
	var n := 0
	for p in devices:
		if devices[p] == id:
			n += 1
	return n


# ---------- Энергия ----------

func recompute_power() -> void:
	powered.clear()
	gen_load.clear()
	for p in devices:
		if devices[p] != BlockDB.TURRET:
			continue
		powered[p] = false
		for g in devices:
			if devices[g] != BlockDB.GENERATOR or float(fuel.get(g, 0.0)) <= 0.0:
				continue
			if absi(g.x - p.x) > POWER_RANGE or absi(g.y - p.y) > POWER_RANGE:
				continue
			var used: float = gen_load.get(g, 0.0)
			if used + TURRET_DRAW <= GEN_CAPACITY:
				gen_load[g] = used + TURRET_DRAW
				powered[p] = true
				break


func is_powered(pos: Vector2i) -> bool:
	return bool(powered.get(pos, false))


# ---------- Обновление ----------

func update(delta: float) -> void:
	if world == null:
		return
	power_timer -= delta
	if power_timer <= 0.0:
		power_timer = 0.25
		recompute_power()
	for g in gen_load:
		var left: float = float(fuel.get(g, 0.0)) - delta
		fuel[g] = maxf(0.0, left)
		if left <= 0.0:
			power_timer = 0.0
	for i in range(tracers.size() - 1, -1, -1):
		tracers[i][2] -= delta
		if tracers[i][2] <= 0.0:
			tracers.remove_at(i)
	for pos in devices:
		var id: int = devices[pos]
		if id != BlockDB.TURRET and id != BlockDB.SPIKES:
			continue
		var cd: float = maxf(0.0, float(cooldowns.get(pos, 0.0)) - delta)
		cooldowns[pos] = cd
		if cd > 0.0 or combat == null:
			continue
		if id == BlockDB.TURRET and is_powered(pos):
			_turret_fire(pos)
		elif id == BlockDB.SPIKES:
			_spikes_hit(pos)
	queue_redraw()


func _physics_process(delta: float) -> void:
	update(delta)


func _tile_center(pos: Vector2i) -> Vector2:
	return Vector2(pos.x * TILE + TILE * 0.5, pos.y * TILE + TILE * 0.5)


func _turret_fire(pos: Vector2i) -> void:
	var from := _tile_center(pos)
	var best: Enemy = null
	var best_d := TURRET_RANGE
	for e in combat.enemies:
		if is_instance_valid(e) and not e.dead:
			var d := from.distance_to(e.center())
			if d <= best_d:
				best_d = d
				best = e
	if best == null:
		return
	cooldowns[pos] = TURRET_COOLDOWN
	tracers.append([from, best.center(), 0.08])
	best.take_damage(TURRET_DAMAGE, 1 if best.center().x >= from.x else -1)


func _spikes_hit(pos: Vector2i) -> void:
	var area := Rect2(pos.x * TILE, pos.y * TILE + 4, TILE, TILE - 4)
	var hit := false
	for e in combat.enemies.duplicate():
		if is_instance_valid(e) and not e.dead and e.rect().intersects(area):
			e.take_damage(SPIKE_DAMAGE, 1 if e.center().x >= pos.x * TILE else -1)
			hit = true
	if hit:
		cooldowns[pos] = SPIKE_COOLDOWN


# ---------- Взаимодействие (клавиша E) ----------

## Возвращает короткое сообщение о результате или "" если на клетке нечего делать.
func interact(t: Vector2i, p: Player) -> String:
	if world == null or not p.tile_in_reach(t):
		return ""
	var id := world.get_block(t.x, t.y)
	match id:
		BlockDB.DOOR, BlockDB.DOOR_OPEN:
			return toggle_door(t)
		BlockDB.GENERATOR:
			return refuel(t, p)
		BlockDB.BED:
			p.spawn_pos = Vector2(t.x * TILE + 1, (t.y + 1) * TILE - Player.SIZE.y)
			return "Точка возрождения: кровать."
	return ""


func toggle_door(t: Vector2i) -> String:
	var opening := world.get_block(t.x, t.y) == BlockDB.DOOR
	var top := t.y
	while _is_door(t.x, top - 1):
		top -= 1
	var y := top
	var new_id := BlockDB.DOOR_OPEN if opening else BlockDB.DOOR
	if not opening and player != null:
		var body := Rect2(player.position, Player.SIZE)
		while _is_door(t.x, y):
			if body.intersects(Rect2(t.x * TILE, y * TILE, TILE, TILE)):
				return "Дверь нельзя закрыть: мешает игрок."
			y += 1
		y = top
	while _is_door(t.x, y):
		world.set_block(t.x, y, new_id)
		y += 1
	return "Дверь открыта." if opening else "Дверь закрыта."


func _is_door(x: int, y: int) -> bool:
	var id := world.get_block(x, y)
	return id == BlockDB.DOOR or id == BlockDB.DOOR_OPEN


func refuel(t: Vector2i, p: Player) -> String:
	var have: float = fuel.get(t, 0.0)
	var added := 0
	while added < 10 and have + FUEL_PER_COAL <= FUEL_MAX and p.inv.count("coal") > 0:
		p.inv.remove("coal", 1)
		have += FUEL_PER_COAL
		added += 1
	fuel[t] = have
	recompute_power()
	if added == 0:
		return "Генератор: топлива %d с (нужен уголь)." % int(have)
	return "Генератор заправлен: %d с." % int(have)


# ---------- Комнаты ----------

## Заливка свободного пространства от клетки t. enclosed = true, если пространство замкнуто и невелико.
func room_at(t: Vector2i, limit: int = ROOM_LIMIT) -> Dictionary:
	var result := {"enclosed": false, "size": 0, "beds": 0, "turrets": 0, "generators": 0,
		"doors": 0, "tiles": []}
	if world.is_solid(t.x, t.y):
		return result
	var seen := {t: true}
	var queue: Array[Vector2i] = [t]
	var head := 0
	var doors := {}
	while head < queue.size():
		if queue.size() > limit:
			result["size"] = queue.size()
			return result
		var c := queue[head]
		head += 1
		var id := world.get_block(c.x, c.y)
		if id == BlockDB.BED:
			result["beds"] += 1
		elif id == BlockDB.TURRET:
			result["turrets"] += 1
		elif id == BlockDB.GENERATOR:
			result["generators"] += 1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + d
			if seen.has(n):
				continue
			var nid := world.get_block(n.x, n.y)
			if nid == BlockDB.DOOR:
				doors[n] = true
			if world.is_solid(n.x, n.y):
				continue
			seen[n] = true
			queue.append(n)
	result["enclosed"] = true
	result["size"] = queue.size()
	var door_count := 0
	for d in doors:
		if not doors.has(d + Vector2i(0, -1)):
			door_count += 1          # дверь в два блока считается один раз
	result["doors"] = door_count
	result["tiles"] = queue
	return result


# ---------- Отрисовка ----------

func _draw() -> void:
	for tr in tracers:
		draw_line(tr[0], tr[1], Color(1.0, 0.9, 0.4, 0.9), 1.5)
	for pos in devices:
		var id: int = devices[pos]
		var c := _tile_center(pos)
		if id == BlockDB.TURRET:
			draw_circle(c + Vector2(0, -2), 2.5, Color(0.3, 1.0, 0.4) if is_powered(pos) else Color(0.9, 0.2, 0.2))
		elif id == BlockDB.GENERATOR:
			var on := gen_load.has(pos)
			draw_circle(c + Vector2(0, -2), 2.5, Color(1.0, 0.85, 0.2) if on else Color(0.4, 0.4, 0.4))
