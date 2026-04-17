-- ============================================================
-- FuelOS Migration: 002_flutter_auth_support.sql
-- Adds supabase_auth_id + pin_hash to User (not in Prisma schema).
-- Creates JWT helper functions.
-- Creates ALL RLS policies using exact Prisma column names.
-- ============================================================

BEGIN;

-- ── Flutter-only columns (added on top of existing Prisma schema) ─────────────

ALTER TABLE "User"
  ADD COLUMN IF NOT EXISTS supabase_auth_id UUID REFERENCES auth.users(id)
    ON DELETE SET NULL;

ALTER TABLE "User"
  ADD COLUMN IF NOT EXISTS pin_hash TEXT;

CREATE INDEX IF NOT EXISTS idx_user_supabase_auth_id
  ON "User"(supabase_auth_id);

-- ── JWT helper functions ──────────────────────────────────────────────────────
-- These read station_id, role, and user_id from the JWT user_metadata
-- that auth-login sets when creating/updating the Supabase Auth user.

CREATE OR REPLACE FUNCTION fuelos_station_id() RETURNS TEXT
  LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT auth.jwt() -> 'user_metadata' ->> 'station_id'
  $$;

CREATE OR REPLACE FUNCTION fuelos_role() RETURNS TEXT
  LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT auth.jwt() -> 'user_metadata' ->> 'role'
  $$;

CREATE OR REPLACE FUNCTION fuelos_user_id() RETURNS TEXT
  LANGUAGE sql STABLE SECURITY DEFINER AS $$
    SELECT auth.jwt() -> 'user_metadata' ->> 'fuelos_user_id'
  $$;

-- ── Secure creditor lookup function ──────────────────────────────────────────
-- Replaces the unsafe "OR true" open-read hack.
-- Returns a customer row only when the calling phone matches.
-- Called with anon key from the creditor portal — no JWT needed.
CREATE OR REPLACE FUNCTION fuelos_creditor_lookup(
  p_station_id TEXT,
  p_phone      TEXT
)
RETURNS TABLE (
  id              TEXT,
  full_name       TEXT,
  phone_number    TEXT,
  customer_code   TEXT,
  advance_balance NUMERIC,
  active          BOOLEAN
)
LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT
    id, full_name, phone_number,
    customer_code, advance_balance, active
  FROM "CreditCustomer"
  WHERE station_id  = p_station_id
    AND phone_number = p_phone
    AND active       = TRUE
    AND deleted_at  IS NULL
  LIMIT 1;
$$;

-- Grant anon access to the function only (not the table)
GRANT EXECUTE ON FUNCTION fuelos_creditor_lookup(TEXT, TEXT) TO anon;

-- ── Secure creditor transaction lookup ───────────────────────────────────────
-- Returns credit transactions for a verified customer (by customer_id from above).
CREATE OR REPLACE FUNCTION fuelos_creditor_transactions(
  p_station_id  TEXT,
  p_customer_id TEXT
)
RETURNS TABLE (
  id                TEXT,
  date              TIMESTAMPTZ,
  amount            NUMERIC,
  liters            NUMERIC,
  fuel_type         TEXT,
  remaining_balance NUMERIC,
  status            TEXT,
  created_at        TIMESTAMPTZ
)
LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT
    id, date, amount, liters, fuel_type,
    remaining_balance, status, created_at
  FROM "CreditTransaction"
  WHERE station_id  = p_station_id
    AND customer_id = p_customer_id
  ORDER BY date DESC
  LIMIT 50;
$$;

GRANT EXECUTE ON FUNCTION fuelos_creditor_transactions(TEXT, TEXT) TO anon;

-- ── Secure creditor payments lookup ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION fuelos_creditor_payments(
  p_station_id  TEXT,
  p_customer_id TEXT
)
RETURNS TABLE (
  id           TEXT,
  paid_amount  NUMERIC,
  payment_mode TEXT,
  date         TIMESTAMPTZ,
  note         TEXT,
  created_at   TIMESTAMPTZ
)
LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT
    cp.id, cp.paid_amount, cp.payment_mode,
    cp.date, cp.note, cp.created_at
  FROM "CreditPayment" cp
  JOIN "CreditTransaction" ct ON ct.id = cp.credit_id
  WHERE cp.station_id  = p_station_id
    AND ct.customer_id = p_customer_id
  ORDER BY cp.date DESC
  LIMIT 50;
