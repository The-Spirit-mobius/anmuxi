extends RefCounted

const DIRECTIONS = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const LEVELS = [
	{
		"name": "01 · 一铲归途",
		"subtitle": "挖开土块，观察 A 等待后向右转的习惯。",
		"map": ["#########", "#.A..Ta##", "#####P###", "#########"],
		"hint": "向上挖掉唯一的土块，再开始巡游。A 会沿通道进入绿色墓地。",
	},
	{
		"name": "02 · 先送追随者",
		"subtitle": "B 隔墙感应 A；先送 B，再用挖出的土引导 A。",
		"map": ["#########", "#.A.P...#", "##a###b##", "######T##", "######B.#", "#########"],
		"hint": "从上方走到黄色墓地，向下挖土。等 B 归墓后，返回上方第5列；等 A 回到最左端时暂停，再填住第2行第4列。A 会右转向下归墓。",
	},
	{
		"name": "03 · 墓园回环",
		"subtitle": "A 绕圈巡游，B 锁定方向走 5 格；安排两次感应。",
		"map": ["###############", "#####A....#####", "#####.###.#####", "#####P##a.#####", "#####...b.#####", "#####T#########", "#....B......###", "###############"],
		"hint": "向下走一格，再向下挖土。B 先沿竖道接近 A，再在中间横道感应 A 并向右进入黄色墓地。最后填住第5行第10列，让向下走的 A 右转进入绿色墓地。",
	},
]

var grid: Array = []
var ghosts: Array = []
var graves: Dictionary = {}
var player = Vector2i.ZERO
var facing = 0
var soil = 0
var level_index = 0
var move_interval = 0.42
var a_turn_delay = 0.8
var b_sense_delay = 0.7
var b_charge_distance = 5
var won = false
var actions = 0
var elapsed = 0.0
var last_message = "先观察路线，再开始巡游。"

func load_level(index: int) -> void:
	level_index = clampi(index, 0, LEVELS.size() - 1)
	grid.clear()
	ghosts.clear()
	graves.clear()
	soil = 0
	facing = 0
	won = false
	actions = 0
	elapsed = 0.0
	last_message = "先观察路线，再开始巡游。"
	var rows = LEVELS[level_index]["map"]
	for y in range(rows.size()):
		var row: Array = []
		for x in range(rows[y].length()):
			var symbol = rows[y][x]
			var cell = Vector2i(x, y)
			row.append(symbol if symbol in ["#", "T"] else ".")
			if symbol == "P":
				player = cell
			elif symbol in ["a", "b"]:
				graves[symbol.to_upper()] = cell
			elif symbol in ["A", "B"]:
				ghosts.append(make_ghost(symbol, cell, 1 if symbol == "A" else 3))
		grid.append(row)

func make_ghost(kind: String, cell: Vector2i, direction: int) -> Dictionary:
	return {"kind": kind, "pos": cell, "dir": direction, "clock": 0.0,
		"state": "walk", "wait": 0.0, "remaining": 0, "cooldown": 0.0,
		"buried": false, "moves": 0, "senses": 0}

func tile(cell: Vector2i) -> String:
	if cell.y < 0 or cell.y >= grid.size() or cell.x < 0 or cell.x >= grid[0].size():
		return "#"
	return grid[cell.y][cell.x]

func walkable(cell: Vector2i) -> bool:
	return tile(cell) == "."

func move_player(direction: int) -> bool:
	facing = direction
	var destination = player + DIRECTIONS[direction]
	if not walkable(destination):
		return false
	player = destination
	return true

