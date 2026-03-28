extends Node2D

@onready var camera_2d: Camera2D = $Camera2D
@onready var tile_map: TileMap = $TileMap
@onready var player: Node2D = $Player


var viewport_size
#var camera_center = camera_2d.position + (viewport_size/2) * camera_2d.zoom
var camera_center
var offset_tiles = Vector2(-3,-3)
var offset_pixels : Vector2
var pixel_grid_position
var grid_to_pixel
var width = 11
var height = 11
var grid = []  # start empty
var floor_tile_atlas_coords = Vector2i(1,1)
var start = Vector2(29,13)
var add_x = Vector2(1,0)
var add_y = Vector2(0,1)
var source_id = 0
var wall_tile_atlas_coords = Vector2i(1,0)
var goal_tile = Vector2i(9,9)
var goal_tiles: int = 0
var nr_of_boxes: int = 0
var temp_pos = Vector2(520, 296)
var dirs = [
Vector2i(1, 0),
Vector2i(-1, 0),
Vector2i(0, 1),
Vector2i(0, -1)
]
var box_list = []
var box_pos_history = []
var unique_box_pos_history = []

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




# Called when the node enters the scene tree for the first time.
func _ready() -> void:  
	await get_tree().physics_frame
	randomize()
	#seed(1)
	#var box = box_scene.instantiate()
	#box.global_position = Vector2(552, 232)
	#add_child(box)
	#print("box spawned at", box.global_position)
	var layout = [
		[1,1,1,1,1,1,1,1,1,1,1],
		[1,0,0,0,2,0,0,0,0,0,1],
		[1,0,1,0,0,0,0,0,1,0,0],
		[1,0,0,0,1,0,1,0,0,0,1],
		[1,0,0,0,0,0,0,0,0,0,1],
		[1,0,0,1,0,0,0,1,0,0,1],
		[1,0,0,0,0,2,0,0,0,0,1],
		[1,0,1,0,0,0,0,0,1,2,1],
		[1,2,0,0,1,0,1,0,0,0,1],
		[1,0,0,0,0,0,0,0,0,0,1],
		[1,1,1,1,1,1,1,1,1,1,1]
	]
	for y in range(height):
		var row = []
		for x in range(width):
			var tile_coords = Vector2i(start.x + x, start.y + y)
			row.append(tile_coords)
			
			var atlas_coords : Vector2i
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
					print(tile_coords)
			#tile_map.set_cell(0, tile_coords, source_id, atlas_coords)
		grid.append(row)
	#place_player()
	#do_reverse_generation(20)
	#do_reverse_generation_dfs(6)
	

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func grid_to_world(x,y):
	return pixel_grid_position + Vector2(x, y) * 16

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

func is_floor(cell: Vector2i) -> bool:
	var data = tile_map.get_cell_atlas_coords(0, cell)
	return data == floor_tile_atlas_coords

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

func is_border_wall(cell: Vector2i) -> bool:
	return ( cell.x == start.x or cell.x == start.x + width - 1 or cell.y == start.y or cell.y == start.y + height - 1)


## Checks if the player can reach a target grid cell without passing through
## walls or boxes. Uses a flood-fill / breadth-first search through the grid.
func player_can_reach(target: Vector2i) -> bool:
	# Convert the player's world position into grid coordinates
	var start_cell = world_to_grid(player.position)
	# If the player's starting position is outside the level bounds,
	# the search cannot proceed
	if not in_bounds(start_cell):
		return false
	# "open" is the queue of tiles that still need to be explored.
	# It starts with the player's current tile.
	var open = [start_cell]
	# "visited" stores tiles we have already checked.
	# This prevents the algorithm from looping forever.
	var visited = {}
	# Continue searching as long as there are tiles left to explore
	while open.size() > 0:
		# Remove the first tile from the queue (FIFO behaviour)
		# This is why the algorithm behaves like breadth-first search
		var cur = open.pop_front()
		# If the tile we are currently examining is the target,
		# the player can reach it
		if cur == target:
			return true
		# If we have already processed this tile before,
		# skip it and move to the next tile
		if visited.has(cur):
			continue
		# Mark this tile as visited
		visited[cur] = true
		
		# Check all four movement directions
		for d in dirs:
			# Calculate the neighbouring tile in that direction
			var nxt = cur + d
			# Skip if the neighbour is outside the playable grid
			if not in_bounds(nxt):
				continue
			# Skip if have already visited that tile
			if visited.has(nxt):
				continue
			# Skip if the tile contains a wall
			if is_wall(nxt):
				continue
			# Skip if the tile contains a box
			# because the player cannot walk through boxes
			if is_box_at(nxt):
				continue
			# If all checks pass, add this tile to the queue
			# so the algorithm will explore it later
			open.append(nxt)
	# If the search finishes and the target was never reached,
	# then there is no valid path to it
	return false

