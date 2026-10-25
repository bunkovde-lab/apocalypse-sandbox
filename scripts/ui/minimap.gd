class_name Minimap
extends Control
## Миникарта с туманом войны. Мир делится на клетки 8x8 блоков; открытые клетки рисуются цветом блока,
## закрытые — чёрным. M переключает малую карту и карту всего мира.

const CELL := 8
const REVEAL_RADIUS := 20           # блоков вокруг героя
const SMALL_COLS := 110
const SMALL_ROWS := 64

var world: WorldData
var player: Player
var cols := 0
var rows := 0
var explored := PackedByteArray()
var big := false
var timer := 0.0
var texture_rect := TextureRect.new()


func setup(w: WorldData, p: Player) -> void:
	world = w
	player = p
	cols = ceili(float(w.width) / CELL)
	rows = ceili(float(w.height) / CELL)
	explored.resize(cols * rows)
	texture_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	texture_rect.stretch_mode = TextureRect.STRETCH_SCALE
	texture_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	texture_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(texture_rect)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layout()
	reveal(p.tile_pos())


func _layout() -> void:
	var vp := Vector2(1280, 720)
	if is_inside_tree():
		vp = get_viewport().get_visible_rect().size
	set_anchors_preset(Control.PRESET_TOP_LEFT)
	if big:
		texture_rect.size = Vector2(cols * 2, rows * 2)
		size = texture_rect.size
		position = (vp - size) * 0.5
	else:
		texture_rect.size = Vector2(SMALL_COLS * 2, SMALL_ROWS * 2)
		size = texture_rect.size
		position = Vector2(8.0, 118.0)


func toggle_big() -> void:
	big = not big
	_layout()
	refresh()


func reveal(tile: Vector2i, radius: int = REVEAL_RADIUS) -> int:
	var n := 0
	var r2 := radius * radius
	for dy in range(-radius, radius + 1, CELL / 2):
		for dx in range(-radius, radius + 1, CELL / 2):
			if dx * dx + dy * dy > r2:
				continue
			var cx := floori(float(tile.x + dx) / CELL)
			var cy := floori(float(tile.y + dy) / CELL)
			if cx < 0 or cy < 0 or cx >= cols or cy >= rows:
				continue
			var i := cy * cols + cx
			if explored[i] == 0:
				explored[i] = 1
				n += 1
	return n


func is_explored(tile: Vector2i) -> bool:
	var cx := floori(float(tile.x) / CELL)
	var cy := floori(float(tile.y) / CELL)
	if cx < 0 or cy < 0 or cx >= cols or cy >= rows:
		return false
	return explored[cy * cols + cx] == 1


func explored_fraction() -> float:
	var n := 0
	for v in explored:
		n += v
	return float(n) / float(maxi(1, explored.size()))


func _cell_color(cx: int, cy: int) -> Color:
	if explored[cy * cols + cx] == 0:
		return Color.BLACK
	var x := mini(cx * CELL + CELL / 2, world.width - 1)
	var y := mini(cy * CELL + CELL / 2, world.height - 1)
	var id := world.get_block(x, y)
	if id == BlockDB.AIR:
		var above := y < world.surface[x]
		return Color("46516b") if above else Color("1a1b22")
	return BlockDB.colors[id]


## Картинка карты: окно cols_w x rows_h клеток вокруг героя (или вся карта).
func build_image() -> Image:
	var c0 := 0
	var r0 := 0
	var cw := cols
	var rh := rows
	var pc := Vector2i(floori(float(player.tile_pos().x) / CELL), floori(float(player.tile_pos().y) / CELL))
	if not big:
		cw = SMALL_COLS
		rh = SMALL_ROWS
		c0 = clampi(pc.x - cw / 2, 0, maxi(0, cols - cw))
		r0 = clampi(pc.y - rh / 2, 0, maxi(0, rows - rh))
	var img := Image.create(cw, rh, false, Image.FORMAT_RGB8)
	for y in rh:
		for x in cw:
			var gx := c0 + x
			var gy := r0 + y
			img.set_pixel(x, y, _cell_color(gx, gy) if gx < cols and gy < rows else Color.BLACK)
	# алтари боссов, если клетка открыта
	for pos in world.altars:
		var ax := floori(float(pos.x) / CELL) - c0
		var ay := floori(float(pos.y) / CELL) - r0
		if ax >= 0 and ay >= 0 and ax < cw and ay < rh and is_explored(pos):
			img.set_pixel(ax, ay, Color("e03a3a"))
	var px := pc.x - c0
	var py := pc.y - r0
	if px >= 0 and py >= 0 and px < cw and py < rh:
		img.set_pixel(px, py, Color.WHITE)
	return img


func refresh() -> void:
	if world == null:
		return
	texture_rect.texture = ImageTexture.create_from_image(build_image())


func _process(delta: float) -> void:
	if world == null or player == null:
		return
	timer -= delta
	if timer <= 0.0:
		timer = 0.4
		reveal(player.tile_pos())
		refresh()
