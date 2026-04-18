create extension if not exists pgcrypto;

create table if not exists sources (
  id uuid primary key default gen_random_uuid(),
  kind text not null,
  name text not null,
  config jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists documents (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references sources(id) on delete restrict,
  external_id text not null,
  source_type text not null,
  title text not null,
  url text,
  repo text,
  service text,
  team text,
  author text,
  status text,
  created_at timestamptz,
  updated_at timestamptz,
  content_version text,
  object_key text,
  metadata jsonb not null default '{}'::jsonb,
  unique (source_id, external_id)
);

create table if not exists chunks (
  id uuid primary key default gen_random_uuid(),
  document_id uuid not null references documents(id) on delete cascade,
  chunk_index integer not null,
  section text,
  content text not null,
  content_tsv tsvector generated always as (
    to_tsvector('english', coalesce(content, ''))
  ) stored,
  token_count integer,
  qdrant_point_id text not null,
  metadata jsonb not null default '{}'::jsonb,
  unique (document_id, chunk_index),
  unique (qdrant_point_id)
);

create table if not exists principals (
  id uuid primary key default gen_random_uuid(),
  principal_type text not null,
  external_id text not null unique,
  email text,
  created_at timestamptz not null default now()
);

create table if not exists groups (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  created_at timestamptz not null default now()
);

create table if not exists group_memberships (
  principal_id uuid not null references principals(id) on delete cascade,
  group_id uuid not null references groups(id) on delete cascade,
  primary key (principal_id, group_id)
);

create table if not exists acl_entries (
  id uuid primary key default gen_random_uuid(),
  resource_type text not null,
  resource_id uuid not null,
  subject_type text not null,
  subject_id uuid not null,
  permission text not null default 'read',
  created_at timestamptz not null default now()
);

create table if not exists sync_runs (
  id uuid primary key default gen_random_uuid(),
  source_id uuid not null references sources(id) on delete cascade,
  status text not null,
  started_at timestamptz not null default now(),
  finished_at timestamptz,
  cursor text,
  stats jsonb not null default '{}'::jsonb,
  error_text text
);

create table if not exists retrieval_events (
  id uuid primary key default gen_random_uuid(),
  principal_id uuid references principals(id) on delete set null,
  query_text text not null,
  filters jsonb not null default '{}'::jsonb,
  results jsonb not null default '[]'::jsonb,
  latency_ms integer,
  created_at timestamptz not null default now()
);

create index if not exists idx_documents_lookup
  on documents (source_type, repo, service, updated_at desc);

create index if not exists idx_documents_source
  on documents (source_id, external_id);

create index if not exists idx_chunks_document
  on chunks (document_id, chunk_index);

create index if not exists idx_chunks_tsv
  on chunks using gin (content_tsv);

create index if not exists idx_acl_resource
  on acl_entries (resource_type, resource_id);

create index if not exists idx_acl_subject
  on acl_entries (subject_type, subject_id);

create index if not exists idx_group_memberships_principal
  on group_memberships (principal_id, group_id);

create index if not exists idx_sync_runs_source_started
  on sync_runs (source_id, started_at desc);

create index if not exists idx_retrieval_events_created
  on retrieval_events (created_at desc);
