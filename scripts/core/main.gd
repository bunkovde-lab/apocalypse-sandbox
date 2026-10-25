extends Node2D
## Точка входа: генерирует мир, создаёт игрока, врагов, камеру и показ чанков.

@export var world_width := 4200
@export var world_height := 1200
@export var world_seed := 20261025

const SKY_COLOR := Color("8a8070")
const NIGHT_SKY_COLOR := Color("1c2338")
const DARK_COLOR := Color("0d0e12")

var world: WorldData
var renderer: ChunkRenderer
var player: Player
var camera: Camera2D
var hud: Hud
var ui: InventoryUI
var clock := DayClock.new()
var enemies: EnemyManager
var shelter: ShelterManager
var survivors: SurvivorManager
var bosses: BossManager
var camps: CampManager
var seals: SealManager
var layer_spawner: LayerSpawner
var director: EventDirector
var ending: Ending
var tint: CanvasModulate
var ready_done := false


func _ready() -> void:
	InputSetup.register()
	Progress.reset()
	hud = Hud.new()
	add_child(hud)
	hud.set_text("Генерация мира...")
	await get_tree().process_frame

	var t0 := Time.get_ticks_msec()
	world = WorldGen.generate(world_seed, world_width, world_height)
	print("Мир %dx%d создан за %d мс" % [world_width, world_height, Time.get_ticks_msec() - t0])

	tint = CanvasModulate.new()
	add_child(tint)

	renderer = ChunkRenderer.new()
	add_child(renderer)
	renderer.setup(world, TileSetBuilder.build())

	player = Player.new()
	player.world = world
	player.spawn_pos = Vector2(world.spawn_tile.x * 16 + 1, world.spawn_tile.y * 16)
	player.position = player.spawn_pos
	player.died.connect(func() -> void:
		hud.flash_message("Вы погибли. Половина вещей осталась на надгробии.", 4.0))

	player.message.connect(func(text: String) -> void: hud.flash_message(text, 2.5))

	enemies = EnemyManager.new()
	add_child(enemies)
	add_child(player)
	enemies.setup(world, player, clock)
	shelter = ShelterManager.new()
	add_child(shelter)
	shelter.setup(world, player, enemies)
	survivors = SurvivorManager.new()
	add_child(survivors)
	survivors.setup(world, player, shelter, clock)
	survivors.message.connect(func(text: String) -> void: hud.flash_message(text, 3.0))
	bosses = BossManager.new()
	add_child(bosses)
	bosses.setup(world, player, enemies)
	bosses.message.connect(func(text: String) -> void: hud.flash_message(text, 4.0))
	bosses.boss_changed.connect(hud.set_boss)
	camps = CampManager.new()
	add_child(camps)
	camps.setup(world, player, enemies, clock)
	seals = SealManager.new()
	add_child(seals)
	seals.setup(world, player)
	seals.message.connect(func(text: String) -> void: hud.flash_message(text, 4.0))
	layer_spawner = LayerSpawner.new()
	add_child(layer_spawner)
	layer_spawner.setup(world, player, enemies)
	director = EventDirector.new()
	add_child(director)
	director.setup(world, player, enemies, survivors, shelter, clock)
	director.message.connect(func(text: String) -> void: hud.flash_message(text, 4.0))
	ending = Ending.new()
	add_child(ending)
	bosses.won.connect(func(flag: String) -> void:
		if flag == "boss_9":
			ending.show_choice(ending_stats()))
	for dx in [-55, 40, 85]:
		survivors.spawn_stranded(clampi(world.spawn_tile.x + dx, 5, world.width - 6))
	clock.night_started.connect(func(n: int) -> void: hud.flash_message("Ночь %d. Идёт орда." % n, 3.0))
	clock.dawn.connect(func() -> void: hud.flash_message("Рассвет. Орда отступила.", 3.0))
	clock.night_warning.connect(func() -> void: hud.flash_message("Скоро ночь: готовьте оборону!", 4.0))

	camera = Camera2D.new()
	camera.zoom = Vector2(2, 2)
	camera.position = Player.SIZE * 0.5
	camera.limit_left = 0
	camera.limit_right = world_width * 16
	camera.limit_bottom = world_height * 16
	player.add_child(camera)
	camera.make_current()

	ui = InventoryUI.new()
	add_child(ui)
	ui.setup(player)

	renderer.update_view(player.tile_pos())
	renderer.flush()
	ready_done = true


func _process(delta: float) -> void:
	if not ready_done:
		return
	clock.advance(delta)
	var tile := player.tile_pos()
	renderer.update_view(tile)
	renderer.process_queue(2)
	var col := clampi(tile.x, 0, world.width - 1)
	var depth := tile.y - world.surface[col]
	var underground := clampf(depth / 20.0, 0.0, 1.0)
	tint.color = clock.tint().lerp(Color.WHITE, underground)
	var sky := SKY_COLOR.lerp(NIGHT_SKY_COLOR, clock.darkness())
	RenderingServer.set_default_clear_color(sky.lerp(DARK_COLOR, clampf(depth / 30.0, 0.0, 1.0)))
	hud.set_hp(player.hp, player.max_hp)
	hud.set_rad(player.rad)
	var banner := director.active_text()
	var hint := seals.hint()
	hud.set_banner(hint if hint != "" else banner)
	var eq := PackedStringArray()
	for slot in Player.SLOTS:
		if player.equip[slot] != "":
			eq.append(ItemDB.title(player.equip[slot]))
	hud.set_equip(("Надето: " + ", ".join(eq) + "  (защита %d%%)" % int(player.defense() * 100.0)) if not eq.is_empty() else "")
	hud.panel.text = shelter.panel_text()
	hud.set_text("День %d, %s%s   FPS %d   %s\nx %d  y %d  глубина %d   убито %d   этап %d" % [
		clock.day, clock.clock_text(), " (ночь)" if clock.is_night() else "",
		Engine.get_frames_per_second(), seals.depth_title(), tile.x, tile.y, depth, enemies.kills, Progress.stage()])


func ending_stats() -> Dictionary:
	return {"days": clock.day, "kills": enemies.kills, "residents": survivors.residents.size()}