func edit_soil(cell: Vector2i, digging: bool) -> bool:
	if won:
		return false
	if absi(cell.x - player.x) + absi(cell.y - player.y) != 1:
		last_message = "只能操作身边上下左右的一格。"
		return false
	if digging:
		if tile(cell) != "T":
			last_message = "只有棕色土块可以挖；石块不能改变。"
			return false
		if soil >= 1:
			last_message = "已经携带一块土，先填土再挖。"
			return false
		grid[cell.y][cell.x] = "."
		soil += 1
		last_message = "挖开一格，获得一块土。"
	else:
		if soil < 1:
			last_message = "没有携带土，先挖一块土。"
			return false
		if not walkable(cell) or cell in graves.values():
			last_message = "只能向空地填土，不能覆盖墓地。"
			return false
		for ghost in ghosts:
			if not ghost["buried"] and ghost["pos"] == cell:
				last_message = "鬼魂正在这里，等它离开再填。"
				return false
		grid[cell.y][cell.x] = "T"
		soil -= 1
		last_message = "填上一格，改变通路。"
	actions += 1
	return true

func sensed_direction(ghost: Dictionary) -> int:
	for other in ghosts:
		if other["kind"] != "A" or other["buried"]:
			continue
		var delta: Vector2i = other["pos"] - ghost["pos"]
		if delta == Vector2i.ZERO:
			continue
		if delta.y == 0:
			return 1 if delta.x > 0 else 3
		if delta.x == 0:
			return 2 if delta.y > 0 else 0
	return -1

func advance(delta: float) -> void:
	if won:
		return
	elapsed += delta
	for ghost in ghosts:
		if ghost["buried"]:
			continue
		ghost["cooldown"] = maxf(0.0, ghost["cooldown"] - delta)
		if ghost["state"] == "turn":
			ghost["wait"] -= delta
			if ghost["wait"] <= 0.0:
				for attempt in range(4):
					ghost["dir"] = (ghost["dir"] + 1) % 4
					if walkable(ghost["pos"] + DIRECTIONS[ghost["dir"]]):
						break
				ghost["state"] = "walk"
				ghost["clock"] = 0.0
			continue
		if ghost["state"] == "sense":
			ghost["wait"] -= delta
			if ghost["wait"] <= 0.0:
				ghost["state"] = "charge"
				ghost["remaining"] = b_charge_distance
				ghost["clock"] = 0.0
			continue
		if ghost["kind"] == "B" and ghost["state"] == "walk" and ghost["cooldown"] <= 0.0:
			var detected = sensed_direction(ghost)
			if detected >= 0:
				ghost["dir"] = detected
				ghost["state"] = "sense"
				ghost["wait"] = b_sense_delay
				ghost["senses"] += 1
				continue
		ghost["clock"] += delta
		if ghost["clock"] + 0.000001 < move_interval:
			continue
		ghost["clock"] -= move_interval
		var destination: Vector2i = ghost["pos"] + DIRECTIONS[ghost["dir"]]
		if not walkable(destination):
			if ghost["kind"] == "A":
				ghost["state"] = "turn"
				ghost["wait"] = a_turn_delay
			else:
				ghost["dir"] = (ghost["dir"] + 2) % 4
				ghost["remaining"] = 0
				ghost["state"] = "walk"
				ghost["cooldown"] = move_interval
			continue
		ghost["pos"] = destination
		ghost["moves"] += 1
		if ghost["state"] == "charge":
			ghost["remaining"] -= 1
			if ghost["remaining"] <= 0:
				ghost["state"] = "walk"
				ghost["cooldown"] = move_interval
		if graves.get(ghost["kind"], Vector2i(-1, -1)) == destination:
			ghost["buried"] = true
			ghost["state"] = "buried"
			last_message = "鬼魂 %s 已归墓。" % ghost["kind"]
	won = not ghosts.is_empty()
	for ghost in ghosts:
		if not ghost["buried"]:
			won = false
	if won:
		last_message = "所有亡魂已安息。"

func ghost_status(ghost: Dictionary) -> String:
	match ghost["state"]:
		"buried": return "已安息"
		"turn": return "转向等待 · %.1fs" % maxf(0.0, ghost["wait"])
		"sense": return "感应等待 · %.1fs" % maxf(0.0, ghost["wait"])
		"charge": return "追随中 · 剩余 %d 格" % ghost["remaining"]
	return "向前巡游"
