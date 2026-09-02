# Project staging data plane

## Decision

Persistent non-production projects use the `engineering-staging` CloudNativePG
cluster in the `engineering-staging` namespace. It is reconciled by Flux in
`tier-3-projects`, after the shared operators and storage controllers in tier 1.

This is a physical isolation boundary from `postgres-vectorchord`, which remains
the household application database. A staging migration, load spike, extension
change, upgrade, or physical restore must not affect Authentik or household
services.

The project cluster is intentionally shared. Each project receives its own
database, nologin ownership roles, runtime login credentials, connection limit,
and migration contract. This amortizes the approximately 384 MiB memory request
across several staging projects. Move a project to a dedicated CNPG Cluster when
it requires an incompatible extension or PostgreSQL version, independent PITR,
stronger regulatory isolation, or sustained resource guarantees.

CNPG creates `platform_owner` only to own the empty bootstrap `platform`
database and its generated administrative Secret. It intentionally remains
outside `managed.roles`; project applications must never use that principal.

## Initial Onward allocation

Onward owns database `onward_staging` through the nologin role `onward_owner`.
The remaining canonical roles are created as nologin roles so an unreviewed
application candidate cannot connect merely because the data plane exists.
Runtime and migration login roles, OpenBao-derived passwords, and application
migrations are added only after the exact Onward candidate SHA passes its
independent review and promotion gates.

The database declaratively provides the `extensions` schema plus `pgcrypto` and
`uuid-ossp`, matching the PostgreSQL capabilities used by the current Onward
migration set without deploying Supabase Auth, Storage, Realtime, or PostgREST.

## Resource and scaling contract

- One PostgreSQL 17 instance starts at 100 millicores and 384 MiB requested RAM.
- Memory is capped at 1 GiB; CPU is deliberately not capped.
- The retained RBD volume starts at 10 GiB and can expand independently of pod
  resources.
- Application and worker pods may scale to zero. PostgreSQL does not scale to
  zero because it is the persistent authority and cold suspension would weaken
  recovery and operational predictability.
- A project receives a dedicated physical cluster when measured contention or
  recovery requirements justify the additional baseline memory.

## Recovery and observability

A CNPG `ScheduledBackup` immediately creates and then refreshes an
application-consistent RBD `VolumeSnapshot` daily. The backup and database
resources use retain policies. A daily verifier fails unless a completed backup
and ready snapshot are no more than 36 hours old. Prometheus alerts cover pod
readiness, missing metrics, volume pressure, and verifier failures.

Snapshots are cluster-wide: restoring `engineering-staging` rewinds every
project database on it. A project that needs independent point-in-time recovery
must move to its own cluster. Before staging holds durable user data, add a
distinct off-cluster bucket and service credential for this cluster and prove an
isolated restore. It must not reuse the household cluster's WAL archive path.

## Adding another project

1. Add nologin owner and application roles under
   `engineering-staging/app/cluster.yaml` using a project-specific prefix.
2. Add a CNPG `Database` resource with a retained reclaim policy and an explicit
   connection limit.
3. Add runtime login credentials through an `ExternalSecret` backed by the
   project's OpenBao path. Never commit a password or provider token.
4. Apply migrations through an immutable, reviewed image or artifact pinned to
   a full source SHA. Do not run repository-head migrations from an operator
   laptop.
5. Add health checks and dashboards before exposing a staging hostname.
6. Exercise backup and restore evidence before admitting durable user data.

## Supabase boundary

Supabase is not synonymous with PostgreSQL. The present Onward code uses
PostgreSQL, while Supabase Storage is planned but not activated and Realtime has
no implemented consumer. Running the full Supabase service suite here would add
idle memory and operational surface without serving a current code path.
Storage, Realtime, Auth, or PostgREST should be introduced only behind an
approved application contract and with their own resource, backup, and security
tests.
