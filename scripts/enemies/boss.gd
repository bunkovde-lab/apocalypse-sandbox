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
var arena_center := Vector2.ZERO
var ab_timers: Array = []
var ab_state := {}              # индекс способности -> {step, t, dir}
var shield_closed := true
var shield_timer := 0.0
var telegraph := 0.0            # >0: босс готовит удар, рисуется предупреждение
var telegraph_radius := 0.0
var base_damage := 1.0

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
	base_damage = damage


func hp_fraction() -> float:
	return clampf(hp / max_hp, 0.0, 1.0)


func update(delta: float, target: Rect2, horde: bool) -> bool:
	delta = minf(delta, 0.05)
	_prune_minions()
	if boss_id == 1:
		_tick_chief(delta)
	elif boss_id == 2:
		_tick_queen(delta)
	else:
		_tick_generic(delta)
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
	elif boss_id > 2:
		k = _shield_mult()
	var killed := super.take_damage(amount * k, dir)
	# боссы почти не отбрасываются
	knock_time = minf(knock_time, 0.04)
	vel = vel * 0.15
	return killed


# ----- Общая система способностей (боссы 3-9, см. data/enemies.json) -----

func _abilities() -> Array:
	return def.get("abilities", [])


func _shield_ability() -> Dictionary:
	for ab in _abilities():
		if ab["type"] == "shield":
			return ab
	return {}


func _shield_mult() -> float:
	var ab := _shield_ability()
	if ab.is_empty():
		return 1.0
	return float(ab["closed_mult"]) if shield_closed else float(ab["open_mult"])


func _in_phase(ab: Dictionary) -> bool:
	return phase >= int(ab.get("phase_min", 1)) and phase <= int(ab.get("phase_max", 99))


func _tick_generic(delta: float) -> void:
	var f := hp_fraction()
	phase = 1
	for th in def.get("phases", []):
		if f <= float(th):
			phase += 1
	var ps: Array = def.get("phase_speed", [1.0])
	speed = float(def["speed"]) * float(ps[mini(phase - 1, ps.size() - 1)])
	var abs_list := _abilities()
	if ab_timers.size() != abs_list.size():
		ab_timers.clear()
		for ab in abs_list:
			ab_timers.append(minf(float(ab.get("cd", 4.0)), 2.0))
	var near := manager != null and manager.player != null and manager.player.center().distance_to(center()) < 700.0
	for i in abs_list.size():
		var ab: Dictionary = abs_list[i]
		if not _in_phase(ab):
			if str(ab["type"]) in ["charge", "slam"] and ab_state.has(i):
				_end_dash(i)
			continue
		match str(ab["type"]):
			"shield":
				_tick_shield(ab, delta)
			"shoot":
				ab_timers[i] -= delta
				if ab_timers[i] <= 0.0 and near:
					ab_timers[i] = float(ab["cd"])
					_do_shoot(ab)
			"summon":
				ab_timers[i] -= delta
				if ab_timers[i] <= 0.0 and near:
					ab_timers[i] = float(ab["cd"])
					_summon(str(ab["def"]), int(ab["count"]), int(ab["cap"]))
			"charge":
				_tick_charge(i, ab, delta)
			"slam":
				_tick_slam(i, ab, delta)


func _tick_shield(ab: Dictionary, delta: float) -> void:
	if bool(ab.get("while_minions", false)):
		shield_closed = not minions.is_empty()
		return
	shield_timer += delta
	var limit := float(ab["closed"]) if shield_closed else float(ab["open"])
	if shield_timer >= limit:
		shield_timer = 0.0
		shield_closed = not shield_closed


func _do_shoot(ab: Dictionary) -> void:
	if manager == null or manager.player == null:
		return
	var hero := manager.player
	var dmg := float(ab["damage"])
	var spd := float(ab.get("speed", 240.0))
	var col := Color.html(str(ab.get("color", "#ff7a4a")))
	var n := int(ab.get("count", 1))
	var to := hero.center() - center()
	match str(ab.get("pattern", "aimed")):
		"aimed":
			for i in n:
				var a := to.angle() + (i - (n - 1) * 0.5) * 0.08
				manager.hostile_shot(center(), Vector2.from_angle(a), dmg, spd, col)
		"spread":
			var sp := float(ab.get("spread", 0.2))
			for i in n:
				var a := to.angle() + (i - (n - 1) * 0.5) * sp
				manager.hostile_shot(center(), Vector2.from_angle(a), dmg, spd, col)
		"ring":
			for i in n:
				manager.hostile_shot(center(), Vector2.from_angle(TAU * i / n), dmg, spd, col)
		"rain":
			for i in n:
				var x := hero.center().x + randf_range(-170.0, 170.0)
				var origin := _rain_origin(x, hero.center().y)
				manager.hostile_shot(origin, Vector2.DOWN, dmg, spd, col)


