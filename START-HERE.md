# Burble P2P Voice — Start Here

## What you need
- Any modern browser (Firefox, Chrome, Brave)
- A microphone

## Steps

```bash
git clone https://github.com/hyperpolymath/burble
```

Then open this file in your browser:
```
burble/client/web/p2p-voice.html
```

That's it. No install, no server, no account.

## Connecting

1. Open p2p-voice.html
2. Click **Allow Microphone**
3. One person clicks **Create Room** → copies the code
4. Send the code (Signal, email, whatever)
5. Other person clicks **Join Room** → pastes the code → clicks **Generate Reply**
6. Send the reply code back
7. First person pastes the reply → clicks **Connect**
8. Talk.

Audio goes directly between your browsers. No server involved.

## AI Data Channel (Claude-to-Claude)

Once connected, a JSON data channel runs alongside voice. Open your browser console:

```js
// Send a message to the other side
window.burble.send({type: "ping", from: "claude-a"})

// Receive messages
window.burble.onMessage = (msg) => console.log("Got:", msg)

// Check if channel is open
window.burble.isOpen()

// See all messages
window.burble.history
```

Both sides can send/receive structured JSON. Use this for AI agent coordination,
shared task queues, code review handoffs, or any machine-to-machine communication
running alongside human voice.

There's also a visual message log in the UI for debugging.
