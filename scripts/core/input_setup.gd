class_name InputSetup
extends RefCounted
## Регистрирует действия ввода в коде, чтобы не зависеть от настроек редактора.


static func register() -> void:
	_key("move_left", [KEY_A, KEY_LEFT])
	_key("move_right", [KEY_D, KEY_RIGHT])
	_key("jump", [KEY_SPACE, KEY_W, KEY_UP])
	_mouse("mine", MOUSE_BUTTON_LEFT)
	_mouse("place", MOUSE_BUTTON_RIGHT)
	for i in 10:
		_key("hotbar_%d" % (i + 1), [KEY_0 if i == 9 else KEY_1 + i])
	_mouse("hotbar_next", MOUSE_BUTTON_WHEEL_DOWN)
	_mouse("hotbar_prev", MOUSE_BUTTON_WHEEL_UP)
	_key("toggle_inventory", [KEY_TAB, KEY_I])


static func _ensure(action: String) -> bool:
	if InputMap.has_action(action):
		return false
	InputMap.add_action(action)
	return true


static func _key(action: String, keys: Array) -> void:
	if not _ensure(action):
		return
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


static func _mouse(action: String, button: int) -> void:
	if not _ensure(action):
		return
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
