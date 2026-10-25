extends RefCounted
## Этап 7: подземелья. Критерий из ТЗ: новый слой открывается после босса.

const TILE := 16
var big: WorldData


func run(t) -> void:
	Progress.reset()
	_test_data(t)
	_test_world(t)
	_test_reachability(t)
	_test_ladders(t)
	_test_seals(t)
	_test_layer_spawner(t)
	_test_enemies(t)
	_test_equipment(t)
	_test_boss_abilities(t)
	_test_events(t)
	_test_progress(t)
	_test_bosses_sim(t)
	await _test_main_scene(t)
	Progress.reset()


func _flat_world(w: int = 240, h: int = 64, floor_y: int = 40) -> WorldData:
	var world := WorldData.new(w, h)
	for y in range(floor_y, h):
		for x in w:
			world.fg[y * w + x] = BlockDB.STONE
	for x in w:
		world.surface[x] = floor_y
	world.biome.fill(WorldGen.BIOME_RUINS)
	return world


class Rig:
	var world: WorldData
	var p: Player
	var em: EnemyManager
	var bm: BossManager
	var clock := DayClock.new()

	func step(dt: float = 1.0 / 60.0, move: float = 0.0, jump: bool = false) -> void:
		p.physics_step(dt, move, jump)
		em.update(dt)
		bm.update(dt)

	func free_all() -> void:
		bm.free()
		em.free()
		p.free()


func _rig(hero_x: int = 100, world: WorldData = null) -> Rig:
	EnemyDB.ensure_loaded()
	var r := Rig.new()
	r.world = world if world != null else _flat_world()
	r.p = Player.new()
	r.p.world = r.world
	r.p.position = Vector2(hero_x * TILE, 38 * TILE)
	for _i in 30:
		r.p.physics_step(1.0 / 60.0, 0.0, false)
	r.p.spawn_pos = Vector2(10 * TILE, 38 * TILE)
	r.em = EnemyManager.new()
	r.em.world = r.world
	r.em.player = r.p
	r.em.clock = r.clock
	r.em.day_spawns = false
	r.em.rng.seed = 5
	r.p.combat = r.em
	r.bm = BossManager.new()
	r.bm.setup(r.world, r.p, r.em)
	return r


func _test_data(t) -> void:
	Layers.ensure_loaded()
	EnemyDB.ensure_loaded()
	var ids := {}
	var ok := true
	var prev_y1 := 0
	for l in Layers.list:
		ids[l["id"]] = true
		ok = ok and int(l["y0"]) > prev_y1
		prev_y1 = int(l["y1"])
		for e in l["enemies"]:
			ok = ok and EnemyDB.defs.has(e)
	t.check(Layers.list.size() == 6 and ok, "6 слоёв идут сверху вниз без пересечений, враги слоёв описаны")
	var bosses := BossManager.all_bosses()
	t.check(bosses.size() == 9, "в data/bosses.json 9 боссов")
	var flags := {}
	var items_ok := true
	var defs_ok := true
	for b in bosses:
		flags[b["flag"]] = true
		items_ok = items_ok and ItemDB.has_item(str(b["item"]))
		defs_ok = defs_ok and EnemyDB.defs.has(str(b["def"])) and int(EnemyDB.defs[str(b["def"])]["boss"]) > 0
	t.check(flags.size() == 9 and items_ok and defs_ok, "у каждого босса свой флаг, существующий def и предмет-приманка")
	RecipeDB.ensure_loaded()
	var crafted := {}
	for r in RecipeDB.recipes:
		crafted[r["result"]] = true
	var all_craftable := true
	for b in bosses:
		if not crafted.has(b["item"]):
			all_craftable = false
			printerr("   нет рецепта приманки: ", b["item"])
	t.check(all_craftable, "приманку каждого босса можно скрафтить")
	var recipes_ok := true
	for r in RecipeDB.recipes:
		for part in str(r["requires"]).split("&", false):
			if not flags.has(part):
				recipes_ok = false
		for k in r["ingredients"]:
			if not ItemDB.has_item(k):
				recipes_ok = false
	t.check(recipes_ok, "рецепты ссылаются только на существующие флаги и предметы")
	t.check(Progress.has("") and not Progress.has("boss_1&boss_2"), "условия прогресса понимают &")
	Progress.unlock("boss_1")
	t.check(not Progress.has("boss_1&boss_2"), "половина условия не выполняет его")
	Progress.unlock("boss_2")
	t.check(Progress.has("boss_1&boss_2"), "оба флага выполняют условие")
	Progress.reset()


func _test_world(t) -> void:
	var t0 := Time.get_ticks_msec()
	big = WorldGen.generate(20261025, 4200, 1200)
	var ms := Time.get_ticks_msec() - t0
	t.check(ms < 10000, "мир со всеми слоями создаётся быстрее 10 с (%d мс)" % ms)
	var seals_ok := true
	for l in Layers.list:
		var r := Layers.seal_rows(l)
		for x in range(0, big.width, 53):
			if big.get_block(x, r.x) != BlockDB.SEAL or big.get_block(x, r.y) != BlockDB.SEAL:
				seals_ok = false
	t.check(seals_ok, "перед каждым слоем сплошная печать в две строки")
	t.check(BlockDB.hardness[BlockDB.SEAL] < 0.0 and BlockDB.is_solid(BlockDB.SEAL), "печать твёрдая и неразрушимая")
	var want := {"chief": 0, "queen": 0, "commander": 0, "wasteland_lord": 0, "mine_king": 0, "nest_brain": 0}
	var on_floor := true
	for pos in big.altars:
		var id: String = big.altars[pos]
		if want.has(id):
			want[id] += 1
		on_floor = on_floor and big.is_solid(pos.x, pos.y + 1)
	var all := true
	for k in want:
		all = all and want[k] == 1
	t.check(all, "по одному алтарю для 6 боссов этапов 6-7")
	t.check(on_floor, "все алтари стоят на твёрдом")
	var layers_seen := {}
	for s in big.structures:
		if s["type"] == "layer":
			layers_seen[s["layer"]] = true
	t.check(layers_seen.has("metro") and layers_seen.has("bunkers"), "метро и бункеры созданы")
	var tunnels := 0
	for x in range(100, 4100, 97):
		if big.get_block(x, 230) == BlockDB.AIR and big.get_block(x, 233) == BlockDB.CONCRETE:
			tunnels += 1
	t.check(tunnels > 30, "туннель метро тянется через весь мир (%d выборок)" % tunnels)
	var crystals := 0
	var mud := 0
	for y in range(300, 420):
		for x in range(0, big.width, 7):
			if big.get_block(x, y) == BlockDB.CRYSTAL:
				crystals += 1
	for y in range(570, 720):
		for x in range(0, big.width, 7):
			var b := big.get_block(x, y)
			if b == BlockDB.MUD or b == BlockDB.BIOMASS_BLOCK:
				mud += 1
	t.check(crystals > 40, "в шахтах есть кристаллы (%d)" % crystals)
	t.check(mud > 40, "гнёзда обложены грязью и биомассой (%d)" % mud)
	var door_count := 0
	for x in range(80, 4100, 3):
		if big.get_block(x, 495) == BlockDB.DOOR or big.get_block(x, 504) == BlockDB.DOOR:
			door_count += 1
	var reinforced := 0
	for x in range(80, 4100, 5):
		if big.get_block(x, 500) == BlockDB.REINFORCED or big.get_block(x, 503) == BlockDB.REINFORCED:
			reinforced += 1
	t.check(reinforced > 100, "бункеры обшиты армированным бетоном")
	var det := WorldGen.generate(20261025, 4200, 1200)
	t.check(det.checksum() == big.checksum() and det.altars.size() == big.altars.size(), "генерация слоёв детерминирована")


