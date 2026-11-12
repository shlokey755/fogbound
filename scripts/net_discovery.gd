class_name NetDiscovery
extends RefCounted
## NetDiscovery
## Pure helpers for finding a hosted room on the local network (hotspot or
## Wi-Fi). No sockets in here, so tests/test_net_discovery.gd can check the
## protocol and the address maths without a network.
##
## How a joining device finds the host's room:
##   1. The host listens on a UDP "discovery port".
##   2. The joiner sends a short PROBE to every address the host could have:
##      the limited broadcast, each local subnet's broadcast, EVERY address in
##      its own /24 (a hotspot network is tiny), and this machine (so two
##      windows on one laptop find each other).
##   3. The host answers the probe straight back with a one-line room
##      description (name, players, level, game port).
##
## Why probe instead of the host announcing by broadcast: broadcasts are the
## first thing a phone hotspot or router drops, and a joiner that only
## listens for them would see an empty list. A unicast probe + reply works
## whenever the two devices can reach each other at all, and several joiners
## on one machine do not fight over a listening port.

const PROTOCOL := 1
const PROBE := "FOGBOUND?|1"
const REPLY_PREFIX := "FOGBOUND|1|"
const MAX_NAME_LEN := 24

const LOOPBACK := "127.0.0.1"
const LIMITED_BROADCAST := "255.255.255.255"


## Strips the separator and control characters so a room or player name can
## never break the one-line wire format, and caps its length.
static func sanitize(text: String, max_len: int = MAX_NAME_LEN) -> String:
	var out := ""
	for i in range(text.length()):
		var c := text[i]
		if c == "|" or c.unicode_at(0) < 32:
			continue
		out += c
	out = out.strip_edges()
	return out.substr(0, max_len)


static func is_probe(msg: String) -> bool:
	return msg == PROBE


## `host_id` is a short random token the host picks once per room; it lets a
## joiner recognise the same room answering from two addresses.
static func build_reply(host_id: String, room_name: String, players: int, max_players: int,
		level_name: String, port: int, started: bool) -> String:
	return "%s%s|%s|%d|%d|%s|%d|%d" % [
		REPLY_PREFIX, host_id, sanitize(room_name), players, max_players, sanitize(level_name), port, 1 if started else 0]


## Returns {} for anything that is not a well-formed room reply.
static func parse_reply(msg: String) -> Dictionary:
	if not msg.begins_with(REPLY_PREFIX):
		return {}
	var parts := msg.substr(REPLY_PREFIX.length()).split("|")
	if parts.size() != 7:
		return {}
	for i in [2, 3, 5, 6]:
		if not String(parts[i]).is_valid_int():
			return {}
	var port := int(parts[5])
	if port < 1 or port > 65535:
		return {}
	return {
		"host_id": parts[0],
		"name": parts[1],
		"players": int(parts[2]),
		"max": int(parts[3]),
		"level": parts[4],
		"port": port,
		"started": int(parts[6]) == 1,
	}


static func is_ipv4(ip: String) -> bool:
	var parts := ip.split(".")
	if parts.size() != 4:
		return false
	for p in parts:
		if not String(p).is_valid_int() or int(p) < 0 or int(p) > 255:
			return false
	return true


## 10/8, 172.16/12 and 192.168/16: the ranges phone hotspots and home routers
## hand out. (169.254/16 is excluded on purpose: that is "no network" and
## would only ever show a useless address.)
static func is_private_ipv4(ip: String) -> bool:
	if not is_ipv4(ip):
		return false
	var p := ip.split(".")
	var a := int(p[0])
	var b := int(p[1])
	return a == 10 or (a == 172 and b >= 16 and b <= 31) or (a == 192 and b == 168)


## Keeps just the addresses worth showing or probing from a list like
## IP.get_local_addresses() (which also returns IPv6, loopback, link-local).
static func lan_addresses(all_addresses: Array) -> Array:
	var out: Array = []
	for ip in all_addresses:
		if is_private_ipv4(String(ip)) and not out.has(ip):
			out.append(String(ip))
	return out


## "192.168.43.17" -> "192.168.43.255". Assumes a /24, which is what Android
## hotspots, most routers and the probe scan below all use; a smaller subnet
## just ignores the extra probes.
static func directed_broadcast(ip: String) -> String:
	var p := ip.split(".")
	return "%s.%s.%s.255" % [p[0], p[1], p[2]]


## Every address a probe should go to, given this device's own LAN addresses.
static func scan_targets(local_lan_ips: Array) -> Array:
	var targets: Array = [LOOPBACK, LIMITED_BROADCAST]
	for ip in local_lan_ips:
		var p: PackedStringArray = String(ip).split(".")
		var prefix := "%s.%s.%s." % [p[0], p[1], p[2]]
		targets.append(prefix + "255")
		for host in range(1, 255):
			var candidate := prefix + str(host)
			if candidate != ip and not targets.has(candidate):
				targets.append(candidate)
	return targets
