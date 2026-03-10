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




# Called when the node enters the scene tree for the first time.
func _ready() -> void:  
	await get_tree().physics_frame
	randomize()
	#var box = box_scene.instantiate()
	#box.global_position = Vector2(552, 232)
	#add_child(box)
	#print("box spawned at", box.global_position)
	var layout = [
		[1,1,1,1,1,1,1,1,1,1,1],
		[1,0,0,0,0,0,0,0,0,0,1],
		[1,0,1,0,0,0,0,0,1,0,1],
		[1,0,0,0,1,0,1,0,0,0,1],
		[1,0,0,0,2,0,0,0,0,0,1],
		[1,0,0,1,0,2,0,1,0,0,1],
		[1,0,0,0,0,0,0,0,0,0,1],
		[1,0,1,0,0,0,0,0,1,0,1],
		[1,0,0,0,1,0,1,0,0,0,1],
		[1,0,0,0,0,2,0,0,0,0,1],
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
	place_player()
	do_reverse_generation(30)
	

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

func is_box_at(cell: Vector2i, ignore_box = null) -> bool:
	for box in box_list:
		if box == ignore_box:
			continue
		if world_to_grid(box.position) == cell:
			return true
	return false

func player_can_reach(target: Vector2i) -> bool:
	var start_cell = world_to_grid(player.position)
	if not in_bounds(start_cell):
		return false
	var open = [start_cell]
	var visited = {}
	while open.size() > 0:
		var cur = open.pop_front()
		if cur == target:
			return true
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
			if is_box_at(nxt):
				continue
			open.append(nxt)
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

func do_reverse_generation(steps: int):
	for i in range(steps):

		box_list.shuffle()

		for box in box_list:

			var flood = compute_player_flood(box)

			if do_one_reverse_push(box, flood):
				break

func do_one_reverse_push(box, flood):
	var box_cell = world_to_grid(box.position)
	dirs.shuffle()
	for dir in dirs:
		print("trying dir:", dir)
		var new_box = box_cell + dir
		var player_cell = box_cell - dir
		if not in_bounds(new_box):
			print(" fail: new_box out of bounds")
			continue
		if not in_bounds(player_cell):
			print(" fail: player_cell out of bounds")
			continue
		if is_wall(new_box):
			print(" fail: wall at new_box")
			continue
		if is_box_at(new_box, box):
			print(" fail: box at new_box")
			continue
		if is_deadlock(new_box):
			print(" fail: deadlock")
			continue
		if is_wall(player_cell):
			print(" fail: wall at player_cell")
			continue
		if is_box_at(player_cell, box):
			print(" fail: box at player_cell")
			continue
		if not flood.has(player_cell):
			print(" fail: player can't reach", player_cell)
			continue
		
		print(" SUCCESS PUSH")
		# valid reverse push
		print("box moved", box_cell, "->", new_box)
		box.position = grid_to_world_pos(new_box)
		player.position = grid_to_world_pos(box_cell)
		return true
	return false

func compute_player_flood(ignore_box = null) -> Dictionary:
	var start = world_to_grid(player.position)

	var open = [start]
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

			if is_box_at(nxt, ignore_box):
				continue

			open.append(nxt)

	return visited

func in_bounds(cell: Vector2i) -> bool:
	return (
	cell.x >= start.x and
	cell.x < start.x + width and
	cell.y >= start.y and
	cell.y < start.y + height
	)

func is_deadlock(cell: Vector2i) -> bool:
	# allow boxes on goals
	if tile_map.get_cell_atlas_coords(0, cell) == goal_tile:
		return false

	var up = is_wall(cell + Vector2i(0,-1))
	var down = is_wall(cell + Vector2i(0,1))
	var left = is_wall(cell + Vector2i(-1,0))
	var right = is_wall(cell + Vector2i(1,0))

	if up and left:
		return true
	if up and right:
		return true
	if down and left:
		return true
	if down and right:
		return true

	return false