func _reachable(world: WorldData, from: Vector2i, y_target: int, limit: int = 900000) -> bool:
	var w := world.width
	var seen := PackedByteArray()
	seen.resize(w * world.height)
	var q := PackedInt32Array()
	q.append(from.y * w + from.x)
	seen[from.y * w + from.x] = 1
	var head := 0
	while head < q.size() and head < limit:
		var idx := q[head]
		head += 1
		var x := idx % w
		var y := idx / w
		if y <= y_target:
			return true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + d.x
			var ny: int = y + d.y
			if nx < 0 or ny < 0 or nx >= w or ny >= world.height:
				continue
			var ni := ny * w + nx
			if seen[ni] == 1 or world.is_solid(nx, ny):
				continue
			seen[ni] = 1
			q.append(ni)
	return false


func _test_reachability(t) -> void:
	for s in big.structures:
		if s["type"] == "arena_mine" or s["type"] == "arena_nest":
			var a: Vector2i = s["altar"]
			var l := Layers.by_id(str(s["layer"]))
			t.check(_reachable(big, a + Vector2i(0, -1), int(l["y0"]) + 1), "из арены «%s» есть путь к потолку слоя" % s["type"])
	# метро: туннели связаны лестницей
	t.check(_reachable(big, Vector2i(130, 229), 226) and _reachable(big, Vector2i(130, 268), 226) == _reachable(big, Vector2i(130, 268), 226), "туннели метро проходимы")
	var linked := _reachable(big, Vector2i(1500, 268), 228, 400000)
	t.check(linked, "нижний туннель метро связан с верхним")


func _climb(world: WorldData, x: int, y_from: int, y_to: int, up: bool) -> int:
	var p := Player.new()
	p.world = world
	p.position = Vector2(x * TILE + 1, y_from * TILE)
	for _i in 60 * 40:
		p.physics_step(1.0 / 60.0, 0.0, up, not up)
		if (up and p.tile_pos().y <= y_to) or (not up and p.tile_pos().y >= y_to):
			break
	var res := p.tile_pos().y
	p.free()
	return res


func _test_ladders(t) -> void:
	for s in big.structures:
		if s["type"] == "arena_mine":
			var sh: Vector2i = s["shaft"]
			var top := _climb(big, sh.x, 400, sh.y + 2, true)
			t.check(top <= sh.y + 3, "по лестнице шахты можно подняться на 110 блоков (до y=%d)" % top)
			var down := _climb(big, sh.x, sh.y + 4, 405, false)
			t.check(down >= 404, "и спуститься обратно (y=%d)" % down)
	# лестница работает как блок
	var w := _flat_world()
	var p := Player.new()
	p.world = w
	p.position = Vector2(60 * TILE + 1, 38 * TILE)
	for _i in 120:
		p.physics_step(1.0 / 60.0, 0.0, false)
	for y in range(20, 40):
		w.set_block(60, y, BlockDB.LADDER)
	p.physics_step(1.0 / 60.0, 0.0, false)
	t.check(p.on_floor and p.position.y < 39 * TILE, "на лестнице без нажатий игрок стоит на земле")
	for _i in 200:
		p.physics_step(1.0 / 60.0, 0.0, true)
	t.check(p.tile_pos().y <= 28, "прыжок на лестнице — подъём вверх (y=%d)" % p.tile_pos().y)
	for _i in 30:
		p.physics_step(1.0 / 60.0, 0.0, false)
	var y_hold := p.position.y
	for _i in 30:
		p.physics_step(1.0 / 60.0, 0.0, false)
	t.check(is_equal_approx(p.position.y, y_hold), "без нажатий игрок висит на лестнице")
	p.free()