func can_reverse_push(next) -> bool:
	if is_floor(next):
		return true
	return false


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

## Performs multiple reverse Sokoban pushes in order to generate
## a puzzle starting from the solved configuration.
## "steps" controls how many reverse pushes the generator attempts.
func do_reverse_generation(steps: int):
	# Repeat the reverse generation process a fixed number of times
	for i in range(steps):
		# Randomize the order of boxes so the generator does not
		# always attempt to move the same box first
		box_list.shuffle()
		# Try to perform a reverse push with each box
		for box in box_list:
			# Compute all tiles the player can currently reach
			# The box being moved is ignored during this flood-fill
			# so the player can walk around its current position
			var flood = compute_player_flood(box)
			# Attempt to perform one reverse push with this box
			# If the push succeeds, we stop trying other boxes
			# for this step and move on to the next generation step
			if do_one_reverse_push(box, flood):
				break
	# The algorithm looks like this:
	# repeat N times
	# pick a random box
	# compute where the player can walk
	# compute where the player can walk
	# Each successful reverse push moves the puzzle further away from the solved state.

## Attempts to perform one reverse Sokoban push for a given box.
## Reverse pushing means moving the box away from its goal while
## moving the player into the box's previous position.
## Returns true if a valid reverse push was performed, otherwise false.
func do_one_reverse_push(box, flood):
	# Convert the box's world position into grid coordinates
	var box_cell = world_to_grid(box.position)
	# Shuffle the direction list so pushes are attempted in random order
	# This prevents the generator from always expanding in the same pattern
	dirs.shuffle()
	# Try each possible direction
	for dir in dirs:
		#print("trying dir:", dir)
		# Compute where the box would move if reverse pushed
		var new_box = box_cell + dir
		# Compute where the player would need to stand
		# in order to push the box in the forward direction
		var player_cell = box_cell - dir
		# Reject if the new box position would be outside the level bounds
		if not in_bounds(new_box):
			#print(" fail: new_box out of bounds")
			continue
		# Reject if the player's required position is outside the level
		if not in_bounds(player_cell):
			#print(" fail: player_cell out of bounds")
			continue
		# Reject if the box would move into a wall
		if is_wall(new_box):
			#print(" fail: wall at new_box")
			continue
		# Reject if another box already occupies the new box position
		# The current box is ignored in this check
		if is_box_at(new_box, box):
			#print(" fail: box at new_box")
			continue
		# Reject if the new position creates a known deadlock
		# (for example pushing the box into a corner that isn't a goal)
		if is_deadlock(new_box):
			#print(" fail: deadlock")
			continue
		# Reject if the player would have to stand inside a wall
		if is_wall(player_cell):
			#print(" fail: wall at player_cell")
			continue
		# Reject if another box blocks the player's required tile
		if is_box_at(player_cell, box):
			#print(" fail: box at player_cell")
			continue
		# Reject if the player cannot physically walk to the required tile
		# The flood dictionary contains all reachable cells
		if not flood.has(player_cell):
			#print(" fail: player can't reach", player_cell)
			continue
		
		#print(" successful push")
		# If all checks passed, the reverse push is valid.
		# Move the box to the new grid position.
		# valid reverse push
		#print("box moved", box_cell, "->", new_box)
		box.position = grid_to_world_pos(new_box)
		# Move the player to the previous box position.
		# This simulates the player having just pushed the box.
		player.position = grid_to_world_pos(box_cell)
		# Return true to indicate a successful reverse push
		return true
	# If none of the directions produced a valid push, return false
	return false
	# So the generator picks a box, tries each direction, checks if the move is valid, moves the box and player if valid
	# Each check prevents invalid Sokoban states
	# Shuffling of directions ensures: sometimes up first, sometimes left first, sometimes down first
	# which produces more varied puzzles and doesn't cause biased levle layouts 
	

