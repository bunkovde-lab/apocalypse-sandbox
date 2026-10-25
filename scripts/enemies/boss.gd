class_name Boss
extends Enemy
## Босс. Тип берётся из def["boss"]: 1 = Главарь мародёров, 2 = Королева-матка.
## Поведение разбито на фазы, у каждой свой способ победить (см. ТЗ, раздел 6).

var manager: EnemyManager
var boss_id := 1
var phase := 1
var summon_timer := 6.0
var spit_timer := 2.0
var cycle := 0.0           # королева: время в текущей фазе цикла
var laying := false        # королева: уязвима, откладывает яйца
var minions: Array = []

const QUEEN_DEFEND := 14.0
const QUEEN_LAY := 6.0
const QUEEN_ARMOR := 0.25
const QUEEN_OPEN := 1.5


func setup(d: Dictionary, w: WorldData, night: int = 1) -> void:
	super.setup(d, w, night)
	boss_id = int(d["boss"])
	# боссы не растут с ночами, их сила задаётся в данных
	max_hp = float(d["hp"])
	hp = max_hp
	damage = float(d["damage"])


func hp_fraction() -> float:
	return clampf(hp / max_hp, 0.0, 1.0)


func update(delta: float, target: Rect2, horde: bool) -> bool:
	delta = minf(delta, 0.05)
	if boss_id == 1:
		_tick_chief(delta)
	else:
		_tick_queen(delta)
	_prune_minions()
	# босс всегда знает, где игрок
	return super.update(delta, target, true)


func _prune_minions() -> void:
	minions = minions.filter(func(m) -> bool: return is_instance_valid(m) and not m.dead)


func _summon(def_name: String, count: int, cap: int) -> int:
	if manager == null:
		return 0
	var made := 0
	for i in count:
		if minions.size() >= cap:
			break
		var off := (i - (count - 1) * 0.5) * 36.0 + randf_range(-8.0, 8.0)
		var pos := Vector2(center().x + off, position.y)
		var m := manager.spawn_at(EnemyDB.defs[def_name], pos, 1)
		m.position.y = position.y + size.y - m.size.y
		minions.append(m)
		made += 1
	return made


func _shoot_at_target(spd: float, col: Color) -> void:
	if manager == null or manager.player == null:
		return
	var to := manager.player.center() - center()
	if to.length() <= shot_range and manager.line_clear(center(), manager.player.center()):
		manager.hostile_shot(center(), to, shot_damage, spd, col)


# ----- Главарь мародёров -----

func _tick_chief(delta: float) -> void:
	var f := hp_fraction()
	var new_phase := 1 if f > 0.6 else (2 if f > 0.25 else 3)
	if new_phase != phase:
		phase = new_phase
		summon_timer = 1.0
	match phase:
		1:
			keep_dist = 0.0
			retreat = false
			speed = float(def["speed"])
			shot_cd = float(def["shot_cd"])
		2:
			keep_dist = 170.0
			retreat = true
			speed = float(def["speed"])
			shot_cd = 1.4
		3:
			keep_dist = 120.0
			retreat = true
			speed = float(def["speed"]) * 1.5
			shot_cd = 0.9
	# собственная стрельба вместо общей (EnemyManager не знает о фазах босса)
	spit_timer -= delta
	if spit_timer <= 0.0:
		spit_timer = shot_cd
		_shoot_at_target(280.0, Color("ffb04a"))
	if phase >= 2:
		summon_timer -= delta
		if summon_timer <= 0.0:
			summon_timer = 14.0 if phase == 2 else 10.0
			_summon("raider", 2, 4)


# ----- Королева-матка -----

func _tick_queen(delta: float) -> void:
	var enraged := hp_fraction() <= 0.5
	cycle += delta
	var defend_len := QUEEN_DEFEND * (0.7 if enraged else 1.0)
	if laying:
		if cycle >= QUEEN_LAY:
			laying = false
			cycle = 0.0
	elif cycle >= defend_len:
		laying = true
		cycle = 0.0
		_summon("spore_crawler", 3 if not enraged else 5, 10)
	speed = 0.0 if laying else float(def["speed"]) * (1.4 if enraged else 1.0)
	shot_cd = 1.6 if enraged else float(def["shot_cd"])
	if not laying:
		spit_timer -= delta
		if spit_timer <= 0.0:
			spit_timer = shot_cd
			_shoot_at_target(220.0, Color("9bff4a"))
		summon_timer -= delta
		if summon_timer <= 0.0:
			summon_timer = 5.0 if not enraged else 3.5
			_summon("spore_crawler", 1, 6 if not enraged else 10)


func take_damage(amount: float, dir: int) -> bool:
	var k := 1.0
	if boss_id == 2:
		k = QUEEN_OPEN if laying else QUEEN_ARMOR
	var killed := super.take_damage(amount * k, dir)
	# боссы почти не отбрасываются
	knock_time = minf(knock_time, 0.04)
	vel = vel * 0.15
	return killed


func _draw() -> void:
	super._draw()
	if boss_id == 2:
		var col := Color(1.0, 0.9, 0.3, 0.45) if laying else Color(0.4, 0.8, 1.0, 0.25)
		draw_rect(Rect2(Vector2(-3, -3), size + Vector2(6, 6)), col, false, 2.0)
