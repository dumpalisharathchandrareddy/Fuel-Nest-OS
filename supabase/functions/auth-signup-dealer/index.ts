// supabase/functions/auth-signup-dealer/index.ts
import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
}

// Format: pbkdf2_sha256$iterations$saltHex$hashHex
async function hashPassword(password: string): Promise<string> {
  const salt = crypto.getRandomValues(new Uint8Array(16))
  const keyMaterial = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(password),
    'PBKDF2',
    false,
    ['deriveBits'],
  )
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', hash: 'SHA-256', salt, iterations: 100_000 },
    keyMaterial,
    256,
  )
  const toHex = (buf: Uint8Array) =>
    Array.from(buf).map((b) => b.toString(16).padStart(2, '0')).join('')
  return `pbkdf2_sha256$100000$${toHex(salt)}$${toHex(new Uint8Array(bits))}`
}

// Deterministic internal password: SHA-256(userId:INTERNAL_SALT) → "Fuelos1!" + hex[0..47]
// Total length: 56 chars. Meets complexity (upper, lower, digit, special).
async function deriveInternalPassword(userId: string, salt: string): Promise<string> {
  const input = new TextEncoder().encode(userId + ':' + salt)
  const hashBuffer = await crypto.subtle.digest('SHA-256', input)
  const hex = Array.from(new Uint8Array(hashBuffer))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
  return 'Fuelos1!' + hex.slice(0, 48)
}

// JWT payload uses base64url encoding (RFC 4648 §5): - → +, _ → /, pad with =
function decodeBase64Url(b64url: string): string {
  const b64 = b64url.replace(/-/g, '+').replace(/_/g, '/')
  const padded = b64 + '='.repeat((4 - (b64.length % 4)) % 4)
  return atob(padded)
}

