const MAX_BODY_BYTES = 32 * 1024;
const HOUR_MS = 60 * 60 * 1000;
const DAY_MS = 24 * HOUR_MS;
const RECONCILE_INTERVAL_MS = 30 * 1000;
const encoder = new TextEncoder();

function json(body, status = 200, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "content-type": "application/json; charset=utf-8", "cache-control": "no-store", ...headers },
  });
}

async function readBoundedBody(request) {
  const declaredLength = Number(request.headers.get("content-length"));
  if (Number.isFinite(declaredLength) && declaredLength > MAX_BODY_BYTES) {
    throw new Error("body_too_large");
  }
  if (!request.body) return new Uint8Array();
  const reader = request.body.getReader();
  const chunks = [];
  let size = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    size += value.byteLength;
    if (size > MAX_BODY_BYTES) {
      await reader.cancel();
      throw new Error("body_too_large");
    }
    chunks.push(value);
  }
  const result = new Uint8Array(size);
  let offset = 0;
  for (const chunk of chunks) {
    result.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return result;
}

function validText(value, min, max) {
  return typeof value === "string" && value.trim().length >= min && value.length <= max;
}

function validUUID(value) {
  return typeof value === "string" &&
    /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value);
}

function escapeMarkdown(value) {
  return value.replace(/[\\`*_{}\[\]()#+\-.!|<>]/g, "\\$&");
}

function validate(payload) {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) return "invalid_payload";
  if (payload.kind !== "bug" && payload.kind !== "suggestion") return "invalid_kind";
  if (!validText(payload.title, 5, 120)) return "invalid_title";
  if (!validText(payload.description, 10, 5000)) return "invalid_description";
  if (payload.environment !== undefined &&
      (typeof payload.environment !== "string" || payload.environment.length > 500)) return "invalid_environment";
  if (!validUUID(payload.requestId)) return "invalid_request_id";
  return null;
}

async function sha256(text) {
  const digest = await crypto.subtle.digest("SHA-256", encoder.encode(text));
  return [...new Uint8Array(digest)].map((byte) => byte.toString(16).padStart(2, "0")).join("");
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/health") {
      if (request.method !== "GET") return json({ error: "method_not_allowed" }, 405, { allow: "GET" });
      return json({ ok: true });
    }
    if (url.pathname !== "/v1/feedback") return json({ error: "not_found" }, 404);
    if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405, { allow: "POST" });
    if (!(request.headers.get("content-type") ?? "").toLowerCase().includes("application/json")) {
      return json({ error: "content_type_must_be_json" }, 415);
    }
    let bytes;
    try {
      bytes = await readBoundedBody(request);
    } catch (error) {
      return json({ error: error.message === "body_too_large" ? "body_too_large" : "invalid_body" }, 413);
    }
    let payload;
    try {
      payload = JSON.parse(new TextDecoder("utf-8", { fatal: true }).decode(bytes));
    } catch {
      return json({ error: "invalid_json" }, 400);
    }
    const validationError = validate(payload);
    if (validationError) return json({ error: validationError }, 400);
    if (!env.GITHUB_TOKEN || !env.RATE_LIMIT_SALT || !env.FEEDBACK_STATE ||
        !/^[A-Za-z0-9_.-]+$/.test(env.GITHUB_OWNER ?? "") || env.GITHUB_OWNER === "." || env.GITHUB_OWNER === ".." ||
        !/^[A-Za-z0-9_.-]+$/.test(env.GITHUB_REPO ?? "") || env.GITHUB_REPO === "." || env.GITHUB_REPO === "..") {
      return json({ error: "service_not_configured" }, 503);
    }

    try {
      const ip = request.headers.get("CF-Connecting-IP") ?? "unknown";
      const ipHash = await sha256(`${env.RATE_LIMIT_SALT}:${ip}`);
      const id = env.FEEDBACK_STATE.idFromName("global-feedback-state");
      const stub = env.FEEDBACK_STATE.get(id);
      return await stub.fetch("https://state.internal/submit", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ payload, ipHash }),
      });
    } catch {
      return json({ error: "service_unavailable" }, 503);
    }
  },
};

export class FeedbackState {
  constructor(ctx, env) {
    this.ctx = ctx;
    this.env = env;
  }

  async fetch(request) {
    if (request.method !== "POST") return json({ error: "not_found" }, 404);
    try {
      return await this.ctx.blockConcurrencyWhile(() => this.#submit(request));
    } catch {
      return json({ error: "service_unavailable" }, 503);
    }
  }

  async #findExistingIssue(requestId) {
    const query = `repo:${this.env.GITHUB_OWNER}/${this.env.GITHUB_REPO} is:issue in:body "${requestId}"`;
    const searchUrl = new URL("https://api.github.com/search/issues");
    searchUrl.searchParams.set("q", query);
    searchUrl.searchParams.set("per_page", "10");
    try {
      const response = await fetch(searchUrl, {
        method: "GET",
        headers: {
          authorization: `Bearer ${this.env.GITHUB_TOKEN}`,
          accept: "application/vnd.github+json",
          "x-github-api-version": "2022-11-28",
          "user-agent": "flight-footprint-feedback-worker",
        },
        redirect: "error",
        signal: AbortSignal.timeout(10_000),
      });
      if (response.status !== 200) return null;
      const results = await response.json();
      if (results.incomplete_results !== false || !Array.isArray(results.items)) return null;
      const marker = `<!-- ff-feedback: ${requestId} -->`;
      const canonicalPrefix = `https://github.com/${this.env.GITHUB_OWNER}/${this.env.GITHUB_REPO}/issues/`;
      return results.items.find((item) => Number.isInteger(item.number) && item.number > 0 &&
        item.html_url === `${canonicalPrefix}${item.number}` &&
        typeof item.body === "string" && item.body.includes(marker)) ?? null;
    } catch {
      return null;
    }
  }

  async alarm() {
    const now = Date.now();
    const entries = await this.ctx.storage.list({ prefix: "ip:" });
    let hasActiveEvents = false;
    for (const [key, events] of entries) {
      const fresh = events.filter((time) => time > now - HOUR_MS);
      if (fresh.length) {
        hasActiveEvents = true;
        await this.ctx.storage.put(key, fresh);
      } else {
        await this.ctx.storage.delete(key);
      }
    }
    if (hasActiveEvents) await this.ctx.storage.setAlarm(now + HOUR_MS);
  }

  async #submit(request) {
    const { payload, ipHash } = await request.json();
    const now = Date.now();
    const receiptKey = `receipt:${payload.requestId}`;
    const fingerprint = await sha256(JSON.stringify({
      kind: payload.kind,
      title: payload.title,
      description: payload.description,
      environment: payload.environment ?? "",
    }));
    const receipt = await this.ctx.storage.get(receiptKey);
    if (receipt) {
      if (receipt.fingerprint !== fingerprint) return json({ error: "request_id_conflict" }, 409);
      if (receipt.state === "complete") return json(receipt.response, 201);
      if (now - (receipt.lastCheckedAt ?? receipt.createdAt) < RECONCILE_INTERVAL_MS) {
        return json({ error: "submission_uncertain" }, 409);
      }
      receipt.lastCheckedAt = now;
      await this.ctx.storage.put(receiptKey, receipt);
      const foundIssue = await this.#findExistingIssue(payload.requestId);
      if (foundIssue) {
        const result = { issueNumber: foundIssue.number, issueUrl: foundIssue.html_url };
        await this.ctx.storage.put(receiptKey, {
          state: "complete", fingerprint, response: result, createdAt: receipt.createdAt,
        });
        return json(result, 201);
      }
      return json({ error: "submission_uncertain" }, 409);
    }

    const ipKey = `ip:${ipHash}`;
    const globalKey = "global";
    const ipEvents = (await this.ctx.storage.get(ipKey) ?? []).filter((time) => time > now - HOUR_MS);
    const globalEvents = (await this.ctx.storage.get(globalKey) ?? []).filter((time) => time > now - DAY_MS);
    if (ipEvents.length >= 3 || globalEvents.length >= 50) {
      return json({ error: "rate_limited" }, 429, { "retry-after": "3600" });
    }
    ipEvents.push(now);
    globalEvents.push(now);
    await this.ctx.storage.put({ [ipKey]: ipEvents, [globalKey]: globalEvents });
    await this.ctx.storage.setAlarm(now + HOUR_MS);

    await this.ctx.storage.put(receiptKey, { state: "pending", fingerprint, createdAt: now });
    const titlePrefix = payload.kind === "bug" ? "[Bug]" : "[Suggestion]";
    const issueBody = [
      payload.description,
      payload.environment ? `\n\n---\n\n**Environment**\n\n${escapeMarkdown(payload.environment)}` : "",
      `\n\n---\n\nSubmitted through Flight Footprint feedback.\n\n<!-- ff-feedback: ${payload.requestId} -->`,
    ].join("");
    let response;
    try {
      response = await fetch(`https://api.github.com/repos/${this.env.GITHUB_OWNER}/${this.env.GITHUB_REPO}/issues`, {
        method: "POST",
        headers: {
          authorization: `Bearer ${this.env.GITHUB_TOKEN}`,
          accept: "application/vnd.github+json",
          "content-type": "application/json",
          "x-github-api-version": "2022-11-28",
          "user-agent": "flight-footprint-feedback-worker",
        },
        body: JSON.stringify({ title: `${titlePrefix} ${payload.title.trim()}`, body: issueBody }),
        redirect: "error",
        signal: AbortSignal.timeout(10_000),
      });
    } catch {
      return json({ error: "submission_uncertain" }, 409);
    }
    if (!response.ok) {
      if (response.status >= 400 && response.status < 500) await this.ctx.storage.delete(receiptKey);
      return json({ error: response.status >= 500 ? "submission_uncertain" : "upstream_rejected" },
        response.status >= 500 ? 409 : 502);
    }
    if (response.status !== 201) return json({ error: "submission_uncertain" }, 409);
    let issue;
    try {
      issue = await response.json();
      const expectedPrefix = `https://github.com/${this.env.GITHUB_OWNER}/${this.env.GITHUB_REPO}/issues/`;
      if (!Number.isInteger(issue.number) || issue.number <= 0 || typeof issue.html_url !== "string" ||
          issue.html_url !== `${expectedPrefix}${issue.number}`) {
        throw new Error("invalid_github_response");
      }
    } catch {
      return json({ error: "submission_uncertain" }, 409);
    }
    const result = { issueNumber: issue.number, issueUrl: issue.html_url };
    await this.ctx.storage.put(receiptKey, { state: "complete", fingerprint, response: result, createdAt: now });
    return json(result, 201);
  }
}
