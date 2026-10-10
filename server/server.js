// Fogbound signalling server (design doc section 4.3).
//
// This is NOT required to play Fogbound over a local Wi-Fi hotspot --
// the MVP game (see docs/WALKTHROUGH.md phases 1-5) uses Godot's
// ENetMultiplayerPeer directly and never touches this file.
//
// This server exists only to support the *online* room-code mode
// (phase 6, not yet wired into the Godot project): it hands out
// short room codes and relays WebRTC handshake messages (offer /
// answer / ICE candidates) between a host and its clients so they
// can open a direct peer-to-peer data channel. No gameplay traffic
// (player positions, tether state, scores) ever passes through this
// server -- once the WebRTC data channel is open, Godot's
// WebRTCMultiplayerPeer takes over and this server is no longer in
// the loop for that match.
//
// Run locally:
//   cd server && npm install && npm start
//
// Then point a Godot client's net_online.gd SIGNAL_URL at
// ws://<this-machine's-IP>:8080 (or wss://... behind a reverse proxy
// with TLS in production -- browsers and most mobile stacks require
// wss:// for anything not on localhost).

const { WebSocketServer } = require("ws");
const { randomInt } = require("crypto");

const PORT = process.env.PORT || 8080;
const ALPHABET = "ABCDEFGHJKMNPQRSTUVWXYZ23456789"; // 31 chars, no I L O 0 1
const MAX_PLAYERS = 16;
const ROOM_TTL_MS = 2 * 60 * 60 * 1000; // expire never-started rooms after 2h

// code -> { host, clients: Map(id -> ws), nextId, started, createdAt }
const rooms = new Map();

function send(ws, msg) {
  if (ws && ws.readyState === 1 /* OPEN */) {
    ws.send(JSON.stringify(msg));
  }
}

function newCode() {
  let code;
  do {
    code = Array.from({ length: 5 }, () => ALPHABET[randomInt(ALPHABET.length)]).join("");
  } while (rooms.has(code));
  return code;
}

function cleanupStaleRooms() {
  const now = Date.now();
  for (const [code, room] of rooms.entries()) {
    if (!room.started && now - room.createdAt > ROOM_TTL_MS) {
      rooms.delete(code);
    }
  }
}
setInterval(cleanupStaleRooms, 10 * 60 * 1000);

const wss = new WebSocketServer({ port: PORT, maxPayload: 16 * 1024 });

wss.on("connection", (ws) => {
  ws.on("message", (raw) => {
    let m;
    try {
      m = JSON.parse(raw);
    } catch {
      return; // ignore malformed payloads rather than crashing the connection
    }

    switch (m.type) {
      case "create_room": {
        const code = newCode();
        rooms.set(code, {
          host: ws,
          clients: new Map(),
          nextId: 2,
          started: false,
          createdAt: Date.now(),
        });
        ws.room = code;
        ws.peerId = 1;
        send(ws, { type: "room_created", code });
        break;
      }

      case "join_room": {
        const code = String(m.code || "").toUpperCase();
        const room = rooms.get(code);
        if (!room) return send(ws, { type: "error", reason: "no_such_room" });
        if (room.started) return send(ws, { type: "error", reason: "already_started" });
        if (room.clients.size >= MAX_PLAYERS - 1) return send(ws, { type: "error", reason: "room_full" });

        const id = room.nextId++;
        room.clients.set(id, ws);
        ws.room = code;
        ws.peerId = id;
        send(ws, { type: "joined", id });
        send(room.host, { type: "peer_joined", id });
        break;
      }

      case "offer":
      case "answer":
      case "candidate": {
        const room = rooms.get(ws.room);
        if (!room) return;
        const target = m.to === 1 ? room.host : room.clients.get(m.to);
        send(target, { ...m, from: ws.peerId });
        break;
      }

      case "start_match": {
        const room = rooms.get(ws.room);
        if (room && ws === room.host) room.started = true;
        break;
      }

      default:
        break; // unknown message type, ignore
    }
  });

  ws.on("close", () => {
    const room = rooms.get(ws.room);
    if (!room) return;

    if (ws === room.host) {
      for (const client of room.clients.values()) {
        send(client, { type: "error", reason: "host_left" });
      }
      rooms.delete(ws.room);
    } else {
      room.clients.delete(ws.peerId);
      send(room.host, { type: "peer_left", id: ws.peerId });
    }
  });
});

console.log(`Fogbound signalling server listening on ws://0.0.0.0:${PORT}`);
