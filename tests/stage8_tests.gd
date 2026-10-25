extends RefCounted
## Этап 8: корпоративный район, лаборатории, реактор, финал. Критерий ТЗ: игру можно пройти.

const TILE := 16
var big: WorldData


func run(t) -> void:
	Progress.reset()
	ItemDB.ensure_loaded()
	big = WorldGen.generate(20261025, 4200, 1200)
	_test_structures(t)
	_test_reachability(t)
	_test_loot(t)
	_test_progression(t)
	_test_fights(t)
	_test_ending_logic(t)
	await _test_main_ending(t)
	Progress.reset()


func _structs(type: String) -> Array:
	var res := []
	for s in big.structures:
		if s["type"] == type:
			res.append(s)
	return res


func _test_structures(t) -> void:
	for pair in [["corp_guard", "arena_corp"], ["director", "arena_lab"], ["core", "arena_core"]]:
		var n := 0
		for pos in big.altars:
			if big.altars[pos] == pair[0]:
				n += 1
		t.check(n == 1, "один алтарь «%s»" % pair[0])
		var ss := _structs(pair[1])
		t.check(ss.size() == 1, "структура %s зарегистрирована" % pair[1])
		if ss.size() == 1:
			var a: Vector2i = ss[0]["altar"]
			t.check(big.get_block(a.x, a.y) == BlockDB.ALTAR and big.is_solid(a.x, a.y + 1), "%s: алтарь на твёрдом полу" % pair[1])
			var r: Rect2i = ss[0]["rect"]
			t.check(r.has_point(a), "%s: алтарь внутри своего прямоугольника" % pair[1])
	var all_ids := {}
	for pos in big.altars:
		all_ids[big.altars[pos]] = true
	t.check(all_ids.size() == 9, "в мире алтари всех 9 боссов")
	# слои по содержимому
	var lab_blocks := 0
	var reactor_blocks := 0
	var corp := 0
	for y in range(730, 990, 3):
		for x in range(0, big.width, 11):
			if big.get_block(x, y) == BlockDB.LAB_WALL:
				lab_blocks += 1
	for y in range(995, 1196, 3):
		for x in range(0, big.width, 11):
			if big.get_block(x, y) == BlockDB.REACTOR_WALL:
				reactor_blocks += 1
	var c: Vector2i = _structs("arena_corp")[0]["altar"]
	for y in range(c.y - 25, c.y + 2):
		for x in range(c.x - 80, c.x + 80):
			if big.get_block(x, y) == BlockDB.CORP_WALL:
				corp += 1
	t.check(lab_blocks > 800, "лаборатории обшиты лабораторными стенами (%d)" % lab_blocks)
	t.check(reactor_blocks > 800, "реактор из реакторных стен (%d)" % reactor_blocks)
	t.check(corp > 120, "корпоративный район из белых стен (%d)" % corp)
	t.check(big.biome[c.x] == WorldGen.BIOME_CORPORATE, "район стоит в корпоративном биоме")
	# печати остаются сплошными
	var seals_ok := true
	for l in Layers.list:
		var rr := Layers.seal_rows(l)
		for x in range(0, big.width, 37):
			if big.get_block(x, rr.x) != BlockDB.SEAL or big.get_block(x, rr.y) != BlockDB.SEAL:
				seals_ok = false
	t.check(seals_ok, "лестницы и залы не пробили печати")
	# мир собирается без «дыр» в границах мира
	t.check(big.get_block(0, 1199) != BlockDB.AIR and big.get_block(4199, 1199) != BlockDB.AIR, "дно мира сплошное")


func _bfs_to(from: Vector2i, y_target: int) -> bool:
	var w := big.width
	var seen := PackedByteArray()
	seen.resize(w * big.height)
	var q := PackedInt32Array()
	q.append(from.y * w + from.x)
	seen[from.y * w + from.x] = 1
	var head := 0
	while head < q.size():
		var idx := q[head]
		head += 1
		var x := idx % w
		var y := idx / w
		if y <= y_target:
			return true
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = x + d.x
			var ny: int = y + d.y
			if nx < 0 or ny < 0 or nx >= w or ny >= big.height:
				continue
			var ni := ny * w + nx
			if seen[ni] == 1 or big.is_solid(nx, ny):
				continue
			seen[ni] = 1
			q.append(ni)
	return false


func _test_reachability(t) -> void:
	var d: Vector2i = _structs("arena_lab")[0]["altar"]
	t.check(_bfs_to(d + Vector2i(0, -1), 724), "из зала Директора можно подняться к потолку лабораторий")
	var c: Vector2i = _structs("arena_core")[0]["altar"]
	t.check(_bfs_to(c + Vector2i(0, -1), 994), "из зала Ядра можно подняться к потолку реактора")
	var g: Vector2i = _structs("arena_corp")[0]["altar"]
	t.check(_bfs_to(g + Vector2i(0, -1), g.y - 12), "на плиту корпоративного района можно выйти на поверхность")
	# башни: ладдер на второй этаж
	var base := g.y + 2
	var ladders := 0
	for x in range(g.x - 80, g.x + 80):
		for y in range(base - 15, base - 2):
			if big.get_block(x, y) == BlockDB.LADDER:
				ladders += 1
	t.check(ladders >= 16, "в башнях есть лестницы на верхние этажи (%d)" % ladders)


