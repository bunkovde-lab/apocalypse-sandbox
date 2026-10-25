class_name SealManager
extends Node
## Печати между слоями. Печать снимается, когда выполнено условие слоя (победа над боссами).

signal message(text: String)
signal opened(layer_id: String)

var world: WorldData
var player: Player
var timer := 0.0


func setup(w: WorldData, p: Player) -> void:
	Layers.ensure_loaded()
	world = w
	player = p


func _physics_process(delta: float) -> void:
	update(delta)


func update(delta: float) -> void:
	timer -= delta
	if timer <= 0.0:
		timer = 0.5
		refresh()


## Открывает все слои, условия которых выполнены. Возвращает число открытых сейчас.
func refresh() -> int:
	var n := 0
	for l in Layers.list:
		if not world.seals_open.has(l["id"]) and Layers.is_unlocked(l) and world.height > int(l["y0"]):
			open_layer(l)
			n += 1
	return n


func open_layer(l: Dictionary) -> void:
	var r := Layers.seal_rows(l)
	var px := player.tile_pos().x
	world.open_rows(r.x, r.y, px - 80, px + 80)
	world.seals_open[l["id"]] = true
	opened.emit(str(l["id"]))
	message.emit("Печать снята: слой «%s» открыт." % l["title"])


## Подсказка у закрытой печати, иначе "".
func hint() -> String:
	var ty := player.tile_pos().y
	var tx := player.tile_pos().x
	for l in Layers.list:
		var y0: int = l["y0"]
		if not Layers.is_unlocked(l) and ty >= y0 - 20 and ty < y0 and world.get_block(tx, y0 - 1) == BlockDB.SEAL:
			return "Печать. Чтобы пройти дальше, победите: %s." % l["boss_name"]
	return ""


## Название слоя под ногами игрока.
func depth_title() -> String:
	var ty := player.tile_pos().y
	var l := Layers.at_y(ty)
	if not l.is_empty():
		return str(l["title"])
	var col := clampi(player.tile_pos().x, 0, world.width - 1)
	return "Поверхность" if ty < world.surface[col] + 14 else "Подземелье"
