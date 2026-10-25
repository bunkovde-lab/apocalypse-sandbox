extends RefCounted
## Этап 2: инвентарь и крафт. Критерий из ТЗ: предмет можно добыть, скрафтить и положить в быстрый слот.

const TILE := 16


func run(t) -> void:
	_test_item_db(t)
	_test_inventory(t)
	_test_recipes(t)
	_test_crafting_rules(t)
	_test_player_inventory(t)
	_test_progression(t)
	_test_world_resources(t)
	await _test_ui(t)


func _flat_world(w: int = 64, h: int = 64, floor_y: int = 40) -> WorldData:
	var world := WorldData.new(w, h)
	for y in range(floor_y, h):
		for x in w:
			world.fg[y * w + x] = BlockDB.STONE
	for x in w:
		world.surface[x] = floor_y
	return world


func _player(world: WorldData, tile_x: int = 10) -> Player:
	var p := Player.new()
	p.world = world
	p.position = Vector2(tile_x * TILE, 0)
	for _i in 120:
		p.physics_step(1.0 / 60.0, 0.0, false)
	return p


func _test_item_db(t) -> void:
	ItemDB.ensure_loaded()
	t.check(ItemDB.stack_max("dirt") == 999 and ItemDB.stack_max("wood_pick") == 1, "блоки складываются по 999, инструменты по 1")
	t.check(ItemDB.block_id("stone") == BlockDB.STONE, "предмет-блок знает свой блок")
	t.check(ItemDB.block_id("iron_ore") == -1 and ItemDB.block_id("wood_pick") == -1, "руду и кирку ставить нельзя")
	t.check(ItemDB.tool_power("iron_pick") > ItemDB.tool_power("wood_pick"), "железная кирка сильнее деревянной")
	t.check(ItemDB.title("workbench") == "Верстак", "название предмета по-русски")
	var all_blocks_have_items := true
	for id in range(1, BlockDB.count):
		if BlockDB.drops[id] != "" and not ItemDB.has_item(BlockDB.drops[id]):
			all_blocks_have_items = false
	t.check(all_blocks_have_items, "всё, что выпадает из блоков, описано как предмет")


func _test_inventory(t) -> void:
	var inv := Inventory.new()
	var signals := [0]
	inv.changed.connect(func() -> void: signals[0] += 1)
	t.check(inv.add("dirt", 1500) == 0, "1500 земли помещается")
	t.check(inv.slot_count(0) == 999 and inv.slot_count(1) == 501, "стопки по 999 и остаток")
	t.check(inv.count("dirt") == 1500 and signals[0] == 1, "общее количество и один сигнал изменения")
	t.check(inv.remove("dirt", 1000) and inv.count("dirt") == 500, "списание из нескольких стопок")
	t.check(not inv.remove("dirt", 501) and inv.count("dirt") == 500, "нельзя списать больше, чем есть")
	inv.swap(1, 5)
	t.check(inv.slot_item(5) == "dirt" and inv.slot_item(1) == "", "ячейки меняются местами")
	inv.add("dirt", 600)
	inv.swap(0, 5)
	t.check(inv.count("dirt") == 1100 and inv.slot_count(0) + inv.slot_count(5) == 1100, "одинаковые стопки сливаются")

	var full := Inventory.new()
	for i in Inventory.SIZE:
		full.add("wood_pick", 1)
	t.check(full.add("wood_pick", 1) == 1, "в полном инвентаре предмет не помещается")
	t.check(not full.can_add("dirt", 1), "can_add видит нехватку места")
	var snap := full.snapshot()
	full.remove("wood_pick", 10)
	full.restore(snap)
	t.check(full.count("wood_pick") == Inventory.SIZE, "снимок состояния восстанавливается")


func _test_recipes(t) -> void:
	RecipeDB.ensure_loaded()
	t.check(RecipeDB.recipes.size() >= 10, "в игре минимум 10 рецептов (%d)" % RecipeDB.recipes.size())
	var ok := true
	for r in RecipeDB.recipes:
		if not ItemDB.has_item(r["result"]):
			ok = false
		for k in r["ingredients"]:
			if not ItemDB.has_item(k):
				ok = false
		var st: String = r["station"]
		if st != "" and not (BlockDB.name_to_id.has(st) and BlockDB.station[BlockDB.name_to_id[st]] == 1):
			ok = false
	t.check(ok, "все предметы и станции в рецептах существуют")

	# Каждый рецепт достижим: ингредиенты либо добываются, либо делаются другим рецептом.
	var obtainable := {}
	for id in range(1, BlockDB.count):
		if BlockDB.drops[id] != "":
			obtainable[BlockDB.drops[id]] = true
	var changed := true
	while changed:
		changed = false
		for r in RecipeDB.recipes:
			if obtainable.has(r["result"]):
				continue
			var can := true
			for k in r["ingredients"]:
				if not obtainable.has(k):
					can = false
			if can:
				obtainable[r["result"]] = true
				changed = true
	var all_reachable := true
	for r in RecipeDB.recipes:
		if not obtainable.has(r["result"]):
			all_reachable = false
	t.check(all_reachable, "любой рецепт можно выполнить, начиная с добычи блоков")