func _test_loot(t) -> void:
	var data_c := 0
	var alloy := 0
	var fuel := 0
	var mut := 0
	for pos in big.tombstones:
		var items: Dictionary = big.tombstones[pos]
		if pos.y >= 722 and pos.y <= 990 and items.has("data_crystal"):
			data_c += 1
		if pos.y >= 722 and items.has("alloy"):
			alloy += 1
		if pos.y >= 992 and items.has("fuel_rod"):
			fuel += 1
		if items.has("mutagen"):
			mut += 1
	t.check(data_c >= 20 and alloy >= 20, "в лабораториях хватает данных и сплава (%d / %d ящиков)" % [data_c, alloy])
	t.check(fuel >= 3, "в реакторе есть топливные стержни (%d)" % fuel)
	t.check(mut >= 3, "мутаген лежит в ящиках (%d)" % mut)
	var ok := true
	for pos in big.tombstones:
		if big.get_block(pos.x, pos.y) != BlockDB.LOOT and big.get_block(pos.x, pos.y) != BlockDB.TOMBSTONE:
			ok = false
		for k in big.tombstones[pos]:
			if not ItemDB.has_item(k):
				ok = false
				printerr("   неизвестный предмет в ящике: ", k)
	t.check(ok, "каждый ящик стоит на своём месте и содержит существующие предметы")


func _test_progression(t) -> void:
	# сквозной маршрут: чем открывается каждый слой и какие предметы нужны для вызова
	RecipeDB.ensure_loaded()
	Progress.reset()
	var order := ["boss_1", "boss_2", "boss_3", "boss_4", "boss_5", "boss_6", "boss_7", "boss_8", "boss_9"]
	var ids := ["chief", "queen", "commander", "wasteland_lord", "corp_guard", "mine_king", "nest_brain", "director", "core"]
	var available_ok := true
	for i in order.size():
		var info := BossManager.boss_info(ids[i])
		var item := str(info["item"])
		var recipe := {}
		for r in RecipeDB.recipes:
			if r["result"] == item:
				recipe = r
		if recipe.is_empty():
			available_ok = false
			continue
		# рецепт приманки должен быть доступен ДО победы над этим боссом
		if Progress.has(str(recipe.get("requires", ""))) == false:
			available_ok = false
			printerr("   приманка %s недоступна к бою %s (нужно %s)" % [item, ids[i], recipe.get("requires")])
		Progress.unlock(order[i])
	t.check(available_ok, "приманка каждого босса открывается до встречи с ним")
	t.check(Progress.is_finished() and Progress.stage() == 5, "после всех боссов — финал")
	Progress.reset()
	# слои открываются в логичном порядке
	var order_ok := true
	var unlocked := 0
	for id in ["chief", "queen", "commander", "wasteland_lord", "corp_guard", "mine_king", "nest_brain", "director"]:
		var info := BossManager.boss_info(id)
		Progress.unlock(str(info["flag"]))
		var now := 0
		for l in Layers.list:
			if Layers.is_unlocked(l):
				now += 1
		if now < unlocked:
			order_ok = false
		unlocked = now
	t.check(order_ok and unlocked == 6, "после 8 боссов открыты все 6 слоёв")
	Progress.reset()


func _flat_world() -> WorldData:
	var world := WorldData.new(240, 64)
	for y in range(40, 64):
		for x in 240:
			world.fg[y * 240 + x] = BlockDB.STONE
	for x in 240:
		world.surface[x] = 40
	world.biome.fill(WorldGen.BIOME_RUINS)
	return world