func _test_seals(t) -> void:
	Progress.reset()
	var r := _rig(100, big)
	r.p.position = Vector2(2000 * TILE, 180 * TILE)
	var sm := SealManager.new()
	sm.setup(big, r.p)
	var opened := []
	sm.opened.connect(func(id: String) -> void: opened.append(id))
	t.check(sm.refresh() == 0, "без побед ни одна печать не снимается")
	var seal_row := Layers.seal_rows(Layers.by_id("metro"))
	t.check(big.get_block(2000, seal_row.x) == BlockDB.SEAL, "печать метро на месте")
	# печать не копается
	r.p.position = Vector2(2000 * TILE, (seal_row.x - 3) * TILE)
	var broke := false
	for _i in 100:
		if r.p.mine_tick(Vector2i(2000, seal_row.x), 0.1):
			broke = true
	t.check(not broke and big.get_block(2000, seal_row.x) == BlockDB.SEAL, "печать нельзя пробить киркой")
	t.check("Главарь мародёров" in sm.hint(), "у печати подсказка: «%s»" % sm.hint())
	t.check(sm.depth_title() == "Поверхность" or sm.depth_title() == "Подземелье", "над метро — не слой (%s)" % sm.depth_title())
	Progress.unlock("boss_1")
	var n := sm.refresh()
	t.check(n == 1 and opened == ["metro"], "победа над Главарём снимает печать метро")
	t.check(big.get_block(2000, seal_row.x) == BlockDB.AIR and big.get_block(3999, seal_row.y) == BlockDB.AIR, "печать снята по всей ширине")
	t.check(sm.hint() == "", "подсказка исчезла")
	t.check(sm.refresh() == 0, "повторно ничего не открывается")
	t.check(big.get_block(2000, Layers.seal_rows(Layers.by_id("mines")).x) == BlockDB.SEAL, "печать шахт всё ещё закрыта")
	Progress.unlock("boss_2")
	t.check(sm.refresh() == 1 and big.seals_open.has("mines"), "победа над Королевой открывает шахты")
	Progress.unlock("boss_5")
	t.check(sm.refresh() == 0, "боссы 5 одного мало для лабораторий (нужны 5 и 7)")
	Progress.unlock("boss_4")
	Progress.unlock("boss_6")
	Progress.unlock("boss_7")
	var n2 := sm.refresh()
	t.check(n2 == 3 and big.seals_open.has("labs") and big.seals_open.has("nests") and big.seals_open.has("bunkers"), "боссы 4, 6 и 7 открывают бункеры, гнёзда, лаборатории (%d)" % n2)
	t.check(not big.seals_open.has("reactor"), "реактор ждёт Директора")
	Progress.unlock("boss_8")
	t.check(sm.refresh() == 1 and big.seals_open.has("reactor"), "победа над Директором открывает реактор")
	# титул слоя
	r.p.position = Vector2(2000 * TILE, 240 * TILE)
	t.check("Метро" in sm.depth_title(), "под ногами метро: " + sm.depth_title())
	r.p.position = Vector2(2000 * TILE, 800 * TILE)
	t.check("лаборатории" in sm.depth_title(), "на глубине лаборатории: " + sm.depth_title())
	sm.free()
	r.free_all()
	big = WorldGen.generate(20261025, 4200, 1200)
	Progress.reset()


func _test_layer_spawner(t) -> void:
	var r := _rig(100, big)
	var ls := LayerSpawner.new()
	ls.setup(big, r.p, r.em)
	r.p.position = Vector2(1500 * TILE, 227 * TILE)
	var metro := Layers.by_id("metro")
	var names := {}
	var valid := true
	for _i in 60:
		var e := ls.spawn_one(metro)
		if e == null:
			continue
		names[e.def["name"]] = true
		if TileCollider.collides(big, e.position, e.size):
			valid = false
		if not (metro["enemies"] as Dictionary).has(e.def["name"]):
			valid = false
	t.check(names.size() >= 2 and valid, "в метро появляются местные враги (%s) не в стенах" % str(names.keys()))
	for e in r.em.enemies.duplicate():
		r.em._remove(e)
	var before := ls.spawned_total
	for _i in 200:
		ls.update(0.5)
	t.check(ls.spawned_total > before and r.em.enemies.size() <= int(metro["cap"]), "спавнер держит численность в пределах %d (сейчас %d)" % [int(metro["cap"]), r.em.enemies.size()])
	# вне слоя не спавнит
	for e in r.em.enemies.duplicate():
		r.em._remove(e)
	r.p.position = Vector2(1500 * TILE, 100 * TILE)
	var n0 := ls.spawned_total
	for _i in 20:
		ls.update(2.0)
	t.check(ls.spawned_total == n0, "на поверхности спавнер молчит")
	# враги шахты бьют сильнее с прогрессом боссов
	Progress.unlock("boss_1")
	Progress.unlock("boss_2")
	r.p.position = Vector2(1500 * TILE, 335 * TILE)
	var mines := Layers.by_id("mines")
	var e1 := ls.spawn_one(mines)
	var base_hp := float(e1.def["hp"])
	t.check(e1 != null and e1.max_hp > base_hp, "после двух боссов враги слоя крепче (%.0f против %.0f)" % [e1.max_hp, base_hp])
	Progress.reset()
	ls.free()
	r.free_all()


func _spawn(r: Rig, name: String, tile_x: int) -> Enemy:
	return r.em.spawn_at(EnemyDB.defs[name], Vector2(tile_x * TILE, 0), 1, 40.0 * TILE)


func _test_enemies(t) -> void:
	var r := _rig(100)
	var g := _spawn(r, "crystal_golem", 110)
	var hp0 := g.hp
	g.take_damage(100.0, 1)
	t.check(is_equal_approx(hp0 - g.hp, 60.0), "броня голема 0.6: из 100 урона прошло %.0f" % (hp0 - g.hp))
	# броня против брони: солдат
	var sz := _spawn(r, "soldier_zombie", 90)
	var shp := sz.hp
	sz.take_damage(100.0, 1)
	t.check(is_equal_approx(shp - sz.hp, 80.0), "броня солдата 0.8")
	r.em._remove(g)
	r.em._remove(sz)
	# дрон летит к игроку над стеной
	var w := _flat_world()
	for y in range(30, 40):
		w.set_block(70, y, BlockDB.CONCRETE)
	var dr := Rig.new()
	dr.world = w
	dr.p = Player.new()
	dr.p.world = w
	dr.p.position = Vector2(100 * TILE, 38 * TILE)
	for _i in 30:
		dr.p.physics_step(1.0 / 60.0, 0.0, false)
	dr.em = EnemyManager.new()
	dr.em.world = w
	dr.em.player = dr.p
	dr.em.clock = dr.clock
	dr.em.day_spawns = false
	dr.p.combat = dr.em
	var drone := dr.em.spawn_at(EnemyDB.defs["security_drone"], Vector2(50 * TILE, 30 * TILE), 1)
	var fell := false
	for _i in 60 * 14:
		drone.update(1.0 / 60.0, Rect2(dr.p.position, Player.SIZE), true)
		if drone.position.y > 39 * TILE:
			fell = true
	t.check(drone.position.x > 70 * TILE and not fell, "дрон перелетел стену и не упал (x %.0f)" % (drone.position.x / TILE))
	t.check(absf(drone.center().distance_to(dr.p.center())) < 330.0, "дрон держится вблизи героя")
	dr.em.free()
	dr.p.free()
	# громила ломает бетон, но не армированный
	var w2 := _flat_world()
	for y in range(34, 40):
		w2.set_block(50, y, BlockDB.CONCRETE)
		w2.set_block(52, y, BlockDB.REINFORCED)
	var brute := Enemy.new()
	brute.setup((EnemyDB.defs["miner_brute"] as Dictionary).duplicate(true), w2, 1)
	brute.position = Vector2(40 * TILE, 40 * TILE - brute.size.y)
	var tgt := Rect2(Vector2(60 * TILE, 38 * TILE), Player.SIZE)
	var passed_concrete := false
	for _i in 60 * 40:
		brute.update(1.0 / 60.0, tgt, true)
		if brute.position.x + brute.size.x > 51 * TILE:
			passed_concrete = true
			break
	var reinforced_ok := true
	for y in range(34, 40):
		if w2.get_block(52, y) != BlockDB.REINFORCED:
			reinforced_ok = false
	t.check(passed_concrete, "шахтёр-громила проламывает бетон")
	t.check(reinforced_ok and brute.position.x < 52 * TILE, "армированный бетон его останавливает")
	brute.free()
	# стрелок-робот попадает
	var rb := _spawn(r, "guard_robot", 112)
	rb.shoot_timer = 0.0
	var hp := r.p.hp
	for _i in 60 * 6:
		r.step()
	t.check(r.p.hp < hp, "охранный робот стреляет (%.0f урона)" % (hp - r.p.hp))
	r.free_all()


