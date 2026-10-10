# Fogbound: Design & Architecture Document (v3)

A 2D multiplayer maze game for up to 16 players. Players form one team or several smaller teams, enter a foggy room with diminished vision, stay linked by "held hands" tethers, and use random clue objects to find the way out. Stretch a tether too far and it snaps for good.

Engine: Godot 4.x. Networking: hybrid. Local Wi-Fi hotspot play (Mini Militia style) and remote play through room codes.

All numbers in this document are starting values for playtesting, not final balance. All code is a reference sketch and has not been run.

---

## 0. What Changed From v2

| Area | v2 | v3 |
|---|---|---|
| Tether model | Linear pull between safe and snap distance | Spring-damper force with a 4-state tension machine |
| Snapping | Instant at 100% | Instant, except a 1.5 s buffer when the rope is snagged on a wall corner |
| Vision | Fixed circle | 5 m normal, 1.5 m in fog, shared lantern light, wall-blocked sight |
| Networking | Hotspot only | Hybrid: hotspot (ENet) plus online room codes (WebSocket signalling + WebRTC P2P with STUN/TURN) |
| Clues | Pickup objects | Code fragments from the outer maze, decoded at a console in the fog room |
| Lobby | Basic | Room code banner, pod matrix, ready toggles |

### Glossary

| Term | Meaning |
|---|---|
| Team | A group formed in the lobby. Its size at match start is the "original size" used for scoring |
| Pod | A connected group of players during the match. A snap can split a team into several pods |
| Link | A tether between two players |
| Tension | Rope length divided by maximum length (0 to 100%) |
| Fog room | The dense foggy room in the middle of the maze |
| Fragment | A clue object that holds part of the exit code |
| Console | The decoding terminal where a pod enters the exit sequence |
| Host | The device that runs all game rules and physics |

---

## 1. Concept Summary

| Item | Description |
|---|---|
| Genre | 2D top-down team maze / survival puzzle |
| Players | 2 to 16 per match |
| Teams | One large team or several smaller ones (minimum 2 members each) |
| Setting | A maze with a dense, claustrophobic foggy room in the middle |
| Core mechanic | Diminished vision plus a tether that stretches, pulls and can snap |
| Win condition | A pod reaches the exit. Score depends on how intact the team stayed |
| Multiplayer | Local hotspot host, or online room code. One transport per match |

**One-line pitch:** Nobody can see far, nobody can let go, and one wrong sprint can cut your team in half.

---

## 2. Core Gameplay Loop

1. Players open a room (local hotspot or online code) and gather in the lobby.
2. Players group themselves into pods (teams). Every team needs at least 2 members.
3. The host starts the match. Maze, clue positions and fragments come from a shared seed.
4. Everyone spawns in the fog room at the centre, tethered in chain order.
5. Teams travel out into the maze and read fragment objects scattered in the outer maze.
6. Teams return to the console in the fog room, enter the decoded sequence, and the exit gate unlocks.
7. Teams reach the exit. Tethers may snap along the way, splitting teams into smaller pods.
8. Any pod that drops below 2 members is eliminated. Pods that reach the exit score by size.

> Assumption A1: the source notes describe clues in the "outer maze" and decoding "in the foggy centre", while the original brief says "make it out of the foggy room". This document reconciles them as: spawn in the fog room, collect fragments outside, decode at the console in the fog room, exit at the maze perimeter. The maze generator takes spawn, console and exit positions as config, so flipping this later is cheap. See section 14.

---

## 3. Key Mechanics

### 3.1 Units and Scale

Use one consistent scale everywhere.

| Quantity | Meters | Pixels (1 m = 1 tile = 16 px) |
|---|---|---|
| Tile size | 1 | 16 |
| Move speed | 4 m/s | 64 px/s |
| Normal vision radius | 5 | 80 |
| Fog vision radius | 1.5 | 24 |
| Lantern bonus in fog | +1.5 | +24 |
| Tether rest length L0 | 3 | 48 |
| Tether max distance D_max | 6 | 96 |
| Snag buffer | 1.5 s | not applicable |
| Reference viewport | not applicable | 320 x 180 (20 x 11 tiles) |

### 3.2 Fog, Vision and Shared Light

- Normal vision is 5 m. Inside the fog room it shrinks to 1.5 m, tweened over about 0.4 s when crossing the room boundary.
- Walls block sight. Vision is a raycast-style field of view, done with `PointLight2D` plus `LightOccluder2D` on walls.
- Other pods are visible only if inside your lit area.
- Light-emitting items (lantern, glow relic) can be carried and share light with linked teammates:

| Player | Vision radius in fog |
|---|---|
| Normal | 1.5 m |
| Carrying a lantern | 3.0 m |
| Directly linked to a lantern carrier (link intact) | 2.25 m |

Because the green tether zone reaches 3 m and fog vision is only 1.5 m, teammates will often be out of each other's sight but still connected. That is intentional: the tether line is always drawn for your own pod, even through fog, and it is the main way players read where their team is.

### 3.3 Tether Physics (Spring-Damper)

Each link behaves like a rope with a rest length. It only pulls, never pushes, and it is slack until the rope is longer than L0.

```
F = -k (d - L0) - c (v_rel)        applied only while d > L0, and clamped so it never pushes
```

| Symbol | Meaning | Starting value |
|---|---|---|
| k | Spring stiffness | 10 (1/s^2) |
| c | Damping coefficient, about 2 x sqrt(k x m) for critical damping | 6.3 |
| d | Effective rope length (see 3.4) | measured |
| L0 | Rest length | 48 px |
| v_rel | Rate of change of rope length | measured |
| m | Player mass | 1 |

Because players are kinematic bodies, the force is converted into a separate `pull_velocity` that is added to input velocity and then capped by tension state.

### 3.4 Tension State Machine

Tension is the effective rope length as a fraction of the maximum:

```
tension = d / D_max          (D_max = 96 px)
```

