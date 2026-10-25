class_name DayClock
extends RefCounted
## Смена дня и ночи. time = доля суток (0 = рассвет). Ночь идёт с 0.62 до 0.94.

signal night_started(night: int)
signal dawn

const DAY_LENGTH := 480.0       # секунд в сутках
const NIGHT_START := 0.62
const NIGHT_END := 0.94
const FADE := 0.05              # длительность сумерек в долях суток
const NIGHT_TINT := Color(0.45, 0.5, 0.72)

var time := 0.1
var day := 1


func is_night() -> bool:
	return time >= NIGHT_START and time < NIGHT_END


func advance(delta: float) -> void:
	var was_night := is_night()
	time += delta / DAY_LENGTH
	if time >= 1.0:
		time -= 1.0
		day += 1
	var now_night := is_night()
	if now_night and not was_night:
		night_started.emit(day)
	elif was_night and not now_night:
		dawn.emit()


## 0 днём, 1 глубокой ночью, плавный переход в сумерках.
func darkness() -> float:
	var dusk := smoothstep(NIGHT_START - FADE, NIGHT_START + FADE, time)
	var morning := 1.0 - smoothstep(NIGHT_END - FADE, NIGHT_END + FADE, time)
	return dusk * morning


func tint() -> Color:
	return Color.WHITE.lerp(NIGHT_TINT, darkness())


## Часы для показа: 0 долей суток = 6:00.
func clock_text() -> String:
	var hours := fmod(6.0 + time * 24.0, 24.0)
	return "%02d:%02d" % [int(hours), int((hours - int(hours)) * 60.0)]
