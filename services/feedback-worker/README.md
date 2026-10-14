# Flight Footprint feedback Worker

This Worker accepts `POST /v1/feedback` JSON and creates an issue in the fixed `yiming-space/flight-footprint` repository. `GET /health` returns a minimal health response. There is no CORS requirement for the native Android, iOS, or desktop clients.

Request fields:

```json
{
  "kind": "bug",
  "title": "Map does not load",
  "description": "The map stays blank after opening the app.",
  "environment": "App version 1.2.0; Android 15",
  "requestId": "123e4567-e89b-42d3-a456-426614174000"
}
```

`kind` is `bug` or `suggestion`; title is 5–120 characters, description is 10–5000, optional environment is at most 500 characters, and `requestId` is a UUID generated once per submission. The UTF-8 request body is capped at 32 KiB. Success is `201 {"issueNumber":17,"issueUrl":"https://github.com/yiming-space/flight-footprint/issues/17"}`. Errors use `{"error":"..."}`. `submission_uncertain` returns HTTP 409: the client should keep the same request ID and must not create a new submission automatically. When the same request is retried, the Worker searches GitHub for its hidden marker at most once every 30 seconds; it returns success if it finds an exact matching issue, and otherwise keeps the submission uncertain. The issue body contains a hidden request ID marker (`<!-- ff-feedback: UUID -->`) for this reconciliation.

## Configuration and deployment

1. Install a current Node.js and Wrangler, then run `npm install` in this directory.
2. Create a fine-grained GitHub token scoped only to `yiming-space/flight-footprint` with Issues: Read and write. The Worker does not accept a repository URL or issue endpoint from callers.
3. Configure secrets interactively so the values do not appear in shell history:

   ```sh
   npx wrangler secret put GITHUB_TOKEN
   npx wrangler secret put RATE_LIMIT_SALT
   ```

   Use a long random `RATE_LIMIT_SALT`; it lets the Worker store only a salted hash of the client IP. The token and salt are never returned by the API.
4. Run `npm test`, then `npx wrangler deploy`. The first deployment creates the SQLite-backed Durable Object migration declared in `wrangler.toml`.
5. Configure the Flutter build with the deployed base URL, including the endpoint path:

   ```sh
   flutter build apk --dart-define=FLIGHT_FOOTPRINT_FEEDBACK_URL=https://YOUR-WORKER.workers.dev/v1/feedback
   ```

   The compile-time value is public endpoint configuration, not a secret. Rebuild and redistribute the app for the value to take effect.

The Durable Object applies a shared cap of 3 submissions per salted IP hash per hour and 50 per day globally. Successful receipts and uncertain pending records are retained indefinitely to prevent request-ID reuse from creating duplicates. Expired per-IP rate events are cleaned by a Durable Object alarm. These limits reduce accidental bursts and constrain some abuse, but they are not complete bot or denial-of-service protection; requests can still consume Worker and Durable Object capacity. IP limits can affect people sharing a public network. The Worker creates public GitHub issues, so user-provided title, description, and environment become public. It does not accept attachments or automatically collect device records. The application should let users review and remove sensitive details before submission.

An upstream timeout, 5xx, unexpected success status, or malformed issue response leaves a pending receipt to avoid duplicate issues when GitHub may have accepted the first request. A retry performs a read-only search using GitHub's Search issues and pull requests endpoint and accepts only an exact request ID marker plus canonical issue URL in the configured repository. Search errors or no match never trigger another create request. GitHub documents search query qualifiers, per-page parameters, and response codes in its [REST search API reference](https://docs.github.com/en/rest/search/search) and [issue search qualifier reference](https://docs.github.com/en/search-github/searching-on-github/searching-issues-and-pull-requests). A GitHub 4xx rejection clears the pending receipt so the same request can be retried after configuration is corrected. Only an exact HTTP 201 response with a positive number and canonical issue URL for the configured repository is accepted as initial success.