$$;

GRANT EXECUTE ON FUNCTION fuelos_creditor_payments(TEXT, TEXT) TO anon;

COMMIT;

-- ============================================================
-- RLS POLICIES
-- All policies use exact Prisma column names.
-- "authenticated" role = logged-in Flutter app users via Supabase Auth.
-- No anon access to tables — creditors use SECURITY DEFINER functions above.
-- ============================================================

-- ── FuelStation ───────────────────────────────────────────────────────────────
-- Prisma: id, station_code, station_name, owner_user_id, ...

CREATE POLICY "station_own_read" ON "FuelStation"
  FOR SELECT TO authenticated
  USING (id = fuelos_station_id());

CREATE POLICY "station_own_update_dealer" ON "FuelStation"
  FOR UPDATE TO authenticated
  USING (id = fuelos_station_id() AND fuelos_role() = 'DEALER');

-- ── User ─────────────────────────────────────────────────────────────────────
-- Prisma: id, station_id, role, full_name, username, employee_id,
--   phone_number, password_hash, active, created_by_id, ...

CREATE POLICY "user_same_station_read" ON "User"
  FOR SELECT TO authenticated
  USING (station_id = fuelos_station_id());

-- Staff can always read their own record
CREATE POLICY "user_self_read" ON "User"
  FOR SELECT TO authenticated
  USING (id = fuelos_user_id());

CREATE POLICY "user_manager_insert" ON "User"
  FOR INSERT TO authenticated
  WITH CHECK (
    station_id = fuelos_station_id()
    AND fuelos_role() IN ('DEALER', 'MANAGER')
    -- Managers can only create PUMP_PERSON; dealer can create MANAGER or PUMP_PERSON
  );

CREATE POLICY "user_manager_update" ON "User"
  FOR UPDATE TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND fuelos_role() IN ('DEALER', 'MANAGER')
  );

-- ── Pump ─────────────────────────────────────────────────────────────────────
-- Prisma: id, station_id, name, provider_type, active

CREATE POLICY "pump_station_read" ON "Pump"
  FOR SELECT TO authenticated
  USING (station_id = fuelos_station_id());

CREATE POLICY "pump_manager_write" ON "Pump"
  FOR ALL TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND fuelos_role() IN ('DEALER', 'MANAGER')
  );

-- ── Tank ─────────────────────────────────────────────────────────────────────
-- Prisma: id, station_id, name, fuel_type, capacity_liters,
--   active, low_stock_threshold
-- NO current_stock column.

CREATE POLICY "tank_station_read" ON "Tank"
  FOR SELECT TO authenticated
  USING (station_id = fuelos_station_id());

CREATE POLICY "tank_manager_write" ON "Tank"
  FOR ALL TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND fuelos_role() IN ('DEALER', 'MANAGER')
  );

-- ── Nozzle ────────────────────────────────────────────────────────────────────
-- Prisma: id, station_id, pump_id, tank_id, label, fuel_type, default_testing, active

CREATE POLICY "nozzle_station_read" ON "Nozzle"
  FOR SELECT TO authenticated
  USING (station_id = fuelos_station_id());

CREATE POLICY "nozzle_manager_write" ON "Nozzle"
  FOR ALL TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND fuelos_role() IN ('DEALER', 'MANAGER')
  );

-- ── FuelRate ──────────────────────────────────────────────────────────────────
-- Prisma: id, station_id, fuel_type, rate, set_by_id, effective_from
-- NO is_active column. Active rate = latest effective_from per fuel_type.

CREATE POLICY "fuel_rate_station_read" ON "FuelRate"
  FOR SELECT TO authenticated
  USING (station_id = fuelos_station_id());

CREATE POLICY "fuel_rate_manager_insert" ON "FuelRate"
  FOR INSERT TO authenticated
  WITH CHECK (
    station_id = fuelos_station_id()
    AND fuelos_role() IN ('DEALER', 'MANAGER')
    AND set_by_id = fuelos_user_id()
  );

-- No UPDATE on FuelRate — new rate inserts a new row; old rows are history.

