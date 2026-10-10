class_name PodGraph
extends RefCounted
## PodGraph
## Tracks which players are still linked together as a connected
## component ("pod") after tether snaps or disconnects. Host-only:
## this is pure graph logic over peer ids, with no scene dependency,
## so it's easy to unit test in isolation (see tests/test_pod_graph.gd).

# edges[peer_id] = { other_peer_id: true, ... } for every ALIVE link
var edges: Dictionary = {}

# All known player ids, alive or not (eliminated players are removed
# via remove_player()).
var all_players: Array = []


func add_player(peer_id: int) -> void:
	if not all_players.has(peer_id):
		all_players.append(peer_id)
	if not edges.has(peer_id):
		edges[peer_id] = {}


func remove_player(peer_id: int) -> void:
	all_players.erase(peer_id)
	edges.erase(peer_id)
	for other in edges.keys():
		edges[other].erase(peer_id)


func add_link(a: int, b: int) -> void:
	add_player(a)
	add_player(b)
	edges[a][b] = true
	edges[b][a] = true


## Breaks the link between a and b. This is permanent for this pair
## (design doc section 3.6 / 14.2) -- call add_link again explicitly
## if a future game mode allows re-linking.
func snap_link(a: int, b: int) -> void:
	if edges.has(a):
		edges[a].erase(b)
	if edges.has(b):
		edges[b].erase(a)


## Recomputes connected components via flood fill (BFS). Returns
## Array[Array[int]], one inner array per pod.
func recompute_pods() -> Array:
	var visited := {}
	var pods: Array = []

	for p in all_players:
		if visited.has(p):
			continue
		var pod: Array = []
		var queue: Array = [p]
		visited[p] = true
		while queue.size() > 0:
			var cur = queue.pop_back()
			pod.append(cur)
			for neighbour in edges.get(cur, {}).keys():
				if not visited.has(neighbour):
					visited[neighbour] = true
					queue.append(neighbour)
		pods.append(pod)

	return pods


func pod_of(peer_id: int, pods: Array) -> Array:
	for pod in pods:
		if pod.has(peer_id):
			return pod
	return []
