# AI Context Platform Starter

This scaffold is a `v1` starter for an enterprise AI context platform aimed at `SRE` and `SWE` workflows. It is opinionated in a few ways:

- `Qdrant` handles semantic retrieval
- `Postgres` is the source of truth for metadata, ACLs, sync state, and audit events
- `MinIO` stands in for `S3` object storage
- `MCP` is the tool interface exposed to assistants and internal clients

## Goals

- Provide trusted retrieval across engineering and operations data
- Keep source attribution attached to every answer
- Enforce per-document and per-chunk access control
- Support incremental sync from multiple source systems
- Separate canonical metadata from vector indexing

## Suggested Repo Layout

```text
ai-context-platform/
├── apps/
│   ├── api/                # FastAPI service for search, documents, admin
│   ├── mcp-server/         # MCP tools backed by retrieval service
│   └── worker/             # ingest, parse, chunk, embed, index jobs
├── libs/
│   ├── core/               # config, auth helpers, logging, shared types
│   ├── db/                 # migrations, SQLAlchemy models, repositories
│   ├── retrieval/          # hybrid retrieval, ACL filtering, citations
│   ├── connectors/         # GitHub, docs, incidents
│   ├── embeddings/         # chunking and embedding adapters
│   └── storage/            # object storage abstraction
├── docs/
│   └── retrieval-design.md
├── migrations/
│   └── 0001_initial_schema.sql
├── .env.example
├── docker-compose.yml
└── README.md
```

## Runtime Architecture

```text
GitHub / Jira / Docs / Incident Data
  -> worker ingestion jobs
  -> MinIO raw snapshots
  -> parse/chunk/embed pipeline
  -> Qdrant semantic index
  -> Postgres metadata + ACL + audit + sync state

API / MCP server
  -> retrieval service
  -> Qdrant + Postgres + MinIO
```

## Local Stack

The included `docker-compose.yml` starts:

- `postgres` on `localhost:5432`
- `qdrant` on `localhost:6333`
- `minio` on `localhost:9000`
- `minio-console` on `localhost:9001`

## Quick Start

1. Copy `.env.example` to `.env`.
2. Start the dependencies:

   ```bash
   docker compose up -d
   ```

3. Apply the initial schema:

   ```bash
   psql "postgresql://context:contextdev@localhost:5432/context_platform" \
     -f migrations/0001_initial_schema.sql
   ```

4. Verify MinIO bucket creation:

   ```bash
   docker compose logs minio-init
   ```

5. Build the services in this order:

- `worker`: one connector end-to-end first
- `retrieval`: ACL-aware semantic + keyword search
- `api`: search and document fetch endpoints
- `mcp-server`: focused tools over the retrieval service

## First MCP Tools

These are the first five tools worth implementing:

- `search_knowledge(query, source_types, repo, service, team, time_from, time_to, top_k)`
- `get_document(document_id)`
- `find_related_incidents(service, symptom, top_k)`
- `find_related_changes(repo, service, time_from, time_to, top_k)`
- `get_runbook(service, alert_name)`

Every tool response should include:

- a short summary
- cited source documents
- source URLs
- retrieval scores or confidence hints

## Initial Source Priorities

For `v1`, keep the connector surface small:

- `GitHub`: PRs, issues, ADRs, design docs
- `docs`: markdown runbooks and architecture notes
- `incidents`: postmortems, ticket exports, or PagerDuty/Jira-derived records

This is enough to demonstrate cross-domain retrieval for both `SRE` and `SWE` use cases without turning the project into a connector farm.

## Enterprise Signals To Add Early

- ACL enforcement before final ranking
- citations on every result
- incremental sync cursors
- retrieval audit events
- evaluation queries with expected citations
- stale-content and failed-sync visibility

## Suggested Next Milestones

1. Implement `documents` and `chunks` persistence plus one markdown connector.
2. Create the Qdrant collection and index chunk payloads with service/repo metadata.
3. Implement `search_knowledge` with semantic retrieval and document citations.
4. Add Postgres full-text search and merge it into a hybrid retriever.
5. Add eval cases for common `SRE` and `SWE` questions.
