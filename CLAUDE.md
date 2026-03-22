# CLAUDE.md — Burble P2P Voice + AI Bridge

## What this is

Burble is a P2P voice chat with an AI data channel. When two people connect via `p2p-voice.html`, their Claude Code instances can also exchange messages over the same encrypted WebRTC link.

## Quick start (receiver side)

You've been sent a room code. Do this:

```bash
git clone https://github.com/hyperpolymath/burble
cd burble

# Start the AI bridge (runs in background)
deno run --allow-net client/web/burble-ai-bridge.js &

# Open the voice client in your browser
xdg-open client/web/p2p-voice.html
```

In the browser:
1. Click **Allow Microphone**
2. Click **Join Room**
3. Paste the code you were sent
4. Click **Generate Reply**
5. Copy the reply code and send it back

Once connected, the AI bridge auto-links. Test it:

```bash
# Check bridge is connected
curl http://localhost:6474/status

# Send a message to the other Claude
curl -X POST http://localhost:6474/send -H "Content-Type: application/json" \
  -d '{"type":"hello","from":"receiver"}'

# Poll for messages from the other side
curl http://localhost:6474/recv
```

## Claude-to-Claude protocol

Messages are JSON over WebRTC DataChannel. No schema enforced — any valid JSON works. Suggested message types:

```json
{"type": "ping"}
{"type": "pong"}
{"type": "task", "action": "review", "file": "src/main.rs", "from": "claude-a"}
{"type": "result", "status": "ok", "findings": [], "from": "claude-b"}
{"type": "chat", "message": "Working on the FFI layer now", "from": "claude-a"}
```

## API reference

All on `localhost:6474`:

| Method | Path | Description |
|--------|------|-------------|
| POST | /send | Send JSON to remote peer |
| GET | /recv | Poll received messages (drains queue) |
| GET | /status | Connection status + queue depth |
| GET | /health | Health check |

## Scope

This CLAUDE.md applies ONLY to the `burble/` directory. Do not modify files outside this directory.

## Build commands

```bash
just p2p-ai        # Start bridge + open P2P voice
just p2p            # Open P2P voice only (no bridge)
just ai-bridge      # Start AI bridge only
just server         # Start Elixir server (for server mode, not needed for P2P)
just test           # Run tests
just build          # Build everything
```

## Architecture

```
Your Claude ←curl→ Deno bridge (:6474) ←WS→ Browser ←WebRTC→ Their Browser ←WS→ Their bridge ←curl→ Their Claude
                                              ↕                      ↕
                                         Voice (DTLS-SRTP, encrypted P2P)
```

## Do not

- Do not modify files outside `burble/`
- Do not install npm packages (use Deno)
- Do not create a central server for the P2P mode
- Do not send real credentials or secrets over the data channel
