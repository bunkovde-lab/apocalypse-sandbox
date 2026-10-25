extends RefCounted
## Этап 5: выжившие и стабильность. Критерий из ТЗ: стабильность меняется от еды, воды, обороны и комфорта.

const TILE := 16


func run(t) -> void:
	_test_formulas(t)
	_test_rescue(t)
	_test_production(t)
	_test_reserve(t)
	_test_stability_scenarios(t)
	_test_workers(t)
	_test_crisis_and_arrival(t)
	_test_hero_buff(t)
	await _test_main_scene(t)


func _flat_world(w: int = 120, h: int = 64, floor_y: int = 40) -> WorldData:
	var world := WorldData.new(w, h)
	for y in range(floor_y, h):
		for x in w:
			world.fg[y * w + x] = BlockDB.STONE
	for x in w:
		world.surface[x] = floor_y
	return world


class Rig:
	var world: WorldData
	var p: Player
	var em: EnemyManager
	var sh: ShelterManager
	var sm: SurvivorManager
	var clock := DayClock.new()

	func tick(seconds: float, dt: float = 0.05) -> void:
		var n := int(seconds / dt)
		for _i in n:
			sh.update(dt)
			sm.update(dt)

	func free_all() -> void:
		sm.free()
		sh.free()
		em.free()
		p.free()


func _rig() -> Rig:
	var r := Rig.new()
	r.world = _flat_world()
	r.p = Player.new()
	r.p.world = r.world
	r.p.position = Vector2(56 * TILE, 38 * TILE)
	r.em = EnemyManager.new()
	r.em.world = r.world
	r.em.player = r.p
	r.em.clock = r.clock
	r.p.combat = r.em
	r.sh = ShelterManager.new()
	r.sh.setup(r.world, r.p, r.em)
	r.sm = SurvivorManager.new()
	r.sm.setup(r.world, r.p, r.sh, r.clock)
	return r


func _build_room(world: WorldData) -> void:
	for x in range(49, 59):
		for y in range(35, 40):
			world.set_block(x, y, BlockDB.CONCRETE)
	for x in range(50, 58):
		for y in range(36, 40):
			world.set_block(x, y, BlockDB.AIR)
	world.set_block(49, 38, BlockDB.DOOR)
	world.set_block(49, 39, BlockDB.DOOR)


## Стандартная база: комната, 2 кровати, 2 грядки, генератор, очиститель, турель.
func _base(r: Rig, beds: int = 2) -> void:
	_build_room(r.world)
	for i in beds:
		r.world.set_block(50 + i, 39, BlockDB.BED)
	r.world.set_block(53, 39, BlockDB.PLANTER)
	r.world.set_block(54, 39, BlockDB.PLANTER)
	r.world.set_block(55, 39, BlockDB.PURIFIER)
	r.world.set_block(56, 39, BlockDB.GENERATOR)
	r.world.set_block(57, 38, BlockDB.TURRET)
	r.sh.fuel[Vector2i(56, 39)] = 600.0
	r.sh.recompute_power()


func _add_resident(r: Rig, role: String = "") -> Survivor:
	var s := r.sm.spawn_stranded(40)
	s.position = r.p.position
	r.p.position = Vector2(56 * TILE, 38 * TILE)
	var msg := r.sm.rescue(s)
	if role != "":
		s.role = role
	return s


