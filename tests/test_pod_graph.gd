extends SceneTree
## test_pod_graph.gd
## Standalone smoke test for PodGraph, runnable without the editor or
## GUT via:
##   godot --headless --script res://tests/test_pod_graph.gd
## Exits with code 0 on success, 1 on first failure, and prints a
## PASS/FAIL line per case. See docs/WALKTHROUGH.md "Testing".

var failures := 0


func _init() -> void:
	_test_chain_stays_one_pod_until_snapped()
	_test_snap_splits_chain_into_two_pods()
	_test_remove_player_detaches_from_all_links()
	_test_score_table_tiers()

	if failures == 0:
		print("ALL TESTS PASSED")
		quit(0)
	else:
		print("%d TEST(S) FAILED" % failures)
		quit(1)


func _check(label: String, condition: bool) -> void:
	if condition:
		print("PASS: %s" % label)
	else:
		print("FAIL: %s" % label)
		failures += 1


func _test_chain_stays_one_pod_until_snapped() -> void:
	var g := PodGraph.new()
	g.add_link(1, 2)
	g.add_link(2, 3)
	g.add_link(3, 4)
	var pods := g.recompute_pods()
	_check("chain of 4 forms a single pod", pods.size() == 1 and pods[0].size() == 4)


func _test_snap_splits_chain_into_two_pods() -> void:
	var g := PodGraph.new()
	g.add_link(1, 2)
	g.add_link(2, 3)
	g.add_link(3, 4)
	g.snap_link(2, 3)
	var pods := g.recompute_pods()
	_check("snapping the middle link yields 2 pods", pods.size() == 2)

	var sizes := []
	for p in pods:
		sizes.append(p.size())
	sizes.sort()
	_check("split pods are size 2 and 2", sizes == [2, 2])


func _test_remove_player_detaches_from_all_links() -> void:
	var g := PodGraph.new()
	g.add_link(1, 2)
	g.add_link(2, 3)
	g.remove_player(2)
	var pods := g.recompute_pods()
	var found_two_in_any_pod := false
	for p in pods:
		if p.has(2):
			found_two_in_any_pod = true
	_check("removed player no longer appears in any pod", not found_two_in_any_pod)
	_check("removing the hub of a 3-chain leaves 2 solo pods", pods.size() == 2)


func _test_score_table_tiers() -> void:
	_check("full team of 16 scores 1200", ScoreTableStatic.score_for(16, 16) == 1200)
	_check("half team (8 of 16) scores 500", ScoreTableStatic.score_for(8, 16) == 500)
	_check("quarter team (4 of 16) scores 200", ScoreTableStatic.score_for(4, 16) == 200)
	_check("eighth team (2 of 16) scores 50", ScoreTableStatic.score_for(2, 16) == 50)
	_check("bare minimum pair from a team of 3 scores 10", ScoreTableStatic.score_for(2, 3) == 10)
	_check("full tiny team (2 of 2) still scores 1200", ScoreTableStatic.score_for(2, 2) == 1200)
