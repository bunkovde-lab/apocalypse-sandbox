class_name InventoryUI
extends CanvasLayer
## Быстрая панель внизу экрана всегда видна. Tab/I открывает окно: сетка инвентаря и список рецептов.
## Предмет в сетке: нажать на ячейку, затем на другую, и они поменяются местами.

var player: Player
var hotbar_buttons: Array[Button] = []
var grid_buttons: Array[Button] = []
var recipe_buttons: Array[Button] = []
var panel: PanelContainer
var held := -1
var stations := {}


func setup(p: Player) -> void:
	player = p
	ItemDB.ensure_loaded()
	RecipeDB.ensure_loaded()
	_build()
	player.inv.changed.connect(refresh)
	player.selected_changed.connect(refresh)
	var timer := Timer.new()
	timer.wait_time = 0.3
	timer.autostart = true
	timer.timeout.connect(func() -> void:
		if panel.visible:
			refresh())
	add_child(timer)
	refresh()


func toggle() -> void:
	panel.visible = not panel.visible
	held = -1
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_inventory"):
		toggle()


func _slot_button(width: float = 92.0) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(width, 44)
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	b.add_theme_font_size_override("font_size", 11)
	return b


func _build() -> void:
	var bar := HBoxContainer.new()
	bar.anchor_left = 0.5
	bar.anchor_right = 0.5
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	bar.grow_vertical = Control.GROW_DIRECTION_BEGIN
	bar.offset_bottom = -36
	bar.add_theme_constant_override("separation", 2)
	add_child(bar)
	for i in Inventory.HOTBAR:
		var b := _slot_button()
		b.pressed.connect(func() -> void: player.selected = i)
		bar.add_child(b)
		hotbar_buttons.append(b)

	panel = PanelContainer.new()
	panel.visible = false
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)

	var grid := GridContainer.new()
	grid.columns = Inventory.HOTBAR
	grid.add_theme_constant_override("h_separation", 2)
	grid.add_theme_constant_override("v_separation", 2)
	row.add_child(grid)
	for i in Inventory.SIZE:
		var b := _slot_button(80.0)
		b.pressed.connect(func() -> void: _on_grid_pressed(i))
		grid.add_child(b)
		grid_buttons.append(b)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(300, 190)
	row.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(list)
	for r in RecipeDB.recipes:
		var b := Button.new()
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_size_override("font_size", 12)
		b.pressed.connect(func() -> void: RecipeDB.craft(player.inv, stations, r))
		list.add_child(b)
		recipe_buttons.append(b)


func _on_grid_pressed(i: int) -> void:
	if held == -1:
		if player.inv.slot_count(i) > 0:
			held = i
	else:
		player.inv.swap(held, i)
		held = -1
	refresh()


func _slot_text(i: int) -> String:
	var item := player.inv.slot_item(i)
	if item == "":
		return ""
	return "%s\n%d" % [ItemDB.title(item), player.inv.slot_count(i)]


func refresh() -> void:
	if player == null:
		return
	for i in Inventory.HOTBAR:
		var b := hotbar_buttons[i]
		b.text = "%d %s" % [(i + 1) % 10, _slot_text(i)]
		b.modulate = Color(1.0, 0.95, 0.45) if i == player.selected else Color.WHITE
	if not panel.visible:
		return
	for i in Inventory.SIZE:
		grid_buttons[i].text = _slot_text(i)
		grid_buttons[i].modulate = Color(0.6, 1.0, 0.6) if i == held else Color.WHITE
	stations = player.nearby_stations()
	for idx in RecipeDB.recipes.size():
		var r: Dictionary = RecipeDB.recipes[idx]
		var b := recipe_buttons[idx]
		var st: String = r["station"]
		var where := "" if st == "" else " [%s]" % ItemDB.title(st)
		b.text = "%s x%d%s: %s" % [ItemDB.title(r["result"]), r["count"], where, RecipeDB.ingredients_text(r)]
		b.disabled = not RecipeDB.is_craftable(player.inv, stations, r)