func _test_formulas(t) -> void:
	t.check(is_equal_approx(Stability.coverage(4.0, 0.0, 4.0), 1.0), "производство = потреблению: K = 1")
	t.check(is_equal_approx(Stability.coverage(2.0, 0.0, 4.0), 0.5), "половина производства: K = 0.5")
	t.check(is_equal_approx(Stability.coverage(0.0, 6.0, 4.0), 0.5), "запас делится на 3 суток: R/3 = 2 из 4")
	t.check(Stability.coverage(10.0, 99.0, 4.0) == 1.0, "K не больше 1")
	t.check(Stability.coverage(0.0, 0.0, 0.0) == 1.0, "без жителей потребления нет, K = 1")
	t.check(is_equal_approx(Stability.compute(1, 1, 1, 1), 100.0), "всё идеально: S = 100")
	t.check(is_equal_approx(Stability.compute(0, 0, 0, 0), 0.0), "всё плохо: S = 0")
	t.check(is_equal_approx(Stability.compute(1, 0, 0, 0), 30.0), "вес еды 30%")
	t.check(is_equal_approx(Stability.compute(0, 1, 0, 0), 30.0), "вес воды 30%")
	t.check(is_equal_approx(Stability.compute(0, 0, 1, 0), 20.0), "вес обороны 20%")
	t.check(is_equal_approx(Stability.compute(0, 0, 0, 1), 20.0), "вес комфорта 20%")
	t.check(Stability.state_of(80.0) == Stability.PROSPERITY and Stability.state_of(79.9) == Stability.NORMAL, "граница 80")
	t.check(Stability.state_of(50.0) == Stability.NORMAL and Stability.state_of(49.9) == Stability.TENSION, "граница 50")
	t.check(Stability.state_of(25.0) == Stability.TENSION and Stability.state_of(24.9) == Stability.CRISIS, "граница 25")
	t.check(Stability.work_mult(Stability.PROSPERITY) == 1.15 and Stability.work_mult(Stability.TENSION) == 0.8 \
		and Stability.work_mult(Stability.CRISIS) == 0.0, "множители работы: +15%, -20%, стоп")


func _test_rescue(t) -> void:
	var r := _rig()
	var s := r.sm.spawn_stranded(40)
	t.check(r.sm.stranded.size() == 1 and not s.resident, "спасаемый появился на поверхности")
	t.check(absf(s.position.y + Survivor.SIZE.y - 40 * TILE) < 0.01, "стоит на земле")
	var msg := r.sm.rescue(s)
	t.check(not s.resident and "койк" in msg, "без койки не принимают: " + msg)
	r.world.set_block(51, 39, BlockDB.BED)
	r.p.position = s.position + Vector2(10, 0)
	msg = r.sm.interact_at(s.center(), r.p)
	t.check(s.resident and r.sm.residents.size() == 1 and r.sm.stranded.is_empty(), "с койкой спасённый становится жителем: " + msg)
	t.check(s.home == Vector2i(51, 39) and s.role in Survivor.ROLES, "ему назначены койка и роль «%s»" % s.role)
	t.check(absf(s.center().x - 51.5 * TILE) < 20.0, "житель отправлен к своей койке")
	var old: String = s.role
	r.p.position = s.position
	msg = r.sm.interact_at(s.center(), r.p)
	t.check(s.role != old and s.role in Survivor.ROLES, "E по жителю меняет роль: " + msg)
	# далеко от игрока — не сработает
	r.p.position = Vector2(5 * TILE, 38 * TILE)
	t.check(r.sm.interact_at(s.center(), r.p) == "", "издалека взаимодействие не работает")
	# лимит жителей
	for i in 6:
		r.world.set_block(60 + i, 39, BlockDB.BED)
	for i in 5:
		var x := r.sm.spawn_stranded(70 + i)
		x.position = r.p.position
		r.sm.rescue(x)
	t.check(r.sm.residents.size() == 4, "стартовый лимит 4 жителя (сейчас %d)" % r.sm.residents.size())
	r.free_all()