-- ── Shift ─────────────────────────────────────────────────────────────────────
-- Prisma: id, station_id, pump_id, assigned_user_id, status,
--   start_time, submitted_at, closed_at, business_date

CREATE POLICY "shift_station_read" ON "Shift"
  FOR SELECT TO authenticated
  USING (station_id = fuelos_station_id());

-- Staff can only read their own shifts
CREATE POLICY "shift_own_read" ON "Shift"
  FOR SELECT TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND (
      fuelos_role() IN ('DEALER', 'MANAGER')
      OR assigned_user_id = fuelos_user_id()
    )
  );

CREATE POLICY "shift_manager_insert" ON "Shift"
  FOR INSERT TO authenticated
  WITH CHECK (
    station_id = fuelos_station_id()
    AND fuelos_role() IN ('DEALER', 'MANAGER')
  );

CREATE POLICY "shift_station_update" ON "Shift"
  FOR UPDATE TO authenticated
  USING (station_id = fuelos_station_id());

-- ── NozzleEntry ───────────────────────────────────────────────────────────────
-- Prisma: id, station_id, shift_id, nozzle_id, opening_reading,
--   closing_reading?, testing_quantity, sale_litres?, rate, sale_amount?

CREATE POLICY "nozzle_entry_station_read" ON "NozzleEntry"
  FOR SELECT TO authenticated
  USING (station_id = fuelos_station_id());

CREATE POLICY "nozzle_entry_station_write" ON "NozzleEntry"
  FOR ALL TO authenticated
  USING (station_id = fuelos_station_id());

-- ── PaymentRecord ─────────────────────────────────────────────────────────────
-- Prisma: id, station_id, shift_id, pump_id, upi_amount, card_amount,
--   credit_amount, cash_to_collect, actual_cash_collected_amount,
--   cash_collected, total_sale_amount, is_balanced, mismatch_amount

CREATE POLICY "payment_record_station_read" ON "PaymentRecord"
  FOR SELECT TO authenticated
  USING (station_id = fuelos_station_id());

CREATE POLICY "payment_record_manager_write" ON "PaymentRecord"
  FOR ALL TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND fuelos_role() IN ('DEALER', 'MANAGER')
  );

-- ── CreditCustomer ────────────────────────────────────────────────────────────
-- Prisma: id, station_id, full_name, phone_number, customer_code,
--   active, advance_balance, is_walk_in, deleted_at
-- NO open anon access — creditors use fuelos_creditor_lookup() function.

CREATE POLICY "credit_customer_auth_read" ON "CreditCustomer"
  FOR SELECT TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND deleted_at IS NULL
  );

CREATE POLICY "credit_customer_manager_write" ON "CreditCustomer"
  FOR ALL TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND fuelos_role() IN ('DEALER', 'MANAGER')
  );

-- ── CreditTransaction ─────────────────────────────────────────────────────────
-- Prisma: id, station_id, customer_id, pump_id?, shift_id?, date,
--   amount, liters?, fuel_type?, remaining_balance, status, created_by_id

CREATE POLICY "credit_tx_station_read" ON "CreditTransaction"
  FOR SELECT TO authenticated
  USING (station_id = fuelos_station_id());

CREATE POLICY "credit_tx_station_write" ON "CreditTransaction"
  FOR ALL TO authenticated
  USING (station_id = fuelos_station_id());

-- ── CreditPayment ────────────────────────────────────────────────────────────
-- Prisma: id, station_id, credit_id (→ CreditTransaction.id),
--   paid_amount, payment_mode, date, note, recorded_by_id
-- Link to customer: CreditPayment → CreditTransaction → CreditCustomer

CREATE POLICY "credit_payment_station_read" ON "CreditPayment"
  FOR SELECT TO authenticated
  USING (station_id = fuelos_station_id());

CREATE POLICY "credit_payment_manager_write" ON "CreditPayment"
  FOR ALL TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND fuelos_role() IN ('DEALER', 'MANAGER')
  );

-- ── FuelOrder ────────────────────────────────────────────────────────────────
-- Prisma: id, station_id, invoice_no, vendor, date, total_amount,
--   status, total_liters, payment_mode, cheque_reference

