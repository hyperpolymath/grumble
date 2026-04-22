// Burble AI Bridge — background service worker.
// Maintains bridge connection status and provides badge updates.

const DEFAULT_BRIDGE = "http://localhost:6474";

async function updateBadge() {
  try {
    const { bridgeUrl } = await chrome.storage.local.get("bridgeUrl");
    const url = bridgeUrl || DEFAULT_BRIDGE;
    const res = await fetch(`${url}/status`, { signal: AbortSignal.timeout(2000) });
    const data = await res.json();

    if (data.connected) {
      chrome.action.setBadgeText({ text: "" });
      chrome.action.setBadgeBackgroundColor({ color: "#3fb950" });
      if (data.queued > 0) {
        chrome.action.setBadgeText({ text: String(data.queued) });
      }
    } else {
      chrome.action.setBadgeText({ text: "!" });
      chrome.action.setBadgeBackgroundColor({ color: "#d29922" });
    }
  } catch {
    chrome.action.setBadgeText({ text: "" });
  }
}

// Poll every 5 seconds for badge updates.
setInterval(updateBadge, 5000);
updateBadge();