## Computes all grid cells the player can reach from their current position.
## Uses a flood-fill (breadth-first search) to explore the level.
## Returns a dictionary where the keys are reachable grid cells.
## The optional ignore_box parameter allows one box to be ignored
## during the search (useful during reverse push simulation).
func compute_player_flood(ignore_box = null) -> Dictionary:
	# Convert the player's world position to a grid cell
	var start = world_to_grid(player.position)
	# "open" is the queue of cells that still need to be explored
	# We start the search from the player's current cell
	var open = [start]
	# "visited" stores every cell we have already explored
	# The keys will be Vector2i grid cells
	var visited = {}
	# Continue exploring while there are cells left in the queue
	while open.size() > 0:
		# Remove the first cell from the queue (FIFO behaviour)
		# This is what makes it a breadth-first flood search
		var cur = open.pop_front()
		# If this cell has already been processed, skip it
		if visited.has(cur):
			continue
		# Mark this cell as visited / reachable
		visited[cur] = true
		# Check all four neighbouring tiles
		for d in dirs:
			# Compute the neighbour cell in this direction
			var nxt = cur + d
			# Skip if the tile is outside the playable map
			if not in_bounds(nxt):
				continue
			# Skip if we have already visited this tile
			if visited.has(nxt):
				continue
			# Skip if we have already visited this tile
			if is_wall(nxt):
				continue
			# Skip if the tile contains a box
			# HOWEVER: if the box is equal to ignore_box, we pretend it is not there
			# This allows the flood search to treat the moving box as empty space
			if is_box_at(nxt, ignore_box):
				continue
			# If the tile passed all checks, add it to the queue
			# so the flood search will explore it later
			open.append(nxt)
	# When the flood-fill finishes, return all reachable tiles
	# The dictionary keys represent every cell the player can walk to
	return visited
	# Main concept behind the ignore_box parameter. This is critical for the reverse generation
	# Normally the flood-fill treats boxes like walls
	# But during reverse pushes you want to temporarily treat the box being moved as if it wasnt blocking the path
	# When calculating reachability for that specific box, you want to pretend the box is not blocking movement so
	# the player can move around it correctly during the simulation.
	# The is_box_at function ignores the provided box when checking collisions.
	# It returns a dictionary like this conceptually:
	# {
	#(30,14): true
	#(31,14): true
	#(31,15): true
	#(32,15): true
	#...
	# }
	#
	# This is much better than calling player_can_reach repeatedly 
	# Instead of doing: check reachability, check reachability, check reachability for every push attemt
	# Just compute the flood once and reuse it
	# So instead of: O(N * path_search), we get: O(path_search) + O(lookups) which is much faster during generation.
	# 
	#
	#

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
	var up = is_wall(cell + Vector2i( 0, -1))
	var down = is_wall(cell + Vector2i( 0,  1))
	var left = is_wall(cell + Vector2i(-1,  0))
	var right = is_wall(cell + Vector2i( 1,  0))
	
	if (up or down) and (left or right):
		return true
	if up or down:
		var wall_cell = cell + (Vector2i(0, -1) if up else Vector2i(0, 1))
		if not is_border_wall(wall_cell):
			var wall_dir = Vector2i(0, -1) if up else Vector2i(0, 1)
			if not _goal_along_row(cell, wall_dir):
				return true
	if left or right:
		var wall_cell = cell + (Vector2i(-1, 0) if left else Vector2i(1, 0))
		if not is_border_wall(wall_cell):
			var wall_dir = Vector2i(-1, 0) if left else Vector2i(1, 0)
			if not _goal_along_col(cell, wall_dir):
				return true
	return false

