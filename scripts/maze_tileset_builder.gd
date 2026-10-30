class_name MazeTileSetBuilder
extends RefCounted
## MazeTileSetBuilder
## Builds a minimal 3-tile TileSet (floor, wall, puzzle-room floor) entirely in code from
## flat-color placeholder textures, with physics and occlusion already
## wired up for the wall tile. This avoids hand-authoring a .tres
## TileSet resource (an easy place to get Godot's binary-ish format
## subtly wrong without the editor) while still giving game_controller
## a real, working TileSet to paint with set_cell().
##
## Swap this out once you have real tile art: see docs/WALKTHROUGH.md
## "Sprites" for how to build a proper TileSet in the editor instead
## and just assign it to Maze.tile_set in game.tscn.

const TILE_PX := 16
const DEFAULT_FLOOR := Color(0.24, 0.22, 0.19)  # muted warm grey
const DEFAULT_WALL := Color(0.35, 0.38, 0.44)   # cool slate

## floor_color / wall_color come from the active LevelData.LevelDef so
## every level gets its own look; the defaults are the original
## "Understreets" palette.
static func build(floor_color: Color = DEFAULT_FLOOR, wall_color: Color = DEFAULT_WALL) -> TileSet:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE_PX, TILE_PX)

	# Physics layer so walls collide, and a navigation/occlusion layer
	# so PointLight2D shadows work (design doc section 5.4).
	tile_set.add_physics_layer(0)
	tile_set.set_physics_layer_collision_layer(0, 1)
	tile_set.set_physics_layer_collision_mask(0, 1)
	tile_set.add_occlusion_layer(0)

	var source := TileSetAtlasSource.new()
	source.texture = _make_atlas_texture(floor_color, wall_color)
	source.texture_region_size = Vector2i(TILE_PX, TILE_PX)

	# The source must belong to tile_set BEFORE we touch per-tile
	# physics/occlusion data -- TileData looks up layer 0 on its
	# owning TileSet, and if the source isn't attached yet that
	# lookup fails with "Index p_layer_id = 0 is out of bounds".
	tile_set.add_source(source, 0)

	# Atlas coord (0,0) = floor (no collision, no occlusion)
	source.create_tile(Vector2i(0, 0))

	# Atlas coord (2,0) = puzzle-room floor: walkable like floor, but a
	# lighter tint so a seeded room reads as "somewhere that matters"
	# even through the fog.
	source.create_tile(Vector2i(2, 0))

	# Atlas coord (1,0) = wall (full collision + occlusion)
	source.create_tile(Vector2i(1, 0))
	var wall_data: TileData = source.get_tile_data(Vector2i(1, 0), 0)
	var rect := PackedVector2Array([
		Vector2(-TILE_PX / 2.0, -TILE_PX / 2.0),
		Vector2(TILE_PX / 2.0, -TILE_PX / 2.0),
		Vector2(TILE_PX / 2.0, TILE_PX / 2.0),
		Vector2(-TILE_PX / 2.0, TILE_PX / 2.0),
	])
	wall_data.add_collision_polygon(0)
	wall_data.set_collision_polygon_points(0, 0, rect)
	wall_data.set_occluder(0, _make_occluder(rect))

	return tile_set


static func _make_atlas_texture(floor_color: Color, wall_color: Color) -> ImageTexture:
	# 3 tiles side-by-side: floor | wall | puzzle-room floor.
	var img := Image.create(TILE_PX * 3, TILE_PX, false, Image.FORMAT_RGBA8)
	img.fill_rect(Rect2i(0, 0, TILE_PX, TILE_PX), floor_color)
	img.fill_rect(Rect2i(TILE_PX, 0, TILE_PX, TILE_PX), wall_color)
	img.fill_rect(Rect2i(TILE_PX * 2, 0, TILE_PX, TILE_PX), floor_color.lerp(wall_color, 0.35).lightened(0.12))
	return ImageTexture.create_from_image(img)


static func _make_occluder(points: PackedVector2Array) -> OccluderPolygon2D:
	var occ := OccluderPolygon2D.new()
	occ.polygon = points
	return occ
