extends SceneTree

var checks = 0
var failures = 0

func _initialize() -> void:
	call_deferred("verify")

func expect(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(message)

func key(code: Key, pressed: bool) -> void:
	var event = InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)

func verify() -> void:
	var scene = load("res://scenes/main.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	expect(scene.paused and scene.model.level_index == 0, "Game must open paused on tutorial")
	key(KEY_E, true)
	await process_frame
	key(KEY_E, false)
	await process_frame
	expect(scene.model.soil == 1 and scene.model.tile(Vector2i(5, 1)) == ".", "Keyboard E must reach digging through the input pipeline")
	key(KEY_Q, true)
	await process_frame
	key(KEY_Q, false)
	await process_frame
	expect(scene.model.soil == 0 and scene.model.tile(Vector2i(5, 1)) == "T", "Keyboard Q must fill and consume soil")
	key(KEY_E, true)
	await process_frame
	key(KEY_E, false)
	await process_frame
	key(KEY_SPACE, true)
	await process_frame
	key(KEY_SPACE, false)
	await process_frame
	expect(not scene.paused, "Space must start the simulation")
	await create_timer(2.5).timeout
	expect(scene.model.won and scene.next_button.visible, "Real frame updates should complete tutorial and display next-level button")
	scene.level_buttons[2].pressed.emit()
	await process_frame
	expect(scene.model.level_index == 2 and scene.model.ghosts.size() == 2 and scene.paused, "Level button must load both new ghost types and reset pause")
	key(KEY_R, true)
	await process_frame
	key(KEY_R, false)
	await process_frame
	expect(scene.model.actions == 0 and scene.model.soil == 0 and not scene.model.won, "R must reset inventory and progress")
	print("INPUT CHECKS: %d passed / %d total" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