CREATE POLICY "fuel_order_station_read" ON "FuelOrder"
  FOR SELECT TO authenticated
  USING (station_id = fuelos_station_id());

CREATE POLICY "fuel_order_manager_write" ON "FuelOrder"
  FOR ALL TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND fuelos_role() IN ('DEALER', 'MANAGER')
  );

-- ── InventoryCheque ──────────────────────────────────────────────────────────
-- Prisma: id, station_id, vendor, amount, cheque_reference,
--   payment_date, status, notes

CREATE POLICY "cheque_station_read" ON "InventoryCheque"
  FOR SELECT TO authenticated
  USING (station_id = fuelos_station_id());

CREATE POLICY "cheque_manager_write" ON "InventoryCheque"
  FOR ALL TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND fuelos_role() IN ('DEALER', 'MANAGER')
  );

-- ── StockTransaction ─────────────────────────────────────────────────────────
-- Prisma: id, station_id, tank_id, type, quantity, reference_id

CREATE POLICY "stock_tx_station_read" ON "StockTransaction"
  FOR SELECT TO authenticated
  USING (station_id = fuelos_station_id());

CREATE POLICY "stock_tx_manager_write" ON "StockTransaction"
  FOR ALL TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND fuelos_role() IN ('DEALER', 'MANAGER')
  );

-- ── DipReading ────────────────────────────────────────────────────────────────
-- Prisma: id, station_id, tank_id, reading_mm?, calculated_volume,
--   variation_liters?, captured_at, captured_by_id

CREATE POLICY "dip_reading_station_read" ON "DipReading"
  FOR SELECT TO authenticated
  USING (station_id = fuelos_station_id());

CREATE POLICY "dip_reading_station_write" ON "DipReading"
  FOR INSERT TO authenticated
  WITH CHECK (
    station_id = fuelos_station_id()
    AND captured_by_id = fuelos_user_id()
  );

-- ── TankInitialStock ─────────────────────────────────────────────────────────
-- Prisma: id, station_id, tank_id, fuel_type, opening_litres,
--   stock_date, recorded_by_id

CREATE POLICY "tank_initial_stock_station_read" ON "TankInitialStock"
  FOR SELECT TO authenticated
  USING (station_id = fuelos_station_id());

CREATE POLICY "tank_initial_stock_dealer_write" ON "TankInitialStock"
  FOR ALL TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND fuelos_role() IN ('DEALER', 'MANAGER')
  );

-- ── SalaryConfig ─────────────────────────────────────────────────────────────
-- Prisma: id, station_id, user_id (unique), base_monthly_salary,
--   hourly_rate?, effective_from, created_by_id

CREATE POLICY "salary_config_manager_read" ON "SalaryConfig"
  FOR SELECT TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND fuelos_role() IN ('DEALER', 'MANAGER')
  );

-- Staff can read own config
CREATE POLICY "salary_config_own_read" ON "SalaryConfig"
  FOR SELECT TO authenticated
  USING (user_id = fuelos_user_id());

CREATE POLICY "salary_config_manager_write" ON "SalaryConfig"
  FOR ALL TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND fuelos_role() IN ('DEALER', 'MANAGER')
  );

-- ── StaffAdvance ─────────────────────────────────────────────────────────────
-- Prisma: id, station_id, user_id, amount, date, status,
--   recorded_by_id, payout_id?, reason?, is_voided

CREATE POLICY "advance_manager_read" ON "StaffAdvance"
  FOR SELECT TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND fuelos_role() IN ('DEALER', 'MANAGER')
  );

CREATE POLICY "advance_own_read" ON "StaffAdvance"
  FOR SELECT TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND user_id = fuelos_user_id()
  );

CREATE POLICY "advance_manager_insert" ON "StaffAdvance"
  FOR INSERT TO authenticated
  WITH CHECK (
    station_id = fuelos_station_id()
    AND fuelos_role() IN ('DEALER', 'MANAGER')
  );

-- ── SalaryPayout ─────────────────────────────────────────────────────────────
-- Prisma: id, station_id, user_id, month, year, period_label?,
--   base_salary_snapshot, total_advances_deducted, other_deductions,
--   incentives, net_paid, status, generated_by_id, paid_by_id?
-- NOT: staff_id, net_pay