| State | Tension | Rope length | Line colour | Pull cap (x move speed) | Feedback |
|---|---|---|---|---|---|
| Green (Safe) | 0 to 50% | up to 48 px | Green | 0 | None. Independent movement |
| Yellow (Warning) | 50 to 80% | 48 to 77 px | Yellow | 0.25 | Line stretches, creak SFX. Minor drag resistance |
| Red (Danger) | 80 to 99% | 77 to 95 px | Red | 0.8 | Trailing players are dragged along the leader's vector. Flash and haptic buzz from 90% |
| Critical (Dark Red / Black) | 100% | 96 px | Dark red / black | 0.8 | Link snaps permanently |
| Snapped | not applicable | not applicable | Line removed | not applicable | Pods recomputed |

Rough check on the starting numbers: a leader sprinting straight away from a stationary follower gets from first tension to snap in about 2 s (0.6 s in yellow, 1.5 s in red). That is the reaction window. Widen it by lowering the red pull cap or raising D_max.

State transitions use a small hysteresis so the colour does not flicker at boundaries.

```gdscript
enum Tension { GREEN, YELLOW, RED, CRITICAL, SNAPPED }
const EDGES := [0.50, 0.80, 1.00]   # upper bound of GREEN, YELLOW, RED
const HYST := 0.02

static func next_state(t: float, cur: int) -> int:
    var s := cur
    while s < Tension.CRITICAL and t >= EDGES[s]:
        s += 1
    while s > Tension.GREEN and t < EDGES[s - 1] - HYST:
        s -= 1
    return s
```

### 3.5 Rope Wrapping and the Corner Snag Buffer

The rope wraps around wall corners instead of passing through them.

- **Effective length d:** if there is a clear line between two players, d is the straight distance. Otherwise d is the length of the taut path around the corners, found with `AStarGrid2D` on the maze grid and then "string-pulled" (greedy: from the current anchor jump to the farthest waypoint with a clear line).
- **Force direction:** each player is pulled along the first rope segment leading from them, so the pull bends around corners the way a real rope would.
- **Snag:** a link is snagged when it has no straight line of sight (the rope is wrapped on geometry).
- **Buffer:** at 100% tension, a snagged link does not snap immediately. It stays Critical for up to 1.5 s (flashing dark red, with a countdown ring) and snaps only if tension is still 100% when the timer ends. If tension drops, the timer drains. An unsnagged link at 100% snaps immediately.

Reference sketch of the host-side tether system:

```gdscript
# tether_system.gd (host only)
const D_MAX := 96.0
const L0 := 48.0
const K := 10.0
const C := 6.3
const SNAG_BUFFER := 1.5
const MOVE_SPEED := 64.0
const PULL_FRICTION := 10.0                 # stops pull from coasting
const PULL_CAP := [0.0, 0.25, 0.8, 0.8]     # GREEN, YELLOW, RED, CRITICAL

func _physics_process(delta: float) -> void:
    for p in players:
        p.pull_velocity -= p.pull_velocity * PULL_FRICTION * delta
        p.pull_cap = 0.0
    for link in links:
        if link.alive:
            _step_link(link, delta)
    for p in players:
        p.pull_velocity = p.pull_velocity.limit_length(p.pull_cap * MOVE_SPEED)

func _step_link(link, delta: float) -> void:
    var a = link.a
    var b = link.b
    var path := _rope_path(a.position, b.position)   # taut points a -> b
    var d := _path_length(path)
    link.snagged = path.size() > 2
    link.tension = d / D_MAX
    link.state = next_state(link.tension, link.state)

    var stretch := maxf(d - L0, 0.0)
    if stretch > 0.0:
        var dir_a := (path[1] - a.position).normalized()
        var dir_b := (path[path.size() - 2] - b.position).normalized()
        var d_dot := -a.velocity.dot(dir_a) - b.velocity.dot(dir_b)   # v_rel
        var f := maxf(K * stretch + C * d_dot, 0.0)                    # rope only pulls
        a.pull_velocity += dir_a * f * delta
        b.pull_velocity += dir_b * f * delta

    a.pull_cap = maxf(a.pull_cap, PULL_CAP[link.state])
    b.pull_cap = maxf(b.pull_cap, PULL_CAP[link.state])

    if link.state == Tension.CRITICAL:
        link.snap_timer += delta
        var limit := SNAG_BUFFER if link.snagged else 0.0
        if link.snap_timer >= limit:
            _snap(link)
    else:
        link.snap_timer = maxf(link.snap_timer - delta * 2.0, 0.0)

func _snap(link) -> void:
    link.alive = false
    pod_graph.recompute()
    net.rpc("net_link_snapped", link.a.peer_id, link.b.peer_id)
    _eliminate_small_pods()

func _rope_path(from: Vector2, to: Vector2) -> PackedVector2Array:
    if _clear(from, to):
        return PackedVector2Array([from, to])
    var pts := grid.get_point_path(_cell(from), _cell(to))
    return _pull_taut(from, pts, to)

func _pull_taut(from: Vector2, pts: PackedVector2Array, to: Vector2) -> PackedVector2Array:
    var out := PackedVector2Array([from])
    var anchor := from
    var i := 0
    while i < pts.size():
        var j := pts.size() - 1
        while j > i and not _clear(anchor, pts[j]):
            j -= 1
        anchor = pts[j]
        out.append(anchor)
        i = j + 1
    out.append(to)
    return out
```

Performance note: the A* path runs only for snagged links, at most 15 links in a chain of 16, and can be throttled to every 2 to 3 physics ticks.

### 3.6 Snapping and Team Splitting

- A snap is permanent for that link.
- The pod graph is recomputed and the team fractures into smaller pods.
- Pods keep only the clue knowledge their own members collected (see 3.9).
- Example: a chain of 8 snaps between player 4 and player 5 and becomes two pods of 4.

### 3.7 Tether Topology

| Mode | Description | Pros | Cons |
|---|---|---|---|
| Chain | Each player holds the previous player's hand | Simple, clear visuals, clean splits | One runaway leader drags the line |
| Ring / graph | Any teammate can link to any other | Redundant links, one snap does not split | More physics complexity |
| Leader-based | All tethered to one leader | Simple | Less cooperative |