// Decode JWT payload and validate role/ref without logging the key itself.
function validateServiceRoleJwt(key: string): { valid: boolean; error?: string } {
  try {
    const parts = key.split('.')
    if (parts.length !== 3) return { valid: false, error: 'not a 3-segment JWT' }
    const payload = JSON.parse(decodeBase64Url(parts[1]))
    if (payload.role !== 'service_role') {
      return { valid: false, error: `JWT role="${payload.role}", expected "service_role"` }
    }
    if (payload.ref && payload.ref !== 'kcriypstkmbafhqytqrr') {
      return { valid: false, error: `JWT ref="${payload.ref}" does not match project` }
    }
    return { valid: true }
  } catch (e) {
    return { valid: false, error: 'failed to decode JWT payload: ' + (e as Error).message }
  }
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return json('ok', 200)
  }

  try {
    // ── Validate env vars ───────────────────────────────────────────────────
    const SUPABASE_URL = Deno.env.get('SUPABASE_URL')
    const FUELOS_SERVICE_ROLE_KEY = Deno.env.get('FUELOS_SERVICE_ROLE_KEY')
    const SUPABASE_ANON_KEY = Deno.env.get('SUPABASE_ANON_KEY')
    const INTERNAL_SALT = Deno.env.get('INTERNAL_SALT')

    const missingEnv: string[] = []
    if (!SUPABASE_URL) missingEnv.push('SUPABASE_URL')
    if (!FUELOS_SERVICE_ROLE_KEY) missingEnv.push('FUELOS_SERVICE_ROLE_KEY')
    if (!SUPABASE_ANON_KEY) missingEnv.push('SUPABASE_ANON_KEY')
    if (!INTERNAL_SALT) missingEnv.push('INTERNAL_SALT')

    if (missingEnv.length > 0) {
      console.error('auth-signup-dealer: missing env vars:', missingEnv.join(', '))
      return json({ error: 'missing_env', missing: missingEnv }, 500)
    }

    console.log('auth-signup-dealer step: env-ok')

    // ── Validate service role key is a JWT with role=service_role ──────────
    if (!FUELOS_SERVICE_ROLE_KEY!.startsWith('eyJ')) {
      console.error(
        'auth-signup-dealer: FUELOS_SERVICE_ROLE_KEY is not a JWT. ' +
        'Use the legacy JWT service_role key from Project Settings > API. ' +
        'Key prefix: ' + FUELOS_SERVICE_ROLE_KEY!.slice(0, 8) + '...',
      )
      return json({ error: 'invalid_service_role_key', detail: 'Must be the eyJ... JWT service_role key' }, 500)
    }

    const jwtCheck = validateServiceRoleJwt(FUELOS_SERVICE_ROLE_KEY!)
    if (!jwtCheck.valid) {
      console.error('auth-signup-dealer: service role key validation failed:', jwtCheck.error)
      return json({ error: 'invalid_service_role_key', detail: jwtCheck.error }, 500)
    }

    console.log('auth-signup-dealer step: jwt-ok')

    // ── Parse request body ──────────────────────────────────────────────────
    const {
      station_code,
      station_name,
      owner_name,
      phone,
      password,
      address_line_1,
      address_line_2,
      city,
      state,
      postal_code,
    } = await req.json()

    if (!station_code || !station_name || !owner_name || !phone || !password) {
      return json(
        { error: 'station_code, station_name, owner_name, phone, password are required' },
        400,
      )
    }

    if (String(password).length < 6) {
      return json({ error: 'Password must be at least 6 characters' }, 400)
    }

    console.log('auth-signup-dealer step: body-parsed')

    const supabase = createClient(SUPABASE_URL!, FUELOS_SERVICE_ROLE_KEY!)
    const cleanCode = String(station_code).toUpperCase().trim().replace(/\s/g, '')

    // ── Check for duplicate or partial signup ───────────────────────────────
    const { data: existingStation } = await supabase
      .from('FuelStation')
      .select('id, owner_user_id')
      .eq('station_code', cleanCode)
      .maybeSingle()

    console.log('auth-signup-dealer step: station-check')

    if (existingStation) {
      if (existingStation.owner_user_id !== null) {
        return json({ error: 'Station code already registered' }, 409)
      }

      const { data: orphanUser } = await supabase
        .from('User')
        .select('id')
        .eq('station_id', existingStation.id)
        .maybeSingle()

      if (!orphanUser) {
        const { error: deleteErr } = await supabase
          .from('FuelStation')
          .delete()
          .eq('id', existingStation.id)

        if (deleteErr) {
          console.error(
            'auth-signup-dealer: failed to clean partial station',
            existingStation.id,
            deleteErr.message,
          )
          return json(
            {
              error: 'partial_signup_exists',
              detail: 'Partial registration exists and could not be cleaned. Contact support.',
            },
            409,
          )
        }
        // Orphaned station deleted — fall through to fresh signup
      } else {
        return json(
          {
            error: 'partial_signup_exists',
            detail: 'Incomplete registration exists for this station code. Contact support.',
          },
          409,
        )
      }
    }

    const now = new Date().toISOString()
    const stationId = crypto.randomUUID()
    const userId = crypto.randomUUID()

    // ── 1. Create FuelStation (owner_user_id = null until User is created) ──
    const { error: stationErr } = await supabase.from('FuelStation').insert({
      id: stationId,
      station_code: cleanCode,
      station_name: String(station_name).trim(),
      owner_user_id: null,
      address_line_1: address_line_1 ? String(address_line_1).trim() : null,
      address_line_2: address_line_2 ? String(address_line_2).trim() : null,
      city: city ? String(city).trim() : null,
      state: state ? String(state).trim() : null,
      postal_code: postal_code ? String(postal_code).trim() : null,
      country: 'India',
      phone_number: String(phone).trim(),
      active: true,
      created_at: now,
      updated_at: now,
    })

    if (stationErr) {
      console.error('auth-signup-dealer: FuelStation insert failed:', stationErr.message)
      return json({ error: 'station_create_failed', detail: stationErr.message }, 500)
    }

    console.log('auth-signup-dealer step: station-insert')

    // ── 2. Create Supabase Auth user ────────────────────────────────────────
    const internalEmail = `${userId}@internal.fuelos.app`
    const internalPassword = await deriveInternalPassword(userId, INTERNAL_SALT!)

    const { data: authData, error: authErr } =
      await supabase.auth.admin.createUser({
        email: internalEmail,
        password: internalPassword,
        email_confirm: true,
        user_metadata: {
          fuelos_user_id: userId,
          station_id: stationId,
          station_code: cleanCode,
          station_name: String(station_name).trim(),
          role: 'DEALER',
          full_name: String(owner_name).trim(),
        },
      })

    if (authErr || !authData?.user) {
      console.error('auth-signup-dealer: auth.admin.createUser failed:', JSON.stringify({
        name: authErr?.name,
        status: (authErr as { status?: number })?.status,
        message: authErr?.message,
      }))
      await supabase.from('FuelStation').delete().eq('id', stationId)
      return json({ error: 'auth_user_create_failed', detail: authErr?.message }, 500)
    }

    console.log('auth-signup-dealer step: auth-create')

    // ── 3. Hash user-facing password and derive username ────────────────────
    const passwordHash = await hashPassword(String(password))
    const username = String(phone).replace(/\D/g, '').slice(-10)

    // ── 4. Create public.User row (columns per Prisma schema) ───────────────
    const { error: userErr } = await supabase.from('User').insert({
      id: userId,
      station_id: stationId,
      role: 'DEALER',
      full_name: String(owner_name).trim(),
      username,
      phone_number: String(phone).trim(),
      password_hash: passwordHash,
      active: true,
      created_at: now,
      updated_at: now,
    })

    if (userErr) {
      console.error('auth-signup-dealer: User insert failed:', userErr.message)
      await supabase.auth.admin.deleteUser(authData.user.id)
      await supabase.from('FuelStation').delete().eq('id', stationId)
      return json({ error: 'user_create_failed', detail: userErr.message }, 500)
    }

    console.log('auth-signup-dealer step: user-insert')

    // ── 5. Link FuelStation.owner_user_id → public.User.id ─────────────────
    const { error: updateErr } = await supabase
      .from('FuelStation')
      .update({ owner_user_id: userId, updated_at: now })
      .eq('id', stationId)

    if (updateErr) {
      console.error('auth-signup-dealer: owner_user_id update failed (non-fatal):', updateErr.message)
    }

    console.log('auth-signup-dealer step: owner-link')

    // ── 6. Create StationSettings (columns per Prisma schema) ───────────────
    const { error: settingsErr } = await supabase.from('StationSettings').insert({
      station_id: stationId,
      manager_can_edit_fuel_rates: false,
      shift_whatsapp_share_policy: 'OPTIONAL',
      inventory_dip_check_enabled: true,
      testing_fuel_default: 5,
      created_at: now,
      updated_at: now,
    })

    if (settingsErr) {
      console.error('auth-signup-dealer: StationSettings insert failed (non-fatal):', settingsErr.message)
    }

    // ── 7. Sign in to get session ───────────────────────────────────────────
    const anonClient = createClient(SUPABASE_URL!, SUPABASE_ANON_KEY!)

    const { data: sessionData, error: signInErr } =
      await anonClient.auth.signInWithPassword({
        email: internalEmail,
        password: internalPassword,
      })

    console.log('auth-signup-dealer step: session-create')

    if (signInErr || !sessionData?.session) {
      console.error('auth-signup-dealer: sign-in after signup failed:', signInErr?.message)
      return json({
        access_token: null,
        refresh_token: null,
        user: {
          id: userId,
          full_name: String(owner_name).trim(),
          role: 'DEALER',
          phone_number: String(phone).trim(),
          station_id: stationId,
          station_code: cleanCode,
          station_name: String(station_name).trim(),
        },
        warning: 'Station created. Please log in.',
      })
    }

    return json({
      access_token: sessionData.session.access_token,
      refresh_token: sessionData.session.refresh_token,
      user: {
        id: userId,
        full_name: String(owner_name).trim(),
        role: 'DEALER',
        phone_number: String(phone).trim(),
        username,
        station_id: stationId,
        station_code: cleanCode,
        station_name: String(station_name).trim(),
      },
    })
  } catch (err) {
    const e = err as Error
    console.error('auth-signup-dealer: unhandled error:', JSON.stringify({
      name: e.name,
      message: e.message,
      stack: e.stack,
    }))
    return json({ error: 'internal_server_error', detail: e.message }, 500)
  }
})

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
