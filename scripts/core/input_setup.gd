class_name InputSetup
extends RefCounted
## Регистрирует действия ввода в коде, чтобы не зависеть от настроек редактора.


static func register() -> void:
	_key("move_left", [KEY_A, KEY_LEFT])
	_key("move_right", [KEY_D, KEY_RIGHT])
	_key("jump", [KEY_SPACE, KEY_W, KEY_UP])
	_mouse("mine", MOUSE_BUTTON_LEFT)
	_mouse("place", MOUSE_BUTTON_RIGHT)
	for i in 6:
		_key("hotbar_%d" % (i + 1), [KEY_1 + i])
	_mouse("hotbar_next", MOUSE_BUTTON_WHEEL_DOWN)
	_mouse("hotbar_prev", MOUSE_BUTTON_WHEEL_UP)


static func _ensure(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)


static func _key(action: String, keys: Array) -> void:
	_ensure(action)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)


static func _mouse(action: String, button: int) -> void:
	_ensure(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