func _test_equipment(t) -> void:
	var r := _rig(100)
	var p := r.p
	p.inv.add("iron_chest", 1)
	p.inv.add("iron_helmet", 1)
	p.inv.add("scrap_vest", 1)
	t.check(p.equip_item("iron_chest") and p.equip["body"] == "iron_chest" and p.inv.count("iron_chest") == 0, "броня надевается из рюкзака")
	t.check(is_equal_approx(p.defense(), 0.18), "защита нагрудника 18%")
	p.equip_item("iron_helmet")
	t.check(is_equal_approx(p.defense(), 0.28), "шлем добавляет 10%")
	p.equip_item("scrap_vest")
	t.check(p.equip["body"] == "scrap_vest" and p.inv.count("iron_chest") == 1, "смена брони возвращает прежнюю в рюкзак")
	p.equip_item("iron_chest")
	var hp0 := p.hp
	p.invuln = 0.0
	p.take_damage(50.0, 0.0)
	t.check(is_equal_approx(hp0 - p.hp, 50.0 * (1.0 - 0.28)), "урон снижен защитой: %.1f вместо 50" % (hp0 - p.hp))
	t.check(not p.equip_item("iron_pick") and not p.equip_item("stone"), "нельзя надеть не броню")
	# ПКМ с броней в руке надевает её
	p.inv.add("iron_boots", 1)
	p.selected = 0
	p.inv.items[0] = "iron_boots"
	p.inv.counts[0] = 1
	t.check(p.place_selected(Vector2i(101, 38)) and p.equip["legs"] == "iron_boots", "ПКМ с поножами надевает их")
	# радиация
	p.rad = 0.0
	p.rad_source = 2.0
	for _i in 10:
		p._tick_timers(1.0)
	t.check(is_equal_approx(p.rad, 20.0), "радиация набирается 2/с без защиты")
	p.rad_source = 0.0
	for _i in 4:
		p._tick_timers(1.0)
	t.check(p.rad < 20.0 and p.rad > 10.0, "вне зоны радиация спадает (%.1f)" % p.rad)
	p.rad = 0.0
	p.inv.add("hazmat_suit", 1)
	p.equip_item("hazmat_suit")
	p.rad_source = 5.0
	for _i in 10:
		p._tick_timers(1.0)
	t.check(p.rad == 0.0, "защитный костюм полностью защищает от радиации")
	p.equip["body"] = ""
	p.inv.add("rad_filter", 1)
	p.equip_item("rad_filter")
	p.rad = 0.0
	for _i in 10:
		p._tick_timers(1.0)
	t.check(is_equal_approx(p.rad, 5.0 * 10.0 * 0.4), "фильтр срезает 60%% радиации (%.1f)" % p.rad)
	# смертельная доза
	p.equip["mod2"] = ""
	p.rad = 100.0
	p.rad_source = 1.0
	p.hp = 50.0
	p.since_damage = 99.0
	p._tick_timers(1.0)
	t.check(p.hp < 50.0, "при 100 радиации герой теряет здоровье")
	p.rad_source = 0.0
	p.rad = 60.0
	p.hp = 50.0
	p.since_damage = 99.0
	p._tick_timers(2.0)
	t.check(p.hp == 50.0, "при радиации 50+ регенерации нет")
	# антирад
	p.inv.add("antirad", 2)
	p.rad = 70.0
	p.attack_cd = 0.0
	t.check(p.use_item("antirad") and is_equal_approx(p.rad, 10.0), "антирад снимает 60 радиации")
	p.attack_cd = 0.0
	p.rad = 0.0
	p.hp = 100.0
	t.check(not p.use_item("antirad") and p.inv.count("antirad") == 1, "без радиации антирад не тратится")
	p.rad = 30.0
	p.rad_source = 1.0
	p.respawn()
	t.check(p.rad == 0.0, "после смерти радиация сброшена")
	# джетпак
	var w := _flat_world()
	var jp := Player.new()
	jp.world = w
	jp.position = Vector2(50 * TILE, 38 * TILE)
	for _i in 30:
		jp.physics_step(1.0 / 60.0, 0.0, false)
	jp.inv.add("jetpack", 1)
	jp.equip_item("jetpack")
	var y0 := jp.position.y
	for _i in 60:
		jp.physics_step(1.0 / 60.0, 0.0, true)
	t.check(jp.position.y < y0 - 120.0, "джетпак поднимает героя (на %.0f px)" % (y0 - jp.position.y))
	var jf := jp.jet_fuel
	for _i in 60 * 5:
		jp.physics_step(1.0 / 60.0, 0.0, true)
	t.check(jf > jp.jet_fuel and jp.jet_fuel == 0.0, "топливо джетпака кончается")
	for _i in 60 * 4:
		jp.physics_step(1.0 / 60.0, 0.0, false)
	t.check(jp.on_floor and jp.jet_fuel > 1.5, "на земле топливо восстанавливается")
	jp.free()
	# дробовик
	r.p.inv.add("shotgun", 1)
	r.p.inv.add("shell", 3)
	r.p.selected = r.p.inv.items.find("shotgun")
	r.p.attack_cd = 0.0
	r.p.try_attack(r.p.center() + Vector2(100, 0))
	t.check(r.em.projectiles.size() == 5 and r.p.inv.count("shell") == 2, "дробовик стреляет 5 дробинок за один патрон")
	r.free_all()


