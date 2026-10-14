import test from "node:test";
import assert from "node:assert/strict";
import { FeedbackState } from "../src/index.mjs";

const goodPayload = (overrides = {}) => ({
  kind: "bug",
  title: "Map does not load",
  description: "The map stays blank after opening the app.",
  requestId: "123e4567-e89b-42d3-a456-426614174000",
  ...overrides,
});

function storageContext() {
  const data = new Map();
  return {
    storage: {
      async get(key) { return data.get(key); },
      async put(keyOrEntries, value) {
        if (typeof keyOrEntries === "string") data.set(keyOrEntries, value);
        else for (const [key, entry] of Object.entries(keyOrEntries)) data.set(key, entry);
      },
      async delete(key) { return data.delete(key); },
      async list({ prefix = "" } = {}) {
        return new Map([...data.entries()].filter(([key]) => key.startsWith(prefix)));
      },
      async setAlarm() {},
    },
    blockConcurrencyWhile(fn) { return fn(); },
  };
}

function workerEnv(stub = { fetch: async () => new Response("{}") }) {
  return {
    GITHUB_OWNER: "yiming-space",
    GITHUB_REPO: "flight-footprint",
    GITHUB_TOKEN: "test-secret-token",
    RATE_LIMIT_SALT: "test-only-salt",
    FEEDBACK_STATE: {
      idFromName(name) { assert.equal(name, "global-feedback-state"); return name; },
      get() { return stub; },
    },
  };
}

async function send(payload, env = workerEnv(), options = {}) {
  const body = options.raw ?? JSON.stringify(payload);
  return (await import("../src/index.mjs")).default.fetch(new Request("https://feedback.test/v1/feedback", {
    method: "POST",
    headers: { "content-type": options.contentType ?? "application/json", "cf-connecting-ip": "192.0.2.10" },
    body,
  }), env);
}

test("health and unknown routes disclose no configuration", async () => {
  const worker = (await import("../src/index.mjs")).default;
  const health = await worker.fetch(new Request("https://feedback.test/health"), {});
  assert.deepEqual(await health.json(), { ok: true });
  assert.equal(health.headers.get("cache-control"), "no-store");
  const missing = await worker.fetch(new Request("https://feedback.test/nope"), {});
  assert.equal(missing.status, 404);
  assert.doesNotMatch(await missing.text(), /test-secret-token|flight-footprint/);
});

test("rejects content type, malformed UTF-8/JSON, and oversized streamed body", async () => {
  assert.equal((await send(goodPayload(), workerEnv(), { contentType: "text/plain" })).status, 415);
  assert.equal((await send(null, workerEnv(), { raw: "{" })).status, 400);
  const oversized = " ".repeat(32 * 1024 + 1);
  assert.equal((await send(null, workerEnv(), { raw: oversized })).status, 413);
});

test("validates required fields and bounds", async () => {
  for (const payload of [
    goodPayload({ kind: "other" }),
    goodPayload({ title: "tiny" }),
    goodPayload({ description: "short" }),
    goodPayload({ environment: "x".repeat(501) }),
    goodPayload({ requestId: "nope" }),
  ]) assert.equal((await send(payload)).status, 400);
});

test("returns configuration error without echoing secrets", async () => {
  const response = await send(goodPayload(), {});
  assert.equal(response.status, 503);
  assert.deepEqual(await response.json(), { error: "service_not_configured" });
});

test("creates one issue and returns the stored response for a matching retry", async () => {
  const ctx = storageContext();
  let calls = 0;
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (url, init) => {
    calls++;
    assert.equal(url, "https://api.github.com/repos/yiming-space/flight-footprint/issues");
    assert.equal(init.headers.authorization, "Bearer test-secret-token");
    const issue = JSON.parse(init.body);
    assert.equal(issue.title, "[Bug] Map does not load");
    assert.ok(issue.body.includes("<!-- ff-feedback: 123e4567-e89b-42d3-a456-426614174000 -->"));
    return Response.json({ number: 17, html_url: "https://github.com/yiming-space/flight-footprint/issues/17" }, { status: 201 });
  };
  try {
    const state = new FeedbackState(ctx, workerEnv());
    const submit = () => state.fetch(new Request("https://state.internal/submit", {
      method: "POST", body: JSON.stringify({ payload: goodPayload(), ipHash: "hashed-ip" }),
    }));
    const first = await submit();
    const second = await submit();
    assert.equal(first.status, 201);
    assert.deepEqual(await first.json(), { issueNumber: 17, issueUrl: "https://github.com/yiming-space/flight-footprint/issues/17" });
    assert.equal(second.status, 201);
    assert.equal(calls, 1);
  } finally { globalThis.fetch = originalFetch; }
});

