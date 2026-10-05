extends Control

const Model = preload("res://scripts/ghost_model.gd")
const MINT = Color("91e2c2")
const GOLD = Color("edc17d")
const INK = Color("10191f")
const MUTED = Color("91a3ab")
const BOARD = Rect2(32, 166, 784, 470)

var model = Model.new()
var paused = true
var show_hint = false
var animation_time = 0.0
var input_clock = 0.0
var cell_size = 56.0
var board_origin = Vector2.ZERO
var font: SystemFont
var start_button: Button
var next_button: Button
var level_buttons: Array = []
var message_label: Label
var hint_label: Label
var render_positions: Dictionary = {}

func _ready() -> void:
	font = SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei", "Noto Sans CJK SC", "Arial"])
	var interface_theme = Theme.new()
	interface_theme.default_font = font
	interface_theme.default_font_size = 16
	theme = interface_theme
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_interface()
	load_level(0)

func _button(caption: String, at: Vector2, dimensions: Vector2, callback: Callable) -> Button:
	var button = Button.new()
	button.text = caption
	button.position = at
	button.size = dimensions
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_color_override("font_color", Color("e7eeeb"))
	for state in ["normal", "hover", "pressed"]:
		var style = StyleBoxFlat.new()
		style.bg_color = Color("283c40") if state == "normal" else Color("3b5956")
		style.border_color = Color("506c65")
		style.set_border_width_all(1)
		style.set_corner_radius_all(8)
		button.add_theme_stylebox_override(state, style)
	button.pressed.connect(callback)
	add_child(button)
	return button

func _build_interface() -> void:
	for index in range(Model.LEVELS.size()):
		level_buttons.append(_button(Model.LEVELS[index]["name"], Vector2(38 + index * 260, 104), Vector2(248, 40), load_level.bind(index)))
	start_button = _button("开始巡游  /  Space", Vector2(866, 34), Vector2(232, 44), toggle_pause)
	_button("重置 / R", Vector2(1110, 34), Vector2(124, 44), restart)
	_slider("move_interval", Vector2(872, 445), 0.18, 1.0, 0.02, model.move_interval)
	_slider("a_turn_delay", Vector2(872, 496), 0.1, 2.0, 0.1, model.a_turn_delay)
	_slider("b_sense_delay", Vector2(872, 547), 0.1, 2.0, 0.1, model.b_sense_delay)
	_slider("b_charge_distance", Vector2(872, 598), 1, 8, 1, model.b_charge_distance)
	_button("查看关卡提示  /  Tab", Vector2(872, 654), Vector2(340, 36), toggle_hint)
	_button("上一关", Vector2(872, 711), Vector2(164, 36), change_level.bind(-1))
	_button("下一关", Vector2(1048, 711), Vector2(164, 36), change_level.bind(1))
	next_button = _button("下一关  →", Vector2(307, 430), Vector2(234, 44), change_level.bind(1))
	next_button.visible = false
	message_label = Label.new()
	message_label.position = Vector2(54, 724)
	message_label.size = Vector2(740, 38)
	message_label.add_theme_color_override("font_color", Color("e2eae6"))
	message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(message_label)
	hint_label = Label.new()
	hint_label.position = Vector2(67, 550)
	hint_label.size = Vector2(715, 88)
	hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint_label.add_theme_font_size_override("font_size", 15)
	hint_label.add_theme_color_override("font_color", Color("e3e9e5"))
	add_child(hint_label)

func _slider(property_name: String, at: Vector2, minimum: float, maximum: float, increment: float, initial: float) -> void:
	var slider = HSlider.new()
	slider.position = at
	slider.size = Vector2(340, 22)
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = increment
	slider.value = initial
	slider.focus_mode = Control.FOCUS_NONE
	slider.value_changed.connect(func(value: float):
		model.set(property_name, int(value) if property_name == "b_charge_distance" else value)
		queue_redraw()
	)
	add_child(slider)

func load_level(index: int) -> void:
	model.load_level(index)
	paused = true
	show_hint = false
	render_positions.clear()
	cell_size = minf(66.0, minf((BOARD.size.x - 30) / model.grid[0].size(), (BOARD.size.y - 48) / model.grid.size()))
	board_origin = BOARD.position + (BOARD.size - Vector2(model.grid[0].size(), model.grid.size()) * cell_size) / 2.0
	for ghost in model.ghosts:
		render_positions[ghost["kind"]] = center(ghost["pos"])
	hint_label.text = Model.LEVELS[model.level_index]["hint"]
	_sync_interface()
	queue_redraw()

func restart() -> void:
	load_level(model.level_index)

func change_level(offset: int) -> void:
	load_level(posmod(model.level_index + offset, Model.LEVELS.size()))