**Recommendation:** chain, ordered by join sequence in the pod. Ring is a later variant.

### 3.8 Survival and Elimination Rules

| Rule | Detail |
|---|---|
| Minimum team size | 2 members |
| Game over | If a 2-member pod's link snaps, both players are eliminated immediately |
| Dynamic splitting | Larger pods fracture into smaller pods with fragmented clues |
| Solo player | A player left alone (pod of 1) is eliminated |
| Disconnect | Treated like removal from the chain, then pods recomputed (see 4.9) |

### 3.9 Clues, Fragments and the Exit

Clue types:

| Clue | Role | Effect |
|---|---|---|
| Symbol tablet (fragment) | Code | Holds one symbol of the exit sequence and its position in the sequence |
| Map fragment | Helper | Reveals part of the maze layout |
| Compass | Helper | Points roughly toward the exit gate |
| Footprints | Helper | Show a path a previous explorer took |
| Sound source | Helper | Positional audio, louder near the exit |
| Lantern / glow relic | Light | Carriable, shares light with linked teammates (see 3.2) |

Rules:
- Fragments are scattered in the outer maze at seeded random positions.
- Reading a fragment records the reader. It is not consumed, so it can be read again.
- A pod's notebook is the set of fragments read by its current members. After a split, each pod keeps only what its own members read, and can re-read fragments in the world to recover the rest.
- The pod enters the sequence at the console in the fog room. A correct sequence unlocks and reveals the exit gate. Optional: a wrong entry locks the console for 10 s.
- Fragment sequences are generated from the seed on the host. Clients never receive the answer until they read fragments.

### 3.10 Scoring

Only pods that reach the exit score, by how intact their team remained.

| Team state on arrival | Points |
|---|---|
| Complete, unbroken team | 1,200 |
| Half team | 500 |
| Half of the half | 200 |
| Further split | 50 |
| Bare-minimum 2-player squad | 10 |

Tiers are ratio-based (pod size divided by original team size) and data-driven, so they work for team sizes that are not powers of two.

```gdscript
# score_table.gd
const TIERS := [
    {"min_ratio": 1.0,   "points": 1200},
    {"min_ratio": 0.5,   "points": 500},
    {"min_ratio": 0.25,  "points": 200},
    {"min_ratio": 0.125, "points": 50},
    {"min_ratio": 0.0,   "points": 10},
]

static func score_for(pod_size: int, original_size: int) -> int:
    var ratio := float(pod_size) / float(original_size)
    for t in TIERS:
        if ratio >= t.min_ratio:
            return t.points
    return 10
```

Rules: a 2-player squad always scores 10. Multiple pods from one team can each score when they reach the exit (assumed additive, see section 14).

### 3.11 Optional Game Modes

- **Co-op survival:** one big team, best score across the run.
- **Race:** several teams on the same maze.
- **Hunter variant:** a monster in the fog attacks tethers.
- **Timed collapse:** the fog thickens and the room shrinks over time.

---

## 4. Networking: Hybrid Architecture

### 4.1 One Game, Two Transports

The game code is written once against Godot's `multiplayer` API (RPCs, host authority). Only the peer object differs, so switching between local and online is a menu choice, not a rewrite.

```
              +---------------------------------------+
              |  Game code (identical in both modes)  |
              |  host-authoritative rules and physics |
              +-------------------+-------------------+
                                  | multiplayer.multiplayer_peer
                +-----------------+-----------------+
                |                                   |
      ENetMultiplayerPeer                 WebRTCMultiplayerPeer
      (LAN / hotspot, UDP)                (online, P2P data channels)
                |                                   |
      UDP broadcast discovery          Cloud signalling server (WebSocket)
      or manual IP entry               room codes + STUN / TURN
```

Rule: one transport per match. A single Godot multiplayer API instance uses one peer type, so mixed rooms (some players on hotspot, some online) are not supported. Local friends can also join an online room by code.

| | Local (hotspot) | Online (room code) |
|---|---|---|
| Join method | Discover host on LAN, or type IP | Type a 5-character code |
| Transport | ENet (UDP) | WebRTC data channels (UDP-like) |
| Server needed | None | Small signalling server, plus STUN/TURN |
| Latency | Very low | Depends on route, typically higher |
| Extra setup | Hotspot must allow client-to-client traffic | NAT traversal, TURN fallback |
| Failure modes | Broadcast blocked, host phone sleeps | NAT failure, TURN cost, mobile network switches |

### 4.2 Local Mode (Mini Militia Style)

One device turns on its hotspot and hosts. The others join that Wi-Fi.

```gdscript
# net_local.gd (Autoload)
extends Node

const PORT := 7777
const MAX_PLAYERS := 16

func host_game() -> void:
    var peer := ENetMultiplayerPeer.new()
    peer.create_server(PORT, MAX_PLAYERS - 1)     # 15 clients + host
    multiplayer.multiplayer_peer = peer

func join_game(ip: String) -> void:
    var peer := ENetMultiplayerPeer.new()
    peer.create_client(ip, PORT)
    multiplayer.multiplayer_peer = peer
```

LAN discovery (host broadcasts once per second, clients listen):

```gdscript
# lan_discovery.gd
extends Node

const BROADCAST_PORT := 7778
var udp := PacketPeerUDP.new()

func start_advertising(room_name: String) -> void:
    udp.set_broadcast_enabled(true)
    udp.set_dest_address("255.255.255.255", BROADCAST_PORT)
    var timer := Timer.new()
    timer.wait_time = 1.0
    timer.timeout.connect(func():
        udp.put_packet(("FOGBOUND|" + room_name).to_utf8_buffer()))
    add_child(timer)
    timer.start()

func start_listening() -> void:
    udp.bind(BROADCAST_PORT)

func _process(_d):
    while udp.get_available_packet_count() > 0:
        var msg := udp.get_packet().get_string_from_utf8()
        if msg.begins_with("FOGBOUND|"):
            print("Found room at ", udp.get_packet_ip())
```

