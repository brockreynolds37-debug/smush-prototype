extends Node

## FloorArchetypeManager — autoload that picks a floor archetype per floor
## from a weighted pool. Archetypes define win conditions and gameplay modes.

## Weighted archetype pool: [ArchetypeClass, weight]
var _archetype_pool: Array = [
	[CrawlArchetype, 5],
	[EscapeArchetype, 2],
	[SurvivalArenaArchetype, 3],
	[StealthArchetype, 2],
]

## Pick an archetype for the given floor number.
## Tutorial and floor 1 are always Crawl.
func get_archetype_for_floor(floor_num: int) -> FloorArchetype:
	if floor_num <= 1:
		return CrawlArchetype.new()

	var total_weight: float = 0.0
	for entry in _archetype_pool:
		total_weight += entry[1]

	var roll = randf() * total_weight
	var cumulative: float = 0.0
	for entry in _archetype_pool:
		cumulative += entry[1]
		if roll <= cumulative:
			return entry[0].new()

	return CrawlArchetype.new()
