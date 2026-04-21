extends Node2D

@onready var tile_map: TileMap = $TileMap
@onready var player: Node2D = $Player
@onready var retry_button: Button = $RetryLevel
@onready var new_level_button: Button = $NewLevel
@onready var fake_loading_screen: Sprite2D = $FakeLoadingScreen
@onready var animated_sprite_2d: AnimatedSprite2D = $AnimatedSprite2D
@onready var label: Label = $Label
@export var victory_label: Label
@onready var increase_goals_button: Button = $IncreaseGoals
@onready var decrease_goals_button: Button = $DecreaseGoals
@onready var goals_label: Label = $GoalsLabel
@onready var audio_stream_player: AudioStreamPlayer = $AudioStreamPlayer

var level_complete_triggered := false
var background_track_volume: float = 0.07
var victory_track_volume: float = 0.2

var reverse_cancel := false
var quit_requested := false

const PATTERN_SIZE := 4
var pattern_weights: Array = []

signal on_goal(box)
signal left_goal(box)

var width = 19
var height = 12
var floor_tile_atlas_coords = Vector2i(1,1)
var start = Vector2i(29,13)
var source_id = 0
var wall_tile_atlas_coords = Vector2i(1,0)
var goal_tile = Vector2i(9,9)
var dirs = [
Vector2i(1, 0),
Vector2i(-1, 0),
Vector2i(0, 1),
Vector2i(0, -1)
]
var box_list = []
var reachable_cells: Dictionary = {}
var current_seed: int = 0

@export var box_scene: PackedScene
@export var credit_scene: PackedScene
@export var goal_area_scene: PackedScene

var goal_area_list = []

class State:
	var boxes: Array
	var box_lookup: Dictionary
	var player: Vector2i
	var depth: int

	static func build_box_lookup(box_list: Array) -> Dictionary:
		var lookup := {}
		for cell in box_list:
			lookup[cell] = true
		return lookup

	func _init(b: Array, p: Vector2i, d: int, lookup: Dictionary = {}):
		boxes = b.duplicate()
		box_lookup = lookup.duplicate() if not lookup.is_empty() else State.build_box_lookup(boxes)
		player = p
		depth = d

var samples = []
var patterns = []
var adjacency = {}
const SAVE_PATH := "user://save_file.tres"
var nr_of_goals: SaveData
var layouts: Layouts = load("res://layouts.tres")
var reverse_thread: Thread
var reverse_running := false
var wfc_thread: Thread
var wfc_running := false
var boxes_on_goals: int = 0
var dfs_complete: bool = false


# Called when the node enters the scene tree for the first time.
func _ready() -> void:  
	await get_tree().physics_frame
	randomize()
	BackgroundTrack.volume_linear = background_track_volume
	load_save_data()
	
	current_seed = randi()
	samples = [
	layouts.layout1, layouts.layout2, layouts.layout3, layouts.layout4, layouts.layout5,
	layouts.layout6, layouts.layout7, layouts.layout8]


	var pattern_data = extract_patterns(samples, PATTERN_SIZE)
	patterns = pattern_data["patterns"]
	pattern_weights = pattern_data["weights"]

	print("unique patterns found: ", patterns.size())
	adjacency = build_adjacency(patterns, PATTERN_SIZE)
	
	seed(current_seed)
	generate_level(width, height)
	update_goals_label()

func _process(delta: float) -> void:
	if nr_of_goals == null:
		return

	if boxes_on_goals < 0 or boxes_on_goals > nr_of_goals.goals:
		boxes_on_goals = 0

	if dfs_complete:
		check_level_complete()

func load_save_data() -> void:
	if ResourceLoader.exists(SAVE_PATH):
		nr_of_goals = ResourceLoader.load(SAVE_PATH, "", ResourceLoader.CACHE_MODE_IGNORE) as SaveData

	if nr_of_goals == null:
		nr_of_goals = SaveData.new()
		nr_of_goals.goals = 2
		save_save_data()

	nr_of_goals.goals = clamp(nr_of_goals.goals, 1, 4)

func save_save_data() -> void:
	var err = ResourceSaver.save(nr_of_goals, SAVE_PATH)
	print("save err = ", err)
	print("save path = ", ProjectSettings.globalize_path(SAVE_PATH))

func generate_level(w: int, h: int) -> void:
	if wfc_running or reverse_running:
		return

	level_complete_triggered = false
	set_generation_buttons_enabled(false)
	display_fake_loading_screen(true)
	dfs_complete = false
	victory_label.visible = false
	boxes_on_goals = 0
	width = w
	height = h

	box_list.clear()
	for area in goal_area_list:
		if is_instance_valid(area):
			area.queue_free()
	goal_area_list.clear()
	for child in get_children():
		if child.is_in_group("boxes"):
			child.queue_free()
	tile_map.clear()

	_start_wfc_thread(w, h)


func retry_level() -> void:
	seed(current_seed)
	generate_level(width, height)
	audio_stream_player.stop()
	BackgroundTrack.volume_linear = background_track_volume


func spawn_box(pos: Vector2i):
	var box = box_scene.instantiate()
	var tile_local_pos = tile_map.map_to_local(pos)
	box.position = tile_map.position + tile_local_pos
	box.add_to_group("boxes")
	box.move_back.connect(player._on_box_move_back)
	add_child(box)
	box_list.append(box)
	print("spawned box, position =", box.position)
	print(tile_local_pos)
	print(tile_map.local_to_map(box.position))
	print()

func spawn_goal_area(cell: Vector2i) -> void:
	var area = goal_area_scene.instantiate()
	area.cell = cell
	area.position = grid_to_world_pos(cell)
	area.body_entered.connect(_on_goal_area_body_entered.bind(area, cell))
	area.body_exited.connect(_on_goal_area_body_exited.bind(area, cell))
	add_child(area)
	goal_area_list.append(area)

func _on_goal_area_body_entered(body: Node, area: Area2D, cell: Vector2i) -> void:
	emit_signal("on_goal", body)
	if not dfs_complete:
		return
	boxes_on_goals += 1
	print("box on goal")
	print(boxes_on_goals)

func _on_goal_area_body_exited(body: Node, area: Area2D, cell: Vector2i) -> void:
	emit_signal("left_goal", body)
	if not dfs_complete:
		return
	boxes_on_goals -= 1
	print(boxes_on_goals)


