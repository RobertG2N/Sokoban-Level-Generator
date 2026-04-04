extends Node2D

@onready var tile_map: TileMap = $TileMap
@onready var player: Node2D = $Player




var width = 15
var height = 12
var grid = []  # start empty
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

class State:
	var boxes: Array
	var player: Vector2i
	var depth: int

	func _init(b: Array, p: Vector2i, d: int):
		boxes  = b.duplicate()
		player = p
		depth  = d
	
	func key() -> String:
		var sorted = boxes.duplicate()
		sorted.sort_custom(func(a, b): return str(a) < str(b))
		var s = str(player)
		for box in sorted:
			s += str(box)
		return s

var samples = []
var patterns = []
var adjacency = {}
var nr_of_goals = 2
var layouts: Layouts = load("res://layouts.tres")

# Called when the node enters the scene tree for the first time.
func _ready() -> void:  
	await get_tree().physics_frame
	randomize()
	current_seed = randi()
	samples = [layouts.layout1, layouts.layout2]
	patterns = extract_patterns(samples, 3)
	print("unique patterns found: ", patterns.size())
	adjacency = build_adjacency(patterns, 3)
	
	seed(current_seed)
	generate_level(width, height)
	

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func generate_level(w: int, h: int) -> void:
	width = w
	height = h
	# clear previous state
	grid = []
	box_list.clear()
	for child in get_children():
		if child.is_in_group("boxes"):
			child.queue_free()
	tile_map.clear()
	
	var layout = run_wfc(width, height, patterns, adjacency)
	layout = add_border(layout)
	while not is_layout_connected(layout):
		layout = run_wfc(width, height, patterns, adjacency)
		layout = add_border(layout)
	layout = place_goals(layout, nr_of_goals)
	reachable_cells = compute_reachable_cells(layout)
	
	for y in range(height):
		var row = []
		for x in range(width):
			var tile_coords = Vector2i(start.x + x, start.y + y)
			row.append(tile_coords)
			var atlas_coords: Vector2i
			match layout[y][x]:
				0:
					atlas_coords = floor_tile_atlas_coords
					tile_map.set_cell(0, tile_coords, source_id, atlas_coords)
				1:
					atlas_coords = wall_tile_atlas_coords
					tile_map.set_cell(0, tile_coords, source_id, atlas_coords)
				2:
					atlas_coords = goal_tile
					tile_map.set_cell(0, tile_coords, source_id, atlas_coords)
					spawn_box(tile_coords)
		grid.append(row)
	
	place_player()
	do_reverse_generation_dfs()



func retry_level() -> void:
	seed(current_seed)
	generate_level(width, height)


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

func world_to_grid(pos: Vector2) -> Vector2i:
	return tile_map.local_to_map(pos - tile_map.position)

func grid_to_world_pos(cell: Vector2i) -> Vector2:
	return tile_map.position + tile_map.map_to_local(cell)

func is_wall(cell: Vector2i) -> bool:
	var data = tile_map.get_cell_atlas_coords(0, cell)
	return data == wall_tile_atlas_coords

func is_goal(cell: Vector2i) -> bool:
	var data = tile_map.get_cell_atlas_coords(0, cell)
	return data == goal_tile

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

## Detects simple Sokoban corner deadlocks.
## Returns true if placing a box on this cell would make it permanently stuck.
## Boxes on goal tiles are allowed and are not considered deadlocks.
func is_deadlock(cell: Vector2i) -> bool:
	if is_goal(cell):
		return false

	var up = is_wall(cell + Vector2i(0, -1))
	var down = is_wall(cell + Vector2i(0, 1))
	var left = is_wall(cell + Vector2i(-1, 0))
	var right = is_wall(cell + Vector2i(1, 0))

	# 1. true corner deadlock
	if (up or down) and (left or right):
		return true

	# 2. next to outer border = dead
	# this is much cheaper and less strict than full wall-line analysis
	if is_next_to_border(cell):
		return true

	return false





func _snapshot_has_box(cell: Vector2i, snapshot: Array, ignore_idx: int) -> bool:
	for i in range(snapshot.size()):
		if i == ignore_idx:
			continue
		if snapshot[i] == cell:
			return true
	return false

func _flood(from: Vector2i, snapshot: Array, ignore_idx: int) -> Dictionary:
	var open = [from]
	var visited = {}
	while open.size() > 0:
		var cur = open.pop_front()
		if visited.has(cur):
			continue
		visited[cur] = true
		for d in dirs:
			var nxt = cur + d
			if not in_bounds(nxt):
				continue
			if visited.has(nxt):
				continue
			if is_wall(nxt):
				continue
			if _snapshot_has_box(nxt, snapshot, ignore_idx):
				continue
			open.append(nxt)
	return visited
	

