extends Node2D
## Точка входа: генерирует мир, создаёт игрока, камеру и показ чанков.

@export var world_width := 4200
@export var world_height := 1200
@export var world_seed := 20261025

const SKY_COLOR := Color("8a8070")
const DARK_COLOR := Color("0d0e12")

var world: WorldData
var renderer: ChunkRenderer
var player: Player
var camera: Camera2D
var hud: Hud
var ui: InventoryUI
var ready_done := false


func _ready() -> void:
	InputSetup.register()
	hud = Hud.new()
	add_child(hud)
	hud.set_text("Генерация мира...")
	await get_tree().process_frame

	var t0 := Time.get_ticks_msec()
	world = WorldGen.generate(world_seed, world_width, world_height)
	print("Мир %dx%d создан за %d мс" % [world_width, world_height, Time.get_ticks_msec() - t0])

	renderer = ChunkRenderer.new()
	add_child(renderer)
	renderer.setup(world, TileSetBuilder.build())

	player = Player.new()
	player.world = world
	player.position = Vector2(world.spawn_tile.x * 16 + 1, world.spawn_tile.y * 16)
	add_child(player)

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


func _process(_delta: float) -> void:
	if not ready_done:
		return
	var tile := player.tile_pos()
	renderer.update_view(tile)
	renderer.process_queue(2)
	var col := clampi(tile.x, 0, world.width - 1)
	var depth := tile.y - world.surface[col]
	RenderingServer.set_default_clear_color(SKY_COLOR.lerp(DARK_COLOR, clampf(depth / 30.0, 0.0, 1.0)))
	hud.set_text("FPS %d   x %d  y %d   глубина %d" % [
		Engine.get_frames_per_second(), tile.x, tile.y, depth])
