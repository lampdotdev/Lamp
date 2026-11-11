// One call to the relay's page side (`/api/relay`, RELAY.md) with the room's page credential, for the change page and
// the idea dialog on a link's page alike. An answer that isn't OK throws, with the relay's error and the HTTP status.
export async function relayCall(op: string, { token, method = "GET", body, query = "" }: { token?: string | null; method?: string; body?: unknown; query?: string } = {}) {
  const response = await fetch(`/api/relay?op=${op}${query}`, {
    method, headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), ...(body ? { "Content-Type": "application/json" } : {}) },
    body: body ? JSON.stringify(body) : undefined,
  });
  const answer = await response.json().catch(() => ({}));
  if (!response.ok) throw Object.assign(new Error(answer.error ?? `HTTP ${response.status}`), { status: response.status });
  return answer;
}