func _test_production(t) -> void:
	var r := _rig()
	_base(r)
	r.sh.evaluate()
	# две запитанные грядки по 4, очиститель 6
	t.check(is_equal_approx(r.sh.prod_food, 8.0), "2 запитанные грядки дают 8 еды в сутки: %.1f" % r.sh.prod_food)
	t.check(is_equal_approx(r.sh.prod_water, 6.0), "запитанный очиститель даёт 6 воды: %.1f" % r.sh.prod_water)
	r.sh.fuel[Vector2i(56, 39)] = 0.0
	r.sh.recompute_power()
	r.sh.evaluate()
	t.check(is_equal_approx(r.sh.prod_food, 2.0), "без энергии грядки дают по 1: %.1f" % r.sh.prod_food)
	t.check(is_equal_approx(r.sh.prod_water, 0.0), "без энергии очиститель стоит")
	# сборник дождя: только под открытым небом
	r.world.set_block(20, 39, BlockDB.RAIN_COLLECTOR)
	r.sh.evaluate()
	t.check(is_equal_approx(r.sh.prod_water, 2.0), "сборник дождя под небом даёт 2 воды")
	r.world.set_block(20, 30, BlockDB.STONE)
	r.sh.evaluate()
	t.check(is_equal_approx(r.sh.prod_water, 0.0), "под крышей сборник дождя не работает")
	# энергетический бюджет: генератор 12 ед.: грядки 2+2, очиститель 4, турель 4 = 12
	r.sh.fuel[Vector2i(56, 39)] = 600.0
	r.sh.recompute_power()
	var all_on := true
	for p in [Vector2i(53, 39), Vector2i(54, 39), Vector2i(55, 39), Vector2i(57, 38)]:
		if not r.sh.is_powered(p):
			all_on = false
	t.check(all_on, "генератор тянет всю базу ровно на 12 единиц")
	r.world.set_block(58, 38, BlockDB.PURIFIER)
	r.sh.recompute_power()
	t.check(not r.sh.is_powered(Vector2i(58, 38)), "лишний потребитель без энергии")
	r.free_all()


func _test_reserve(t) -> void:
	var r := _rig()
	_base(r)
	_add_resident(r)
	r.sh.evaluate()
	t.check(r.sh.cons_food == 2.0 and r.sh.cons_water == 3.0, "один житель: еда 2, вода 3 в сутки")
	t.check(r.sh.capacity == 0.0, "без склада запас копить негде")
	r.sh.economy_step(DayClock.DAY_LENGTH)
	t.check(r.sh.reserve_food == 0.0, "без склада излишки пропадают")
	r.world.set_block(52, 39, BlockDB.CRATE)
	r.sh.evaluate()
	t.check(r.sh.capacity == 40.0, "склад даёт ёмкость 40")
	r.sh.economy_step(DayClock.DAY_LENGTH)
	t.check(is_equal_approx(r.sh.reserve_food, 6.0), "за сутки в запас +6 еды (8-2): %.2f" % r.sh.reserve_food)
	t.check(is_equal_approx(r.sh.reserve_water, 3.0), "за сутки в запас +3 воды (6-3): %.2f" % r.sh.reserve_water)
	for _i in 30:
		r.sh.economy_step(DayClock.DAY_LENGTH)
	t.check(r.sh.reserve_food == 40.0, "запас не превышает ёмкость")
	# вырубили энергию: производство падает, запас покрывает дефицит
	r.sh.fuel[Vector2i(56, 39)] = 0.0
	r.sh.recompute_power()
	r.sh.evaluate()
	t.check(r.sh.k_water == 1.0 and r.sh.prod_water == 0.0, "воды нет, но запас 40/3 ≥ потребления 3: K_w = 1")
	r.sh.reserve_water = 3.0
	r.sh.evaluate()
	t.check(is_equal_approx(r.sh.k_water, 1.0 / 3.0), "запас 3 → (0+3/3)/3 = 1/3: %.3f" % r.sh.k_water)
	r.free_all()


