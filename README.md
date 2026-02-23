# FleetFix Agent (Elastic Agent Builder + Elasticsearch)

FleetFix is a custom multi-step AI agent built with **Elastic Agent Builder** that diagnoses **Elastic Agent / Fleet** failures using data stored in **Elasticsearch**, retrieves the correct **runbook**, and (with confirmation) **creates a tracking ticket** via **Elastic Workflows**.

## Why this exists
Fleet/Elastic Agent enrollment and policy issues are repetitive, high-friction ops problems. FleetFix automates:
- “What’s failing lately?” (cluster top error signatures)
- “What’s the fix?” (fetch the best runbook)
- “Track it” (create a ticket record consistently)

## Architecture

```mermaid
flowchart TD
  U[Operator / SRE] -->|chat| AB[FleetFix Agent<br/>Elastic Agent Builder + Managed LLM]
  AB --> T1[Tool: detect_failure_clusters<br/>ES|QL]
  AB --> T2[Tool: search_runbooks<br/>Index Search Tool]
  AB --> T3[Tool: get_runbook_by_signature<br/>ES|QL]
  AB --> T4[Tool: create_ticket<br/>Workflow Tool]

  T1 --> ES1[(fleetfix_logs)]
  T2 --> ES2[(fleetfix_runbooks)]
  T3 --> ES2
  T4 --> WF[Workflow: fleetfix_create_ticket.yaml]
  WF --> ES3[(fleetfix_tickets)]
```

---

## 1. Data Model

### Indices
- `fleetfix_logs` — synthetic Fleet/Elastic Agent logs (time-series)
  - Key fields: `@timestamp`, `host.name`, `error.signature`, `message`, `service.name`, `log.level`
- `fleetfix_runbooks` — troubleshooting KB keyed by `signature`
  - Key fields: `signature`, `title`, `root_causes`, `fix_steps`, `verify_steps`, `tags`, `updated_at`
- `fleetfix_tickets` — ticket records created by the workflow tool
  - Key fields: `created_at`, `title`, `severity`, `signature`, `status`, `recommended_steps`, `raw_log_sample`, `host.name`

---

## 2. Repo Tree

```
fleetfix-agent/
  README.md                          # Project documentation
  LICENSE                            # OSS license (MIT)
  .gitignore                         # Secrets + generated files ignored
  agent_builder/
    agents/
      fleetfix_agent.json            # Exported Agent Builder agent definition
    tools/
      fleetfix.detect_failure_clusters.json
      fleetfix.search_runbooks.json
      fleetfix.get_runbook_by_signature.json
      fleetfix.create_ticket.json    # Workflow tool definition
  workflows/
    fleetfix_create_ticket.yaml      # Elastic Workflow used to create tickets
  dashboards/
    fleetfix_saved_objects.ndjson    # Kibana saved objects export for dashboard (optional but recommended)
  data/
    fleetfix_logs.ndjson             # Generated synthetic logs (large dataset)
    fleetfix_runbooks.ndjson         # Generated runbooks KB
  scripts/
    env.example.ps1                  # Template for local env vars (copy -> env.ps1)
    create_indices.ps1               # Creates indices + mappings via Elasticsearch API
    create_indices.devtools.txt      # UI fallback: paste into Kibana Dev Tools
    generate_fleetfix_data.ps1       # Generates synthetic fleetfix_logs.ndjson
    generate_fleetfix_runbooks.ps1   # Generates fleetfix_runbooks.ndjson
    bulk_ingest.ps1                  # Bulk ingest NDJSON into Elasticsearch (_bulk)
    export_agent_builder.ps1         # Export tools + agent from Kibana (for maintainers)
    import_agent_builder.ps1         # Import tools + agent into Kibana
    export_dashboard.ps1             # Export dashboard saved objects by title (for maintainers)
    import_saved_objects.ps1         # Import saved objects NDJSON into Kibana
    smoke_test.ps1                   # Minimal verification (tools + agent)
    setup_all.ps1                    # One-shot setup script
```

---

## 3. Build Steps

### Prerequisites

#### A) Elastic deployment
You need an Elastic deployment (Elastic Cloud / Serverless or self-managed) with:
- Kibana URL (example): `https://<deployment>.kb.<region>.<provider>.elastic.cloud`
- Elasticsearch URL (example): `https://<deployment>.es.<region>.<provider>.elastic.cloud`

#### B) API key
Create an API key that can:
- Create indices and bulk index into `fleetfix_*` (Elasticsearch)
- Create/update Agent Builder tools and agents, and execute tools (Kibana)
- Import Saved Objects (dashboard) (Kibana)