func check_level_complete() -> void:
	var complete = (boxes_on_goals == nr_of_goals.goals)
	victory_label.visible = complete

	if complete and not level_complete_triggered:
		level_complete_triggered = true
		BackgroundTrack.volume_linear = 0.0
		audio_stream_player.play()
		audio_stream_player.volume_linear = background_track_volume


func update_goals_label() -> void:
	goals_label.text = "Boxes: " + str(nr_of_goals.goals)


func is_wall_in_layout(layout: Array, cell: Vector2i) -> bool:
	var local = cell - start
	if local.x < 0 or local.x >= width or local.y < 0 or local.y >= height:
		return true
	return layout[local.y][local.x] == 1

func is_goal_in_layout(layout: Array, cell: Vector2i) -> bool:
	var local = cell - start
	if local.x < 0 or local.x >= width or local.y < 0 or local.y >= height:
		return false
	return layout[local.y][local.x] == 2

func is_deadlock_in_layout_world(layout: Array, cell: Vector2i) -> bool:
	if is_goal_in_layout(layout, cell):
		return false

	var up = is_wall_in_layout(layout, cell + Vector2i(0, -1))
	var down = is_wall_in_layout(layout, cell + Vector2i(0, 1))
	var left = is_wall_in_layout(layout, cell + Vector2i(-1, 0))
	var right = is_wall_in_layout(layout, cell + Vector2i(1, 0))

	if (up or down) and (left or right):
		return true

	if is_next_to_border(cell):
		return true

	return false

func set_generation_buttons_enabled(enabled: bool) -> void:
	retry_button.disabled = not enabled
	new_level_button.disabled = not enabled

func _flood_layout(from: Vector2i, snapshot: Array, ignore_idx: int, layout: Array, box_lookup: Dictionary = {}) -> Dictionary:
	var open: Array = [from]
	var head := 0
	var visited := {}

	while head < open.size():
		if reverse_cancel:
			return {}

		var cur: Vector2i = open[head]
		head += 1

		if visited.has(cur):
			continue
		visited[cur] = true

		for d in dirs:
			if reverse_cancel:
				return {}

			var nxt: Vector2i = cur + d
			if not in_bounds(nxt):
				continue
			if visited.has(nxt):
				continue
			if is_wall_in_layout(layout, nxt):
				continue
			if _snapshot_has_box(nxt, snapshot, ignore_idx, box_lookup):
				continue
			open.append(nxt)

	return visited

func make_state_floods(state: State, layout: Array) -> Array:
	var floods: Array = []
	floods.resize(state.boxes.size())

	for i in range(state.boxes.size()):
		floods[i] = _flood_layout(state.player, state.boxes, i, layout)

	return floods

func make_deadlock_lookup(layout: Array) -> Dictionary:
	var out := {}

	for y in range(height):
		for x in range(width):
			var cell := Vector2i(start.x + x, start.y + y)
			if is_deadlock_in_layout_world(layout, cell):
				out[cell] = true

	return out


func total_reachable_pushes_from_floods(layout: Array, state: State, floods: Array) -> int:
	var total := 0

	for i in range(state.boxes.size()):
		total += count_reachable_pushes_for_box(layout, state.boxes[i], state.boxes, floods[i], i)

	return total


func score_state_from_floods(state: State, goal_cells: Array, layout: Array, floods: Array) -> int:
	var moved_boxes := 0
	var total_distance := 0

	for box_cell in state.boxes:
		var on_goal := false
		var best_dist := 999999

		for goal_cell in goal_cells:
			if box_cell == goal_cell:
				on_goal = true

			var dist = abs(box_cell.x - goal_cell.x) + abs(box_cell.y - goal_cell.y)
			if dist < best_dist:
				best_dist = dist

		if not on_goal:
			moved_boxes += 1

		total_distance += best_dist

	var reachable_pushes := total_reachable_pushes_from_floods(layout, state, floods)
	var edge_penalty := count_edge_boxes(state.boxes)
	var pair_penalty := count_adjacent_box_pairs(state.boxes)

	return (
		state.depth * 10000 +
		moved_boxes * 2000 +
		total_distance * 100 +
		reachable_pushes * 250 -
		edge_penalty * 250 -
		pair_penalty * 200
	)

func _canonical_player_cell_layout(player_cell: Vector2i, boxes: Array, layout: Array, box_lookup: Dictionary = {}) -> Vector2i:
	var flood = _flood_layout(player_cell, boxes, -1, layout, box_lookup)
	var best = Vector2i(999999, 999999)

	for cell in flood.keys():
		if cell.x < best.x or (cell.x == best.x and cell.y < best.y):
			best = cell

	return best

func _state_key_layout(boxes: Array, player_cell: Vector2i, layout: Array, box_lookup: Dictionary = {}) -> String:
	var sorted = boxes.duplicate()
	sorted.sort_custom(func(a, b): return str(a) < str(b))

	var canonical_player = _canonical_player_cell_layout(player_cell, boxes, layout, box_lookup)

	var s = str(canonical_player)
	for box in sorted:
		s += str(box)
	return s

func _cell_id(cell: Vector2i) -> int:
	var local = cell - start
	return local.y * width + local.x