func toggle_pause() -> void:
	if model.won:
		return
	paused = not paused
	_sync_interface()

func toggle_hint() -> void:
	show_hint = not show_hint
	_sync_interface()

func _sync_interface() -> void:
	start_button.text = "开始巡游  /  Space" if paused else "暂停观察  /  Space"
	start_button.disabled = model.won
	next_button.visible = model.won
	next_button.text = "再玩一轮  →" if model.level_index == Model.LEVELS.size() - 1 else "下一关  →"
	hint_label.visible = show_hint and not model.won
	message_label.text = model.last_message
	for index in range(level_buttons.size()):
		level_buttons[index].modulate = MINT if index == model.level_index else Color.WHITE

func _process(delta: float) -> void:
	animation_time += delta
	input_clock -= delta
	if not paused and not model.won:
		model.advance(minf(delta, 0.1))
	if not model.won and input_clock <= 0.0:
		var direction = held_direction()
		if direction >= 0:
			model.move_player(direction)
			input_clock = 0.14
	for ghost in model.ghosts:
		var kind = ghost["kind"]
		render_positions[kind] = render_positions.get(kind, center(ghost["pos"])).lerp(center(ghost["pos"]), minf(1.0, delta * 14))
	_sync_interface()
	queue_redraw()

func held_direction() -> int:
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP): return 0
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT): return 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN): return 2
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT): return 3
	return -1

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_SPACE: toggle_pause()
			KEY_R: restart()
			KEY_TAB: toggle_hint()
			KEY_N: change_level(1)
			KEY_1: load_level(0)
			KEY_2: load_level(1)
			KEY_3: load_level(2)
			KEY_E:
				model.edit_soil(model.player + Model.DIRECTIONS[model.facing], true)
			KEY_Q:
				model.edit_soil(model.player + Model.DIRECTIONS[model.facing], false)
			_:
				var direction = held_direction()
				if direction >= 0 and not model.won:
					model.move_player(direction)
					input_clock = 0.16
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and not model.won:
		var cell = mouse_cell()
		if event.button_index == MOUSE_BUTTON_LEFT:
			model.edit_soil(cell, true)
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			model.edit_soil(cell, false)
		_sync_interface()

func mouse_cell() -> Vector2i:
	var local = (get_local_mouse_position() - board_origin) / cell_size
	return Vector2i(floori(local.x), floori(local.y))

func center(cell: Vector2i) -> Vector2:
	return board_origin + (Vector2(cell) + Vector2(0.5, 0.5)) * cell_size

func text_at(caption: String, at: Vector2, font_size: int = 16, tint: Color = Color("e4ece7"), width: float = -1) -> void:
	draw_string(font, at, caption, HORIZONTAL_ALIGNMENT_LEFT, width, font_size, tint)

func panel(rect: Rect2, tint: Color, radius: int = 12, border: Color = Color("2c3a40")) -> void:
	var style = StyleBoxFlat.new()
	style.bg_color = tint
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	draw_style_box(style, rect)

func _draw() -> void:
	if model.grid.is_empty(): return
	draw_rect(Rect2(Vector2.ZERO, size), Color("10181e"))
	for i in range(42):
		var spark = Vector2(fmod(i * 193.0 + 73, 1280), fmod(i * 113.0 + 91, 820))
		draw_circle(spark, 1.2, Color(0.5, 0.75, 0.64, 0.1 + 0.04 * sin(animation_time + i)))
	text_at("安墓息", Vector2(38, 53), 32, MINT)
	text_at("掘土 · 改路 · 引魂归墓", Vector2(180, 51), 18)
	text_at(Model.LEVELS[model.level_index]["subtitle"], Vector2(38, 83), 15, MUTED)
	panel(BOARD, Color("172329"))
	_draw_map()
	_draw_sensing()
	for ghost in model.ghosts:
		if not ghost["buried"]: _draw_ghost(ghost)
	_draw_keeper()
	_draw_hover()
	text_at("绿色 A / 墓地", Vector2(44, 666), 15, MINT)
	text_at("黄色 B / 墓地", Vector2(212, 666), 15, GOLD)
	text_at("棕色：可挖土块", Vector2(380, 666), 15, Color("c9956d"))
	text_at("灰色：固定石块", Vector2(584, 666), 15, MUTED)
	panel(Rect2(32, 686, 784, 104), Color("1c2c30"))
	text_at("携带土块  %d / 1" % model.soil, Vector2(54, 714), 17, GOLD)
	text_at("已暂停 · 可移动和改土" if paused else "巡游中", Vector2(254, 714), 15, MINT)
	text_at("改土 %d 次" % model.actions, Vector2(636, 714), 15, MUTED)
	text_at("WASD / 方向键移动    左键挖土 · 右键填土    E / Q 操作面前一格", Vector2(54, 776), 14, MUTED)
	_draw_sidebar()
	if show_hint and not model.won:
		panel(Rect2(54, 518, 740, 130), Color(0.09, 0.15, 0.17, 0.97), 10, Color("60766b"))
		text_at("关卡提示 · Tab 收起", Vector2(67, 544), 17, MINT)
	if model.won:
		draw_rect(BOARD, Color(0.04, 0.09, 0.1, 0.76))
		panel(Rect2(194, 294, 460, 206), Color("213936"), 16, MINT)
		text_at("今夜，亡魂已安息", Vector2(270, 350), 26, MINT)
		text_at("用了 %d 次改土 · 观察了 %.1f 秒" % [model.actions, model.elapsed], Vector2(267, 389), 17)

