-- ============================================================
-- FuelOS Migration: 003_creditor_portal_rpc.sql
-- Replaces the three separate creditor SECURITY DEFINER functions
-- with a single fuelos_creditor_portal_data(station_code, phone) RPC.
--
-- Changes:
--   1. Recreate JWT helpers with SET search_path = public.
--   2. Drop old creditor functions and revoke anon grants.
--   3. Create fuelos_creditor_portal_data — resolves station_id
--      and customer_id server-side; never exposes either to the client.
-- ============================================================

BEGIN;

-- ── 1. Recreate JWT helpers with fixed search_path ────────────────────────────

CREATE OR REPLACE FUNCTION fuelos_station_id() RETURNS TEXT
  LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path = public AS $$
    SELECT auth.jwt() -> 'user_metadata' ->> 'station_id'
  $$;

CREATE OR REPLACE FUNCTION fuelos_role() RETURNS TEXT
  LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path = public AS $$
    SELECT auth.jwt() -> 'user_metadata' ->> 'role'
  $$;

CREATE OR REPLACE FUNCTION fuelos_user_id() RETURNS TEXT
  LANGUAGE sql STABLE SECURITY DEFINER
  SET search_path = public AS $$
    SELECT auth.jwt() -> 'user_metadata' ->> 'fuelos_user_id'
  $$;

-- ── 2. Drop old creditor functions ───────────────────────────────────────────

REVOKE EXECUTE ON FUNCTION fuelos_creditor_lookup(TEXT, TEXT)         FROM anon;
REVOKE EXECUTE ON FUNCTION fuelos_creditor_transactions(TEXT, TEXT)   FROM anon;
REVOKE EXECUTE ON FUNCTION fuelos_creditor_payments(TEXT, TEXT)       FROM anon;

DROP FUNCTION IF EXISTS fuelos_creditor_lookup(TEXT, TEXT);
DROP FUNCTION IF EXISTS fuelos_creditor_transactions(TEXT, TEXT);
DROP FUNCTION IF EXISTS fuelos_creditor_payments(TEXT, TEXT);

-- ── 3. Single creditor portal RPC ─────────────────────────────────────────────
-- Accepts only station_code (public) and phone (caller-known).
-- Resolves FuelStation.id and CreditCustomer.id internally — never returned.
-- Returns JSONB: { found, customer, transactions, payments }
--               or { found: false } when no match.
--
-- Anon callers cannot read FuelStation, CreditCustomer, CreditTransaction, or
-- CreditPayment directly — all table-level RLS remains authenticated-only.

CREATE OR REPLACE FUNCTION fuelos_creditor_portal_data(
  p_station_code TEXT,
  p_phone        TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_station_id  TEXT;
  v_customer_id TEXT;
  v_customer    JSONB;
  v_txns        JSONB;
  v_payments    JSONB;
BEGIN
  -- Resolve station (SECURITY DEFINER bypasses RLS on FuelStation for anon)
  SELECT id INTO v_station_id
  FROM "FuelStation"
  WHERE station_code = p_station_code
  LIMIT 1;

  IF v_station_id IS NULL THEN
    RETURN jsonb_build_object('found', FALSE);
  END IF;

  -- Find active, non-deleted customer; keep id server-side only
  SELECT
    id,
    jsonb_build_object(
      'full_name',       full_name,
      'phone_number',    phone_number,
      'customer_code',   customer_code,
      'active',          active
    )
  INTO v_customer_id, v_customer
  FROM "CreditCustomer"
  WHERE station_id   = v_station_id
    AND phone_number = p_phone
    AND active       = TRUE
    AND deleted_at  IS NULL
  LIMIT 1;

  IF v_customer_id IS NULL THEN
    RETURN jsonb_build_object('found', FALSE);
  END IF;

  -- Last 50 transactions; no id or customer_id in output
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'date',              t.date,
        'amount',            t.amount,
        'liters',            t.liters,
        'fuel_type',         t.fuel_type,
        'remaining_balance', t.remaining_balance,
        'status',            t.status,
        'created_at',        t.created_at
      )
      ORDER BY t.date DESC
    ),
    '[]'::JSONB
  ) INTO v_txns
  FROM (
    SELECT date, amount, liters, fuel_type,
           remaining_balance, status, created_at
    FROM "CreditTransaction"
    WHERE station_id  = v_station_id
      AND customer_id = v_customer_id
    ORDER BY date DESC
    LIMIT 50
  ) t;

  -- Last 50 payments; no id exposed; linked via CreditTransaction join server-side
  SELECT COALESCE(
    jsonb_agg(
      jsonb_build_object(
        'paid_amount',  p.paid_amount,
        'payment_mode', p.payment_mode,
        'date',         p.date,
        'note',         p.note,
        'created_at',   p.created_at
      )
      ORDER BY p.date DESC
    ),
    '[]'::JSONB
  ) INTO v_payments
  FROM (
    SELECT cp.paid_amount, cp.payment_mode, cp.date, cp.note, cp.created_at
    FROM "CreditPayment" cp
    JOIN "CreditTransaction" ct ON ct.id = cp.credit_id
    WHERE cp.station_id  = v_station_id
      AND ct.customer_id = v_customer_id
    ORDER BY cp.date DESC
    LIMIT 50
  ) p;

  RETURN jsonb_build_object(
    'found',        TRUE,
    'customer',     v_customer,
    'transactions', v_txns,
    'payments',     v_payments
  );
END;
$$;

GRANT EXECUTE ON FUNCTION fuelos_creditor_portal_data(TEXT, TEXT) TO anon;

COMMIT;