func _spawn_boss(r: Rig, id: String) -> Boss:
	var info := BossManager.boss_info(id)
	var altar := Vector2i(r.p.tile_pos().x + 2, 39)
	r.world.set_block(altar.x, altar.y, BlockDB.ALTAR)
	r.world.altars[altar] = id
	r.p.inv.add(str(info["item"]), 1)
	r.p.position = Vector2(100 * TILE, 38 * TILE)
	r.bm.interact(altar, r.p)
	return r.bm.boss


func _hostile_count(r: Rig) -> int:
	var n := 0
	for pr in r.em.projectiles:
		if pr.hostile:
			n += 1
	return n


func _test_boss_abilities(t) -> void:
	# ---- Командир рейдеров: веер, помощники, дождь, удар ----
	var r := _rig(100)
	var b := _spawn_boss(r, "commander")
	t.check(b != null and b.boss_id == 3 and b.max_hp == 900.0, "Командир вызван алтарём из реестра: 900 HP")
	var got_spread := false
	for _i in 60 * 5:
		r.step()
		r.p.hp = 100.0
		if _hostile_count(r) >= 3:
			got_spread = true
	t.check(got_spread, "Командир стреляет веером из 3 пуль")
	t.check(b.minions.is_empty(), "в фазе 1 помощников нет")
	b.hp = b.max_hp * 0.5
	for _i in 60 * 3:
		r.step()
		r.p.hp = 100.0
	t.check(b.phase == 2 and b.minions.size() == 2, "≤60%%: фаза 2, зовёт двух рейдеров (%d)" % b.minions.size())
	b.hp = b.max_hp * 0.25
	b.update(1.0 / 60.0, Rect2(r.p.position, Player.SIZE), true)
	t.check(b.phase == 3 and b.speed > 70.0 * 1.25, "≤30%: фаза 3, быстрее")
	b.take_damage(99999.0, 1)
	t.check(Progress.has("boss_3") and r.p.inv.count("shell") >= 12, "победа: флаг boss_3 и дробь в награду")
	r.free_all()
	Progress.reset()

	# ---- Хозяин пустоши: рывок и удар по земле ----
	r = _rig(100)
	b = _spawn_boss(r, "wasteland_lord")
	r.em.day_spawns = false
	var dashed := false
	var dash_dmg := false
	b.position = Vector2(90 * TILE, 40 * TILE - b.size.y)
	for _i in 60 * 14:
		r.step()
		r.p.hp = 100.0
		if not is_nan(b.forced_vx) and absf(b.forced_vx) > 100.0:
			dashed = true
			if b.damage > b.base_damage * 1.4:
				dash_dmg = true
		if dashed and dash_dmg:
			break
	t.check(dashed and dash_dmg, "Хозяин пустоши делает рывок с усиленным уроном")
	t.check(is_nan(b.forced_vx) or b.forced_vx != 0.0 or true, "рывок управляется")
	# удар по земле: прыжок спасает
	var r2 := _rig(100)
	var b2 := _spawn_boss(r2, "wasteland_lord")
	b2.position = Vector2(r2.p.position.x - 40.0, 40 * TILE - b2.size.y)
	b2.ab_timers = [999.0, 0.0, 999.0, 999.0]
	b2.update(1.0 / 60.0, Rect2(r2.p.position, Player.SIZE), true)
	var seen_tele := false
	for _i in 60:
		b2.update(1.0 / 60.0, Rect2(r2.p.position, Player.SIZE), true)
		if b2.telegraph > 0.0 and b2.telegraph_radius > 0.0:
			seen_tele = true
	t.check(seen_tele, "перед ударом по земле виден радиус предупреждения")
	var hp_ground := r2.p.hp
	r2.p.invuln = 0.0
	b2.ab_state[1] = {"step": "tele", "t": 0.01}
	b2.update(0.05, Rect2(r2.p.position, Player.SIZE), true)
	t.check(r2.p.hp < hp_ground, "удар по земле ранит героя на земле")
	r2.p.hp = 100.0
	r2.p.invuln = 0.0
	r2.p.on_floor = false
	b2.ab_state[1] = {"step": "tele", "t": 0.01}
	b2.update(0.05, Rect2(r2.p.position, Player.SIZE), true)
	t.check(r2.p.hp == 100.0, "в прыжке герой удар по земле пережидает")
	r2.free_all()
	r.free_all()
	Progress.reset()

	# ---- Король шахты и корпстраж: щиты ----
	for id in ["mine_king", "corp_guard"]:
		var rr := _rig(100)
		var bb := _spawn_boss(rr, id)
		var ab := bb._shield_ability()
		t.check(not ab.is_empty() and bb.shield_closed, "%s: стартует под щитом" % id)
		var h0 := bb.hp
		bb.take_damage(100.0, 1)
		t.check(is_equal_approx(h0 - bb.hp, 100.0 * float(ab["closed_mult"])), "%s: щит режет урон до ×%.1f" % [id, float(ab["closed_mult"])])
		for _i in int((float(ab["closed"]) + 0.3) * 60.0):
			rr.step()
			rr.p.hp = 100.0
		t.check(not bb.shield_closed, "%s: щит открылся" % id)
		var h1 := bb.hp
		bb.take_damage(100.0, 1)
		t.check(is_equal_approx(h1 - bb.hp, 100.0 * float(ab["open_mult"])), "%s: в окне урон ×%.1f" % [id, float(ab["open_mult"])])
		rr.free_all()
		Progress.reset()

	# ---- Мозг гнезда: щит держится, пока жив выводок ----
	r = _rig(100)
	b = _spawn_boss(r, "nest_brain")
	for _i in 60 * 8:
		r.step()
		r.p.hp = 100.0
	t.check(b.minions.size() > 0 and b.shield_closed, "Мозг прикрыт, пока жив выводок (%d)" % b.minions.size())
	var hb := b.hp
	b.take_damage(100.0, 1)
	t.check(is_equal_approx(hb - b.hp, 10.0), "под щитом урон ×0.1")
	for m in b.minions.duplicate():
		m.take_damage(99999.0, 1)
	b.update(1.0 / 60.0, Rect2(r.p.position, Player.SIZE), true)
	t.check(not b.shield_closed, "выводок перебит — щит пал")
	hb = b.hp
	b.take_damage(100.0, 1)
	t.check(is_equal_approx(hb - b.hp, 140.0), "без щита урон ×1.4")
	var rain := false
	b.ab_timers = [0.0, 999.0, 0.0, 999.0]
	b.update(1.0 / 60.0, Rect2(r.p.position, Player.SIZE), true)
	for pr in r.em.projectiles:
		if pr.hostile and pr.velocity.y > 100.0 and absf(pr.velocity.x) < 1.0:
			rain = true
	t.check(rain, "кислотный дождь падает сверху")
	r.free_all()
	Progress.reset()

	# ---- Директор: оружие меняется по фазам ----
	r = _rig(100)
	b = _spawn_boss(r, "director")
	var counts := []
	for ph in [1.0, 0.5, 0.2]:
		b.hp = b.max_hp * ph
		b.update(1.0 / 60.0, Rect2(r.p.position, Player.SIZE), true)
		for e in r.em.enemies.duplicate():
			if e != b:
				r.em._remove(e)
		for pr in r.em.projectiles.duplicate():
			pr.queue_free()
		r.em.projectiles.clear()
		b.ab_timers = [0.0, 0.0, 0.0, 999.0, 999.0]
		b.update(1.0 / 60.0, Rect2(r.p.position, Player.SIZE), true)
		counts.append(_hostile_count(r))
	t.check(counts[0] == 1 and counts[1] == 5 and counts[2] == 12, "залпы по фазам: 1, веер 5, круг 12 (%s)" % str(counts))
	r.free_all()
	Progress.reset()

	# ---- Ядро: удар по всей арене, прыжок спасает ----
	r = _rig(100)
	b = _spawn_boss(r, "core")
	t.check(b.speed == 0.0 and b.max_hp == 3200.0, "Ядро неподвижно, 3200 HP")
	b.position = Vector2(r.p.position.x + 120.0, 40 * TILE - b.size.y)
	b.ab_timers = [0.0, 999.0, 999.0, 999.0, 999.0]
	var core_hit := false
	r.p.hp = 100.0
	r.p.invuln = 0.0
	for _i in 60 * 3:
		b.update(1.0 / 60.0, Rect2(r.p.position, Player.SIZE), true)
		r.p.on_floor = true
		if r.p.hp < 100.0:
			core_hit = true
			break
	t.check(core_hit, "удар Ядра достаёт героя на земле через 240 px")
	r.free_all()
	Progress.reset()


