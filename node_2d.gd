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

@export var box_scene: PackedScene
@onready var box_template: Node2D = $Box_Template



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
	

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func grid_to_world(x,y):
	return pixel_grid_position + Vector2(x, y) * 16

func spawn_box(pos: Vector2i):
	var box = box_scene.instantiate()
	var tile_local_pos = tile_map.map_to_local(pos)
	box.position = tile_map.position + tile_local_pos
	box.move_back.connect(player._on_box_move_back)
	add_child(box)
	print("spawned box, position =", box.global_position)