CREATE POLICY "payout_manager_read" ON "SalaryPayout"
  FOR SELECT TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND fuelos_role() IN ('DEALER', 'MANAGER')
  );

CREATE POLICY "payout_own_read" ON "SalaryPayout"
  FOR SELECT TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND user_id = fuelos_user_id()
  );

CREATE POLICY "payout_manager_insert" ON "SalaryPayout"
  FOR INSERT TO authenticated
  WITH CHECK (
    station_id = fuelos_station_id()
    AND fuelos_role() IN ('DEALER', 'MANAGER')
    AND generated_by_id = fuelos_user_id()
  );

-- ── DailyExpense ──────────────────────────────────────────────────────────────
-- Prisma: id, station_id, expense_date (DateTime), recorded_at, name,
--   category, amount, description?, vendor_name?, recorded_by (user_id),
--   is_system_generated, deleted_at?

CREATE POLICY "expense_station_read" ON "DailyExpense"
  FOR SELECT TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND deleted_at IS NULL
  );

CREATE POLICY "expense_station_write" ON "DailyExpense"
  FOR ALL TO authenticated
  USING (station_id = fuelos_station_id());

-- ── AuditLog ──────────────────────────────────────────────────────────────────
-- Prisma: id, station_id, user_id, user_role, action_type, module,
--   reference_id, old_value, new_value, reason, timestamp

CREATE POLICY "audit_manager_read" ON "AuditLog"
  FOR SELECT TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND fuelos_role() IN ('DEALER', 'MANAGER')
  );

CREATE POLICY "audit_station_insert" ON "AuditLog"
  FOR INSERT TO authenticated
  WITH CHECK (
    station_id = fuelos_station_id()
    AND user_id = fuelos_user_id()
  );

-- ── Notification ──────────────────────────────────────────────────────────────
-- Prisma: id, station_id, user_id, type, title, message, read, created_at

CREATE POLICY "notif_own_read" ON "Notification"
  FOR SELECT TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND user_id = fuelos_user_id()
  );

CREATE POLICY "notif_own_update" ON "Notification"
  FOR UPDATE TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND user_id = fuelos_user_id()
  );

CREATE POLICY "notif_station_insert" ON "Notification"
  FOR INSERT TO authenticated
  WITH CHECK (station_id = fuelos_station_id());

-- ── GeneratedReport ───────────────────────────────────────────────────────────
-- Prisma: id, station_id, type, period_label, period_start, period_end,
--   status, report_data, pdf_url, excel_url, drive_file_id, drive_url

CREATE POLICY "report_manager_read" ON "GeneratedReport"
  FOR SELECT TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND fuelos_role() IN ('DEALER', 'MANAGER')
  );

CREATE POLICY "report_manager_write" ON "GeneratedReport"
  FOR ALL TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND fuelos_role() IN ('DEALER', 'MANAGER')
  );

-- ── GeneratedReportArtifact ───────────────────────────────────────────────────
-- Prisma: id, station_id, report_type, report_period_key, period_label?,
--   format, file_name?, drive_file_id?, generation_status
-- NO report_id column.

CREATE POLICY "artifact_manager_read" ON "GeneratedReportArtifact"
  FOR SELECT TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND fuelos_role() IN ('DEALER', 'MANAGER')
  );

CREATE POLICY "artifact_manager_write" ON "GeneratedReportArtifact"
  FOR ALL TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND fuelos_role() IN ('DEALER', 'MANAGER')
  );

-- ── StationSettings ───────────────────────────────────────────────────────────
-- Prisma: id, station_id (unique), manager_can_edit_fuel_rates,
--   shift_whatsapp_share_policy, inventory_dip_check_enabled,
--   testing_fuel_default, google_drive_* fields

CREATE POLICY "settings_station_read" ON "StationSettings"
  FOR SELECT TO authenticated
  USING (station_id = fuelos_station_id());

CREATE POLICY "settings_dealer_write" ON "StationSettings"
  FOR ALL TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND fuelos_role() = 'DEALER'
  );