## Самая высокая свободная точка над героем в колонке x (не выше 220 px).
func _rain_origin(x: float, hero_y: float) -> Vector2:
	var tx := floori(x / 16.0)
	var y := hero_y
	while y > hero_y - 220.0 and not world.is_solid(tx, floori((y - 16.0) / 16.0)):
		y -= 8.0
	return Vector2(x, y)


func _end_dash(i: int) -> void:
	ab_state.erase(i)
	forced_vx = NAN
	damage = base_damage
	telegraph = 0.0


func _tick_charge(i: int, ab: Dictionary, delta: float) -> void:
	var st: Dictionary = ab_state.get(i, {"step": "idle", "t": 0.0, "dir": 1})
	match st["step"]:
		"idle":
			ab_timers[i] -= delta
			if ab_timers[i] <= 0.0 and manager != null and manager.player != null:
				st = {"step": "tele", "t": float(ab["telegraph"]), "dir": 1}
		"tele":
			forced_vx = 0.0
			telegraph = st["t"]
			telegraph_radius = 0.0
			st["t"] -= delta
			if st["t"] <= 0.0:
				var dir := 1 if manager.player.center().x >= center().x else -1
				st = {"step": "dash", "t": float(ab["duration"]), "dir": dir}
				damage = base_damage * float(ab.get("damage_mult", 1.0))
		"dash":
			telegraph = 0.0
			forced_vx = float(st["dir"]) * speed * float(ab["speed_mult"])
			st["t"] -= delta
			if st["t"] <= 0.0:
				_end_dash(i)
				ab_timers[i] = float(ab["cd"])
				return
	ab_state[i] = st


func _tick_slam(i: int, ab: Dictionary, delta: float) -> void:
	var st: Dictionary = ab_state.get(i, {"step": "idle", "t": 0.0})
	match st["step"]:
		"idle":
			ab_timers[i] -= delta
			if ab_timers[i] <= 0.0 and manager != null and manager.player != null \
					and manager.player.center().distance_to(center()) < float(ab["radius"]) * 3.0:
				st = {"step": "tele", "t": float(ab["telegraph"])}
		"tele":
			telegraph = st["t"]
			telegraph_radius = float(ab["radius"])
			st["t"] -= delta
			if st["t"] <= 0.0:
				telegraph = 0.0
				ab_timers[i] = float(ab["cd"])
				var hero := manager.player
				# удар по земле: спасает прыжок
				if hero.on_floor and absf(hero.center().x - center().x) <= float(ab["radius"]) \
						and absf(hero.center().y - center().y) < 90.0:
					hero.take_damage(float(ab["damage"]), center().x)
				st = {"step": "idle", "t": 0.0}
	ab_state[i] = st


func _draw() -> void:
	super._draw()
	if telegraph > 0.0:
		if telegraph_radius > 0.0:
			draw_arc(size * 0.5, telegraph_radius, 0.0, TAU, 48, Color(1, 0.3, 0.2, 0.7), 2.0)
		else:
			draw_rect(Rect2(Vector2(-4, -4), size + Vector2(8, 8)), Color(1, 0.4, 0.2, 0.6), false, 2.0)
	if boss_id > 2 and not _shield_ability().is_empty():
		var col := Color(0.4, 0.8, 1.0, 0.35) if shield_closed else Color(1.0, 0.9, 0.3, 0.45)
		draw_rect(Rect2(Vector2(-3, -3), size + Vector2(6, 6)), col, false, 2.0)
	if boss_id == 2:
		var col := Color(1.0, 0.9, 0.3, 0.45) if laying else Color(0.4, 0.8, 1.0, 0.25)
		draw_rect(Rect2(Vector2(-3, -3), size + Vector2(6, 6)), col, false, 2.0)