test("rejects request ID reuse with different content and rate limits by hashed IP", async () => {
  const ctx = storageContext();
  let calls = 0;
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => {
    calls++;
    return Response.json({ number: calls, html_url: `https://github.com/yiming-space/flight-footprint/issues/${calls}` }, { status: 201 });
  };
  try {
    const state = new FeedbackState(ctx, workerEnv());
    const submit = (payload, ipHash = "same-ip") => state.fetch(new Request("https://state.internal/submit", {
      method: "POST", body: JSON.stringify({ payload, ipHash }),
    }));
    await submit(goodPayload());
    assert.equal((await submit(goodPayload({ title: "Different title" }))).status, 409);
    for (let i = 1; i < 3; i++) await submit(goodPayload({ requestId: `123e4567-e89b-42d3-a456-42661417400${i}` }));
    assert.equal((await submit(goodPayload({ requestId: "123e4567-e89b-42d3-a456-426614174004" }))).status, 429);
    assert.equal(calls, 3);
  } finally { globalThis.fetch = originalFetch; }
});

test("enforces the shared daily cap and escapes environment Markdown", async () => {
  const ctx = storageContext();
  let sentBody;
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (_url, init) => {
    sentBody = JSON.parse(init.body);
    return Response.json({ number: 1, html_url: "https://github.com/yiming-space/flight-footprint/issues/1" }, { status: 201 });
  };
  try {
    const state = new FeedbackState(ctx, workerEnv());
    const request = (payload, ipHash) => state.fetch(new Request("https://state.internal/submit", {
      method: "POST", body: JSON.stringify({ payload, ipHash }),
    }));
    await request(goodPayload({ environment: "`<script>alert(1)</script>`" }), "first-ip");
    assert.ok(sentBody.body.includes("\\`\\<script\\>alert\\(1\\)"));
    await ctx.storage.put("global", Array.from({ length: 50 }, () => Date.now()));
    const capped = await request(goodPayload({ requestId: "123e4567-e89b-42d3-a456-426614174001" }), "second-ip");
    assert.equal(capped.status, 429);
  } finally { globalThis.fetch = originalFetch; }
});

test("keeps an uncertain upstream outcome pending so a retry cannot create a duplicate", async () => {
  const ctx = storageContext();
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async () => { throw new Error("timeout"); };
  try {
    const state = new FeedbackState(ctx, workerEnv());
    const request = () => state.fetch(new Request("https://state.internal/submit", {
      method: "POST", body: JSON.stringify({ payload: goodPayload(), ipHash: "hashed-ip" }),
    }));
    assert.equal((await request()).status, 409);
    const retry = await request();
    assert.equal(retry.status, 409);
    assert.deepEqual(await retry.json(), { error: "submission_uncertain" });
  } finally { globalThis.fetch = originalFetch; }
});

test("keeps timeout receipts pending beyond 24 hours", async () => {
  const ctx = storageContext();
  const originalFetch = globalThis.fetch;
  const originalNow = Date.now;
  let now = originalNow();
  let calls = 0;
  Date.now = () => now;
  globalThis.fetch = async () => {
    calls++;
    if (calls === 1) throw new Error("timeout");
    return Response.json({ incomplete_results: false, items: [] });
  };
  try {
    const state = new FeedbackState(ctx, workerEnv());
    const request = () => state.fetch(new Request("https://state.internal/submit", {
      method: "POST", body: JSON.stringify({ payload: goodPayload(), ipHash: "hashed-ip" }),
    }));
    assert.equal((await request()).status, 409);
    now += 25 * 60 * 60 * 1000;
    assert.equal((await request()).status, 409);
    assert.equal(calls, 2);
  } finally {
    Date.now = originalNow;
    globalThis.fetch = originalFetch;
  }
});

