extends Resource
class_name SaveData

## Stores the player's persistent generation settings.
## This resource is saved to disk and loaded again when the game starts.

# Number of boxes/goals to generate. Each box needs one matching goal tile.
@export var goals: int = 2

# Selected difficulty index used by the generator to choose layout samples and DFS depth.
@export var difficulty: int = 1