func _bot_run(world: WorldData, id: String, kit: Dictionary, limit: float) -> Dictionary:
	EnemyDB.ensure_loaded()
	var p := Player.new()
	p.world = world
	p.position = Vector2(100 * TILE, 38 * TILE)
	for _i in 30:
		p.physics_step(1.0 / 60.0, 0.0, false)
	var em := EnemyManager.new()
	em.world = world
	em.player = p
	em.clock = DayClock.new()
	em.day_spawns = false
	p.combat = em
	var bm := BossManager.new()
	bm.setup(world, p, em)
	for k in kit:
		p.inv.add(k, kit[k])
	for it in ["alloy_helmet", "alloy_chest", "alloy_boots"]:
		if p.inv.count(it) > 0:
			p.equip_item(it)
	var info := BossManager.boss_info(id)
	var altar := Vector2i(102, 39)
	world.set_block(altar.x, altar.y, BlockDB.ALTAR)
	world.altars[altar] = id
	p.inv.add(str(info["item"]), 1)
	bm.interact(altar, p)
	var dt := 1.0 / 60.0
	var time := 0.0
	var gun := "plasma_rifle"
	var gun_slot: int = p.inv.items.find(gun)
	while time < limit and bm.is_active() and p.deaths == 0:
		var boss: Boss = bm.boss
		var target: Enemy = boss
		var best := 1e9
		for e in em.enemies:
			if is_instance_valid(e) and not e.dead:
				var d := e.center().distance_to(p.center())
				if d < best:
					best = d
					target = e
		var to := target.center() - p.center()
		var move := 0.0
		var jump := false
		if absf(to.x) < 120.0:
			move = -signf(to.x)
			var hx := p.position.x / 16.0
			if (move < 0.0 and hx < 14.0) or (move > 0.0 and hx > 226.0):
				move = -move
		elif absf(to.x) > 230.0:
			move = signf(to.x)
		if boss.telegraph > 0.0 and boss.telegraph_radius > 0.0 and absf(boss.center().x - p.center().x) < boss.telegraph_radius + 30.0:
			jump = p.on_floor
		p.physics_step(dt, move, jump)
		em.update(dt)
		bm.update(dt)
		if p.hp < 65.0 and p.inv.count("medkit") > 0 and p.attack_cd <= 0.0:
			p.selected = p.inv.items.find("medkit")
			p.use_item("medkit")
		elif p.inv.count("cell") > 0 and gun_slot >= 0:
			p.selected = gun_slot
			p.try_attack(target.center())
		time += dt
	var won := Progress.has(str(info["flag"])) and p.deaths == 0
	var res := {"won": won, "time": time, "hp": p.hp, "deaths": p.deaths}
	bm.free()
	em.free()
	p.free()
	return res


func _test_fights(t) -> void:
	var kit := {"medkit": 20, "plasma_rifle": 1, "cell": 700, "alloy_helmet": 1, "alloy_chest": 1, "alloy_boots": 1, "antirad": 3}
	for entry in [["corp_guard", 400.0], ["director", 480.0], ["core", 700.0]]:
		Progress.reset()
		var res := _bot_run(_flat_world(), entry[0], kit, entry[1])
		t.check(res["won"], "герой в сплаве с плазмой побеждает «%s» за %.0f с" % [entry[0], res["time"]])
	Progress.reset()
	# с дубиной и без брони — нет
	var weak := _bot_run(_flat_world(), "director", {"wood_club": 1, "medkit": 2}, 150.0)
	t.check(not weak["won"], "голыми руками Директор не берётся")
	Progress.reset()
	# способности: Страж у себя открывает щит, Директор меняет оружие
	EnemyDB.ensure_loaded()
	for id in ["boss_corp_guard", "boss_director", "boss_core"]:
		var d: Dictionary = EnemyDB.defs[id]
		t.check(d.has("abilities") and (d["abilities"] as Array).size() >= 3, "%s: у босса набор способностей" % id)
	var core: Dictionary = EnemyDB.defs["boss_core"]
	t.check(float(core["speed"]) == 0.0 and float(core["hp"]) >= 3000.0, "«Ядро» неподвижно и самое живучее")


func _test_ending_logic(t) -> void:
	var st := {"days": 42, "kills": 311, "residents": 4}
	var a := Ending.epilogue("shutdown", st)
	var b := Ending.epilogue("control", st)
	t.check(a != b and "42" in a and "311" in a and "4" in a, "эпилоги различаются и показывают статистику")
	Progress.reset()
	t.check(Progress.ending == "", "до финала концовка не выбрана")


func _test_main_ending(t) -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	var main = scene.instantiate()
	main.world_width = 2400
	main.world_height = 1200
	t.root.add_child(main)
	var guard := 0
	while not main.ready_done and guard < 1200:
		await t.process_frame
		guard += 1
	t.check(main.ready_done and main.ending != null, "сцена запущена, финальный экран подключён")
	t.check(not main.ending.open and not t.root.get_tree().paused, "финал сначала закрыт")
	main.bosses.won.emit("boss_3")
	t.check(not main.ending.open, "победа над рядовым боссом финал не открывает")
	main.bosses.won.emit("boss_9")
	t.check(main.ending.open and t.root.get_tree().paused, "победа над Ядром открывает выбор и ставит игру на паузу")
	t.check(not main.ending.close(), "пока не выбрана концовка, закрыть нельзя")
	t.check(main.ending.choose("control") and Progress.ending == "control", "выбор концовки запоминается")
	t.check(not main.ending.choose("shutdown"), "повторно выбрать нельзя")
	t.check(main.ending.close() and not t.root.get_tree().paused and not main.ending.open, "Enter возвращает в игру")
	main.queue_free()
	await t.process_frame
	t.root.get_tree().paused = false
	Progress.reset()