func _draw_map() -> void:
	for y in range(model.grid.size()):
		for x in range(model.grid[y].size()):
			var cell = Vector2i(x, y)
			var rect = Rect2(board_origin + Vector2(cell) * cell_size, Vector2.ONE * cell_size)
			var tile = model.tile(cell)
			if tile == "#":
				draw_rect(rect.grow(-1), Color("303d42"))
				draw_line(rect.position + Vector2(4, 4), rect.position + Vector2(cell_size - 4, 4), Color("455259"), 2)
				if (x + y) % 3 == 0:
					draw_line(rect.position + Vector2(cell_size * 0.56, 5), rect.position + Vector2(cell_size * 0.45, cell_size * 0.52), Color("26343a"), 2)
			else:
				draw_rect(rect.grow(-1), Color("203934") if (x + y) % 2 == 0 else Color("233d37"))
				draw_circle(rect.position + Vector2(cell_size * 0.2, cell_size * 0.7), 1.4, Color("3c5345"))
				if tile == "T":
					panel(rect.grow(-5), Color("865c43"), 5, Color("b78c64"))
					for dot in range(4):
						draw_circle(rect.position + Vector2(0.26 + dot * 0.14, 0.36 + (dot % 2) * 0.22) * cell_size, 2.5, Color("b18c62"))
	for kind in model.graves:
		_draw_grave(center(model.graves[kind]), MINT if kind == "A" else GOLD, kind)

func _draw_grave(at: Vector2, tint: Color, kind: String) -> void:
	var scale = cell_size / 60.0
	draw_circle(at, 24 * scale, Color(tint, 0.08))
	draw_arc(at, 25 * scale, 0, TAU, 32, Color(tint, 0.35), 1.5, true)
	panel(Rect2(at + Vector2(-14, -18) * scale, Vector2(28, 34) * scale), Color("425751"), 7, tint)
	text_at(kind, at + Vector2(-5, 6) * scale, int(18 * scale), tint)
	draw_line(at + Vector2(-18, 19) * scale, at + Vector2(18, 19) * scale, tint, 3)

func _draw_sensing() -> void:
	for ghost in model.ghosts:
		if ghost["kind"] != "B" or ghost["buried"]: continue
		for other in model.ghosts:
			if other["kind"] != "A" or other["buried"]: continue
			if ghost["pos"].x == other["pos"].x or ghost["pos"].y == other["pos"].y:
				draw_dashed_line(center(ghost["pos"]), center(other["pos"]), Color(GOLD, 0.5), 2, 7, true, true)
		if ghost["state"] == "charge":
			var end = ghost["pos"] + Model.DIRECTIONS[ghost["dir"]] * ghost["remaining"]
			draw_dashed_line(center(ghost["pos"]), center(end), Color(GOLD, 0.32), 3, 5, true, true)

func _draw_ghost(ghost: Dictionary) -> void:
	var tint = MINT if ghost["kind"] == "A" else GOLD
	var at: Vector2 = render_positions[ghost["kind"]]
	var scale = cell_size / 64.0
	at.y += sin(animation_time * 3 + (0 if ghost["kind"] == "A" else 1.5)) * 2.5
	draw_circle(at, 27 * scale, Color(tint, 0.07))
	draw_circle(at + Vector2(0, 17) * scale, 16 * scale, Color(0.02, 0.07, 0.07, 0.3))
	draw_circle(at + Vector2(0, -5) * scale, 15 * scale, tint)
	var body = PackedVector2Array()
	for point in [Vector2(-15, -5), Vector2(15, -5), Vector2(15, 15), Vector2(8, 11), Vector2(1, 16), Vector2(-6, 11), Vector2(-15, 15)]:
		body.append(at + point * scale)
	draw_colored_polygon(body, tint)
	draw_circle(at + Vector2(-5, -7) * scale, 2.7 * scale, INK)
	draw_circle(at + Vector2(5, -7) * scale, 2.7 * scale, INK)
	text_at(ghost["kind"], at + Vector2(-5, 9) * scale, int(14 * scale), INK)
	var direction = Vector2(Model.DIRECTIONS[ghost["dir"]])
	var tip = at + direction * 26 * scale
	var side = direction.orthogonal()
	draw_colored_polygon(PackedVector2Array([tip, tip - direction * 8 * scale + side * 4 * scale, tip - direction * 8 * scale - side * 4 * scale]), tint)
	if ghost["state"] in ["turn", "sense"]:
		var duration = model.a_turn_delay if ghost["state"] == "turn" else model.b_sense_delay
		var progress = clampf(1.0 - ghost["wait"] / duration, 0.01, 1.0)
		draw_arc(at, 23 * scale, -PI / 2, -PI / 2 + progress * TAU, 32, tint, 2.5, true)

