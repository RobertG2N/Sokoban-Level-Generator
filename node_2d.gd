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
var width = 7
var height = 7
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
		[1,1,1,1,1,1,1],
		[1,0,0,0,0,2,1],
		[1,0,1,0,1,0,1],
		[1,0,0,0,1,0,1],
		[1,1,1,0,1,0,1],
		[1,2,0,0,0,0,1],
		[1,1,1,1,1,1,1]
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
	do_reverse_generation(15)
	

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

func is_box_at(cell: Vector2i) -> bool:
	for c in get_children():
		if c.is_in_group("boxes"):
			if world_to_grid(c.position) == cell:
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
	for i in steps:
		var rand_dir_index = randi_range(0,3)
		for j in box_list.size():
			do_one_reverse_push(box_list[j], rand_dir_index)
			#if box_list[j] == null:
				#continue
			#else: 
				#box_list[j]. position = tile_map.map_to_local(unique_box_pos_history.pop_front())
				
		
	

func do_one_reverse_push(box, dir):
	var b = tile_map.local_to_map(box.position)
	var p = tile_map.local_to_map(player.position)
	var next = b + dirs[dir]
	if can_reverse_push(next):
		p = b
		b = next
		box_pos_history.append(b)
		
		for i in box_pos_history:
			if not i in unique_box_pos_history:
				unique_box_pos_history.append(i)
				print(unique_box_pos_history)
			else: continue
		box.position = tile_map.map_to_local(unique_box_pos_history.pop_front())
		
		player.position = tile_map.map_to_local(p)
	else: return
	

func in_bounds(cell: Vector2i) -> bool:
	return (
	cell.x >= start.x and
	cell.x < start.x + width and
	cell.y >= start.y and
	cell.y < start.y + height
	)
