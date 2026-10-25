extends SceneTree
## Снимок экрана игры для проверки глазами.
## Запуск: xvfb-run -a -s "-screen 0 1280x720x24" godot --path . --rendering-driver opengl3 -s res://tools/shot.gd -- out.png [dx] [dy]
## dx, dy: на сколько блоков сместить игрока от точки старта (dy > 0 вниз, при этом блоки на пути вынимаются).


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var out: String = args[0] if args.size() > 0 else "/tmp/shot.png"
	var main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	while not main.ready_done:
		await process_frame
	if args.size() >= 3:
		var dx := int(args[1])
		var dy := int(args[2])
		var p: Player = main.player
		var tx := p.tile_pos().x + dx
		var ty: int = main.world.surface[tx] + dy if dy > 0 else main.world.surface[tx] - 3
		for y in range(ty - 2, ty + 3):
			for x in range(tx - 1, tx + 2):
				if dy > 0:
					main.world.set_block(x, y, BlockDB.AIR)
		p.position = Vector2(tx * 16, ty * 16)
	if OS.get_environment("SHOT_NIGHT") == "1":
		main.clock.time = 0.8
		main.enemies.day_spawns = false
		var px: int = main.player.tile_pos().x
		for pair in [["zombie_walker", -9], ["zombie_runner", -5], ["zombie_fat", 7], ["zombie_walker", 11]]:
			main.enemies.spawn_enemy(EnemyDB.defs[pair[0]], px + pair[1], 3)
		main.player.add_item("iron_sword", 1)
		main.player.take_damage(35.0, main.player.center().x - 30.0)
	if OS.get_environment("SHOT_BASE") == "1":
		var px: int = main.player.tile_pos().x + 3
		var gy: int = main.world.surface[px]
		for x in range(px - 1, px + 12):
			main.world.set_block(x, gy - 1, BlockDB.AIR)
		for x in range(px, px + 11):
			for y in range(gy - 5, gy):
				main.world.set_block(x, y, BlockDB.AIR)
			main.world.set_block(x, gy - 5, BlockDB.CONCRETE)
			main.world.set_bg(x, gy - 1, BlockDB.WOOD)
			for y in range(gy - 4, gy):
				main.world.set_bg(x, y, BlockDB.SCRAP)
		for y in range(gy - 5, gy):
			main.world.set_block(px, y, BlockDB.CONCRETE)
			main.world.set_block(px + 10, y, BlockDB.CONCRETE)
		main.world.set_block(px + 10, gy - 1, BlockDB.DOOR)
		main.world.set_block(px + 10, gy - 2, BlockDB.DOOR)
		main.world.set_block(px + 2, gy - 1, BlockDB.BED)
		main.world.set_block(px + 4, gy - 1, BlockDB.WORKBENCH)
		main.world.set_block(px + 6, gy - 1, BlockDB.GENERATOR)
		main.world.set_block(px + 8, gy - 1, BlockDB.TURRET)
		main.world.set_block(px + 12, gy - 1, BlockDB.SPIKES)
		main.world.set_block(px + 3, gy - 1, BlockDB.BED)
		main.world.set_block(px + 5, gy - 1, BlockDB.PLANTER)
		main.world.set_block(px + 7, gy - 1, BlockDB.PURIFIER)
		main.world.set_block(px + 9, gy - 1, BlockDB.CRATE)
		main.shelter.fuel[Vector2i(px + 6, gy - 1)] = 300.0
		for i in 2:
			var sv: Survivor = main.survivors.stranded[0]
			sv.position = Vector2((px + 4) * 16, (gy - 3) * 16)
			main.survivors.rescue(sv)
		main.survivors.residents[0].role = "farmer"
		main.survivors.residents[1].role = "engineer"
		main.shelter.recompute_power()
		for _i in 400:
			main.survivors.update(0.05)
			main.shelter.update(0.05)
		main.shelter.recompute_power()
		main.player.position = Vector2((px + 3) * 16, (gy - 3) * 16)
		main.player.spawn_pos = main.player.position
	if OS.get_environment("SHOT_UI") == "1":
		for item in {"wood": 24, "stone": 40, "scrap": 7, "iron_ore": 9, "coal": 4, "workbench": 1}.keys():
			main.player.add_item(item, {"wood": 24, "stone": 40, "scrap": 7, "iron_ore": 9, "coal": 4, "workbench": 1}[item])
		main.ui.toggle()
	await create_timer(1.5).timeout
	var img := root.get_viewport().get_texture().get_image()
	img.save_png(out)
	print("снимок сохранён: ", out, " ", img.get_size())
	quit()