func _dfs_generate_full_thread(
	initial_boxes: Array,
	initial_player: Vector2i,
	layout: Array,
	reachable_lookup: Dictionary,
	max_depth: int,
	max_nodes: int = 5000
) -> Dictionary:
	var start_state = State.new(initial_boxes, initial_player, 0)
	var stack: Array = [start_state]
	var visited: Dictionary = {}
	visited[_state_key_layout(start_state.boxes, start_state.player, layout, start_state.box_lookup)] = true

	var goal_cells = initial_boxes.duplicate()
	var best: State = start_state
	var best_score := score_state(start_state, goal_cells, layout)

	var nodes_expanded := 0

	while stack.size() > 0:
		if reverse_cancel:
			return {"cancelled": true}

		var state: State = stack.pop_back()
		nodes_expanded += 1

		var current_score = score_state(state, goal_cells, layout)
		if current_score > best_score:
			best = state
			best_score = current_score

		if state.depth >= max_depth:
			continue

		if nodes_expanded >= max_nodes:
			break

		var box_indices: Array = []
		for i in range(state.boxes.size()):
			box_indices.append(i)
		box_indices.shuffle()

		for box_idx in box_indices:
			if reverse_cancel:
				return {"cancelled": true}

			var box_cell: Vector2i = state.boxes[box_idx]
			var flood = _flood_layout(state.player, state.boxes, box_idx, layout, state.box_lookup)

			if reverse_cancel:
				return {"cancelled": true}

			var dir_list = dirs.duplicate()
			dir_list.shuffle()

			for dir in dir_list:
				if reverse_cancel:
					return {"cancelled": true}

				var new_box: Vector2i = box_cell + dir
				var req_player: Vector2i = box_cell - dir

				if not in_bounds(new_box):
					continue
				if not in_bounds(req_player):
					continue

				if is_wall_in_layout(layout, new_box):
					continue
				if is_wall_in_layout(layout, req_player):
					continue

				if _snapshot_has_box(new_box, state.boxes, box_idx, state.box_lookup):
					continue
				if _snapshot_has_box(req_player, state.boxes, box_idx, state.box_lookup):
					continue

				if is_deadlock_in_layout_world(layout, new_box):
					continue

				var local_new_box = new_box - start
				if not reachable_lookup.has(local_new_box):
					continue

				if not flood.has(req_player):
					continue

				var new_boxes = state.boxes.duplicate()
				new_boxes[box_idx] = new_box
				var new_lookup = _move_box_lookup(state.box_lookup, box_cell, new_box)

				if creates_2x2_lock(layout, new_boxes, new_box, new_lookup):
					continue

				var next_player: Vector2i = box_cell
				var next_flood = _flood_layout(next_player, new_boxes, box_idx, layout, new_lookup)

				if reverse_cancel:
					return {"cancelled": true}

				if not has_reachable_box_push(layout, new_box, new_boxes, next_flood, box_idx, new_lookup):
					continue

				var next_state = State.new(new_boxes, next_player, state.depth + 1, new_lookup)
				var k = _state_key_layout(next_state.boxes, next_state.player, layout, next_state.box_lookup)

				if visited.has(k):
					continue

				visited[k] = true
				stack.push_back(next_state)

	if reverse_cancel:
		return {"cancelled": true}

	var final_spawn = find_best_player_spawn(layout, best.boxes, best.player, best.box_lookup)

	return {
		"boxes": best.boxes,
		"player": best.player,
		"spawn_player": final_spawn,
		"depth": best.depth,
		"score": best_score,
		"cancelled": false
	}


func _start_wfc_thread(w: int, h: int, max_attempts: int = 100) -> void:
	if wfc_running or reverse_running:
		return

	reverse_cancel = false
	quit_requested = false
	wfc_running = true
	wfc_thread = Thread.new()
	wfc_thread.start(
		_thread_wfc_job.bind(
			w,
			h,
			patterns.duplicate(true),
			adjacency.duplicate(true),
			pattern_weights.duplicate(true),
			nr_of_goals.goals,
			max_attempts
		)
	)

func _thread_wfc_job(
	w: int,
	h: int,
	patterns_snapshot: Array,
	adjacency_snapshot: Dictionary,
	weights_snapshot: Array,
	goal_count: int,
	max_attempts: int
) -> void:
	var result = _generate_layout_thread(
		w,
		h,
		patterns_snapshot,
		adjacency_snapshot,
		weights_snapshot,
		goal_count,
		max_attempts
	)
	call_deferred("_apply_wfc_result", result)

func _generate_layout_thread(
	w: int,
	h: int,
	patterns_snapshot: Array,
	adjacency_snapshot: Dictionary,
	weights_snapshot: Array,
	goal_count: int,
	max_attempts: int = 100
) -> Dictionary:
	var attempts := 0
	var inner_w: int = max(1, w - 2)
	var inner_h: int = max(1, h - 2)

	while attempts < max_attempts:
		if reverse_cancel:
			return {"cancelled": true}

		attempts += 1

		var inner_layout = run_wfc(inner_w, inner_h, patterns_snapshot, adjacency_snapshot, weights_snapshot)
		if reverse_cancel:
			return {"cancelled": true}
		if inner_layout.is_empty():
			continue

		var layout = add_border(inner_layout)
		if reverse_cancel:
			return {"cancelled": true}
		if not is_layout_connected(layout):
			continue

		layout = place_goals(layout, goal_count)
		if reverse_cancel:
			return {"cancelled": true}
		if layout.is_empty():
			continue

		var reachable = compute_reachable_cells(layout)
		if reverse_cancel:
			return {"cancelled": true}
		if reachable.is_empty():
			continue

		return {
			"cancelled": false,
			"layout": layout,
			"reachable": reachable,
			"attempts": attempts
		}

	return {
		"cancelled": false,
		"layout": [],
		"reachable": {},
		"attempts": attempts
	}

func _apply_wfc_result(result: Dictionary) -> void:
	wfc_running = false

	if wfc_thread:
		wfc_thread.wait_to_finish()
		wfc_thread = null

	if result.get("cancelled", false):
		display_fake_loading_screen(false)
		set_generation_buttons_enabled(true)

		if quit_requested:
			get_tree().quit()
		return

	if quit_requested:
		display_fake_loading_screen(false)
		set_generation_buttons_enabled(true)
		get_tree().quit()
		return

	var layout: Array = result.get("layout", [])
	if layout.is_empty():
		push_error("Failed to generate a valid level after %d attempts" % int(result.get("attempts", 0)))
		display_fake_loading_screen(false)
		set_generation_buttons_enabled(true)
		return

	reachable_cells = result["reachable"]

	for y in range(height):
		for x in range(width):
			var tile_coords = Vector2i(start.x + x, start.y + y)

			match layout[y][x]:
				0:
					tile_map.set_cell(0, tile_coords, source_id, floor_tile_atlas_coords)
				1:
					tile_map.set_cell(0, tile_coords, source_id, wall_tile_atlas_coords)
				2:
					tile_map.set_cell(0, tile_coords, source_id, goal_tile)
					spawn_box(tile_coords)
					spawn_goal_area(tile_coords)

	place_player()
	_start_reverse_thread(layout.duplicate(true))

