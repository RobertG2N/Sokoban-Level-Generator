# Sokoban Level Generator

A procedural Sokoban-style puzzle level generator built using the Godot Engine and GDScript.

The project generates playable grid-based puzzle levels by creating layouts, placing goals, and generating valid starting positions for boxes and the player. It combines procedural generation techniques with validation methods to create unique Sokoban-style challenges.

## Overview

This project explores procedural level generation for Sokoban-style puzzles.

The system generates wall and floor layouts using **Wave Function Collapse**, places goal tiles through rule-based filtering and scoring, and uses a reverse search approach to generate valid starting states for boxes and the player.

The project also includes a playable Sokoban prototype where users can generate new levels, adjust difficulty settings, and test generated puzzles.

## Features

- Procedural Sokoban-style level generation
- Wave Function Collapse based layout generation
- Rule-based goal placement with filtering and scoring
- Reverse reachable cell calculation
- Reverse depth-first search for box and player starting positions
- Dynamic difficulty adjustment
- Adjustable number of boxes
- Grid-based player movement and box pushing
- Level regeneration and retry functionality
- Multi-threaded level generation
- Persistent user settings

## Technologies

- **Godot Engine 4**
- **GDScript**
- Procedural Generation Algorithms
- Wave Function Collapse
- Depth-First Search
- Git


## Running From Source

### Requirements

- Godot Engine 4+

### Steps

1. Clone this repository.
2. Open Godot.
3. Select **Import**.
4. Choose the `project.godot` file inside this repo.

