extends SceneTree
## Запуск: tools/test.sh [stage1 stage2 ...]
## Каждый файл tests/<stage>_tests.gd содержит метод run(t), где t.check(условие, описание).

const STAGES := ["stage1", "stage2", "stage3", "stage4", "stage5", "stage6"]

var checks := 0
var failures := 0


func check(cond: bool, msg: String) -> void:
	checks += 1
	if cond:
		print("  ok    ", msg)
	else:
		failures += 1
		printerr("  FAIL  ", msg)


func _initialize() -> void:
	var wanted := OS.get_cmdline_user_args()
	for stage in STAGES:
		if not wanted.is_empty() and not wanted.has(stage):
			continue
		print("== ", stage)
		var script: GDScript = load("res://tests/%s_tests.gd" % stage)
		var suite = script.new()
		await suite.run(self)
	print("RESULT: %d проверок, %d провалено" % [checks, failures])
	quit(1 if failures > 0 else 0)