func _test_crafting_rules(t) -> void:
	RecipeDB.ensure_loaded()
	var bench: Dictionary = RecipeDB.recipes.filter(func(r): return r["result"] == "workbench")[0]
	var pick: Dictionary = RecipeDB.recipes.filter(func(r): return r["result"] == "wood_pick")[0]
	var inv := Inventory.new()
	t.check(not RecipeDB.craft(inv, {}, bench), "без ингредиентов крафт не идёт")
	inv.add("wood", 10)
	t.check(RecipeDB.craft(inv, {}, bench), "верстак делается руками из 10 дерева")
	t.check(inv.count("wood") == 0 and inv.count("workbench") == 1, "ингредиенты списаны, результат получен")
	inv.add("wood", 8)
	t.check(not RecipeDB.craft(inv, {}, pick), "кирку без верстака не сделать")
	t.check(RecipeDB.craft(inv, {"workbench": true}, pick) and inv.count("wood_pick") == 1, "кирка делается рядом с верстаком")

	var packed := Inventory.new()
	for i in 39:
		packed.add("wood_pick", 1)
	packed.add("wood", 20)
	t.check(not RecipeDB.craft(packed, {"workbench": true}, pick), "нет места для результата: крафт отменяется")
	t.check(packed.count("wood") == 20, "при отмене ингредиенты возвращаются")


func _test_player_inventory(t) -> void:
	var world := _flat_world()
	var p := _player(world)
	var below := Vector2i(p.tile_pos().x, 40)

	var hand_ticks := 0
	while not p.mine_tick(below, 0.05) and hand_ticks < 80:
		hand_ticks += 1
	t.check(p.item_count("stone") == 1, "добыча идёт в инвентарь игрока")
	p.add_item("wood_pick", 1)
	p.selected = 0
	t.check(p.selected_item() == "stone", "в первой ячейке лежит добытый камень")
	var slot := 3
	p.inv.swap(1, slot)
	p.selected = slot
	t.check(p.selected_item() == "wood_pick" and p.mine_power() >= 1.4, "выбранная кирка увеличивает силу копания")
	var below2 := Vector2i(below.x + 1, 40)
	var pick_ticks := 0
	while not p.mine_tick(below2, 0.05) and pick_ticks < 80:
		pick_ticks += 1
	t.check(pick_ticks < hand_ticks, "с киркой копать быстрее (%d против %d тиков)" % [pick_ticks, hand_ticks])

	p.selected = 0
	t.check(p.place_selected(below), "блок из выбранной ячейки ставится")
	t.check(p.item_count("stone") == 1 and world.get_block(below.x, below.y) == BlockDB.STONE, "один камень остался, блок на месте")

	# Полный инвентарь: добычу некуда деть, блок остаётся.
	var full := _player(_flat_world(), 20)
	for i in Inventory.SIZE:
		full.inv.add("wood_pick", 1)
	var tile := Vector2i(full.tile_pos().x, 40)
	var broke := false
	for _i in 100:
		broke = broke or full.mine_tick(tile, 0.05)
	t.check(not broke and full.world.get_block(tile.x, tile.y) == BlockDB.STONE, "при полном инвентаре блок не ломается")
	p.free()
	full.free()


func _test_progression(t) -> void:
	# Весь путь: дерево -> верстак -> кирка -> кузница -> слитки -> железная кирка, меч, пистолет, патроны.
	var world := _flat_world(80, 64, 40)
	var p := _player(world, 20)
	var here := p.tile_pos()
	p.add_item("wood", 40)
	p.add_item("stone", 30)
	p.add_item("scrap", 6)
	p.add_item("iron_ore", 66)
	p.add_item("copper_ore", 15)
	p.add_item("coal", 28)

	t.check(_craft(p, "workbench"), "шаг 1: верстак")
	t.check(p.place_block(Vector2i(here.x + 2, 39), "workbench"), "верстак ставится в мир")
	t.check(p.nearby_stations().has("workbench"), "игрок видит верстак рядом")
	t.check(_craft(p, "wood_pick") and _craft(p, "wood_club"), "шаг 2: деревянная кирка и дубина")
	t.check(not _craft(p, "concrete"), "бетон без песка не делается")
	p.add_item("sand", 1)
	t.check(_craft(p, "concrete") and p.item_count("concrete") == 2, "бетон из камня и песка")
	t.check(_craft(p, "forge"), "шаг 3: кузница")
	t.check(not _craft(p, "iron_bar"), "слитки без кузницы рядом не плавятся")
	t.check(p.place_block(Vector2i(here.x - 2, 39), "forge"), "кузница ставится в мир")
	for _i in 8:
		_craft(p, "iron_bar")
	for _i in 5:
		_craft(p, "copper_bar")
	t.check(p.item_count("iron_bar") == 8 and p.item_count("copper_bar") == 5, "шаг 4: 8 железных и 5 медных слитков")
	t.check(_craft(p, "iron_pick") and ItemDB.tool_power("iron_pick") > 2.0, "шаг 5: железная кирка")
	t.check(p.item_count("iron_bar") == 0, "слитки потрачены")
	for _i in 14:
		_craft(p, "iron_bar")
	t.check(_craft(p, "iron_sword"), "железный меч")
	t.check(_craft(p, "pistol"), "пистолет")
	t.check(_craft(p, "bullet") and p.item_count("bullet") == 10, "патроны по 10 штук за слиток")

	# Станция вне зоны не работает.
	var far := _player(world, 70)
	far.add_item("iron_ore", 3)
	far.add_item("coal", 1)
	t.check(not _craft(far, "iron_bar"), "кузница далеко: плавка недоступна")
	p.free()
	far.free()