Some phone hotspots block broadcast. Always provide manual IP entry and optionally a QR code of the host IP.

### 4.3 Online Mode: Room Code System

Components:

| Component | Role |
|---|---|
| Cloud signalling server (WebSocket) | Registers rooms, issues codes, relays connection setup messages. Carries no gameplay traffic |
| STUN server | Lets each device discover its public address (free public STUN servers exist) |
| TURN server | Relay fallback when direct P2P fails, common behind mobile-carrier NAT |
| Host device | Runs the game. Every client opens a WebRTC connection to the host only (star topology) |

Room codes:
- 5 characters from a 31-character alphabet with no I, L, O, 0 or 1 (for example `MZ749`). That gives about 28.6 million codes.
- Generated with a cryptographically secure random source, checked for uniqueness.
- Rooms expire if the host disconnects, or after a timeout if never started. Rooms lock when the match starts (no late joins in v1).

Connection flow:

1. Host taps "Create Online Room". The app opens a WebSocket and sends `create_room`.
2. The server replies with a code. The lobby shows it in the banner.
3. A client enters the code. The server assigns the client a peer id (2 to 16) and tells the host.
4. The client creates a WebRTC offer for the host. Offer, answer and ICE candidates are relayed through the server.
5. STUN finds direct paths. If none works, TURN relays.
6. Once the data channel opens, `multiplayer.peer_connected` fires exactly as in local mode. Signalling is no longer needed and gameplay flows peer to peer.

Signalling messages:

| Message | Direction | Purpose |
|---|---|---|
| `create_room` | host to server | Ask for a new room |
| `room_created {code}` | server to host | Return the code |
| `join_room {code}` | client to server | Join by code |
| `joined {id}` | server to client | Assigned peer id |
| `peer_joined {id}` / `peer_left {id}` | server to host | Roster changes |
| `offer` / `answer` / `candidate` | relayed via server | WebRTC handshake, addressed with `to`, stamped with `from` |
| `start_match` | host to server | Lock the room |
| `error {reason}` | server to any | `no_such_room`, `room_full`, `already_started`, `host_left` |

Signalling server (Node.js, roughly 60 lines with the `ws` package):

```js
// server.js   (npm i ws)
const { WebSocketServer } = require("ws");
const { randomInt } = require("crypto");

const ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"; // 31 chars, no I L O 0 1
const MAX_PLAYERS = 16;
const rooms = new Map(); // code -> { host, clients: Map(id -> ws), nextId, started }

const send = (ws, msg) => ws && ws.readyState === 1 && ws.send(JSON.stringify(msg));

function newCode() {
  let code;
  do {
    code = Array.from({ length: 5 }, () => ALPHABET[randomInt(ALPHABET.length)]).join("");
  } while (rooms.has(code));
  return code;
}

const wss = new WebSocketServer({ port: process.env.PORT || 8080, maxPayload: 16 * 1024 });

wss.on("connection", (ws) => {
  ws.on("message", (raw) => {
    let m;
    try { m = JSON.parse(raw); } catch { return; }

    if (m.type === "create_room") {
      const code = newCode();
      rooms.set(code, { host: ws, clients: new Map(), nextId: 2, started: false });
      ws.room = code; ws.peerId = 1;
      send(ws, { type: "room_created", code });

    } else if (m.type === "join_room") {
      const code = String(m.code || "").toUpperCase();
      const room = rooms.get(code);
      if (!room) return send(ws, { type: "error", reason: "no_such_room" });
      if (room.started) return send(ws, { type: "error", reason: "already_started" });
      if (room.clients.size >= MAX_PLAYERS - 1) return send(ws, { type: "error", reason: "room_full" });
      const id = room.nextId++;
      room.clients.set(id, ws);
      ws.room = code; ws.peerId = id;
      send(ws, { type: "joined", id });
      send(room.host, { type: "peer_joined", id });

    } else if (["offer", "answer", "candidate"].includes(m.type)) {
      const room = rooms.get(ws.room);
      if (!room) return;
      const target = m.to === 1 ? room.host : room.clients.get(m.to);
      send(target, { ...m, from: ws.peerId });

    } else if (m.type === "start_match") {
      const room = rooms.get(ws.room);
      if (room && ws === room.host) room.started = true;
    }
  });

  ws.on("close", () => {
    const room = rooms.get(ws.room);
    if (!room) return;
    if (ws === room.host) {
      room.clients.forEach((c) => send(c, { type: "error", reason: "host_left" }));
      rooms.delete(ws.room);
    } else {
      room.clients.delete(ws.peerId);
      send(room.host, { type: "peer_left", id: ws.peerId });
    }
  });
});
```

Godot client (host and client share one script):

