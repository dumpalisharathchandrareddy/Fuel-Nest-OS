-- ============================================================
-- PUMPora Central Registry — registry_schema.sql
-- Run this in YOUR OWN Supabase project (not dealer's).
-- This is the central lookup: station_code → dealer's Supabase URL.
-- ============================================================

-- Station registry table
CREATE TABLE IF NOT EXISTS station_registry (
  id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  station_code    TEXT NOT NULL UNIQUE,      -- e.g. 'RAMFUELS01' (UPPERCASE)
  station_name    TEXT NOT NULL,             -- Display name
  supabase_url    TEXT NOT NULL,             -- Dealer's Supabase project URL
  anon_key        TEXT NOT NULL,             -- Dealer's Supabase anon key
  active          BOOLEAN NOT NULL DEFAULT TRUE,
  registered_at   TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Indexes
CREATE INDEX IF NOT EXISTS idx_registry_station_code ON station_registry(station_code);
CREATE INDEX IF NOT EXISTS idx_registry_active ON station_registry(active) WHERE active = TRUE;

-- RLS — enable
ALTER TABLE station_registry ENABLE ROW LEVEL SECURITY;

-- Anyone can read active registrations (needed for station code lookup in app)
-- The anon_key is safe to expose — it's already public in Supabase by design
CREATE POLICY "anyone_can_lookup"
  ON station_registry
  FOR SELECT
  USING (active = TRUE);

-- Only service role can insert/update (done from edge function with service key)
-- Inserts happen from FuelOS dealer signup flow via your registry edge function

-- ── Optional: Registry Edge Function for dealer self-registration ──────────
-- If you want dealers to register themselves without you doing it manually,
-- create a Supabase Edge Function in YOUR registry project:
--
-- POST /register-station
-- Body: { station_code, station_name, supabase_url, anon_key }
-- Auth: simple shared secret in header
--
-- The Flutter app calls this during DealerSignupScreen → Step 1.

-- ── Sample data (for testing) ─────────────────────────────────────────────
-- INSERT INTO station_registry (station_code, station_name, supabase_url, anon_key)
-- VALUES (
--   'TESTSTATION1',
--   'Test Station One',
--   'https://your-test-project.supabase.co',
--   'your-test-anon-key-here'
-- );