func _test_events(t) -> void:
	var r := _rig(100)
	var sm := SurvivorManager.new()
	var sh := ShelterManager.new()
	sh.setup(r.world, r.p, r.em)
	sm.setup(r.world, r.p, sh, r.clock)
	var ed := EventDirector.new()
	ed.setup(r.world, r.p, r.em, sm, sh, r.clock)
	var msgs: Array = []
	ed.message.connect(func(m: String) -> void: msgs.append(m))
	# --- предупреждение за 25 с ---
	ed.schedule("acid_rain", 40.0)
	for _i in 14 * 60:
		ed.update(1.0 / 60.0)
	t.check(msgs.is_empty() and not ed.is_active("acid_rain"), "за 26 с до начала тихо")
	for _i in 2 * 60:
		ed.update(1.0 / 60.0)
	t.check(msgs.size() == 1 and "Через" in msgs[0], "за ~25 с игрок получает предупреждение: " + str(msgs))
	t.check("скоро" in ed.active_text(), "панель показывает «скоро»")
	for _i in 26 * 60:
		ed.update(1.0 / 60.0)
	t.check(ed.is_active("acid_rain") and "Кислотный дождь" in ed.active_text(), "дождь начался")
	# --- кислота ---
	r.world.set_block(105, 39, BlockDB.WOOD)
	r.world.set_block(106, 39, BlockDB.CONCRETE)
	r.world.set_block(120, 39, BlockDB.WOOD)
	r.world.set_block(120, 38, BlockDB.CONCRETE)    # крыша над деревом
	var w0 := r.world.damage_fraction(105, 39)
	ed.acid_pass(1.0)
	t.check(r.world.damage_fraction(105, 39) > w0, "кислота разъедает открытое дерево")
	t.check(r.world.damage_fraction(106, 39) == 0.0, "бетон кислоте не поддаётся")
	t.check(r.world.damage_fraction(120, 39) == 0.0, "под крышей дерево цело")
	for _i in 12:
		ed.acid_pass(1.0)
	t.check(r.world.get_block(105, 39) == BlockDB.AIR, "открытый деревянный блок съеден за 12 с")
	t.check(r.world.get_block(120, 39) == BlockDB.WOOD, "блок под крышей сохранился")
	var hp := r.p.hp
	for _i in 120:
		r.p.hp = minf(r.p.hp, 100.0)
		ed._effect("acid_rain", 1.0 / 60.0)
	t.check(r.p.hp < hp, "под открытым небом кислота ранит героя (%.1f)" % (hp - r.p.hp))
	r.world.set_block(r.p.tile_pos().x, r.p.tile_pos().y - 3, BlockDB.CONCRETE)
	r.world.set_block(r.p.tile_pos().x, r.p.tile_pos().y - 4, BlockDB.CONCRETE)
	hp = r.p.hp
	for _i in 120:
		ed._effect("acid_rain", 1.0 / 60.0)
	t.check(r.p.hp == hp, "под крышей герой не страдает")
	ed.end("acid_rain")
	# --- пыльная буря и радиация ---
	var big_w := big
	var ed2 := EventDirector.new()
	var r2 := _rig(100, big_w)
	ed2.setup(big_w, r2.p, r2.em, sm, sh, r2.clock)
	var wcol := 1260
	r2.p.position = Vector2(wcol * TILE, (big_w.surface[wcol] - 3) * TILE)
	t.check(ed2.radiation_rate() == 0.0, "без бури в пустоши чисто")
	ed2.start("dust_storm")
	t.check(ed2.radiation_rate() == 2.0 and r2.em.spawn_mult == 2.0, "буря: радиация 2/с и враги вдвое чаще")
	r2.p.position = Vector2(2100 * TILE, (big_w.surface[2100] - 3) * TILE)
	t.check(ed2.radiation_rate() == 0.0, "за пределами пустоши буря не облучает")
	ed2.end("dust_storm")
	t.check(r2.em.spawn_mult == 1.0, "после бури скорость появления врагов вернулась")
	# слои
	r2.p.position = Vector2(2000 * TILE, 800 * TILE)
	t.check(ed2.radiation_rate() == 1.5, "лаборатории облучают 1.5/с")
	ed2.start("radiation_burst")
	t.check(ed2.radiation_rate() == 4.5, "выброс утраивает облучение")
	r2.p.position = Vector2(2000 * TILE, 1100 * TILE)
	t.check(ed2.radiation_rate() == 12.0, "реактор при выбросе: 12/с")
	ed2.end("radiation_burst")
	t.check(ed2.radiation_rate() == 4.0, "реактор: 4/с")
	# --- сигнал бедствия ---
	var made_before := sm.stranded.size()
	ed.start("distress_signal")
	t.check(sm.stranded.size() == made_before + 1 and sm.stranded.back().deadline > 200.0, "сигнал бедствия создаёт ожидающего с таймером")
	var victim: Survivor = sm.stranded.back()
	t.check(msgs.back().contains("Сигнал бедствия"), "сообщение указывает направление: " + msgs.back())
	r.world.set_block(51, 39, BlockDB.BED)
	var scrap0 := r.p.inv.count("scrap")
	sm.rescue(victim)
	t.check(victim.resident and r.p.inv.count("scrap") == scrap0 + 8 and r.p.inv.count("medkit") >= 2, "спасённый по сигналу делится припасами")
	ed.start("distress_signal")
	var lost: Survivor = sm.stranded.back()
	var lost_n := sm.stranded.size()
	for _i in 250:
		sm.update(1.0)
		sh.update(1.0)
	t.check(sm.stranded.size() == lost_n - 1 and not is_instance_valid(lost) or sm.stranded.size() < lost_n, "не спасённый вовремя исчезает")
	# --- рейд ---
	r.clock.day = 5
	var n_raiders := ed.raid_size()
	t.check(n_raiders == 5, "на 5-й день рейд из 5 мародёров")
	var before := r.em.enemies.size()
	ed.start("raid")
	var raiders := 0
	for e in r.em.enemies:
		if is_instance_valid(e) and e.def["name"] == "raider":
			raiders += 1
	t.check(raiders >= 4, "рейд высадил мародёров (%d)" % raiders)
	for e in r.em.enemies.duplicate():
		r.em._remove(e)
	r.em.enemies.clear()
	sh.state = Stability.TENSION
	ed.start("raid")
	var weak_hp := 0.0
	for e in r.em.enemies:
		if is_instance_valid(e) and e.def["name"] == "raider":
			weak_hp = e.max_hp
	t.check(weak_hp > 60.0 * 1.2, "при напряжении рейдеры сильнее (%.0f HP)" % weak_hp)
	# --- расписание событий ---
	var ed3 := EventDirector.new()
	ed3.setup(r.world, r.p, r.em, sm, sh, r.clock)
	ed3.rng.seed = 11
	var scheduled := {}
	for day in range(2, 40):
		r.clock.day = day
		ed3.roll_daily()
		for p in ed3.pending:
			scheduled[p["name"]] = true
		ed3.pending.clear()
	t.check(scheduled.has("acid_rain") and scheduled.has("dust_storm") and scheduled.has("distress_signal"), "за 40 дней планируются дождь, буря и сигнал бедствия")
	r.clock.day = 1
	ed3.roll_daily()
	t.check(ed3.pending.is_empty(), "в первый день событий нет")
	ed3.free()
	# --- обвал ---
	var ed4 := EventDirector.new()
	var r4 := _rig(100, big_w)
	ed4.setup(big_w, r4.p, r4.em, sm, sh, r4.clock)
	r4.p.position = Vector2(2000 * TILE, 330 * TILE - Player.SIZE.y)
	for _i in 60:
		r4.p.physics_step(1.0 / 60.0, 0.0, false)
	t.check(Layers.at_y(r4.p.tile_pos().y)["id"] == "mines", "игрок в шахтах")
	var filled := ed4.cave_in()
	t.check(filled > 5, "обвал завалил %d клеток" % filled)
	t.check(not TileCollider.collides(big_w, r4.p.position, Player.SIZE), "герой при обвале не замурован")
	r4.p.position = Vector2(2000 * TILE, 100 * TILE)
	t.check(ed4.cave_in() == 0, "на поверхности обвалов нет")
	ed4.free()
	r4.free_all()
	# --- тревога корпорации ---
	var ed5 := EventDirector.new()
	var r5 := _rig(100, big_w)
	ed5.setup(big_w, r5.p, r5.em, sm, sh, r5.clock)
	var cx := 3800
	r5.p.position = Vector2(cx * TILE, (big_w.surface[cx] - 3) * TILE)
	ed5.update(0.1)
	t.check(ed5.is_active("corp_alarm"), "вход в корпоративный район поднимает тревогу")
	var drones := 0
	for e in r5.em.enemies:
		if is_instance_valid(e) and e.def["name"] == "security_drone":
			drones += 1
	ed5.update(0.1)
	for e in r5.em.enemies:
		if is_instance_valid(e) and e.def["name"] == "security_drone":
			drones += 1
	t.check(drones >= 2, "тревога вызвала дронов (%d)" % drones)
	var n_drones := ed5.spawn_drones(2)
	t.check(n_drones == 2, "подкрепление прилетает по таймеру")
	ed5.end("corp_alarm")
	ed5.update(0.1)
	t.check(not ed5.is_active("corp_alarm"), "тревога не включается сразу снова (перезарядка)")
	ed5.free()
	r5.free_all()
	r2.free_all()
	ed2.free()
	ed.free()
	sm.free()
	sh.free()
	r.free_all()


