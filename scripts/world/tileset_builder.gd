class_name TileSetBuilder
extends RefCounted
## Собирает TileSet из цветов блоков (data/blocks.json) прямо при запуске.
## Это заглушка: позже заменяется настоящим пиксель-артом, id блоков остаются теми же.

const TILE := 16


static func build() -> TileSet:
	BlockDB.ensure_loaded()
	var img := Image.create(TILE * BlockDB.count, TILE, false, Image.FORMAT_RGBA8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1234
	for id in range(1, BlockDB.count):
		_paint_tile(img, id, rng)
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(img)
	src.texture_region_size = Vector2i(TILE, TILE)
	for id in range(1, BlockDB.count):
		src.create_tile(Vector2i(id, 0))
	var ts := TileSet.new()
	ts.tile_size = Vector2i(TILE, TILE)
	ts.add_source(src, 0)
	return ts


static func _paint_tile(img: Image, id: int, rng: RandomNumberGenerator) -> void:
	var base := BlockDB.colors[id]
	var ox := id * TILE
	for py in TILE:
		for px in TILE:
			var j := rng.randf_range(-0.06, 0.06)
			var c := Color(clampf(base.r + j, 0.0, 1.0), clampf(base.g + j, 0.0, 1.0), clampf(base.b + j, 0.0, 1.0), 1.0)
			if px == 0 or py == 0:
				c = c.lightened(0.08)
			elif px == TILE - 1 or py == TILE - 1:
				c = c.darkened(0.18)
			img.set_pixel(ox + px, py, c)
	var speck := BlockDB.specks[id]
	if speck.a > 0.0:
		for _i in 8:
			var sx := rng.randi_range(1, TILE - 5)
			var sy := rng.randi_range(1, TILE - 5)
			for dy in 3:
				for dx in 3:
					img.set_pixel(ox + sx + dx, sy + dy, speck)
