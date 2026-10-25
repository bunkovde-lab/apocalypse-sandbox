class_name Stability
extends RefCounted
## Формулы стабильности убежища из ТЗ (раздел 10). Чистые функции, без узлов.
##   K = min(1, (P + R/3) / C)
##   S = 100 * (0.3*K_f + 0.3*K_w + 0.2*K_def + 0.2*K_com)

const PROSPERITY := 3
const NORMAL := 2
const TENSION := 1
const CRISIS := 0


## Коэффициент обеспеченности ресурсом. Если потребления нет, всё в порядке.
static func coverage(production: float, reserve: float, consumption: float) -> float:
	if consumption <= 0.0:
		return 1.0
	return clampf((production + reserve / 3.0) / consumption, 0.0, 1.0)


static func compute(k_food: float, k_water: float, k_def: float, k_com: float) -> float:
	return 100.0 * (Balance.g("weight_food") * k_food + Balance.g("weight_water") * k_water \
		+ Balance.g("weight_def") * k_def + Balance.g("weight_com") * k_com)


static func state_of(s: float) -> int:
	if s >= Balance.g("state_prosperity"):
		return PROSPERITY
	if s >= Balance.g("state_normal"):
		return NORMAL
	if s >= Balance.g("state_tension"):
		return TENSION
	return CRISIS


static func state_title(state: int) -> String:
	match state:
		PROSPERITY: return "процветание"
		NORMAL: return "норма"
		TENSION: return "напряжение"
	return "кризис"


## Множитель работы жителей по состоянию.
static func work_mult(state: int) -> float:
	match state:
		PROSPERITY: return 1.15
		NORMAL: return 1.0
		TENSION: return 0.8
	return 0.0