```gdscript
# net_online.gd (Autoload)
extends Node

signal room_created(code: String)
signal join_failed(reason: String)

const SIGNAL_URL := "wss://signal.example.com"
const RTC_CONFIG := {"iceServers": [
    {"urls": ["stun:stun.l.google.com:19302"]},
    # {"urls": ["turn:turn.example.com:3478"], "username": "user", "credential": "secret"},
]}

var ws := WebSocketPeer.new()
var rtc := WebRTCMultiplayerPeer.new()
var conns := {}          # peer_id -> WebRTCPeerConnection
var first_msg := ""
var opened := false

func host_room() -> void:
    rtc.create_server()
    multiplayer.multiplayer_peer = rtc
    _open({"type": "create_room"})

func join_room(code: String) -> void:
    _open({"type": "join_room", "code": code})

func _open(msg: Dictionary) -> void:
    first_msg = JSON.stringify(msg)
    ws.connect_to_url(SIGNAL_URL)

func _process(_d: float) -> void:
    ws.poll()
    if ws.get_ready_state() != WebSocketPeer.STATE_OPEN:
        return
    if not opened:
        opened = true
        ws.send_text(first_msg)
    while ws.get_available_packet_count() > 0:
        _on_message(JSON.parse_string(ws.get_packet().get_string_from_utf8()))

func _on_message(m: Dictionary) -> void:
    match m.type:
        "room_created":
            room_created.emit(m.code)
        "joined":                                    # client side
            rtc.create_client(int(m.id))
            multiplayer.multiplayer_peer = rtc
            _new_conn(1, true)                       # client sends the offer to the host
        "peer_joined":                               # host side
            _new_conn(int(m.id), false)
        "offer", "answer":
            conns[int(m.from)].set_remote_description(m.type, m.sdp)
        "candidate":
            conns[int(m.from)].add_ice_candidate(m.media, int(m.index), m.name)
        "error":
            join_failed.emit(m.reason)

func _new_conn(id: int, make_offer: bool) -> void:
    var pc := WebRTCPeerConnection.new()
    pc.initialize(RTC_CONFIG)
    pc.session_description_created.connect(func(type, sdp):
        pc.set_local_description(type, sdp)
        _send({"type": type, "to": id, "sdp": sdp}))
    pc.ice_candidate_created.connect(func(media, index, name):
        _send({"type": "candidate", "to": id, "media": media, "index": index, "name": name}))
    conns[id] = pc
    rtc.add_peer(pc, id)
    if make_offer:
        pc.create_offer()

func _send(msg: Dictionary) -> void:
    ws.send_text(JSON.stringify(msg))
```

Important platform note: the Web export has WebRTC built in, but Android and desktop exports need the `webrtc-native` GDExtension added to the project. Check its release page for your Godot version and target platforms before committing to this route.

NAT, TURN and hosting:
- STUN alone works for many home networks but fails on strict NATs. Mobile carrier networks commonly use carrier-grade NAT, so plan on a TURN fallback.
- TURN options: self-host `coturn` on a small VPS, or use a hosted TURN service. TURN relays real gameplay traffic, so check current free-tier limits and pricing.
- The signalling server is tiny. A free-tier app host is enough for development, but some free tiers put idle apps to sleep, so the first room creation can be slow. Verify current provider terms.
- Signalling security: rate-limit join attempts per IP (codes are short), cap payload size (done above), delete rooms on host disconnect, and never trust a client-supplied peer id.
- Privacy: WebRTC exposes peers' IP addresses to the host during connection. Mention it in the privacy note if you publish.

### 4.4 Authority and Sync

The host owns physics, the link graph, clue state and scoring. Clients send input and render replicated state.

| Data | Authority | Delivery |
|---|---|---|
| Player input | Owning client | Unreliable, ordered, about 20 to 30 Hz |
| Player snapshots (position, facing, state) | Host | Unreliable, ordered, 20 Hz |
| Per-link tension (1 byte each) | Host | Inside the snapshot |
| Snap events and pod changes | Host | Reliable |
| Maze seed, teams, chain order | Host | Reliable, once at start |
| Fragment reads, notebook changes | Host | Reliable |
| Console attempts and exit unlock | Host | Reliable |
| Pings and markers | Client via host | Reliable (low volume) |
| Scoring, elimination | Host | Reliable |
| Lobby state | Host | Reliable |

The source notes mention "tells/snaps" as critical data. This document reads "tells" as tether events (tension warnings and snaps).

```gdscript
@rpc("any_peer", "call_remote", "unreliable_ordered")
func net_input(dir: Vector2, seq: int) -> void:
    if not multiplayer.is_server(): return
    var sender := multiplayer.get_remote_sender_id()     # never trust an id in the payload
    players[sender].set_input(dir, seq)

@rpc("authority", "call_remote", "unreliable_ordered")
func net_snapshot(packed: PackedByteArray) -> void:
    pass  # decode, push into interpolation buffer

@rpc("authority", "call_remote", "reliable")
func net_link_snapped(a_id: int, b_id: int) -> void:
    pass  # play snap effect, update local pod view
```

Client rendering:
- Remote players are drawn about 100 ms in the past (two snapshot intervals) and interpolated between the two newest snapshots.
- Local mode: little or no prediction is needed at LAN latency.
- Online mode: predict the local player's own movement from input, then softly correct toward the host's authoritative position (which includes pull) when the error exceeds a threshold.

Bandwidth estimate: a 16-player snapshot with link tensions is roughly 130 bytes of payload, about 200 bytes on the wire. At 20 Hz the host sends about 4 KB/s to each client, so roughly 60 KB/s (around 0.5 Mbit/s) upstream at full capacity. Measure it before relying on this.

### 4.5 Fog Privacy

Fog rendering is a client effect. For race modes the host should only send positions of other pods that fall inside a viewer's vision radius, to limit map-hack cheating. In co-op this is unnecessary.

### 4.6 Fragment and Clue Secrecy

Positions of clue objects derive from the seed, but the code sequence itself stays on the host and is revealed only when a player reads a fragment. Keep the sequence out of client memory until then.

### 4.7 Matchmaking Summary

| Step | Local | Online |
|---|---|---|
| Create room | Enable hotspot, tap Host | Tap Create Online Room, receive code |
| Join | Tap a discovered room, or enter IP | Enter the 5-character code |
| Lobby | Host runs it | Host runs it |
| Start | Host taps Start | Host taps Start, server locks the room |

### 4.8 Latency and Tick Rates

- Host physics at 60 Hz. Snapshots every third tick (20 Hz).
- The tether runs entirely on the host, so the rope visual on a client lags the truth by about 100 ms. The tension colour is sent as data, so the warning state is authoritative even if the geometry lags slightly.

### 4.9 Disconnects

- A client that drops is treated as removed from its chain, then pods are recomputed.
- Optional for online mode: a 10 s reconnect window during which the dropped player's avatar freezes and its links are held below Red so a network blip cannot snap the team.
- If the host drops, the match ends for everyone (host migration is out of scope for v1). In online mode the signalling server deletes the room.

---

## 5. Technical Architecture (Godot 4)

### 5.1 Project Structure