func _test_stability_scenarios(t) -> void:
	var r := _rig()
	_base(r)
	_add_resident(r)
	_add_resident(r)
	r.sh.evaluate()
	t.check(r.sh.k_food == 1.0 and r.sh.k_water == 1.0, "2 жителя: еды 8 ≥ 4, воды 6 ≥ 6")
	t.check(r.sh.base_room_ok, "комната с койкой замкнута")
	t.check(is_equal_approx(r.sh.k_com, 1.0), "комфорт: койки, комната, свет → 1.0")
	t.check(is_equal_approx(r.sh.k_def, 16.0 / 18.0), "оборона (турель 8 + комната 8) / волна 18: %.3f" % r.sh.k_def)
	var expected := 100.0 * (0.3 + 0.3 + 0.2 * 16.0 / 18.0 + 0.2)
	t.check(absf(r.sh.stability - expected) < 0.01 and r.sh.state == Stability.PROSPERITY, "S = %.1f, процветание" % r.sh.stability)
	var s_full := r.sh.stability
	# ломаем еду
	r.world.set_block(53, 39, BlockDB.AIR)
	r.world.set_block(54, 39, BlockDB.AIR)
	r.sh.evaluate()
	t.check(r.sh.stability < s_full - 20.0, "без грядок S падает: %.1f" % r.sh.stability)
	# убираем воду
	r.world.set_block(55, 39, BlockDB.AIR)
	r.sh.evaluate()
	t.check(r.sh.k_water == 0.0 and r.sh.stability < 40.0, "без воды S ещё ниже: %.1f" % r.sh.stability)
	# убираем турель, дыра в потолке
	r.world.set_block(57, 38, BlockDB.AIR)
	r.world.set_block(53, 35, BlockDB.AIR)
	r.sh.evaluate()
	t.check(r.sh.k_def == 0.0 and not r.sh.base_room_ok, "оборона 0 без турели и замкнутой комнаты")
	t.check(r.sh.k_com < 1.0, "комфорт падает без комнаты: %.2f" % r.sh.k_com)
	t.check(r.sh.state != Stability.PROSPERITY, "итог: уже не процветание (S %.1f)" % r.sh.stability)
	var txt := r.sh.panel_text()
	t.check("стабильность" in txt and "Жители 2/4" in txt, "панель убежища показывает данные")
	r.free_all()


func _test_workers(t) -> void:
	var r := _rig()
	_base(r, 3)
	var farmer := _add_resident(r, "farmer")
	var eng := _add_resident(r, "engineer")
	var builder := _add_resident(r, "builder")
	r.sh.evaluate()
	r.tick(0.6)
	t.check(farmer.station != Survivor.NO_STATION and r.world.get_block(farmer.station.x, farmer.station.y) == BlockDB.PLANTER, "фермер выбрал грядку")
	t.check(eng.station != Survivor.NO_STATION and r.world.get_block(eng.station.x, eng.station.y) == BlockDB.PURIFIER, "инженер выбрал очиститель")
	t.check(builder.station == Survivor.NO_STATION, "у строителя нет станции")
	r.tick(15.0)
	t.check(farmer.working and eng.working, "фермер и инженер дошли и работают")
	t.check(r.sh.manned.has(farmer.station) and r.sh.manned.has(eng.station), "станции отмечены как обслуживаемые")
	var wm := r.sh.work_mult()
	r.sh.evaluate()
	var expect_food := 4.0 * 1.5 * wm + 4.0
	t.check(absf(r.sh.prod_food - expect_food) < 0.01, "работающий фермер: грядка ×1.5×%.2f → еда %.2f" % [wm, r.sh.prod_food])
	var expect_water := 6.0 * 1.5 * wm
	t.check(absf(r.sh.prod_water - expect_water) < 0.01, "работающий инженер → вода %.2f" % r.sh.prod_water)
	# второй фермер берёт вторую грядку, а не ту же
	r.world.set_block(57, 39, BlockDB.BED)
	var f2 := _add_resident(r, "farmer")
	t.check(f2.resident, "четвёртый житель принят (койка есть)")
	r.tick(1.0)
	t.check(f2.station != Survivor.NO_STATION and f2.station != farmer.station, "второй фермер идёт на другую грядку")
	# смена роли освобождает станцию
	farmer.role = "builder"
	r.tick(1.0)
	t.check(farmer.station == Survivor.NO_STATION, "смена роли снимает с грядки")
	# строитель чинит блоки
	builder.skills["builder"] = 3
	r.world.set_block(51, 36, BlockDB.WOOD)
	r.world.damage_block(51, 36, 0.4)
	t.check(r.world.damage_fraction(51, 36) > 0.5, "блок рядом с базой повреждён")
	r.tick(3.0)
	t.check(r.world.damage_fraction(51, 36) == 0.0, "строитель починил блок сам")
	# разрушенная грядка снимает работника
	var st := f2.station
	r.world.set_block(st.x, st.y, BlockDB.AIR)
	r.tick(1.0)
	t.check(f2.station != st, "грядку сломали — фермер переназначен")
	r.free_all()


