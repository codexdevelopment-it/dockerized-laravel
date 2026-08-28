-- Runs once, on a fresh PostgreSQL data directory, via /docker-entrypoint-initdb.d.
-- Safe to keep: no-op when the extension already exists (e.g. created later by
-- an application migration).
CREATE EXTENSION IF NOT EXISTS vector;