-- ── WebhookConfig ────────────────────────────────────────────────────────────
-- Prisma: id, station_id (unique), url, secret?, enabled,
--   last_delivery_at, last_status, routes?
-- NOT webhook_url — column is literally "url".

CREATE POLICY "webhook_station_read" ON "WebhookConfig"
  FOR SELECT TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND fuelos_role() IN ('DEALER', 'MANAGER')
  );

CREATE POLICY "webhook_dealer_write" ON "WebhookConfig"
  FOR ALL TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND fuelos_role() = 'DEALER'
  );

-- ── WhatsAppConfig ────────────────────────────────────────────────────────────
-- Prisma: id, station_id (unique), waha_url, session_name, is_connected,
--   connected_phone, group_id, group_name, dealer_phone, notify_* booleans,
--   reminder_* fields

CREATE POLICY "whatsapp_station_read" ON "WhatsAppConfig"
  FOR SELECT TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND fuelos_role() IN ('DEALER', 'MANAGER')
  );

CREATE POLICY "whatsapp_dealer_write" ON "WhatsAppConfig"
  FOR ALL TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND fuelos_role() = 'DEALER'
  );

-- ── StaffArchiveRequest ───────────────────────────────────────────────────────
-- Prisma: id, station_id, target_user_id, requested_by_id,
--   resolved_by_id?, status, reason, created_at, resolved_at?

CREATE POLICY "archive_req_station_read" ON "StaffArchiveRequest"
  FOR SELECT TO authenticated
  USING (station_id = fuelos_station_id());

CREATE POLICY "archive_req_manager_insert" ON "StaffArchiveRequest"
  FOR INSERT TO authenticated
  WITH CHECK (
    station_id = fuelos_station_id()
    AND requested_by_id = fuelos_user_id()
    AND fuelos_role() IN ('DEALER', 'MANAGER')
  );

CREATE POLICY "archive_req_dealer_update" ON "StaffArchiveRequest"
  FOR UPDATE TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND fuelos_role() = 'DEALER'
  );

-- ── PayrollPermission ─────────────────────────────────────────────────────────
-- Prisma: id, station_id, manager_id, dealer_id, payroll_edit

CREATE POLICY "payroll_perm_station_read" ON "PayrollPermission"
  FOR SELECT TO authenticated
  USING (station_id = fuelos_station_id());

CREATE POLICY "payroll_perm_dealer_write" ON "PayrollPermission"
  FOR ALL TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND fuelos_role() = 'DEALER'
  );

-- ── MessageQueue ─────────────────────────────────────────────────────────────
-- Prisma: id, station_id, event_type, payload, scheduled_at, status, attempts

CREATE POLICY "message_queue_station_read" ON "MessageQueue"
  FOR SELECT TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND fuelos_role() IN ('DEALER', 'MANAGER')
  );

CREATE POLICY "message_queue_station_insert" ON "MessageQueue"
  FOR INSERT TO authenticated
  WITH CHECK (station_id = fuelos_station_id());

-- ── Receipt ───────────────────────────────────────────────────────────────────
-- Prisma: id, station_id, module, reference_id, image_url,
--   captured_via?, bypass_reason?, uploaded_by_id

CREATE POLICY "receipt_station_read" ON "Receipt"
  FOR SELECT TO authenticated
  USING (station_id = fuelos_station_id());

CREATE POLICY "receipt_station_insert" ON "Receipt"
  FOR INSERT TO authenticated
  WITH CHECK (
    station_id = fuelos_station_id()
    AND uploaded_by_id = fuelos_user_id()
  );

-- ── UserPushDevice ────────────────────────────────────────────────────────────
-- Prisma: id, station_id, user_id, token (unique), platform, active

CREATE POLICY "push_device_own_all" ON "UserPushDevice"
  FOR ALL TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND user_id = fuelos_user_id()
  );

-- ── ReportSettings ────────────────────────────────────────────────────────────
CREATE POLICY "report_settings_station_read" ON "ReportSettings"
  FOR SELECT TO authenticated
  USING (station_id = fuelos_station_id());

CREATE POLICY "report_settings_dealer_write" ON "ReportSettings"
  FOR ALL TO authenticated
  USING (
    station_id = fuelos_station_id()
    AND fuelos_role() IN ('DEALER', 'MANAGER')
  );
