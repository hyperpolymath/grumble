// SPDX-License-Identifier: PMPL-1.0-or-later
// Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath) <j.d.a.jewell@open.ac.uk>
//
// Burble Signaling Relay — Deno Deploy version.
// Ephemeral room-name rendezvous. Rooms expire after 60 seconds.
// No data persisted. No accounts. No logs. No tracking.
//
// Deploy: deployctl deploy --project=burble-relay signaling/relay-deno-deploy.ts

const rooms = new Map<string, { data: string; expires: number }>();

// Cleanup expired entries
setInterval(() => {
  const now = Date.now();
  for (const [k, v] of rooms) {
    if (now > v.expires) rooms.delete(k);
  }
}, 10_000);

// CORS origin policy.
// This is a PUBLIC WebRTC signaling relay — browsers from any origin need to
// reach it for the rendezvous handshake. Wildcard "*" is the safe default
// because signaling carries only ephemeral SDP blobs (no credentials, no
// session tokens).
//
// To restrict in production, set ALLOWED_ORIGINS in the Deno Deploy dashboard
// (comma-separated):
//   ALLOWED_ORIGINS=https://burble.example.com,https://app.example.com
const ALLOWED_ORIGINS = Deno.env.get("ALLOWED_ORIGINS") || "*";

function getCorsHeaders(req: Request): Record<string, string> {
  const origin = req.headers.get("Origin") || "";
  const allowedOrigin = ALLOWED_ORIGINS === "*"
    ? "*"
    : ALLOWED_ORIGINS.split(",").map(o => o.trim()).includes(origin) ? origin : "";
  return {
    "Access-Control-Allow-Origin": allowedOrigin,
    "Access-Control-Allow-Methods": "GET, PUT, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type",
    "Content-Type": "application/json",
  };
}

Deno.serve((req: Request) => {
  const url = new URL(req.url);
  const cors = getCorsHeaders(req);

  if (req.method === "OPTIONS") return new Response(null, { headers: cors });

  if (url.pathname === "/" || url.pathname === "/health") {
    return new Response(JSON.stringify({ ok: true, rooms: rooms.size, service: "burble-relay" }), { headers: cors });
  }

  const match = url.pathname.match(/^\/room\/([a-zA-Z0-9_-]+)\/(offer|answer)$/);
  if (!match) {
    return new Response(JSON.stringify({ error: "not found", usage: "PUT/GET /room/:name/offer or /room/:name/answer" }), { status: 404, headers: cors });
  }

  const [, name, type] = match;
  const key = `${name}:${type}`;

  // PUT — store with 60s TTL
  if (req.method === "PUT") {
    return req.text().then(body => {
      rooms.set(key, { data: body, expires: Date.now() + 60_000 });
      return new Response(JSON.stringify({ ok: true, room: name, type }), { headers: cors });
    });
  }

  // GET — single check (client polls)
  if (req.method === "GET") {
    const entry = rooms.get(key);
    if (entry && Date.now() < entry.expires) {
      const data = entry.data;
      if (type === "answer") rooms.delete(key); // one-shot
      return new Response(data, { headers: cors });
    }
    return new Response(JSON.stringify({ error: "not ready" }), { status: 404, headers: cors });
  }

  return new Response(JSON.stringify({ error: "method not allowed" }), { status: 405, headers: cors });
});