test("reconciles a pending timeout to an existing matching issue without another POST", async () => {
  const ctx = storageContext();
  const originalFetch = globalThis.fetch;
  const originalNow = Date.now;
  let now = originalNow();
  let posts = 0;
  let lookups = 0;
  Date.now = () => now;
  globalThis.fetch = async (url, init) => {
    if (init.method === "POST") { posts++; throw new Error("timeout after GitHub accepted request"); }
    lookups++;
    assert.equal(init.redirect, "error");
    assert.equal(init.headers.authorization, "Bearer test-secret-token");
    const parsed = new URL(url);
    assert.equal(parsed.pathname, "/search/issues");
    assert.equal(parsed.searchParams.get("per_page"), "10");
    assert.equal(parsed.searchParams.get("q"), 'repo:yiming-space/flight-footprint is:issue in:body "123e4567-e89b-42d3-a456-426614174000"');
    return Response.json({
      incomplete_results: false,
      items: [{
        number: 31,
        html_url: "https://github.com/yiming-space/flight-footprint/issues/31",
        body: "Report\n\n<!-- ff-feedback: 123e4567-e89b-42d3-a456-426614174000 -->",
      }],
    });
  };
  try {
    const state = new FeedbackState(ctx, workerEnv());
    const request = () => state.fetch(new Request("https://state.internal/submit", {
      method: "POST", body: JSON.stringify({ payload: goodPayload(), ipHash: "hashed-ip" }),
    }));
    assert.equal((await request()).status, 409);
    now += 31_000;
    const recovered = await request();
    assert.equal(recovered.status, 201);
    assert.deepEqual(await recovered.json(), {
      issueNumber: 31,
      issueUrl: "https://github.com/yiming-space/flight-footprint/issues/31",
    });
    assert.equal((await request()).status, 201);
    assert.equal(posts, 1);
    assert.equal(lookups, 1);
  } finally {
    Date.now = originalNow;
    globalThis.fetch = originalFetch;
  }
});

test("negative reconciliation remains uncertain and is throttled for 30 seconds", async () => {
  const ctx = storageContext();
  const originalFetch = globalThis.fetch;
  const originalNow = Date.now;
  let now = originalNow();
  let calls = 0;
  Date.now = () => now;
  globalThis.fetch = async (_url, init) => {
    calls++;
    if (init.method === "POST") throw new Error("timeout");
    return Response.json({ incomplete_results: false, items: [] });
  };
  try {
    const state = new FeedbackState(ctx, workerEnv());
    const request = () => state.fetch(new Request("https://state.internal/submit", {
      method: "POST", body: JSON.stringify({ payload: goodPayload(), ipHash: "hashed-ip" }),
    }));
    assert.equal((await request()).status, 409);
    now += 31_000;
    assert.equal((await request()).status, 409);
    now += 1_000;
    assert.equal((await request()).status, 409);
    assert.equal(calls, 2);
  } finally {
    Date.now = originalNow;
    globalThis.fetch = originalFetch;
  }
});

test("unexpected GitHub success status or issue URL stays pending for reconciliation", async () => {
  for (const responseFactory of [
    () => new Response(JSON.stringify({ number: 18, html_url: "https://github.com/yiming-space/flight-footprint/issues/18" }), { status: 200 }),
    () => Response.json({ number: 18, html_url: "https://github.com/yiming-space/flight-footprint/issues/18/evil" }),
  ]) {
    const ctx = storageContext();
    const originalFetch = globalThis.fetch;
    let calls = 0;
    globalThis.fetch = async () => { calls++; return responseFactory(); };
    try {
      const state = new FeedbackState(ctx, workerEnv());
      const request = () => state.fetch(new Request("https://state.internal/submit", {
        method: "POST", body: JSON.stringify({ payload: goodPayload(), ipHash: "hashed-ip" }),
      }));
      assert.equal((await request()).status, 409);
      assert.equal((await request()).status, 409);
      assert.equal(calls, 1);
    } finally { globalThis.fetch = originalFetch; }
  }
});
