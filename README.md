# AI Digital Twin

A conversational "digital twin" that represents me on [rahulbalajee.com](https://rahulbalajee.com) — visitors chat with an AI that answers as me, grounded in my real CV, LinkedIn profile, and writing style. Built as a full-stack, serverless AWS application with infrastructure as code and keyless CI/CD.

## Architecture

```
User Browser
    │ HTTPS
CloudFront (CDN, ACM cert, custom domain)
    ├──► S3 static website (Next.js frontend)
    │
    │ HTTPS API calls
API Gateway (HTTP API, throttled)
    │
Lambda (FastAPI via Mangum)
    ├──► Amazon Bedrock — Nova 2 Lite (global inference profile)
    └──► S3 memory bucket (conversation persistence, one JSON object per session)
```

**Frontend** — Next.js 16 / React 19, statically exported to S3, served through CloudFront. The API URL is baked in at build time from Terraform outputs.

**Backend** — FastAPI on Lambda behind API Gateway. Each chat request replays conversation history (capped) to Bedrock's Converse API with a system prompt assembled from `backend/data/` (structured facts, prose summary, LinkedIn text extracted from PDF, style notes).

**Infrastructure** — Terraform with remote state in S3 (native lockfile locking, no DynamoDB), split into:

- `terraform/bootstrap/` — account-level singletons applied once: state bucket, GitHub OIDC deploy role
- `terraform/` — the per-environment app stack (workspaces: `dev` / `test` / `prod`)

**CI/CD** — GitHub Actions deploys via **OIDC federation**: no AWS keys stored anywhere. The deploy role's trust policy only accepts tokens from this repo's deployment environments; push to `main` auto-deploys dev, prod is a manual, gated dispatch.

## Engineering decisions worth noting

- **Least-privilege IAM everywhere.** The Lambda role can invoke exactly one Bedrock model and touch exactly one bucket. The CI role's IAM write access is scoped to `role/twin-*` — notably `iam:PassRole`, the classic escalation primitive, is never granted on `*`.
- **Cost armor for a public LLM endpoint.** API Gateway throttling, Lambda reserved concurrency, a history cap on tokens sent per request, and a deliberately cheap model tier — a "denial of wallet" attack bottoms out at pocket change.
- **Event-loop hygiene.** boto3 is synchronous; every storage and model call is wrapped in `asyncio.to_thread` so one visitor's S3/Bedrock latency never blocks another's request.
- **Fail-fast configuration.** Missing env vars kill the server at startup with a clear message, not at request time with a mystery 500.
- **Session privacy.** Session IDs are server-generated UUIDs, validated on every entry path (blocking path traversal into the memory bucket); listing/reading endpoints are not exposed through API Gateway.
- **Reproducible Lambda builds.** Dependencies are pinned from `uv.lock` and installed inside the official Lambda container image for the target architecture — no "works on my Mac" wheels in production.

## Repository layout

```
backend/            FastAPI app
  server.py         routes, storage (S3/local), Bedrock call
  context.py        system prompt assembly
  resources.py      loads facts/summary/style/LinkedIn from data/
  lambda_handler.py Mangum adapter (Lambda entrypoint)
  deploy.py         builds lambda-deployment.zip in Docker
  data/             the twin's knowledge (facts.json, summary, style, LinkedIn PDF)
frontend/           Next.js chat UI (static export)
terraform/          app stack (workspace per environment)
  bootstrap/        one-time account-level setup (state bucket, OIDC role)
scripts/            deploy.sh / destroy.sh
.github/workflows/  CI/CD (OIDC, no stored credentials)
```

## Local development

Backend (requires Python 3.11+, [uv](https://docs.astral.sh/uv/), and AWS credentials with Bedrock access):

```bash
cd backend
cp .env.example .env   # or create .env with the variables below
uv run server.py       # http://localhost:8000 — interactive docs at /docs
```

`.env` variables:

| Variable | Required | Notes |
|---|---|---|
| `CORS_ORIGINS` | yes | e.g. `http://localhost:3000` |
| `BEDROCK_MODEL_ID` | yes | e.g. `global.amazon.nova-2-lite-v1:0` |
| `BEDROCK_REGION` | no | falls back to `AWS_REGION`, then `ap-south-1` |
| `USE_S3` | no | `false` locally — conversations go to `memory/` on disk |
| `S3_BUCKET` | if `USE_S3=true` | the memory bucket |

Frontend:

```bash
cd frontend
npm install
npm run dev            # http://localhost:3000, talks to localhost:8000
```

## Deployment

One-time account setup, then per-environment deploys:

```bash
# once: state bucket + CI role
cd terraform/bootstrap && terraform init && terraform apply

# per environment (builds Lambda zip, applies Terraform, builds + syncs frontend,
# invalidates CloudFront)
./scripts/deploy.sh dev
./scripts/deploy.sh prod
```

Or let CI do it: pushing to `main` deploys dev; prod deploys run from the Actions tab (workflow dispatch with an environment picker).

Teardown (typed confirmation required — deletes stored conversations):

```bash
./scripts/destroy.sh dev
```

## Costs

Designed to idle at ~$0: pay-per-request Lambda/API Gateway/S3, no provisioned capacity, a budget-tier model, and hard concurrency/throttle ceilings. The only fixed cost is the Route53 hosted zone.
