class_name EnemyManager
extends Node2D
## Создаёт и ведёт врагов и пули: ночные волны, дневные одиночки, урон игроку, добыча с врагов.

signal enemy_killed(enemy: Enemy)

const SPAWN_MIN := 28            # блоков от игрока (за краем экрана)
const SPAWN_MAX := 40
const DESPAWN_DIST := 90.0 * 16.0

var world: WorldData
var player: Player
var clock: DayClock
var enemies: Array[Enemy] = []
var projectiles: Array[Projectile] = []
var rng := RandomNumberGenerator.new()
var spawn_timer := 0.0
var day_spawn_timer := 10.0
var wave_budget := 0
var wave_night := 0
var day_spawns := true
var kills := 0


func setup(w: WorldData, p: Player, c: DayClock) -> void:
	EnemyDB.ensure_loaded()
	world = w
	player = p
	clock = c
	rng.seed = w.seed_value + 99
	clock.night_started.connect(_on_night_started)
	clock.dawn.connect(_on_dawn)
	player.combat = self


static func wave_size(night: int) -> int:
	return mini(6 + 3 * night, 45)


static func max_alive(night: int) -> int:
	return mini(6 + 2 * night, 16)


func _physics_process(delta: float) -> void:
	update(delta)


func update(delta: float) -> void:
	if world == null or player == null:
		return
	_update_projectiles(delta)
	var target := Rect2(player.position, Player.SIZE)
	var horde := clock.is_night()
	for e in enemies.duplicate():
		if not is_instance_valid(e) or e.dead:
			continue
		var touching: bool = e.update(delta, target, horde)
		if touching and e.attack_cd <= 0.0 and player.hp > 0.0:
			if player.take_damage(e.damage, e.center().x):
				e.attack_cd = Enemy.ATTACK_COOLDOWN
		if e.center().distance_to(player.center()) > DESPAWN_DIST:
			_remove(e)
	_spawn_logic(delta)


func _spawn_logic(delta: float) -> void:
	if clock.is_night():
		if wave_budget > 0:
			spawn_timer -= delta
			if spawn_timer <= 0.0 and enemies.size() < max_alive(wave_night):
				if spawn_random(wave_night):
					wave_budget -= 1
				spawn_timer = maxf(0.6, 2.0 - 0.15 * wave_night)
	elif day_spawns:
		day_spawn_timer -= delta
		if day_spawn_timer <= 0.0:
			day_spawn_timer = 25.0
			if enemies.size() < 2:
				spawn_random(1)


## Создаёт врага на поверхности за краем экрана. Возвращает true, если нашлось место.
func spawn_random(night: int) -> bool:
	var def := EnemyDB.pick(night, rng)
	for _attempt in 12:
		var side := 1 if rng.randf() < 0.5 else -1
		var x := player.tile_pos().x + side * rng.randi_range(SPAWN_MIN, SPAWN_MAX)
		x = clampi(x, 4, world.width - 5)
		var e := spawn_enemy(def, x, night)
		if e != null:
			return true
	return false


func spawn_enemy(def: Dictionary, tile_x: int, night: int = 1) -> Enemy:
	var s := world.surface[tile_x]
	for dy in range(1, 5):
		if world.is_solid(tile_x, s - dy):
			return null   # дерево или куча хлама
	var e := Enemy.new()
	e.setup(def, world, night)
	e.position = Vector2(tile_x * 16.0, s * 16.0 - e.size.y)
	e.died.connect(_on_enemy_died)
	add_child(e)
	enemies.append(e)
	return e


## Удар по области. Возвращает число пострадавших врагов.
func melee_hit(area: Rect2, dmg: float, dir: int) -> int:
	var hits := 0
	for e in enemies.duplicate():
		if is_instance_valid(e) and not e.dead and e.rect().intersects(area):
			e.take_damage(dmg, dir)
			hits += 1
	return hits


func fire(from: Vector2, dir: Vector2, dmg: float, speed: float = 600.0) -> Projectile:
	var p := Projectile.new()
	p.world = world
	p.position = from
	p.velocity = dir.normalized() * speed
	p.damage = dmg
	add_child(p)
	projectiles.append(p)
	return p


func _update_projectiles(delta: float) -> void:
	for p in projectiles.duplicate():
		if not p.step(delta, enemies):
			projectiles.erase(p)
			p.queue_free()


func _on_enemy_died(e: Enemy) -> void:
	kills += 1
	for drop in e.def.get("drops", []):
		if rng.randf() < float(drop["chance"]):
			player.inv.add(str(drop["item"]), rng.randi_range(int(drop["min"]), int(drop["max"])))
	enemy_killed.emit(e)
	_remove(e)


func _remove(e: Enemy) -> void:
	enemies.erase(e)
	if is_instance_valid(e):
		e.queue_free()


func _on_night_started(night: int) -> void:
	wave_night = night
	wave_budget = wave_size(night)
	spawn_timer = 1.0


func _on_dawn() -> void:
	wave_budget = 0
	for e in enemies.duplicate():
		_remove(e)