func _draw_keeper() -> void:
	var at = center(model.player)
	var scale = cell_size / 64.0
	draw_circle(at, 25 * scale, Color(0.8, 0.84, 0.89, 0.09))
	draw_circle(at + Vector2(0, 17) * scale, 16 * scale, Color(0.02, 0.06, 0.06, 0.4))
	panel(Rect2(at + Vector2(-11, -1) * scale, Vector2(22, 25) * scale), Color("7896ac"), 5, Color("a9bfca"))
	draw_circle(at + Vector2(0, -9) * scale, 8 * scale, Color("d6bea0"))
	draw_rect(Rect2(at + Vector2(-12, -17) * scale, Vector2(24, 6) * scale), Color("4d6576"))
	draw_rect(Rect2(at + Vector2(-7, -24) * scale, Vector2(14, 10) * scale), Color("526f80"))
	draw_line(at + Vector2(14, -9) * scale, at + Vector2(19, 16) * scale, Color("bcb395"), 3 * scale)
	draw_circle(at + Vector2(19, 18) * scale, 5 * scale, Color("c5d1d2"))
	var destination = center(model.player + Model.DIRECTIONS[model.facing])
	draw_line(at.lerp(destination, 0.33), at.lerp(destination, 0.49), Color("d8e5e6"), 2)

func _draw_hover() -> void:
	var cell = mouse_cell()
	if cell.x < 0 or cell.y < 0 or cell.x >= model.grid[0].size() or cell.y >= model.grid.size(): return
	var adjacent = absi(cell.x - model.player.x) + absi(cell.y - model.player.y) == 1
	var rect = Rect2(board_origin + Vector2(cell) * cell_size, Vector2.ONE * cell_size)
	draw_rect(rect.grow(-2), Color(MINT if adjacent else MUTED, 0.7), false, 2)
	text_at("%d,%d" % [cell.y + 1, cell.x + 1], rect.position + Vector2(4, cell_size - 5), 11, Color("d0dad4"))

func _draw_sidebar() -> void:
	panel(Rect2(844, 104, 390, 686), Color("1b282e"))
	text_at("亡魂档案", Vector2(872, 145), 22)
	text_at("A  ·  右转的巡游者", Vector2(872, 184), 18, MINT)
	text_at("一直向前。撞墙后等待，再向右转，", Vector2(872, 212), 14, MUTED)
	text_at("直到找到可以前进的方向。", Vector2(872, 234), 14, MUTED)
	var status_a = "本关没有 A"
	var status_b = "本关没有 B"
	for ghost in model.ghosts:
		if ghost["kind"] == "A": status_a = model.ghost_status(ghost)
		else: status_b = model.ghost_status(ghost)
	text_at(status_a, Vector2(872, 261), 16, MINT)
	draw_line(Vector2(872, 280), Vector2(1207, 280), Color("35444a"))
	text_at("B  ·  感应的追随者", Vector2(872, 312), 18, GOLD)
	text_at("同一行 / 列感应 A，墙体不遮挡。", Vector2(872, 340), 14, MUTED)
	text_at("等待后锁定方向走 %d 格；撞墙掉头。" % model.b_charge_distance, Vector2(872, 362), 14, MUTED)
	text_at(status_b, Vector2(872, 389), 16, GOLD)
	text_at("移动间隔                         %.2f 秒" % model.move_interval, Vector2(872, 438), 14)
	text_at("A 撞墙等待                       %.1f 秒" % model.a_turn_delay, Vector2(872, 489), 14)
	text_at("B 感应等待                       %.1f 秒" % model.b_sense_delay, Vector2(872, 540), 14)
	text_at("B 锁定移动                       %d 格" % model.b_charge_distance, Vector2(872, 591), 14)
	text_at("暂停可改土；参数用于后续触发。", Vector2(872, 634), 13, MUTED)
	text_at("1 / 2 / 3 切换关卡 · R 重新开始", Vector2(872, 776), 13, MUTED)