func _start_reverse_thread(layout: Array, max_depth: int = 20, max_nodes: int = 5000) -> void:
	if reverse_running:
		return

	var box_snapshot: Array = []
	for b in box_list:
		box_snapshot.append(world_to_grid(b.position))

	var player_cell: Vector2i = world_to_grid(player.position)
	var reachable_snapshot: Dictionary = reachable_cells.duplicate(true)

	reverse_cancel = false
	quit_requested = false
	reverse_running = true
	reverse_thread = Thread.new()
	reverse_thread.start(
		_thread_reverse_job.bind(
			box_snapshot,
			player_cell,
			layout.duplicate(true),
			reachable_snapshot,
			max_depth,
			max_nodes
		)
	)

func _thread_reverse_job(
	box_snapshot: Array,
	player_cell: Vector2i,
	layout: Array,
	reachable_lookup: Dictionary,
	max_depth: int,
	max_nodes: int
) -> void:
	var result = _dfs_generate_full_thread(
		box_snapshot,
		player_cell,
		layout,
		reachable_lookup,
		max_depth,
		max_nodes
	)
	call_deferred("_apply_reverse_result", result)

func _apply_reverse_result(result: Dictionary) -> void:
	reverse_running = false

	if reverse_thread:
		reverse_thread.wait_to_finish()
		reverse_thread = null

	if result.get("cancelled", false):
		display_fake_loading_screen(false)
		set_generation_buttons_enabled(true)

		if quit_requested:
			get_tree().quit()
		return

	if quit_requested:
		display_fake_loading_screen(false)
		set_generation_buttons_enabled(true)
		get_tree().quit()
		return

	for i in range(box_list.size()):
		box_list[i].position = grid_to_world_pos(result["boxes"][i])

	player.position = grid_to_world_pos(result["spawn_player"])
	player.position = player.position.round()

	boxes_on_goals = 0
	dfs_complete = true
	check_level_complete()

	print("final reverse depth = ", result["depth"])
	print("final score = ", result["score"])

	display_fake_loading_screen(false)
	set_generation_buttons_enabled(true)

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		if wfc_running or reverse_running:
			reverse_cancel = true
			quit_requested = true
			return

		get_tree().quit()

func _exit_tree() -> void:
	reverse_cancel = true

	if wfc_thread:
		wfc_thread.wait_to_finish()
		wfc_thread = null

	if reverse_thread:
		reverse_thread.wait_to_finish()
		reverse_thread = null

func world_to_grid(pos: Vector2) -> Vector2i:
	return tile_map.local_to_map(pos - tile_map.position)

func grid_to_world_pos(cell: Vector2i) -> Vector2:
	return tile_map.position + tile_map.map_to_local(cell)

func is_wall(cell: Vector2i) -> bool:
	var data = tile_map.get_cell_atlas_coords(0, cell)
	return data == wall_tile_atlas_coords


func is_box_at(cell: Vector2i, ignore_box = null) -> bool:
	for box in box_list:
		if box == ignore_box:
			continue
		if world_to_grid(box.position) == cell:
			return true
	return false


func is_next_to_border(cell: Vector2i) -> bool:
	return (
		cell.x == start.x + 1 or
		cell.x == start.x + width - 2 or
		cell.y == start.y + 1 or
		cell.y == start.y + height - 2
	)



func place_player():
	for y in range(height):
		for x in range(width):
			var cell = Vector2i(start.x + x, start.y + y)
			if is_wall(cell):
				continue
			if is_box_at(cell):
				continue
			player.position = grid_to_world_pos(cell)
			player.position = player.position.round()
			return


## Checks whether a grid cell lies within the playable level area.
## Returns true if the cell is inside the level bounds, otherwise false.
func in_bounds(cell: Vector2i) -> bool:
	# The function returns the result of all these conditions combined.
	# Every condition must be true for the cell to be considered inside the map.
	return (
	# Check that the cell's x coordinate is not left of the level start
	cell.x >= start.x and
	# Check that the cell's x coordinate is not past the right edge
	# (start.x + width defines the right boundary of the level)
	cell.x < start.x + width and
	# Check that the cell's y coordinate is not above the level start
	cell.y >= start.y and
	# Check that the cell's y coordinate is not past the bottom edge
	cell.y < start.y + height
	)

func _snapshot_has_box(cell: Vector2i, snapshot: Array, ignore_idx: int, box_lookup: Dictionary = {}) -> bool:
	if not box_lookup.is_empty():
		if ignore_idx >= 0 and ignore_idx < snapshot.size() and snapshot[ignore_idx] == cell:
			return false
		return box_lookup.has(cell)

	for i in range(snapshot.size()):
		if i == ignore_idx:
			continue
		if snapshot[i] == cell:
			return true
	return false


func is_layout_connected(layout: Array) -> bool:
	var start_cell = Vector2i(-1, -1)
	var floor_count = 0

	for y in range(height):
		if reverse_cancel:
			return false

		for x in range(width):
			if layout[y][x] == 0:
				floor_count += 1
				if start_cell == Vector2i(-1, -1):
					start_cell = Vector2i(x, y)

	if floor_count == 0:
		return false

	var open = [start_cell]
	var visited = {}
	while open.size() > 0:
		if reverse_cancel:
			return false

		var cur = open.pop_front()
		if visited.has(cur):
			continue
		visited[cur] = true
		for d in dirs:
			if reverse_cancel:
				return false

			var nxt = cur + d
			if nxt.x < 0 or nxt.x >= width or nxt.y < 0 or nxt.y >= height:
				continue
			if visited.has(nxt):
				continue
			if layout[nxt.y][nxt.x] == 1:
				continue
			open.append(nxt)
	return visited.size() == floor_count

func place_goals(layout: Array, num_goals: int) -> Array:
	var floor_count: int = count_floor_cells(layout)
	var candidates: Array = []
	var min_reach: int = max(8, int(floor_count * 0.18))

	for y in range(height):
		if reverse_cancel:
			return []

		for x in range(width):
			if reverse_cancel:
				return []

			var cell := Vector2i(x, y)

			if not is_valid_goal_cell(layout, cell):
				continue

			var info: Dictionary = score_goal_cell(layout, cell)
			if reverse_cancel:
				return []

			if info["reach_size"] < min_reach:
				continue

			candidates.append(info)

	print("floor_count = ", floor_count)
	print("goal candidates = ", candidates.size())

	if candidates.size() < num_goals:
		return []

	candidates.shuffle()
	candidates.sort_custom(func(a, b): return a["score"] > b["score"])

	var top_n: int = min(10, candidates.size())
	var seed_index: int = randi() % top_n
	var seed: Dictionary = candidates[seed_index]

	var seed_cell: Vector2i = seed["cell"]
	var core: Dictionary = seed["reach"]

	layout[seed_cell.y][seed_cell.x] = 2

	var goals_placed: int = 1
	var placed_goals: Array = [seed_cell]

	var pool: Array = []
	for item in candidates:
		if reverse_cancel:
			return []

		var item_cell: Vector2i = item["cell"]

		if item_cell == seed_cell:
			continue

		if core.has(item_cell):
			pool.append(item)

	pool.shuffle()
	pool.sort_custom(func(a, b): return a["score"] > b["score"])

	for item in pool:
		if reverse_cancel:
			return []

		if goals_placed >= num_goals:
			break

		var cell: Vector2i = item["cell"]

		if has_adjacent_goal(layout, cell):
			continue

		if not goal_has_spacing(placed_goals, cell, 3):
			continue

		layout[cell.y][cell.x] = 2
		placed_goals.append(cell)
		goals_placed += 1

	if goals_placed < num_goals:
		return []

	return layout



