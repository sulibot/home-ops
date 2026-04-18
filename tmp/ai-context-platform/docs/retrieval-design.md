# Retrieval Design

This starter assumes `hybrid retrieval` from day one:

- semantic retrieval from `Qdrant`
- keyword retrieval from `Postgres` full-text search
- metadata filters from `Postgres` and `Qdrant` payload
- ACL enforcement before final ranking

## Query Flow

1. Resolve the caller principal and groups.
2. Build the candidate ACL scope from `acl_entries`.
3. Run semantic search in `Qdrant` using metadata filters such as `source_type`, `repo`, `service`, `team`, and time range.
4. Run keyword search against `chunks.content_tsv`.
5. Merge the two candidate sets on `chunk_id`.
6. Re-score candidates with weighted blending or a reranker.
7. Collapse chunk-level results into document-level citations.
8. Return a short answer plus supporting sources.

## Why Keep Canonical Metadata Out Of Qdrant

`Qdrant` is the retrieval index, not the system of record. Keep these in `Postgres`:

- authoritative document metadata
- ACL entries
- group membership
- sync cursors
- audit events
- connector configuration

This keeps reindexing and payload changes cheap while preserving governance and auditability.

## Suggested Qdrant Payload Fields

- `chunk_id`
- `document_id`
- `source_type`
- `repo`
- `service`
- `team`
- `updated_at`
- `title`
- `url`
- `acl_subjects`

## Scoring Guidance

A simple first-pass blend is enough for `v1`:

- `0.65 * semantic_score`
- `0.35 * keyword_score`

If the corpus grows or answer quality plateaus, add:

- cross-encoder reranking
- time-decay boosts for incident/change data
- query-type routing for design versus incident lookups
