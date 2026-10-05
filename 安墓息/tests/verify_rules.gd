extends SceneTree

const Model = preload("res://scripts/ghost_model.gd")
var failures = 0
var checks = 0

func expect(condition: bool, description: String) -> void:
	checks += 1
	if not condition:
		failures += 1
		push_error(description)

func tick(model, seconds: float) -> void:
	for i in range(ceili(seconds / 0.02)):
		model.advance(0.02)

func actor(model, kind: String) -> Dictionary:
	for ghost in model.ghosts:
		if ghost["kind"] == kind: return ghost
	return {}

func run_until(model, predicate: Callable, seconds: float = 120.0) -> bool:
	for i in range(ceili(seconds / 0.02)):
		if predicate.call(): return true
		model.advance(0.02)
	return predicate.call()

func _initialize() -> void:
	var model = Model.new()
	model.load_level(0)
	var a = actor(model, "A")
	a["pos"] = Vector2i(4, 1)
	model.advance(model.move_interval)
	expect(a["state"] == "turn" and a["dir"] == 1, "A should wait before rotating")
	tick(model, model.a_turn_delay - 0.1)
	expect(a["dir"] == 1, "A must preserve heading during wait")
	tick(model, 0.12)
	expect(a["dir"] == 3 and a["state"] == "walk", "A should search clockwise for an open tile")

	model.load_level(1)
	a = actor(model, "A")
	var b = actor(model, "B")
	a["pos"] = Vector2i(6, 1)
	expect(model.tile(Vector2i(6, 3)) == "T" and model.sensed_direction(b) == 0, "B must sense A through soil")
	model.advance(0.02)
	expect(b["state"] == "sense" and b["moves"] == 0, "B should wait after sensing")
	a["buried"] = true
	tick(model, model.b_sense_delay + 0.02)
	expect(b["state"] == "charge" and b["remaining"] == 5, "A disappearing must not cancel a committed charge")
	tick(model, model.move_interval + 0.02)
	expect(b["state"] == "walk" and b["dir"] == 2 and b["remaining"] == 0, "Blocked B should cancel charge and reverse")

	model.load_level(2)
	a = actor(model, "A")
	b = actor(model, "B")
	a["pos"] = Vector2i(10, 6)
	b["pos"] = Vector2i(2, 6)
	b["dir"] = 1
	model.advance(0.02)
	a["buried"] = true
	tick(model, model.b_sense_delay + 0.02)
	var start = b["moves"]
	expect(run_until(model, func(): return b["state"] != "charge", 10.0), "B charge should finish")
	expect(b["moves"] - start == 5 and b["pos"] == Vector2i(7, 6), "B must move exactly five tiles without reacquiring")
	b["pos"] = Vector2i(11, 6)
	b["dir"] = 1
	b["state"] = "walk"
	b["clock"] = 0.0
	b["cooldown"] = 10.0
	tick(model, model.move_interval + 0.02)
	expect(b["dir"] == 3 and b["pos"] == Vector2i(11, 6), "Patrolling B reverses instead of turning right")

	model.load_level(0)
	expect(not model.edit_soil(Vector2i(5, 3), true), "Stone cannot be excavated")
	expect(model.edit_soil(Vector2i(5, 1), true) and model.soil == 1, "Digging grants one soil")
	model.grid[3][5] = "T"
	expect(not model.edit_soil(Vector2i(5, 3), true) and model.soil == 1, "Capacity must prevent a second excavation")
	model.load_level(0)
	model.edit_soil(Vector2i(5, 1), true)
	expect(model.edit_soil(Vector2i(5, 1), false) and model.soil == 0, "Filling consumes soil")
	expect(not model.edit_soil(Vector2i(5, 1), false), "Empty inventory prevents filling")

	model.load_level(0)
	model.edit_soil(Vector2i(5, 1), true)
	expect(run_until(model, func(): return model.won), "Level 1 must be solvable")

	model.load_level(1)
	model.move_player(1)
	model.move_player(1)
	model.move_player(2)
	expect(model.edit_soil(Vector2i(6, 3), true), "Level 2 soil must be reachable")
	expect(run_until(model, func(): return actor(model, "B")["buried"]), "Level 2 B should enter its grave")
	model.move_player(0)
	model.move_player(3)
	model.move_player(3)
	expect(run_until(model, func(): return actor(model, "A")["pos"].x == 1), "Level 2 A must revisit the left side")
	expect(model.edit_soil(Vector2i(3, 1), false), "Level 2 redirect soil must be reachable")
	expect(run_until(model, func(): return model.won), "Level 2 must be solvable with one dig and one fill")

	model.load_level(2)
	model.move_player(2)
	expect(model.edit_soil(Vector2i(5, 5), true), "Level 3 soil must be reachable")
	expect(run_until(model, func(): return actor(model, "B")["buried"], 300.0), "Level 3 B should enter its grave after successive senses")
	for i in range(3): model.move_player(1)
	expect(run_until(model, func():
		var ghost = actor(model, "A")
		return ghost["pos"].x == 9 and ghost["pos"].y in [2, 3] and ghost["dir"] == 2
	), "Level 3 A must pass above the redirect")
	expect(model.edit_soil(Vector2i(9, 4), false), "Level 3 redirect soil must be reachable")
	expect(run_until(model, func(): return model.won), "Level 3 must be solvable with one dig and one fill")
	print("RULE CHECKS: %d passed / %d total" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