func extract_patterns(layouts: Array, pattern_size: int) -> Dictionary:
	var patterns: Array = []
	var weights: Array = []
	var pattern_index := {}

	for layout in layouts:
		for y in range(layout.size() - pattern_size + 1):
			for x in range(layout[0].size() - pattern_size + 1):
				var pattern: Array = []

				for dy in range(pattern_size):
					var row: Array = []
					for dx in range(pattern_size):
						row.append(layout[y + dy][x + dx])
					pattern.append(row)

				var key := JSON.stringify(pattern)

				if pattern_index.has(key):
					var idx: int = pattern_index[key]
					weights[idx] += 1
				else:
					var new_idx := patterns.size()
					pattern_index[key] = new_idx
					patterns.append(pattern)
					weights.append(1)

	return {
		"patterns": patterns,
		"weights": weights
	}

func build_adjacency(patterns: Array, pattern_size: int) -> Dictionary:
	var adjacency = {}
	for i in range(patterns.size()):
		adjacency[i] = {
			"right": [],
			"left": [],
			"down": [],
			"up": []
		}
	for i in range(patterns.size()):
		for j in range(patterns.size()):
			# check right/left compatibility
			var h_match = true
			for dy in range(pattern_size):
				for dx in range(pattern_size - 1):
					if patterns[i][dy][dx + 1] != patterns[j][dy][dx]:
						h_match = false
						break
			if h_match:
				adjacency[i]["right"].append(j)
				adjacency[j]["left"].append(i)
			# check up/down compatibility
			var v_match = true
			for dy in range(pattern_size - 1):
				for dx in range(pattern_size):
					if patterns[i][dy + 1][dx] != patterns[j][dy][dx]:
						v_match = false
						break
			if v_match:
				adjacency[i]["down"].append(j)
				adjacency[j]["up"].append(i)
				
	return adjacency

func init_wfc(w: int, h: int, num_patterns: int) -> Array:
	var wfc_grid = []
	for y in range(h):
		var row = []
		for x in range(w):
			var candidates = []
			for i in range(num_patterns):
				candidates.append(i)
			row.append(candidates)
		wfc_grid.append(row)
	return wfc_grid

func weighted_random_choice(candidates: Array, weights: Array) -> int:
	var total := 0.0

	for pattern_idx in candidates:
		total += float(weights[pattern_idx])

	if total <= 0.0:
		return candidates[randi() % candidates.size()]

	var roll := randf() * total
	var running := 0.0

	for pattern_idx in candidates:
		running += float(weights[pattern_idx])
		if roll <= running:
			return pattern_idx

	return candidates[candidates.size() - 1]

func cell_entropy(candidates: Array, weights: Array) -> float:
	var sum_w := 0.0
	var sum_w_log_w := 0.0

	for pattern_idx in candidates:
		var w := float(weights[pattern_idx])
		if w <= 0.0:
			continue
		sum_w += w
		sum_w_log_w += w * log(w)

	if sum_w <= 0.0:
		return 0.0

	return log(sum_w) - (sum_w_log_w / sum_w)

func get_lowest_entropy_cell(wfc_grid: Array, weights: Array) -> Vector2i:
	var best_entropy := 1.0e20
	var best_cell := Vector2i(-1, -1)

	for y in range(wfc_grid.size()):
		for x in range(wfc_grid[y].size()):
			var candidates: Array = wfc_grid[y][x]

			if candidates.size() <= 1:
				continue

			var entropy := cell_entropy(candidates, weights)
			entropy += randf() * 0.000001

			if entropy < best_entropy:
				best_entropy = entropy
				best_cell = Vector2i(x, y)

	return best_cell

func collapse_cell(wfc_grid: Array, cell: Vector2i, weights: Array) -> void:
	var candidates: Array = wfc_grid[cell.y][cell.x]
	var chosen := weighted_random_choice(candidates, weights)
	wfc_grid[cell.y][cell.x] = [chosen]

func propagate(wfc_grid: Array, adjacency: Dictionary, start_cell: Vector2i) -> bool:
	var stack = [start_cell]

	while stack.size() > 0:
		if reverse_cancel:
			return false

		var cell: Vector2i = stack.pop_back()

		var neighbours = [
			[Vector2i(cell.x + 1, cell.y), "right"],
			[Vector2i(cell.x - 1, cell.y), "left"],
			[Vector2i(cell.x, cell.y + 1), "down"],
			[Vector2i(cell.x, cell.y - 1), "up"]
		]

		for entry in neighbours:
			if reverse_cancel:
				return false

			var neighbour: Vector2i = entry[0]
			var dir: String = entry[1]

			if neighbour.x < 0 or neighbour.x >= wfc_grid[0].size():
				continue
			if neighbour.y < 0 or neighbour.y >= wfc_grid.size():
				continue

			var neighbour_candidates: Array = wfc_grid[neighbour.y][neighbour.x]

			var allowed := {}
			for pattern_idx in wfc_grid[cell.y][cell.x]:
				for allowed_idx in adjacency[pattern_idx][dir]:
					allowed[allowed_idx] = true

			var new_candidates: Array = []
			for candidate in neighbour_candidates:
				if allowed.has(candidate):
					new_candidates.append(candidate)

			if new_candidates.is_empty():
				return false

			if new_candidates.size() != neighbour_candidates.size():
				wfc_grid[neighbour.y][neighbour.x] = new_candidates
				stack.push_back(neighbour)

	return true