func _craft(p: Player, result: String) -> bool:
	for r in RecipeDB.recipes:
		if r["result"] == result:
			return RecipeDB.craft(p.inv, p.nearby_stations(), r)
	return false


func _test_world_resources(t) -> void:
	var world := WorldGen.generate(20261025, 1200, 400)
	var wood := 0
	var scrap := 0
	var cx := world.width / 2
	var near_wood := false
	var near_scrap := false
	for x in world.width:
		for y in range(world.surface[x] - 12, world.surface[x]):
			var id := world.get_block(x, y)
			if id == BlockDB.WOOD:
				wood += 1
				if absi(x - cx) < 300:
					near_wood = true
			elif id == BlockDB.SCRAP:
				scrap += 1
				if absi(x - cx) < 300:
					near_scrap = true
	t.check(wood > 100 and scrap > 20, "в мире есть деревья (%d) и металлолом (%d)" % [wood, scrap])
	t.check(near_wood and near_scrap, "дерево и металлолом есть недалеко от места старта")
	var grounded := true
	for x in world.width:
		if world.get_block(x, world.surface[x] - 1) == BlockDB.WOOD and not world.is_solid(x, world.surface[x]):
			grounded = false
	t.check(grounded, "деревья стоят на земле")
	var cx_clear := true
	for x in range(cx - 3, cx + 4):
		if world.get_block(x, world.surface[x] - 1) != BlockDB.AIR:
			cx_clear = false
	t.check(cx_clear, "у точки старта нет деревьев и мусора")


func _test_ui(t) -> void:
	var world := _flat_world()
	var p := _player(world)
	t.root.add_child(p)
	var ui := InventoryUI.new()
	t.root.add_child(ui)
	ui.setup(p)
	t.check(ui.hotbar_buttons.size() == 10, "в быстрой панели 10 ячеек")
	p.add_item("dirt", 5)
	t.check(ui.hotbar_buttons[0].text.contains("Земля") and ui.hotbar_buttons[0].text.contains("5"), "ячейка показывает название и число")
	ui.hotbar_buttons[3].pressed.emit()
	t.check(p.selected == 3, "нажатие на ячейку выбирает её")
	t.check(ui.hotbar_buttons[3].modulate != ui.hotbar_buttons[2].modulate, "выбранная ячейка подсвечена")

	ui.toggle()
	t.check(ui.panel.visible, "окно инвентаря открывается")
	var bench_idx := -1
	for i in RecipeDB.recipes.size():
		if RecipeDB.recipes[i]["result"] == "workbench":
			bench_idx = i
	t.check(ui.recipe_buttons[bench_idx].disabled, "без дерева кнопка верстака отключена")
	p.add_item("wood", 10)
	t.check(not ui.recipe_buttons[bench_idx].disabled, "с 10 деревом кнопка верстака активна")
	ui.recipe_buttons[bench_idx].pressed.emit()
	t.check(p.item_count("workbench") == 1 and p.item_count("wood") == 0, "нажатие на рецепт крафтит предмет")

	var first_filled := -1
	for i in Inventory.SIZE:
		if p.inv.slot_count(i) > 0:
			first_filled = i
			break
	var item_before := p.inv.slot_item(first_filled)
	ui.grid_buttons[first_filled].pressed.emit()
	ui.grid_buttons[20].pressed.emit()
	t.check(p.inv.slot_item(20) == item_before and p.inv.slot_item(first_filled) != item_before, "перенос предмета в другую ячейку мышью")
	ui.toggle()
	t.check(not ui.panel.visible, "окно закрывается")
	ui.queue_free()
	p.queue_free()
	await t.process_frame
