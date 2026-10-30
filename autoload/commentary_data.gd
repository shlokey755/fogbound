extends Node
## CommentaryData
## Text for the in-world "developer commentary" nodes -- a Fogbound
## original, not a recreation of any other game's commentary track.
## Framed as notes left behind by the maze's (fictional) builder,
## each one breaking the fourth wall about a REAL mechanic in this
## actual codebase, the way a commentary track explains a real design
## decision rather than narrating lore. Purely cosmetic: reading one
## has no effect on the match, teams, or scoring. See
## scripts/commentary_node.gd for placement and the popup itself.
##
## Entries are looked up by a stable string id (not array index) so
## adding/removing/reordering notes later never shifts another note's
## identity out from under SaveData.has_seen_commentary() records
## that are already on someone's disk.

class Note:
	var id: String
	var title: String
	var body: String

	func _init(p_id: String, p_title: String, p_body: String) -> void:
		id = p_id
		title = p_title
		body = p_body


var notes: Array = [
	Note.new("tether_snag_buffer", "On the 1.5-second grace period",
		"Early versions snapped the tether the instant it hit maximum length. Players hated it -- a rope " +
		"that's merely wrapped tight around a corner isn't actually overstretched, it just LOOKS that long. " +
		"Now a snagged link gets 1.5 seconds before it actually breaks. Same rule, less rage-quitting."),

	Note.new("score_tiers_are_ratios", "On why a 2-player team scores differently here",
		"Scoring isn't a headcount, it's a fraction of your own starting team. Two survivors out of sixteen " +
		"and two survivors out of two are not the same achievement, so they don't pay the same. The small-team " +
		"case still gets a floor, though -- a team that started at the minimum doesn't get punished extra for " +
		"having nothing left to lose."),

	Note.new("fog_room_is_first", "On why the fog room gets carved before anything else",
		"The maze generator doesn't carve corridors and then drop a fog room in the middle. It's the other " +
		"way around -- the fog room is carved FIRST, and every corridor grows outward from its edges. Build it " +
		"the other way and you risk a fog room that's accidentally sealed off from its own maze."),

	Note.new("host_never_trusts_payload", "On why nobody can claim to be someone else",
		"Every multiplayer message here is checked against who actually sent it over the wire, never against " +
		"an ID written inside the message itself. A message that says 'I am player 7' doesn't make it true -- " +
		"only the connection it arrived on does. Small detail, but it's the difference between a game and a " +
		"game you can cheat by editing one number."),

	Note.new("pull_only_never_push", "On why the tether never shoves you",
		"The rope math only ever pulls two players together, never apart. It would've been easy to let a " +
		"compressed tether add a shove, for a slingshot effect -- it just never felt like holding hands. It " +
		"felt like being flicked. So that branch of the force equation stays clamped at zero, on purpose."),

	Note.new("clues_are_never_consumed", "On why you can always re-read a fragment",
		"Fragments don't disappear once someone's read them. If your pod splits and the half that remembers " +
		"the code walks off without you, the fragment is still sitting right there to read again. Losing your " +
		"team should cost you time, not permanently erase progress you already earned."),
]


func get_note(id: String) -> Note:
	for n in notes:
		if n.id == id:
			return n
	return null


func total_count() -> int:
	return notes.size()