func run_wfc(
	w: int,
	h: int,
	patterns: Array,
	adjacency: Dictionary,
	weights: Array,
	max_restarts: int = 32
) -> Array:
	for attempt in range(max_restarts):
		if reverse_cancel:
			return []

		var wfc_grid = init_wfc(w, h, patterns.size())
		var failed := false

		while true:
			if reverse_cancel:
				return []

			var cell = get_lowest_entropy_cell(wfc_grid, weights)

			if cell == Vector2i(-1, -1):
				var layout: Array = []

				for y in range(h):
					var row: Array = []
					for x in range(w):
						var pattern_idx: int = wfc_grid[y][x][0]
						row.append(patterns[pattern_idx][0][0])
					layout.append(row)

				return layout

			collapse_cell(wfc_grid, cell, weights)

			if not propagate(wfc_grid, adjacency, cell):
				if reverse_cancel:
					return []
				failed = true
				break

		if failed:
			continue

	return []

func compute_reachable_cells(layout: Array) -> Dictionary:
	var reachable = {}
	# start with all goal tiles
	for y in range(height):
		if reverse_cancel:
			return {}

		for x in range(width):
			if layout[y][x] == 2:
				reachable[Vector2i(x, y)] = true
	# keep expanding until no new cells are added
	var changed = true
	while changed:
		if reverse_cancel:
			return {}

		changed = false
		for cell in reachable.keys():
			if reverse_cancel:
				return {}

			for d in dirs:
				if reverse_cancel:
					return {}

				# pull direction: box moves from cell to cell + d
				# player must be on cell - d to pull
				var new_box = cell + d
				var player_pos = cell - d
				if new_box.x < 0 or new_box.x >= width or new_box.y < 0 or new_box.y >= height:
					continue
				if player_pos.x < 0 or player_pos.x >= width or player_pos.y < 0 or player_pos.y >= height:
					continue
				if layout[new_box.y][new_box.x] == 1:
					continue
				if layout[player_pos.y][player_pos.x] == 1:
					continue
				if not reachable.has(new_box):
					reachable[new_box] = true
					changed = true
	return reachable

func add_border(inner_layout: Array) -> Array:
	var full_layout: Array = []

	for y in range(height):
		var row: Array = []

		for x in range(width):
			if x == 0 or x == width - 1 or y == 0 or y == height - 1:
				row.append(1)
			else:
				row.append(inner_layout[y - 1][x - 1])

		full_layout.append(row)

	return full_layout

func count_floor_cells(layout: Array) -> int:
	var count = 0
	for y in range(height):
		for x in range(width):
			if layout[y][x] != 1:
				count += 1
	return count

func has_adjacent_goal(layout: Array, cell: Vector2i) -> bool:
	for d in dirs:
		var n = cell + d
		if n.x < 0 or n.x >= width or n.y < 0 or n.y >= height:
			continue
		if layout[n.y][n.x] == 2:
			return true
	return false



func score_goal_cell(layout: Array, cell: Vector2i) -> Dictionary:
	var temp: Array = layout.duplicate(true)
	temp[cell.y][cell.x] = 2

	var reach: Dictionary = compute_reachable_cells(temp)
	var lane_count: int = count_goal_push_lanes(layout, cell)
	var open4: int = count_open_neighbors4(layout, cell)
	var open9: int = count_open_tiles_3x3(layout, cell)
	var corridor: bool = is_straight_corridor_cell(layout, cell)

	var score: int = 0
	score += reach.size() * 10
	score += lane_count * 25
	score += open4 * 20
	score += open9 * 3

	if lane_count >= 2:
		score += 25

	if open9 >= 7:
		score += 20

	if corridor:
		score -= 40

	return {
		"cell": cell,
		"score": score,
		"reach": reach,
		"reach_size": reach.size(),
		"lane_count": lane_count,
		"open4": open4,
		"open9": open9,
		"corridor": corridor
	}


func score_state(state: State, goal_cells: Array, layout: Array) -> int:
	var moved_boxes := 0
	var total_distance := 0

	for box_cell in state.boxes:
		var on_goal = false
		var best_dist = 999999

		for goal_cell in goal_cells:
			if box_cell == goal_cell:
				on_goal = true

			var dist = abs(box_cell.x - goal_cell.x) + abs(box_cell.y - goal_cell.y)
			if dist < best_dist:
				best_dist = dist

		if not on_goal:
			moved_boxes += 1

		total_distance += best_dist

	var reachable_pushes := total_reachable_pushes(layout, state)
	var edge_penalty := count_edge_boxes(state.boxes)
	var pair_penalty := count_adjacent_box_pairs(state.boxes)

	return (
		state.depth * 10000 +
		moved_boxes * 2000 +
		total_distance * 100 +
		reachable_pushes * 250 -
		edge_penalty * 250 -
		pair_penalty * 200
	)

func is_open_layout_cell(layout: Array, cell: Vector2i) -> bool:
	return (
		cell.x >= 0 and cell.x < width and
		cell.y >= 0 and cell.y < height and
		layout[cell.y][cell.x] != 1
	)

func count_goal_push_lanes(layout: Array, goal: Vector2i) -> int:
	var count: int = 0

	for d in dirs:
		var box_from: Vector2i = goal - d
		var player_from: Vector2i = goal - Vector2i(d.x * 2, d.y * 2)

		if is_open_layout_cell(layout, box_from) and is_open_layout_cell(layout, player_from):
			count += 1

	return count


func count_open_neighbors4(layout: Array, cell: Vector2i) -> int:
	var count: int = 0

	for d in dirs:
		var n: Vector2i = cell + d
		if is_open_layout_cell(layout, n):
			count += 1

	return count


func count_open_tiles_3x3(layout: Array, cell: Vector2i) -> int:
	var count: int = 0

	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var n := Vector2i(cell.x + dx, cell.y + dy)
			if is_open_layout_cell(layout, n):
				count += 1

	return count


func is_straight_corridor_cell(layout: Array, cell: Vector2i) -> bool:
	var left_open: bool = is_open_layout_cell(layout, cell + Vector2i(-1, 0))
	var right_open: bool = is_open_layout_cell(layout, cell + Vector2i(1, 0))
	var up_open: bool = is_open_layout_cell(layout, cell + Vector2i(0, -1))
	var down_open: bool = is_open_layout_cell(layout, cell + Vector2i(0, 1))

	var horizontal_corridor: bool = left_open and right_open and not up_open and not down_open
	var vertical_corridor: bool = up_open and down_open and not left_open and not right_open

	return horizontal_corridor or vertical_corridor


