extends SceneTree
## Script-mode tests for NetDiscovery (scripts/net_discovery.gd): the wire
## format and address maths behind "Host game" / "Join game". No network.
## Run: godot --headless --path . --script res://tests/test_net_discovery.gd

var failures := 0


func _init() -> void:
	_test_sanitize()
	_test_reply_round_trip()
	_test_parse_rejects_garbage()
	_test_probe()
	_test_addresses()
	_test_scan_targets()
	_test_scan_hint()
	print("")
	if failures == 0:
		print("net discovery: ALL PASSED")
	else:
		print("net discovery: %d FAILED" % failures)
	quit(0 if failures == 0 else 1)


func _check(label: String, condition: bool) -> void:
	if condition:
		print("PASS: ", label)
	else:
		print("FAIL: ", label)
		failures += 1


func _test_sanitize() -> void:
	_check("sanitize removes the separator", NetDiscovery.sanitize("a|b|c") == "abc")
	_check("sanitize removes control characters", NetDiscovery.sanitize("hi\nthere\t!") == "hithere!")
	_check("sanitize trims spaces", NetDiscovery.sanitize("  Ann  ") == "Ann")
	_check("sanitize caps the length", NetDiscovery.sanitize("x".repeat(100)).length() == NetDiscovery.MAX_NAME_LEN)
	_check("sanitize honours a custom cap", NetDiscovery.sanitize("abcdefgh", 3) == "abc")
	_check("sanitize of nothing is empty", NetDiscovery.sanitize("") == "")


func _test_reply_round_trip() -> void:
	var msg := NetDiscovery.build_reply("a1b2c3", "Ann's room", 3, 16, "The Understreets", 7777, false)
	var info := NetDiscovery.parse_reply(msg)
	_check("reply parses", not info.is_empty())
	_check("reply keeps the host id", info.get("host_id") == "a1b2c3")
	_check("reply keeps the room name", info.get("name") == "Ann's room")
	_check("reply keeps the player count", info.get("players") == 3 and info.get("max") == 16)
	_check("reply keeps the level name", info.get("level") == "The Understreets")
	_check("reply keeps the port", info.get("port") == 7777)
	_check("reply keeps the started flag (false)", info.get("started") == false)
	var started := NetDiscovery.parse_reply(NetDiscovery.build_reply("x", "r", 1, 16, "L", 9000, true))
	_check("started flag round-trips (true)", started.get("started") == true and started.get("port") == 9000)
	var nasty := NetDiscovery.parse_reply(NetDiscovery.build_reply("x", "evil|name|9|9", 1, 16, "L", 7777, false))
	_check("a '|' in a name cannot break the format", not nasty.is_empty() and nasty.get("players") == 1)


func _test_parse_rejects_garbage() -> void:
	_check("empty string is rejected", NetDiscovery.parse_reply("").is_empty())
	_check("wrong prefix is rejected", NetDiscovery.parse_reply("HELLO|1|a|b|1|16|L|7777|0").is_empty())
	_check("too few fields is rejected", NetDiscovery.parse_reply("FOGBOUND|1|a|name|1|16").is_empty())
	_check("too many fields is rejected", NetDiscovery.parse_reply("FOGBOUND|1|a|n|1|16|L|7777|0|extra").is_empty())
	_check("non-numeric player count is rejected", NetDiscovery.parse_reply("FOGBOUND|1|a|n|x|16|L|7777|0").is_empty())
	_check("port 0 is rejected", NetDiscovery.parse_reply("FOGBOUND|1|a|n|1|16|L|0|0").is_empty())
	_check("port 70000 is rejected", NetDiscovery.parse_reply("FOGBOUND|1|a|n|1|16|L|70000|0").is_empty())
	_check("a probe is not a reply", NetDiscovery.parse_reply(NetDiscovery.PROBE).is_empty())


func _test_probe() -> void:
	_check("the probe is recognised", NetDiscovery.is_probe(NetDiscovery.PROBE))
	_check("a reply is not a probe", not NetDiscovery.is_probe(NetDiscovery.build_reply("x", "r", 1, 16, "L", 7777, false)))
	_check("random text is not a probe", not NetDiscovery.is_probe("hello"))


func _test_addresses() -> void:
	_check("192.168.x is private", NetDiscovery.is_private_ipv4("192.168.43.1"))
	_check("10.x is private", NetDiscovery.is_private_ipv4("10.0.0.5"))
	_check("172.16 to 172.31 is private", NetDiscovery.is_private_ipv4("172.16.0.1") and NetDiscovery.is_private_ipv4("172.31.9.9"))
	_check("172.32 is not private", not NetDiscovery.is_private_ipv4("172.32.0.1"))
	_check("public addresses are not private", not NetDiscovery.is_private_ipv4("8.8.8.8"))
	_check("link-local 169.254 is not listed", not NetDiscovery.is_private_ipv4("169.254.1.1"))
	_check("IPv6 is ignored", not NetDiscovery.is_private_ipv4("fe80::1"))
	_check("octet over 255 is not an address", not NetDiscovery.is_ipv4("192.168.1.256"))
	_check("three octets is not an address", not NetDiscovery.is_ipv4("192.168.1"))
	var mixed := NetDiscovery.lan_addresses(["127.0.0.1", "fe80::1", "192.168.43.17", "8.8.8.8", "192.168.43.17", "10.1.2.3"])
	_check("lan_addresses keeps only private IPv4, once each", mixed == ["192.168.43.17", "10.1.2.3"])
	_check("directed broadcast of a /24", NetDiscovery.directed_broadcast("192.168.43.17") == "192.168.43.255")


func _test_scan_targets() -> void:
	var none := NetDiscovery.scan_targets([])
	_check("with no network a probe still tries this machine and the limited broadcast",
			none == [NetDiscovery.LOOPBACK, NetDiscovery.LIMITED_BROADCAST])
	var targets := NetDiscovery.scan_targets(["192.168.43.17"])
	_check("scan includes loopback", targets.has("127.0.0.1"))
	_check("scan includes the subnet broadcast", targets.has("192.168.43.255"))
	_check("scan includes the usual hotspot gateway", targets.has("192.168.43.1"))
	_check("scan skips our own address", not targets.has("192.168.43.17"))
	_check("scan covers the whole /24 once (2 + broadcast + 253 others)", targets.size() == 2 + 1 + 253)
	var seen := {}
	var dup := false
	for t in targets:
		if seen.has(t):
			dup = true
		seen[t] = true
	_check("scan has no duplicate targets", not dup)


func _test_scan_hint() -> void:
	var offline := NetDiscovery.scan_hint([], 0)
	_check("hint with no network tells you to join the hotspot", "hotspot" in offline and "Search again" in offline)
	_check("no network wins even if a stale room is listed", NetDiscovery.scan_hint([], 2) == offline)
	var searching := NetDiscovery.scan_hint(["192.168.43.17"], 0)
	_check("hint on a network with no rooms says the host must tap Host game", "Host game" in searching and "same" in searching)
	_check("hint with rooms says tap a room", NetDiscovery.scan_hint(["192.168.43.17"], 1) == "Tap a room to join.")
	_check("none of the hints ask anyone to type an address", not ("type" in offline.to_lower() or "type" in searching.to_lower()))
