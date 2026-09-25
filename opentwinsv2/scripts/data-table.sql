CREATE TABLE thing_test_data (
  thing_id TEXT NOT NULL,
  ingested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  payload JSONB
);

SELECT create_hypertable('thing_test_data', 'ingested_at');
CREATE INDEX ON thing_test_data (thing_id, ingested_at DESC);