func _dfs_generate_full(initial_boxes: Array, initial_player: Vector2i, max_depth: int, max_nodes: int = 5000) -> State:
	var start_state = State.new(initial_boxes, initial_player, 0)
	var stack: Array = [start_state]
	var visited: Dictionary = {}
	visited[start_state.key()] = true

	var goal_cells = initial_boxes.duplicate()

	var best: State = start_state
	var best_score := score_state(start_state, goal_cells)

	var nodes_expanded := 0

	while stack.size() > 0:
		var state: State = stack.pop_back()
		nodes_expanded += 1

		var current_score = score_state(state, goal_cells)
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
			var box_cell: Vector2i = state.boxes[box_idx]

			var dir_list = dirs.duplicate()
			dir_list.shuffle()

			for dir in dir_list:
				var new_box: Vector2i = box_cell + dir
				var req_player: Vector2i = box_cell - dir

				if not in_bounds(new_box):
					continue
				if not in_bounds(req_player):
					continue

				if is_wall(new_box):
					continue
				if is_wall(req_player):
					continue

				if _snapshot_has_box(new_box, state.boxes, box_idx):
					continue
				if _snapshot_has_box(req_player, state.boxes, box_idx):
					continue

				if is_deadlock(new_box):
					continue

				var local_new_box = new_box - start
				if not reachable_cells.has(local_new_box):
					continue

				var flood = _flood(state.player, state.boxes, box_idx)
				if not flood.has(req_player):
					continue

				var new_boxes = state.boxes.duplicate()
				new_boxes[box_idx] = new_box

				var next_state = State.new(new_boxes, box_cell, state.depth + 1)
				var k = next_state.key()

				if visited.has(k):
					continue

				visited[k] = true
				stack.push_back(next_state)

	return best

func do_reverse_generation_dfs(max_depth: int = 20, max_nodes: int = 5000):
	var box_snapshot: Array = []
	for b in box_list:
		box_snapshot.append(world_to_grid(b.position))

	var player_cell: Vector2i = world_to_grid(player.position)
	var goal_cells = box_snapshot.duplicate()

	var best_state = _dfs_generate_full(box_snapshot, player_cell, max_depth, max_nodes)

	for i in range(box_list.size()):
		box_list[i].position = grid_to_world_pos(best_state.boxes[i])

	player.position = grid_to_world_pos(best_state.player)

	print("final reverse depth = ", best_state.depth)
	print("final score = ", score_state(best_state, goal_cells))

	for i in range(best_state.boxes.size()):
		print("box ", i, " final cell = ", best_state.boxes[i])

	print("player final cell = ", best_state.player)


func is_layout_connected(layout: Array) -> bool:
	var start_cell = Vector2i(-1, -1)
	var floor_count = 0
	
	for y in range(height):
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
		var cur = open.pop_front()
		if visited.has(cur):
			continue
		visited[cur] = true
		for d in dirs:
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
	var floor_count = count_floor_cells(layout)
	var candidates = []

	for y in range(height):
		for x in range(width):
			var cell = Vector2i(x, y)

			if not is_valid_goal_cell(layout, cell):
				continue

			var info = score_goal_cell(layout, cell)

			if info["score"] < max(6, int(floor_count * 0.15)):
				continue

			candidates.append(info)

	print("floor_count = ", floor_count)
	print("goal candidates = ", candidates.size())

	if candidates.size() < num_goals:
		return []

	candidates.sort_custom(func(a, b): return a["score"] > b["score"])

	var top_n = min(8, candidates.size())
	var seed = candidates[randi() % top_n]
	var core = seed["reach"]

	layout[seed["cell"].y][seed["cell"].x] = 2
	var goals_placed = 1

	var pool = []
	for item in candidates:
		if item["cell"] == seed["cell"]:
			continue
		if core.has(item["cell"]):
			pool.append(item)

	pool.shuffle()

	for item in pool:
		if goals_placed >= num_goals:
			break

		var cell = item["cell"]

		if has_adjacent_goal(layout, cell):
			continue

		layout[cell.y][cell.x] = 2
		goals_placed += 1

	if goals_placed < num_goals:
		return []

	return layout



func extract_patterns(layouts: Array, pattern_size: int) -> Array:
	var patterns = []
	for layout in layouts:
		for y in range(len(layout) - pattern_size + 1):
			for x in range(len(layout[0]) - pattern_size + 1):
				var pattern = []
				for dy in range(pattern_size):
					var row = []
					for dx in range(pattern_size):
						row.append(layout[y + dy][x + dx])
					pattern.append(row)
				if not patterns.has(pattern):
					patterns.append(pattern)
	return patterns

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

func get_lowest_entropy_cell(wfc_grid: Array) -> Vector2i:
	var lowest = 999999
	var best_cell = Vector2i(-1, -1)
	for y in range(wfc_grid.size()):
		for x in range(wfc_grid[y].size()):
			var count = wfc_grid[y][x].size()
			if count > 1 and count < lowest:
				lowest = count
				best_cell = Vector2i(x, y)
	return best_cell