```
res://
  autoload/
    net_local.gd
    net_online.gd
    net_router.gd          # picks the transport, exposes one interface
    game_state.gd
    score_table.gd
  scenes/
    main_menu.tscn
    lobby.tscn
    game.tscn
    player.tscn
    clue.tscn
    console.tscn
    exit_gate.tscn
  scripts/
    maze_generator.gd
    tether_system.gd
    pod_graph.gd
    fog_controller.gd
    clue_spawner.gd
    team_manager.gd
  shaders/
    team_palette.gdshader
  assets/
    sprites/
    tilesets/
    audio/
    fonts/
server/
  server.js                # signalling server (Node.js)
```

### 5.2 Scene Tree (Game)

```
Game (Node2D)
 |- CanvasModulate            # near-black, makes everything dark
 |- Maze (TileMapLayer)       # walls carry LightOccluder2D via the TileSet
 |- FogRoom (Area2D)          # sets a player's in_fog flag
 |- Clues (Node2D)
 |- Console (Area2D)
 |- ExitGate (Area2D)
 |- Players (Node2D)
 |    |- Player (CharacterBody2D) x N, each with a PointLight2D
 |- TetherLines (Node2D)      # Line2D per link, coloured by state
 |- HUD (CanvasLayer)
```

### 5.3 Maze Generation

- Recursive backtracker (DFS) or randomised Kruskal on a grid.
- Carve the central fog room first, then corridors outward. Remove a few walls to add loops.
- All randomness uses `RandomNumberGenerator` with the host's seed so every client builds the same maze.
- Placement config: spawn zone, console position (in the fog room) and exit gate (perimeter) are inputs, so the layout in section 2 can be swapped without touching mechanics.
- Build an `AStarGrid2D` from the same grid for rope wrapping (3.5).

### 5.4 Fog Rendering

Use Godot's 2D lighting instead of a flat shader, because it gives wall-blocked vision for free.

- `CanvasModulate` set to near-black.
- Each player in your own pod gets a `PointLight2D` with a radial gradient texture, `shadow_enabled = true`, and `texture_scale = radius_px / (texture_size / 2)`.
- Walls carry occluders from the TileSet occlusion layer.
- Change the radius with a `Tween` when `in_fog` changes or a lantern is picked up or dropped.
- A "seen tiles" memory layer draws explored tiles at low brightness.
- Fallback for weak devices: a simple full-screen circle shader without wall occlusion.

### 5.5 Pod Graph

Players are nodes, alive links are edges. After every snap or disconnect, a flood fill finds connected components. Each component is a pod.

```gdscript
func recompute() -> void:
    pods.clear()
    var visited := {}
    for p in players:
        if visited.has(p): continue
        var pod := []
        var stack := [p]
        while stack.size() > 0:
            var cur = stack.pop_back()
            if visited.has(cur): continue
            visited[cur] = true
            pod.append(cur)
            for n in neighbours_of(cur):       # alive links only
                stack.append(n)
        pods.append(pod)
```

### 5.6 Team Management

- `TeamManager` stores team id, original size (fixed at match start), member ids and chain order.
- Chain order follows the order players joined the pod in the lobby, and can be rearranged there.
- Minimum team size of 2 is enforced before the match can start.

### 5.7 Clue System

- `ClueSpawner` picks floor cells from the seeded RNG and assigns types.
- The host records `read_by[fragment_id] = [player_ids]`. A pod's notebook is every fragment read by any current member.
- After a snap, each pod's notebook is recalculated from its members only.

### 5.8 Player Input on Mobile

- Left thumb: virtual joystick.
- Right side: Ping button, and a Drop / Pick up light-item button.
- Keep the layout minimal. Screens are small and the fog already limits what players can see.

---

## 6. Pre-Game Lobby UI/UX

### 6.1 Layout

```
+--------------------------------------------------------------+
| ROOM CODE   M Z 7 4 9    [ copy ]            Players 12/16   |
+--------------------------------------------------------------+
| UNASSIGNED (2):  [Sam] [Riya]                                |
+--------------------------------------------------------------+
| POD A (4)            | POD B (3)            | POD C (1)      |
|  1 Aman   ready      |  1 Kiran  ready      |  1 Dev   --    |
|  2 Mira   ready      |  2 Zoya   not ready  |  ! Min 2       |
|  3 Jay    ready      |  3 Lee    ready      |  [ Join pod ]  |
|  4 Nia    not ready  |  [ Join pod ]        |                |
+--------------------------------------------------------------+
| [ Ready ]                                       [ START ]    |
+--------------------------------------------------------------+
```

### 6.2 Elements

| Element | Behaviour |
|---|---|
| Room code banner | Large code, 1-tap copy button (copies with `DisplayServer.clipboard_set`), live player counter such as 12/16. In local mode the banner shows the host IP instead |
| Pod matrix | A grid of pod cards. Each shows members in chain order, connection state and warnings. A pod with 1 member shows a "Min 2" warning icon |
| Joining pods | Tap "Join pod" to move yourself. Drag and drop is optional and lets players reorder chain positions |
| Ready toggle | Clients toggle ready / not ready. The host has a Start button instead |
| Unassigned tray | Players who have not chosen a pod |

The pixel font will not contain emoji glyphs. Use small sprite icons for copy and warning instead of emoji characters.

### 6.3 Start Conditions

The Start button is enabled only when all of these are true:

| Condition | Why |
|---|---|
| Every client is ready | Nobody gets dropped in mid-setup |
| No unassigned players | Everyone belongs to a team |
| Every pod has at least 2 members | Minimum team rule |
| At least one pod exists | There is something to play |

If the rules fail, show the reason next to the button, for example "Pod C needs 1 more player".

### 6.4 Lobby Sync

The host owns the lobby state and broadcasts it reliably. Clients only send requests, and the host validates each one.

| Request (client to host) | Host validation |
|---|---|
| `request_join_pod(pod_id)` | Pod exists, total players not above 16 |
| `request_leave_pod()` | Always allowed before start |
| `request_reorder(pod_id, order)` | Only within own pod |
| `set_ready(bool)` | Always allowed |