func _test_crisis_and_arrival(t) -> void:
	var r := _rig()
	# койки есть, еды и воды нет, обороны нет
	r.world.set_block(51, 39, BlockDB.BED)
	r.world.set_block(52, 39, BlockDB.BED)
	var a := _add_resident(r)
	var b := _add_resident(r)
	r.sh.evaluate()
	t.check(r.sh.state == Stability.CRISIS, "голод без обороны: кризис (S %.1f)" % r.sh.stability)
	t.check(r.sh.work_mult() == 0.0, "в кризис работа встаёт")
	var msgs: Array = []
	r.sm.message.connect(func(m: String) -> void: msgs.append(m))
	r.tick(50.0)
	t.check(r.sm.residents.size() == 2, "через 50 с кризиса все ещё на месте")
	r.tick(15.0)
	t.check(r.sm.residents.size() == 1 and msgs.size() == 1, "после 60 с кто-то ушёл: " + str(msgs))
	r.tick(35.0)
	t.check(r.sm.residents.is_empty(), "кризис продолжается — ушёл и второй")
	r.free_all()

	# процветание: новый житель приходит сам
	var q := _rig()
	_base(q, 3)
	_add_resident(q)
	_add_resident(q)
	q.sh.evaluate()
	t.check(q.sh.state == Stability.PROSPERITY, "база процветает (S %.1f)" % q.sh.stability)
	var n := q.sm.arrive_newcomer()
	t.check(n != null and q.sm.residents.size() == 3 and n.resident, "на рассвете приходит новый житель")
	t.check(q.sm.arrive_newcomer() == null, "свободных коек нет — новых нет")
	q.world.set_block(51, 39, BlockDB.AIR)
	q.sh.evaluate()
	q.free_all()

	# новые не приходят в «норме»
	var z := _rig()
	_base(z, 3)
	_add_resident(z)
	z.world.set_block(57, 38, BlockDB.AIR)
	z.world.set_block(53, 35, BlockDB.AIR)
	z.sh.evaluate()
	t.check(z.sh.state != Stability.PROSPERITY and z.sm.arrive_newcomer() == null, "без процветания новичков нет")
	# сигнал рассвета ведёт к приходу
	var d := _rig()
	_base(d, 3)
	_add_resident(d)
	_add_resident(d)
	d.sh.evaluate()
	var before := d.sm.residents.size()
	d.clock.dawn.emit()
	t.check(d.sm.residents.size() == before + 1, "сигнал рассвета приводит нового жителя")
	d.free_all()
	z.free_all()


func _test_hero_buff(t) -> void:
	var r := _rig()
	_base(r)
	_add_resident(r)
	_add_resident(r)
	r.sh.evaluate()
	t.check(r.p.home_state == 1, "процветание даёт герою бафф «Дом»")
	r.p.hp = 50.0
	r.p.since_damage = 99.0
	r.p._tick_timers(1.0)
	t.check(is_equal_approx(r.p.hp, 54.0), "регенерация ×2 при баффе: %.1f" % r.p.hp)
	r.world.set_block(53, 39, BlockDB.AIR)
	r.world.set_block(54, 39, BlockDB.AIR)
	r.world.set_block(55, 39, BlockDB.AIR)
	r.world.set_block(57, 38, BlockDB.AIR)
	r.world.set_block(53, 35, BlockDB.AIR)
	r.world.set_block(50, 39, BlockDB.AIR)
	r.world.set_block(51, 39, BlockDB.AIR)
	r.sh.evaluate()
	t.check(r.p.home_state == -1, "кризис даёт герою дебафф «Тревога»")
	r.free_all()


func _test_main_scene(t) -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main = scene.instantiate()
	main.world_width = 800
	main.world_height = 300
	t.root.add_child(main)
	var guard := 0
	while not main.ready_done and guard < 600:
		await t.process_frame
		guard += 1
	t.check(main.ready_done, "сцена со стадией 5 запускается")
	t.check(main.survivors != null and main.survivors.stranded.size() == 3, "на карте 3 ожидающих спасения")
	t.check(main.player.survivors == main.survivors and main.shelter.survivors == main.survivors, "менеджеры связаны")
	await t.process_frame
	await t.process_frame
	t.check("стабильность" in main.hud.panel.text, "панель убежища в HUD заполнена")
	main.queue_free()
	await t.process_frame