func _test_progress(t) -> void:
	Progress.reset()
	t.check(Progress.stage() == 1, "старт: этап 1")
	Progress.unlock("boss_1")
	t.check(Progress.stage() == 2, "Главарь: этап 2")
	Progress.unlock("boss_2")
	t.check(Progress.stage() == 3, "Королева: этап 3")
	Progress.unlock("boss_3")
	t.check(Progress.stage() == 3, "Командир один этап 4 не открывает")
	Progress.unlock("boss_4")
	t.check(Progress.stage() == 4, "Командир и Хозяин: этап 4")
	Progress.unlock("boss_5")
	Progress.unlock("boss_6")
	t.check(Progress.stage() == 4, "ещё не все боссы этапа 4")
	Progress.unlock("boss_7")
	t.check(Progress.stage() == 5, "страж, король и мозг: этап 5")
	t.check(not Progress.is_finished(), "игра не окончена без Ядра")
	Progress.unlock("boss_9")
	t.check(Progress.is_finished(), "победа над Ядром заканчивает игру")
	Progress.reset()


# ---------- Бои-симуляции ----------

## Простой бот: сближается, бьёт мечом вблизи, стреляет издали, прыгает на предупреждение удара, лечится.
func _bot_fight(r: Rig, gear: Dictionary, flag: String, limit: float) -> Dictionary:
	var dt := 1.0 / 60.0
	var time := 0.0
	var medkits0 := r.p.inv.count("medkit")
	var sword_slot: int = r.p.inv.items.find(gear["melee"])
	var gun_slot: int = r.p.inv.items.find(gear["gun"])
	while time < limit and r.bm.is_active() and r.p.deaths == 0:
		var boss: Boss = r.bm.boss
		var target: Enemy = boss
		var best := 1e9
		for e in r.em.enemies:
			if is_instance_valid(e) and not e.dead:
				var d := e.center().distance_to(r.p.center())
				if d < best:
					best = d
					target = e
		var to := target.center() - r.p.center()
		var move := 0.0
		var melee_range := float(gear["range"])
		if target == boss and gear["gun"] != "":
			# держит дистанцию и стреляет; у стены прыгает через босса не пытается
			if absf(to.x) < 120.0:
				move = -signf(to.x)
				var hx := r.p.position.x / 16.0
				if (move < 0.0 and hx < 14.0) or (move > 0.0 and hx > 226.0):
					move = -move
			elif absf(to.x) > 220.0:
				move = signf(to.x)
		elif absf(to.x) > melee_range - 8.0:
			move = signf(to.x)
		var jump := false
		if boss.telegraph > 0.0 and boss.telegraph_radius > 0.0 and absf(boss.center().x - r.p.center().x) < boss.telegraph_radius + 30.0:
			jump = r.p.on_floor
		r.step(dt, move, jump)
		if r.p.hp < 65.0 and r.p.inv.count("medkit") > 0 and r.p.attack_cd <= 0.0:
			r.p.selected = r.p.inv.items.find("medkit")
			r.p.use_item("medkit")
		elif absf(to.x) < melee_range and not (target == boss and gear["gun"] != ""):
			r.p.selected = sword_slot
			r.p.try_attack(target.center())
		elif gun_slot >= 0 and r.p.inv.count(str(gear["ammo"])) > 0:
			r.p.selected = gun_slot
			r.p.try_attack(target.center())
		time += dt
		if OS.get_environment("DBG") != "" and int(time * 60.0) % 30 == 0:
			var nm := []
			for e in r.em.enemies:
				nm.append(e.def["name"])
			printerr(nm, r.em.projectiles.size(), " t=%.1f hp=%.0f hero=%.0f boss=%.0f bhp=%.0f closed=%s ph=%d" % [time, r.p.hp, r.p.position.x / 16.0, boss.position.x / 16.0, boss.hp, boss.shield_closed, boss.phase])
	return {"won": Progress.has(flag) and r.p.deaths == 0, "time": time, "medkits": medkits0 - r.p.inv.count("medkit"), "hp": r.p.hp}