func goal_has_spacing(placed_goals: Array, cell: Vector2i, min_dist: int = 3) -> bool:
	for existing in placed_goals:
		var goal_cell: Vector2i = existing
		var dist: int = abs(goal_cell.x - cell.x) + abs(goal_cell.y - cell.y)
		if dist < min_dist:
			return false

	return true

func has_goal_push_lane(layout: Array, goal: Vector2i) -> bool:
	return count_goal_push_lanes(layout, goal) > 0

func is_valid_goal_cell(layout: Array, cell: Vector2i) -> bool:
	if layout[cell.y][cell.x] != 0:
		return false

	if has_adjacent_goal(layout, cell):
		return false

	var lane_count: int = count_goal_push_lanes(layout, cell)
	if lane_count == 0:
		return false

	var open4: int = count_open_neighbors4(layout, cell)
	if open4 < 2:
		return false

	var open9: int = count_open_tiles_3x3(layout, cell)
	if open9 < 5:
		return false

	if is_straight_corridor_cell(layout, cell):
		return false

	if lane_count < 2 and open9 < 6:
		return false

	return true

func count_box_pushes(layout: Array, box_cell: Vector2i, boxes: Array, ignore_idx: int = -1) -> int:
	var count := 0

	for dir in dirs:
		var next_box = box_cell + dir
		var need_player = box_cell - dir

		if not in_bounds(next_box):
			continue
		if not in_bounds(need_player):
			continue

		if is_wall_in_layout(layout, next_box):
			continue
		if is_wall_in_layout(layout, need_player):
			continue

		if _snapshot_has_box(next_box, boxes, ignore_idx):
			continue
		if _snapshot_has_box(need_player, boxes, ignore_idx):
			continue

		count += 1

	return count


func has_good_box_mobility(layout: Array, box_cell: Vector2i, boxes: Array, ignore_idx: int = -1) -> bool:
	return count_box_pushes(layout, box_cell, boxes, ignore_idx) >= 1


func is_blocked_cell(layout: Array, cell: Vector2i, boxes: Array, box_lookup: Dictionary = {}) -> bool:
	if not in_bounds(cell):
		return true
	if is_wall_in_layout(layout, cell):
		return true
	if _snapshot_has_box(cell, boxes, -1, box_lookup):
		return true
	return false


func creates_2x2_lock(layout: Array, boxes: Array, moved_box: Vector2i, box_lookup: Dictionary = {}) -> bool:
	var offsets = [
		Vector2i(0, 0),
		Vector2i(-1, 0),
		Vector2i(0, -1),
		Vector2i(-1, -1)
	]

	for off in offsets:
		var c1 = moved_box + off
		var c2 = c1 + Vector2i(1, 0)
		var c3 = c1 + Vector2i(0, 1)
		var c4 = c1 + Vector2i(1, 1)

		var cells = [c1, c2, c3, c4]
		var blocked := 0
		var box_count := 0
		var has_non_goal_box := false

		for cell in cells:
			if is_blocked_cell(layout, cell, boxes, box_lookup):
				blocked += 1

			if _snapshot_has_box(cell, boxes, -1, box_lookup):
				box_count += 1
				if not is_goal_in_layout(layout, cell):
					has_non_goal_box = true

		if blocked == 4 and box_count >= 2 and has_non_goal_box:
			return true

	return false


func count_edge_boxes(boxes: Array) -> int:
	var total := 0

	for cell in boxes:
		if is_next_to_border(cell):
			total += 1

	return total


func count_adjacent_box_pairs(boxes: Array) -> int:
	var total := 0

	for i in range(boxes.size()):
		for j in range(i + 1, boxes.size()):
			var a: Vector2i = boxes[i]
			var b: Vector2i = boxes[j]

			if abs(a.x - b.x) + abs(a.y - b.y) == 1:
				total += 1

	return total


func total_box_mobility(layout: Array, boxes: Array) -> int:
	var total := 0

	for i in range(boxes.size()):
		total += count_box_pushes(layout, boxes[i], boxes, i)

	return total

func count_reachable_pushes_for_box(
	layout: Array,
	box_cell: Vector2i,
	boxes: Array,
	player_flood: Dictionary,
	ignore_idx: int = -1,
	box_lookup: Dictionary = {}
) -> int:
	var count := 0

	for dir in dirs:
		var new_box = box_cell + dir
		var req_player = box_cell - dir

		if not in_bounds(new_box):
			continue
		if not in_bounds(req_player):
			continue

		if is_wall_in_layout(layout, new_box):
			continue
		if is_wall_in_layout(layout, req_player):
			continue

		if _snapshot_has_box(new_box, boxes, ignore_idx, box_lookup):
			continue
		if _snapshot_has_box(req_player, boxes, ignore_idx, box_lookup):
			continue

		if not player_flood.has(req_player):
			continue

		count += 1

	return count


func has_reachable_box_push(
	layout: Array,
	box_cell: Vector2i,
	boxes: Array,
	player_flood: Dictionary,
	ignore_idx: int = -1,
	box_lookup: Dictionary = {}
) -> bool:
	return count_reachable_pushes_for_box(layout, box_cell, boxes, player_flood, ignore_idx, box_lookup) >= 1


func total_reachable_pushes(layout: Array, state: State) -> int:
	var total := 0

	for i in range(state.boxes.size()):
		var flood = _flood_layout(state.player, state.boxes, i, layout, state.box_lookup)
		total += count_reachable_pushes_for_box(layout, state.boxes[i], state.boxes, flood, i, state.box_lookup)

	return total

func is_open_spawn_cell_layout(layout: Array, cell: Vector2i, boxes: Array, box_lookup: Dictionary = {}) -> bool:
	if not in_bounds(cell):
		return false

	if is_wall_in_layout(layout, cell):
		return false

	if _snapshot_has_box(cell, boxes, -1, box_lookup):
		return false

	return true


func first_open_spawn_cell(layout: Array, boxes: Array, box_lookup: Dictionary = {}) -> Vector2i:
	for y in range(height):
		for x in range(width):
			var cell = Vector2i(start.x + x, start.y + y)
			if is_open_spawn_cell_layout(layout, cell, boxes, box_lookup):
				return cell

	return Vector2i(start.x + 1, start.y + 1)


