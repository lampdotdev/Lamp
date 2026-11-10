// STAND-IN for lamp.dev/w/<id>: opens a room on the local relay prototype, shows the pairing code, frames the game
// from its own origin, sends what the player asks for, and puts each new build into the frame.
//
// The page's secret stays in this script's memory: never in a URL (addresses get logged), never where the game's
// origin could read it. The event stream is read with fetch so the secret goes in a header, and it's opened again
// from the last event it had when it drops.

const $ = (id) => document.getElementById(id);
let secret = null, lastSeq = 0, shown = 0, lastRoom = null;

const minutes = (ms) => { const n = Math.max(1, Math.round(ms / 60000)); return n === 1 ? "a minute" : `${n} minutes`; };
const say = (text) => { $("status").textContent = text; };

async function api(path, body) {
  const response = await fetch(path, {
    method: "POST", headers: { "Content-Type": "application/json", ...(secret ? { Authorization: `Bearer ${secret}` } : {}) },
    body: JSON.stringify(body ?? {}),
  });
  const answer = await response.json().catch(() => ({}));
  if (!response.ok) throw Object.assign(new Error(answer.error ?? `HTTP ${response.status}`), { status: response.status });
  return answer;
}

function showRoom(room) {
  lastRoom = room;
  if (room.version && room.version !== shown) show(room.version, room.play);
  $("pair").hidden = room.paired;
  $("ask").hidden = !room.paired;
  if (!room.paired) {
    const expired = !room.code || room.expires <= Date.now();
    $("command").textContent = expired ? "lamp play ······" : `lamp play ${room.code}`;
    $("expires").textContent = expired ? "This code has run out." : `The code works once, for ${minutes(room.expires - Date.now())}.`;
    $("new-code").hidden = !expired;
    say("Waiting for your Mac…");
  } else say(room.helper ? "Your Mac is connected. Ask for a change." : "Your Mac was connected and has gone away. Changes wait until it's back.");
  $("requests").replaceChildren();
  for (const request of room.requests ?? []) showRequest(request);
}

function show(version, play) {
  shown = version;
  $("game").src = play;
  document.body.dataset.version = String(version);
}

function showRequest(request) {
  let item = document.querySelector(`[data-request="${request.id}"]`);
  if (!item) { item = document.createElement("li"); item.dataset.request = request.id; $("requests").prepend(item); }
  item.dataset.state = request.state;
  const words = { queued: "waiting", running: "your agent is working", done: `done: version ${request.version}`, failed: "didn't work", unchanged: "nothing changed" }[request.state] ?? request.state;
  item.textContent = `${request.prompt}: ${words}${request.message ? ` (${request.message})` : ""}`;
  if (request.state === "running") say("Your agent is working on it…");
  if (request.state === "failed") say("That didn't work. The game is as it was.");
  if (request.state === "unchanged") say("Your agent finished without changing the game.");
}

async function listen() {
  for (;;) {
    try {
      const response = await fetch(`/api/page/events?since=${lastSeq}`, { headers: { Authorization: `Bearer ${secret}` } });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const reader = response.body.pipeThrough(new TextDecoderStream()).getReader();
      let buffer = "";
      for (;;) {
        const { value, done } = await reader.read();
        if (done) break;
        buffer += value;
        let end;
        while ((end = buffer.indexOf("\n\n")) >= 0) {
          const block = buffer.slice(0, end); buffer = buffer.slice(end + 2);
          const fields = Object.fromEntries(block.split("\n").filter((line) => !line.startsWith(":")).map((line) => [line.slice(0, line.indexOf(":")), line.slice(line.indexOf(":") + 1).trim()]));
          if (fields.id) lastSeq = Math.max(lastSeq, Number(fields.id));
          if (!fields.data) continue;
          const data = JSON.parse(fields.data);
          if (fields.event === "room") showRoom(data);
          else if (fields.event === "request") showRequest(data);
          else if (fields.event === "build") { show(data.version, data.play); say(`New version ${data.version} is in.`); }
        }
      }
    } catch {}
    say("Reconnecting…");
    await new Promise((done) => setTimeout(done, 1000));
  }
}

$("ask").addEventListener("submit", async (event) => {
  event.preventDefault();
  const prompt = $("prompt").value.trim();
  if (!prompt) return;
  // The request's id is made here, so sending it again after a dropped answer can't make a second one.
  const id = crypto.randomUUID();
  for (let attempt = 0; attempt < 3; attempt++) {
    try { showRequest(await api("/api/page/requests", { id, prompt })); $("prompt").value = ""; return; }
    catch (error) { if (error.status) { say(error.message === "no_helper" ? "Pair your Mac first." : "That request wasn't taken."); return; } }
    await new Promise((done) => setTimeout(done, 1000));
  }
  say("The relay didn't answer.");
});

$("new-code").addEventListener("click", async () => { try { showRoom(await api("/api/page/code")); } catch { say("No new code."); } });

(async () => {
  try {
    const room = await api("/api/rooms");
    secret = room.secret;
    showRoom(room);
    listen();
    // The code's time left, said again as it runs down.
    setInterval(() => { if (lastRoom && !lastRoom.paired) showRoom(lastRoom); }, 10_000);
  } catch { say("The relay isn't answering."); }
})();