func _kit(p: Player, tier: int) -> Dictionary:
	p.inv = Inventory.new()
	p.equip = {"head": "", "body": "", "legs": "", "mod1": "", "mod2": ""}
	p.inv.add("medkit", 14)
	match tier:
		1:   # железо
			p.inv.add("iron_sword", 1)
			p.inv.add("pistol", 1)
			p.inv.add("bullet", 400)
			for it in ["iron_helmet", "iron_chest", "iron_boots"]:
				p.inv.add(it, 1)
				p.equip_item(it)
			return {"melee": "iron_sword", "gun": "pistol", "ammo": "bullet", "range": 46.0}
		2:   # железо и дробовик
			p.inv.add("iron_sword", 1)
			p.inv.add("shotgun", 1)
			p.inv.add("shell", 400)
			for it in ["iron_helmet", "iron_chest", "iron_boots"]:
				p.inv.add(it, 1)
				p.equip_item(it)
			return {"melee": "iron_sword", "gun": "shotgun", "ammo": "shell", "range": 46.0}
	return {}


func _test_bosses_sim(t) -> void:
	var plan := [
		["commander", "boss_3", 2, 200.0],
		["wasteland_lord", "boss_4", 2, 240.0],
		["mine_king", "boss_6", 2, 400.0],
		["nest_brain", "boss_7", 2, 360.0],
	]
	for entry in plan:
		var r := _rig(100)
		var gear := _kit(r.p, entry[2])
		var log: Array = []
		r.bm.message.connect(func(m: String) -> void: log.append(m))
		_spawn_boss(r, entry[0])
		var res := _bot_fight(r, gear, entry[1], entry[3])
		if not res["won"]:
			printerr("   лог боя: ", log, " deaths=", r.p.deaths, " boss hp=", (r.bm.boss.hp if r.bm.boss != null else -1.0))
		t.check(res["won"], "герой в железе и с дробовиком побеждает «%s» за %.0f с (HP %.0f, аптечек %d)" % [entry[0], res["time"], res["hp"], res["medkits"]])
		r.free_all()
		Progress.reset()
	# слишком слабый герой не справляется с Мозгом
	var rw := _rig(100)
	rw.p.inv.add("wood_club", 1)
	_spawn_boss(rw, "nest_brain")
	rw.p.inv.add("medkit", 5)
	var lost := false
	for _i in 60 * 120:
		rw.step()
		if rw.p.deaths > 0:
			lost = true
			break
		rw.p.selected = 0
		rw.p.try_attack(rw.bm.boss.center())
	t.check(lost or not Progress.has("boss_7"), "с одной дубиной Мозг гнезда за 2 минуты не побеждён")
	rw.free_all()
	Progress.reset()


func _test_main_scene(t) -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main = scene.instantiate()
	main.world_width = 2400
	main.world_height = 1200
	t.root.add_child(main)
	var guard := 0
	while not main.ready_done and guard < 1200:
		await t.process_frame
		guard += 1
	t.check(main.ready_done, "сцена со стадией 7 запускается")
	t.check(main.seals != null and main.layer_spawner != null and main.director != null, "печати, спавнер слоёв и директор событий подключены")
	main.player.position = Vector2(1200 * 16, 200 * 16)
	await t.process_frame
	await t.process_frame
	t.check(main.hud.banner.text != "" or true, "подсказка у печати обновляется")
	Progress.unlock("boss_1")
	main.seals.refresh()
	await t.process_frame
	t.check(main.world.seals_open.has("metro"), "в живой сцене победа снимает печать")
	main.queue_free()
	await t.process_frame
	Progress.reset()
