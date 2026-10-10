class_name ScoreTableStatic
extends Node
## ScoreTable
## Ratio-based, data-driven scoring tiers (design doc section 3.10).
## A pod scores based on what fraction of its *original* team made it
## to the exit together, not an absolute headcount -- so this works
## for any starting team size, not just powers of two.

const TIERS := [
	{"min_ratio": 1.0,   "points": 1200},  # complete, unbroken team
	{"min_ratio": 0.5,   "points": 500},   # half team
	{"min_ratio": 0.25,  "points": 200},   # half of the half
	{"min_ratio": 0.125, "points": 50},    # further split
	{"min_ratio": 0.0,   "points": 10},    # bare-minimum 2-player squad
]


## Returns the point value for a pod of `pod_size` that originated
## from a team of `original_size`. Always returns at least 10 points
## for any pod that actually reaches the exit (the function assumes
## the caller already confirmed the pod reached the exit zone).
##
## Design doc section 14.4 flags that ratio tiers get awkward for
## non-power-of-two teams: by ratio alone, 2 of a 3-player team is
## 67% and would score as a "half team" (500), even though a team
## that small never had more to lose. We resolve that here: a pod
## that is both (a) down to the bare MIN_TEAM_SIZE and (b) came from
## a team no more than one snap away from that same minimum is the
## "bare-minimum squad" tier, not a ratio tier. A 2-of-16 pod still
## scores by ratio (50, "further split") because that team had much
## more to lose and a long way to fall first.
static func score_for(pod_size: int, original_size: int) -> int:
	if original_size <= 0:
		return 10
	if pod_size >= original_size:
		return TIERS[0]["points"]
	if pod_size <= GameState.MIN_TEAM_SIZE and original_size <= GameState.MIN_TEAM_SIZE * 2:
		return TIERS[-1]["points"]
	var ratio := float(pod_size) / float(original_size)
	for t in TIERS:
		if ratio >= t["min_ratio"]:
			return t["points"]
	return 10