func _goal_along_row(cell: Vector2i, wall_dir: Vector2i) -> bool:
	if is_goal(cell):
		return true
	for step_dir in [Vector2i(-1, 0), Vector2i(1, 0)]:
		var cur = cell
		while true:
			cur += step_dir
			if not in_bounds(cur) or is_wall(cur):
				break
			if not is_wall(cur + wall_dir):
				break
			if is_goal(cur):
				return true
	return false

func _goal_along_col(cell: Vector2i, wall_dir: Vector2i) -> bool:
	if is_goal(cell):
		return true
	var step_dirs = [Vector2i(0, -1), Vector2i(0, 1)]
	for step_dir in step_dirs:
		var cur = cell
		while true:
			cur += step_dir
			if not in_bounds(cur) or is_wall(cur):
				break
			if not is_wall(cur + wall_dir):
				break
			if is_goal(cur):
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
	

func _dfs_generate(box_idx: int, initial_boxes: Array, initial_player: Vector2i, max_depth: int) -> State:
	var start_state = State.new(initial_boxes, initial_player, 0)
	var stack: Array = []
	var visited: Dictionary = {}
	stack.push_back(start_state)
	visited[start_state.key()] = true
	var best: State = start_state
	while stack.size() > 0:
		var state: State = stack.pop_back()
		if state.depth > best.depth:
			best = state
		if state.depth >= max_depth:
			continue
		var candidates = []
		for d in dirs:
			candidates.append(d)
		candidates.shuffle()
		#print(candidates)
		for dir in candidates:
			var box_cell = state.boxes[box_idx]
			var new_box = box_cell + dir
			var req_player = box_cell - dir
			if not in_bounds(new_box): print("fail: out of bounds ", new_box); continue
			if not in_bounds(req_player): print("fail: req_player out of bounds ", req_player); continue
			if is_wall(new_box): print("fail: wall at ", new_box); continue
			if is_wall(req_player): print("fail: wall at req_player ", req_player); continue
			var new_boxes = state.boxes.duplicate()
			new_boxes[box_idx] = new_box
			if _snapshot_has_box(new_box, state.boxes, box_idx): print("fail: box at ", new_box); continue
			if _snapshot_has_box(req_player, state.boxes, box_idx): print("fail: box at req_player ", req_player); continue
			if is_deadlock(new_box): print("fail: deadlock at ", new_box); continue
			var flood = _flood(state.player, state.boxes, box_idx)
			if not flood.has(req_player): print("fail: player cant reach ", req_player); continue
			var next_state = State.new(new_boxes, box_cell, state.depth + 1)
			if visited.has(next_state.key()): continue
			visited[next_state.key()] = true
			stack.push_back(next_state)
	return best

func do_reverse_generation_dfs(max_depth: int = 20):
	var box_snapshot: Array = []
	for b in box_list:
		box_snapshot.append(world_to_grid(b.position))
	var player_cell = world_to_grid(player.position)
	for i in range(box_list.size()):
		var best_state = _dfs_generate(i, box_snapshot, player_cell, max_depth)
		box_snapshot[i] = best_state.boxes[i]
		player_cell = best_state.player
	for i in range(box_list.size()):
		box_list[i].position = grid_to_world_pos(box_snapshot[i])
	var final_state = State.new(box_snapshot, player_cell, 0)
	_place_player_final(final_state)

func _place_player_final(state: State):
	var best_cell  = Vector2i(-1, -1)
	var best_score = -1
	
	for y in range(height):
		for x in range(width):
			var cell = Vector2i(start.x + x, start.y + y)
			if is_wall(cell):
				continue
			if _snapshot_has_box(cell, state.boxes, -1):
				continue
			var score = 0
			for box_cell in state.boxes:
				score += abs(cell.x - box_cell.x) + abs(cell.y - box_cell.y)
			if score > best_score:
				best_score = score
				best_cell  = cell
	if best_cell != Vector2i(-1, -1):
		player.position = grid_to_world_pos(best_cell)
	else:
		place_player()



func place_boxes_randomly(steps):
	pass
	