Notes:
- Kibana POST/PUT APIs require `kbn-xsrf: true` header.
- Agent Builder “Execute a Tool” endpoint is `POST /api/agent_builder/tools/_execute`.
- Bulk ingestion uses NDJSON and the `_bulk` API with `Content-Type: application/x-ndjson` and a trailing newline.

#### C) Workflows enabled (required for ticket creation)
Workflows are disabled by default. Enable them in Kibana:
1. Stack Management → Advanced Settings
2. Search `workflows:ui:enabled`
3. Toggle ON and save, then reload Kibana
4. Create the workflow from `workflows/fleetfix_create_ticket.yaml`

---

### 3.1 Automated build (one-shot)

1) Clone / fork the repo
```powershell
git clone https://github.com/<your-org-or-user>/fleetfix-agent.git
cd fleetfix-agent
```

2) Configure environment
- Copy `scripts/env.example.ps1` → `scripts/env.ps1`
- Fill in: `ES_URL`, `KIBANA_URL`, `API_KEY`
- Load env:
```powershell
. .\scripts\env.ps1
```

3) Run one-shot setup
```powershell
.\scripts\setup_all.ps1 -LogCount 500 -HostCount 20
```

What it does:
- Creates indices (`fleetfix_logs`, `fleetfix_runbooks`, `fleetfix_tickets`)
- Generates a larger dataset for charts
- Bulk ingests logs + runbooks
- Imports dashboard saved objects (if `dashboards/fleetfix_saved_objects.ndjson` exists)
- Imports Agent Builder tools + agent
- Runs a smoke test

---

### 3.2 UI-only setup (fallback)

1) Create indices
- Kibana → Dev Tools → Console
- Paste + run: `scripts/create_indices.devtools.txt`

2) Generate data locally (recommended for charts)
```powershell
.\scripts\generate_fleetfix_data.ps1 -LogCount 500 -HostCount 20
.\scripts\generate_fleetfix_runbooks.ps1 -Overwrite
```

3) Bulk ingest
```powershell
.\scripts\bulk_ingest.ps1 -EsUrl $env:ES_URL -ApiKey $env:API_KEY -Index fleetfix_logs -NdjsonPath .\data\fleetfix_logs.ndjson
.\scripts\bulk_ingest.ps1 -EsUrl $env:ES_URL -ApiKey $env:API_KEY -Index fleetfix_runbooks -NdjsonPath .\data\fleetfix_runbooks.ndjson
```

4) Enable workflows + create workflow
- Enable `workflows:ui:enabled`
- Create workflow from: `workflows/fleetfix_create_ticket.yaml`

5) Import dashboard (optional)
- Kibana → Stack Management → Saved Objects → Import
- Import: `dashboards/fleetfix_saved_objects.ndjson`

6) Import Agent Builder tools + agent
```powershell
.\scripts\import_agent_builder.ps1 -KibanaUrl $env:KIBANA_URL -ApiKey $env:API_KEY
```

---

### 3.3 Smoke test (validate the build)

Run:
```powershell
.\scripts\smoke_test.ps1 -KibanaUrl $env:KIBANA_URL -ApiKey $env:API_KEY
```

Expected:
- Tool1 executes (detect clusters)
- Tool3 executes (runbook by signature)
- Agent responds to “Get runbook for context_canceled”

---

## 4. Demo Steps

Open Kibana → Agent Builder → **FleetFix Agent** and run:

1) **Top failures**
> What are the top Fleet failures in the last 24 hours?

2) **Runbook**
> Get runbook for context_canceled

3) **Ticket**
> Create a ticket for context_canceled on win-agent-01, severity high.

(Agent should request confirmation before creating the ticket.)

---

## 5. Notes / Troubleshooting

- **Bulk ingest errors**
  - The Bulk API expects NDJSON with alternating action/source lines and a final newline; use `Content-Type: application/x-ndjson`.
- **Kibana POST APIs fail**
  - Ensure `kbn-xsrf: true` header is included.
- **Saved Objects import issues**
  - Saved objects are version-sensitive; import into a compatible Kibana version.
- **Workflow tool fails**
  - Confirm workflows are enabled (`workflows:ui:enabled`) and the workflow exists before using `fleetfix.create_ticket`.
- **ES|QL time duration**
  - Use a duration like `"24 hours"` (string converted to timeduration) for lookback in Tool1.

### Useful docs
- Agent Builder API overview: https://www.elastic.co/docs/api/doc/kibana/group/endpoint-agent-builder
- Execute a tool (`kbn-xsrf` required): https://www.elastic.co/docs/api/doc/kibana/v9/operation/operation-post-agent-builder-tools-execute
- Workflows setup (`workflows:ui:enabled`): https://www.elastic.co/docs/explore-analyze/workflows/setup
- Bulk API NDJSON format: https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-bulk.html

---

## 6. License
MIT — see `LICENSE`