func collect_reachable_push_positions(
	layout: Array,
	boxes: Array,
	player_flood: Dictionary,
	box_lookup: Dictionary = {}
) -> Array:
	var found := {}

	for i in range(boxes.size()):
		var box_cell: Vector2i = boxes[i]

		for dir in dirs:
			var new_box = box_cell + dir
			var req_player = box_cell - dir

			if not in_bounds(new_box):
				continue
			if not in_bounds(req_player):
				continue

			if is_wall_in_layout(layout, new_box):
				continue
			if is_wall_in_layout(layout, req_player):
				continue

			if _snapshot_has_box(new_box, boxes, i, box_lookup):
				continue
			if _snapshot_has_box(req_player, boxes, i, box_lookup):
				continue

			if not player_flood.has(req_player):
				continue

			found[req_player] = true

	return found.keys()


func cell_distance_to_nearest_target(cell: Vector2i, targets: Array) -> int:
	if targets.is_empty():
		return 999999

	var best := 999999
	for t in targets:
		var d = abs(cell.x - t.x) + abs(cell.y - t.y)
		if d < best:
			best = d

	return best


func level_center_cell() -> Vector2i:
	return Vector2i(
		start.x + int(width / 2),
		start.y + int(height / 2)
	)


func choose_best_spawn_in_component(
	component_cells: Array,
	push_positions: Array
) -> Vector2i:
	if component_cells.is_empty():
		return Vector2i(start.x + 1, start.y + 1)

	var center: Vector2i = level_center_cell()
	var best_cell: Vector2i = component_cells[0]
	var best_score: int = -999999999

	for cell in component_cells:
		var nearest_push: int = cell_distance_to_nearest_target(cell, push_positions)
		var center_dist: int = absi(cell.x - center.x) + absi(cell.y - center.y)
		var border_penalty: int = 1 if is_next_to_border(cell) else 0

		var score: int = 0
		score -= nearest_push * 100
		score -= center_dist * 3
		score -= border_penalty * 50

		if score > best_score:
			best_score = score
			best_cell = cell

	return best_cell


func find_best_player_spawn(layout: Array, boxes: Array, fallback_player: Vector2i, box_lookup: Dictionary = {}) -> Vector2i:
	var lookup: Dictionary = box_lookup if not box_lookup.is_empty() else _make_box_lookup(boxes)

	if is_open_spawn_cell_layout(layout, fallback_player, boxes, lookup):
		pass
	else:
		fallback_player = first_open_spawn_cell(layout, boxes, lookup)

	var seen := {}
	var best_cell: Vector2i = fallback_player
	var best_score := -999999999

	for y in range(height):
		for x in range(width):
			var seed = Vector2i(start.x + x, start.y + y)

			if seen.has(seed):
				continue

			if not is_open_spawn_cell_layout(layout, seed, boxes, lookup):
				continue

			var flood = _flood_layout(seed, boxes, -1, layout, lookup)
			for c in flood.keys():
				seen[c] = true

			var component_cells = flood.keys()
			var push_positions = collect_reachable_push_positions(layout, boxes, flood, lookup)
			var candidate = choose_best_spawn_in_component(component_cells, push_positions)

			var component_score := 0
			component_score += push_positions.size() * 10000
			component_score -= cell_distance_to_nearest_target(candidate, push_positions) * 100
			component_score -= component_cells.size()

			if component_score > best_score:
				best_score = component_score
				best_cell = candidate

	return best_cell

func _make_box_lookup(boxes: Array) -> Dictionary:
	return State.build_box_lookup(boxes)


func _move_box_lookup(box_lookup: Dictionary, old_cell: Vector2i, new_cell: Vector2i) -> Dictionary:
	var next_lookup: Dictionary = box_lookup.duplicate()
	next_lookup.erase(old_cell)
	next_lookup[new_cell] = true
	return next_lookup

func _canonical_cell_from_flood(flood: Dictionary) -> Vector2i:
	var best := Vector2i(999999, 999999)
	for cell in flood.keys():
		if cell.x < best.x or (cell.x == best.x and cell.y < best.y):
			best = cell
	return best

func _state_key_from_flood(boxes: Array, full_flood: Dictionary) -> String:
	var sorted := boxes.duplicate()
	sorted.sort_custom(func(a, b): return str(a) < str(b))
 
	var canonical_player := _canonical_cell_from_flood(full_flood)
 
	var s := str(canonical_player)
	for box in sorted:
		s += str(box)
	return s

func _has_push_from_flood(
	layout: Array,
	new_box_cell: Vector2i,
	new_boxes: Array,
	box_idx: int,
	new_lookup: Dictionary,
	player_flood: Dictionary
) -> bool:
	for d in dirs:
		var nb = new_box_cell + d      # where the box would move next
		var rp = new_box_cell - d      # where the player must stand
 
		if not in_bounds(nb) or not in_bounds(rp):
			continue
		if is_wall_in_layout(layout, nb) or is_wall_in_layout(layout, rp):
			continue
		if _snapshot_has_box(nb, new_boxes, box_idx, new_lookup):
			continue
		if _snapshot_has_box(rp, new_boxes, box_idx, new_lookup):
			continue
		if player_flood.has(rp):
			return true
 
	return false

func display_fake_loading_screen(display: bool) -> void:
	fake_loading_screen.visible = display
	animated_sprite_2d.visible = display
	if display: animated_sprite_2d.play("default")
	else: animated_sprite_2d.stop()
	label.visible = display

func on_credits_pressed():
	var credits = credit_scene.instantiate()
	add_child(credits)

func _on_retry_level_pressed() -> void:
	if reverse_running:
		return
	retry_level()


func _on_new_level_pressed() -> void:
	if reverse_running:
		return
	get_tree().reload_current_scene()


func _on_credits_pressed() -> void:
	on_credits_pressed()


func _on_increase_goals_pressed() -> void:
	if reverse_running:
		return
	nr_of_goals.goals = clamp(nr_of_goals.goals + 1, 1, 4)
	update_goals_label()
	save_save_data()


func _on_decrease_goals_pressed() -> void:
	if reverse_running:
		return
	nr_of_goals.goals  = clamp(nr_of_goals.goals - 1, 1, 4)
	update_goals_label()
	save_save_data()
