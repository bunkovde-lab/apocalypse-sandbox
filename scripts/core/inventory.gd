class_name Inventory
extends RefCounted
## Инвентарь: 40 ячеек, первые 10 образуют быструю панель.

signal changed

const SIZE := 40
const HOTBAR := 10

var items := PackedStringArray()
var counts := PackedInt32Array()


func _init() -> void:
	ItemDB.ensure_loaded()
	items.resize(SIZE)
	counts.resize(SIZE)


func slot_item(i: int) -> String:
	return items[i] if counts[i] > 0 else ""


func slot_count(i: int) -> int:
	return counts[i]


func count(item: String) -> int:
	var total := 0
	for i in SIZE:
		if counts[i] > 0 and items[i] == item:
			total += counts[i]
	return total


## Сколько штук предмета ещё поместится.
func room_for(item: String) -> int:
	var m := ItemDB.stack_max(item)
	var room := 0
	for i in SIZE:
		if counts[i] == 0:
			room += m
		elif items[i] == item:
			room += m - counts[i]
	return room


func can_add(item: String, n: int) -> bool:
	return room_for(item) >= n


## Кладёт предметы. Возвращает, сколько не поместилось.
func add(item: String, n: int) -> int:
	var m := ItemDB.stack_max(item)
	var left := n
	for i in SIZE:
		if left == 0:
			break
		if counts[i] > 0 and items[i] == item and counts[i] < m:
			var put := mini(m - counts[i], left)
			counts[i] += put
			left -= put
	for i in SIZE:
		if left == 0:
			break
		if counts[i] == 0:
			var put := mini(m, left)
			items[i] = item
			counts[i] = put
			left -= put
	if left != n:
		changed.emit()
	return left


func remove(item: String, n: int) -> bool:
	if count(item) < n:
		return false
	var left := n
	for i in SIZE:
		if left == 0:
			break
		if counts[i] > 0 and items[i] == item:
			var take := mini(counts[i], left)
			counts[i] -= take
			left -= take
			if counts[i] == 0:
				items[i] = ""
	changed.emit()
	return true


## Меняет ячейки местами; одинаковые предметы сливает в стопку.
func swap(a: int, b: int) -> void:
	if a == b:
		return
	if counts[a] > 0 and counts[b] > 0 and items[a] == items[b]:
		var m := ItemDB.stack_max(items[a])
		var moved := mini(m - counts[b], counts[a])
		counts[b] += moved
		counts[a] -= moved
		if counts[a] == 0:
			items[a] = ""
	else:
		var ti := items[a]
		var tc := counts[a]
		items[a] = items[b]
		counts[a] = counts[b]
		items[b] = ti
		counts[b] = tc
	changed.emit()


func snapshot() -> Dictionary:
	return {"items": items.duplicate(), "counts": counts.duplicate()}


func restore(snap: Dictionary) -> void:
	items = snap["items"].duplicate()
	counts = snap["counts"].duplicate()
	changed.emit()