func collapse_cell(wfc_grid: Array, cell: Vector2i) -> void:
	var candidates = wfc_grid[cell.y][cell.x]
	var chosen = candidates[randi() % candidates.size()]
	wfc_grid[cell.y][cell.x] = [chosen]

func propagate(wfc_grid: Array, adjacency: Dictionary, start_cell: Vector2i) -> bool:
	var stack = [start_cell]
	while stack.size() > 0:
		var cell = stack.pop_back()
		var neighbours = [
			[Vector2i(cell.x + 1, cell.y), "right", "left"],
			[Vector2i(cell.x - 1, cell.y), "left", "right"],
			[Vector2i(cell.x, cell.y + 1), "down", "up"],
			[Vector2i(cell.x, cell.y - 1), "up", "down"]
		]
		for entry in neighbours:
			var neighbour = entry[0]
			var dir = entry[1]
			var opposite = entry[2]
			if neighbour.x < 0 or neighbour.x >= wfc_grid[0].size():
				continue
			if neighbour.y < 0 or neighbour.y >= wfc_grid.size():
				continue
			var neighbour_candidates = wfc_grid[neighbour.y][neighbour.x]
			if neighbour_candidates.size() == 1:
				continue
			# build set of all patterns allowed in this direction from current cell
			var allowed = {}
			for pattern_idx in wfc_grid[cell.y][cell.x]:
				for allowed_idx in adjacency[pattern_idx][dir]:
					allowed[allowed_idx] = true
			# remove any neighbour candidates not in allowed
			var new_candidates = []
			for candidate in neighbour_candidates:
				if allowed.has(candidate):
					new_candidates.append(candidate)
			# if candidates changed, update and add neighbour to stack
			if new_candidates.size() != neighbour_candidates.size():
				if new_candidates.size() == 0:
					return false # contradiction
				wfc_grid[neighbour.y][neighbour.x] = new_candidates
				stack.push_back(neighbour)
	return true

func run_wfc(w: int, h: int, patterns: Array, adjacency: Dictionary) -> Array:
	var wfc_grid = init_wfc(w, h, patterns.size())
	
	while true:
		var cell = get_lowest_entropy_cell(wfc_grid)
		if cell == Vector2i(-1, -1):
			break  # all cells collapsed
		collapse_cell(wfc_grid, cell)
		var success = propagate(wfc_grid, adjacency, cell)
		if not success:
			# contradiction hit, restart
			wfc_grid = init_wfc(w, h, patterns.size())
		
	# convert wfc grid to layout by reading top left cell of each pattern
	var layout = []
	for y in range(h):
		var row = []
		for x in range(w):
			var pattern_idx = wfc_grid[y][x][0]
			row.append(patterns[pattern_idx][0][0])
		layout.append(row)
	return layout

func compute_reachable_cells(layout: Array) -> Dictionary:
	var reachable = {}
	# start with all goal tiles
	for y in range(height):
		for x in range(width):
			if layout[y][x] == 2:
				reachable[Vector2i(x, y)] = true
	# keep expanding until no new cells are added
	var changed = true
	while changed:
		changed = false
		for cell in reachable.keys():
			for d in dirs:
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

func add_border(layout: Array) -> Array:
	for y in range(height):
		layout[y][0] = 1
		layout[y][width - 1] = 1
	for x in range(width):
		layout[0][x] = 1
		layout[height - 1][x] = 1
	return layout

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
	var temp = layout.duplicate(true)
	temp[cell.y][cell.x] = 2
	var reach = compute_reachable_cells(temp)

	return {
		"cell": cell,
		"score": reach.size(),
		"reach": reach
	}


func score_state(state: State, goal_cells: Array) -> int:
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

	# depth is most important
	# then number of boxes moved off goals
	# then overall spread from the goal set
	return state.depth * 10000 + moved_boxes * 1000 + total_distance

func is_open_layout_cell(layout: Array, cell: Vector2i) -> bool:
	return (
		cell.x >= 0 and cell.x < width and
		cell.y >= 0 and cell.y < height and
		layout[cell.y][cell.x] != 1
	)


func has_goal_push_lane(layout: Array, goal: Vector2i) -> bool:
	for d in dirs:
		var box_from = goal - d
		var player_from = goal - Vector2i(d.x * 2, d.y * 2)

		if is_open_layout_cell(layout, box_from) and is_open_layout_cell(layout, player_from):
			return true

	return false

func is_valid_goal_cell(layout: Array, cell: Vector2i) -> bool:
	if layout[cell.y][cell.x] != 0:
		return false

	if has_adjacent_goal(layout, cell):
		return false

	if not has_goal_push_lane(layout, cell):
		return false

	return true



func _on_retry_level_pressed() -> void:
	retry_level()


func _on_new_level_pressed() -> void:
	get_tree().reload_current_scene()