### 6.5 Join Errors (Online)

| Server reason | Message shown |
|---|---|
| `no_such_room` | "Room not found. Check the code" |
| `room_full` | "Room is full (16/16)" |
| `already_started` | "Match already started" |
| `host_left` | "The host left the room" |

---

## 7. Technology Stack

| Layer | Tool | Reason |
|---|---|---|
| Engine | Godot 4.x | Free, light, strong 2D, built-in networking |
| Language | GDScript (C# optional) | Fast iteration |
| LAN networking | `ENetMultiplayerPeer` + High-Level Multiplayer API | Built in, UDP based |
| LAN discovery | `PacketPeerUDP` broadcast | Simple, no dependencies |
| Online networking | `WebRTCMultiplayerPeer` + `WebRTCPeerConnection` | P2P data channels with reliable and unreliable modes |
| WebRTC on native builds | `webrtc-native` GDExtension | Godot exports other than Web need it |
| Signalling client | `WebSocketPeer` (built in) | No extra library |
| Signalling server | Node.js + `ws` | Tiny, fits a web-developer workflow |
| Server hosting | Small free-tier or low-cost app host | Verify current terms |
| STUN | Free public STUN servers | Address discovery |
| TURN | `coturn` self-hosted, or a hosted TURN service | Fallback for strict NAT |
| Maze | Custom DFS script + `TileMapLayer` + `AStarGrid2D` | Generation and rope wrapping |
| Fog | `CanvasModulate`, `PointLight2D`, `LightOccluder2D` | Wall-blocked vision |
| Touch controls | `TouchScreenButton` or a joystick addon from the Godot Asset Library | Quick mobile input |
| Audio | `AudioStreamPlayer2D` | Positional clue sounds |
| Export (primary) | Android via export templates, Android SDK, JDK | Hotspot play is phone-centric |
| Export (testing) | Windows / Linux desktop builds | Fast local multi-instance testing |
| Version control | Git + GitHub | Fits your existing workflow |

Supporting tools:

| Purpose | Tool | Notes |
|---|---|---|
| Pixel art | Aseprite (paid) or LibreSprite (free) | Sprite sheets and animation |
| Free alternative | Piskel (browser) | No install |
| Tilemaps | Godot's built-in TileSet editor | Avoids an extra tool |
| Sound effects | sfxr / jsfxr / Bfxr | Quick retro effects |
| Music | Bosca Ceoil, LMMS, or CC0 tracks | Free and simple |
| Audio editing | Audacity | Trim and normalise |
| Placeholder art | Kenney.nl CC0 packs | Great for prototypes |
| Multi-client testing | Godot "Run multiple instances" | 2 to 4 players on one PC |
| Network impairment | `tc netem` (Linux) or Clumsy (Windows) | Simulate packet loss and latency |
| Signalling tests | A Node script opening 16 fake sockets | Load and edge-case testing |

---

## 8. Art Pipeline: How Sprites Are Created

### 8.1 Style Direction

- Pixel art, top-down, low resolution, muted palette of 16 to 32 colours.
- The fog and light carry the mood, so keep sprites simple and readable.

### 8.2 Sizes

| Asset | Size | Notes |
|---|---|---|
| Tile | 16 x 16 px | 1 tile = 1 m |
| Player | 16 x 16 px | Same grid as tiles |
| Clue objects | 16 x 16 px | Slight outline so they read in dim light |
| Exit gate, console | 32 x 32 px | Stand out from walls |
| UI icons | 16 x 16 or 24 x 24 px | Integer scale only |
| Viewport | 320 x 180 | Scaled up by integer factors |

Set the texture filter to Nearest and use integer scaling.

### 8.3 Player Sprite

- 4-way movement (left can be a flipped right).
- Animations: idle (2 frames), walk (4), pulled (1 to 2), eliminated (3).
- Team colour through a palette swap, not separate sprites. Draw the character in a base palette with a marker colour (pure magenta) for the team-coloured parts, then recolour with a shader.
- Draw a raised hand on the side facing the tether so "holding hands" reads clearly.

```glsl
shader_type canvas_item;
uniform vec4 team_color : source_color;

void fragment() {
    vec4 c = texture(TEXTURE, UV);
    if (distance(c.rgb, vec3(1.0, 0.0, 1.0)) < 0.1) {
        c.rgb = team_color.rgb;
    }
    COLOR = c;
}
```

### 8.4 Tether Visuals

- `Line2D` between linked players, coloured by tension state (3.4).
- Thins slightly as tension rises, shakes at Red, flashes dark red at Critical.
- A snap particle burst and sound at the moment of breaking.
- Always drawn above the fog for your own pod.

### 8.5 Tileset

- Floor: 2 to 3 variants. Fog room floor: a distinct tile.
- Walls: use Godot terrain sets (auto-tiling) so edges join correctly.
- Add occlusion shapes to wall tiles for light-based vision, and physics shapes for collision.

### 8.6 Workflow

1. Draw in Aseprite or LibreSprite with a fixed palette.
2. Export a sprite sheet PNG plus JSON, or export frames.
3. Import into Godot: filter Nearest, mipmaps off.
4. Build `SpriteFrames` for an `AnimatedSprite2D`.
5. Apply the palette-swap shader per team.

### 8.7 Asset Checklist

| Category | Items |
|---|---|
| Characters | Base sheet: idle, walk, pulled, eliminated |
| Tiles | Floor, wall, fog-room floor, exit floor |
| Objects | Symbol tablet, map fragment, compass, footprints, sound source, lantern, glow relic |
| Interactables | Console (idle, active), exit gate (closed, open) |
| Effects | Snap burst, pickup sparkle, fog noise texture |
| UI | Joystick, ping button, tension ring, copy icon, warning icon, ready checkmark, score panel |
| Fonts | One pixel font |

---

## 9. Audio Design

| Sound | Purpose |
|---|---|
| Footsteps | Soft, gives presence in the fog |
| Tension creak | Loops and rises in pitch with tension (Yellow onward) |
| Critical warning | Sharp pulse from 90% tension |
| Snap | Loud crack followed by a brief silence |
| Fragment read | Small chime |
| Console | Beep per symbol, low buzz on wrong entry, rising tone on success |
| Positional clue | Loop that gets louder near the exit |
| Ambient fog | Low drone |
| Exit reached / elimination | Positive sting / muted low tone |

Generate effects with sfxr, then layer or pitch-shift in Audacity.

---

## 10. In-Game UI and HUD

| Element | Details |
|---|---|
| Tension ring | Ring around your character, coloured by state, with a countdown arc during the snag buffer |
| Team roster | Members with pod status and ready state |
| Notebook | Icons of fragments your pod has read, with sequence positions |
| Ping wheel | "This way", "Clue here", "Danger" |
| Minimap (optional) | Explored tiles only |
| Score screen | Per-pod results using section 3.10 |

Text and icons must stay readable against a dark screen on a phone.

---

## 11. Development Roadmap

| Phase | Goal | Deliverable |
|---|---|---|
| 1 | Maze, movement, lighting-based fog | Walk a fogged random maze |
| 2 | Two offline tethered characters | Spring-damper pull working |
| 3 | Tension states, rope wrapping, snag buffer, snapping | Colours, snaps and pods work offline |
| 4 | LAN networking and lobby | Host and join over hotspot, pod matrix, ready toggles |
| 5 | Fragments, console, exit and scoring | Full win loop with tiered points |
| 6 | Online room codes | Signalling server, WebRTC, STUN/TURN |
| 7 | Art, audio and UI pass | Real sprites, sounds, HUD |
| 8 | Playtest and balance | Tune tether values, vision, clue density, NAT tests |

Suggested time for a solo student: 10 to 14 weeks part-time. Phase 6 is the riskiest. Do it after the local game is fun.

---

## 12. Testing Plan

| Test | How |
|---|---|
| Rules and pods | Unit-test the pod graph and score table with scripted link breaks |
| Tether tuning | Offline sandbox with two characters and sliders for k, c, L0, D_max |
| Multi-instance | 2 to 4 Godot instances on one PC |
| Real hotspot | 3 or more phones on one hotspot, check discovery and latency |
| Online NAT | Host on mobile data, client on home Wi-Fi, and different carriers. Force TURN and check it still works |
| Signalling | Node script opening 16 fake sockets, join, leave, full room, wrong code, host leaving |
| Bad networks | `tc netem` or Clumsy: add loss and latency, check interpolation and snap events |
| Load | 16 real or bot clients, watch host CPU, bandwidth and battery |
| Balance | Log how often teams split, where, and after how long |

---

## 13. Known Challenges and Solutions

| Challenge | Solution |
|---|---|
| Tether jitter over the network | Compute on host only, interpolate on clients, send tension as data |
| Unfair snaps on wall corners | Rope wrapping and the 1.5 s snag buffer |
| Griefing (a player deliberately runs) | Pull cap below move speed, warning window, optional vote to cut a link |
| 16 players over a phone hotspot | Compact snapshots, 20 Hz, positions as 16-bit values |
| Broadcast blocked on some hotspots | Manual IP entry, QR code |
| NAT traversal failures online | TURN fallback, clear error message, retry button |
| TURN cost | Prefer direct P2P, cap match length, measure relay usage |
| Room code guessing | Rate limits per IP, short room lifetime, lock on start |
| Native WebRTC availability | Verify the `webrtc-native` extension for your Godot and Android versions early (phase 6 spike) |
| Input lag online | Client-side prediction for the local player with soft correction |
| Mobile network switch drops a player | 10 s reconnect window in online mode |
| Host phone battery and heat | Modest tick rate, light shaders, keep host screen awake |
| Host disconnect ends the match | Accept for v1, host migration is future work |
| Awkward scoring for odd team sizes | Ratio-based, data-driven tiers |

---

## 14. Open Design Questions

These are gaps or contradictions in the current notes. Defaults used in this document are in brackets.

1. **Layout flow:** where do spawn, console and exit sit? [Spawn in fog room, fragments in outer maze, console in fog room, exit at the perimeter. Alternative: spawn on the perimeter and exit inside the fog room.]
2. **Re-linking:** the notes say a snap "permanently" splits a team, yet also say orphans "scramble to reconnect". Can two pods form a new link? [No re-link in v1. A later option is a hold-hands action within about 1 m.]
3. **Solo orphans:** eliminated instantly, or a short reconnect timer? [Instant, matching the minimum-2 rule.]
4. **Multiple pods from one team:** do their scores add? [Yes.]
5. **Snag buffer scope:** does the 1.5 s buffer apply only when the rope is wrapped on a wall, or to every snap? [Only when snagged.]
6. **Lantern sharing:** who benefits, and by how much? [Carrier 3.0 m, directly linked neighbours 2.25 m.]
7. **Mixed rooms:** can hotspot and online players share one match? [No, one transport per match.]
8. **Wrong code penalty:** lockout or unlimited attempts? [Optional 10 s lockout.]
9. **Match timer:** is there one, and what happens to teams still in the maze when it ends?
10. **Race mode:** can rival teams interfere with each other, or is it pure exploration?

---

## 15. Future Ideas

- Cosmetic hand and rope styles per team.
- Maze themes (cave, dungeon, forest, ruins).
- Voice chat between linked players.
- Replay of the winning pod's path.
- Spectator mode for eliminated players.
- Daily fixed-seed challenge.
- Host migration.

---

## 16. Minimum Viable Version (Start Here)

Build only this first:

1. Seeded maze with a central fog room and lighting-based fog.
2. Two to four players over LAN via hotspot.
3. Spring-damper chain tether with the four tension states and colours.
4. Snapping, pod recomputation and the 2-member elimination rule.
5. Three symbol tablets, one console and one exit.
6. Tiered scoring on arrival.
7. A basic lobby with pod selection and Start.

Add rope wrapping and the snag buffer right after, then online room codes. Everything else layers on once this works.
