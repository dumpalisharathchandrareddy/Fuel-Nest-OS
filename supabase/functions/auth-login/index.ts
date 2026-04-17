// supabase/functions/auth-login/index.ts
// Validates credentials against public.User and returns a Supabase Auth session.
// Column names match Prisma schema exactly. supabase_auth_id is NOT in schema.

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
}

// Verifies pbkdf2_sha256$iterations$saltHex$hashHex format.
// Returns false for bcrypt hashes ($2...) — those users must reset their password.
async function verifyPassword(password: string, stored: string): Promise<boolean> {
  if (!stored || stored.startsWith('$2')) return false
  const parts = stored.split('$')
  if (parts.length !== 4 || parts[0] !== 'pbkdf2_sha256') return false
  const iterations = parseInt(parts[1], 10)
  const salt = new Uint8Array((parts[2].match(/.{2}/g) ?? []).map((h) => parseInt(h, 16)))
  const storedHash = parts[3]
  const keyMaterial = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(password),
    'PBKDF2',
    false,
    ['deriveBits'],
  )
  const bits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', hash: 'SHA-256', salt, iterations },
    keyMaterial,
    256,
  )
  const derived = Array.from(new Uint8Array(bits))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
  return derived === storedHash
}

// Must match deriveInternalPassword in auth-signup-dealer exactly.
async function deriveInternalPassword(userId: string, salt: string): Promise<string> {
  const input = new TextEncoder().encode(userId + ':' + salt)
  const hashBuffer = await crypto.subtle.digest('SHA-256', input)
  const hex = Array.from(new Uint8Array(hashBuffer))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
  return 'Fuelos1!' + hex.slice(0, 48)
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
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
      console.error('auth-login: missing env vars:', missingEnv.join(', '))
      return json({ error: 'missing_env', missing: missingEnv }, 500)
    }

    const { identifier, credential, role, is_pin, station_code } =
      await req.json()

    if (!identifier || !credential || !role) {
      return json({ error: 'identifier, credential, role required' }, 400)
    }

    const supabase = createClient(SUPABASE_URL!, FUELOS_SERVICE_ROLE_KEY!)

    // ── 1. Verify station exists ──────────────────────────────────────────
    const { data: station, error: stationErr } = await supabase
      .from('FuelStation')
      .select('id, station_code, station_name')
      .eq('station_code', (station_code as string).toUpperCase().trim())
      .eq('active', true)
      .single()

    if (stationErr || !station) {
      return json({ error: 'Station not found' }, 401)
    }

    // ── 2. Find the user (columns per Prisma schema) ──────────────────────
    const { data: user, error: userErr } = await supabase
      .from('User')
      .select(
        'id, full_name, username, employee_id, phone_number, role, ' +
        'password_hash, pin_hash, active, station_id',
      )
      .eq('station_id', station.id)
      .eq('role', role)
      .eq('active', true)
      .or(
        `username.eq.${identifier},` +
        `employee_id.eq.${identifier},` +
        `phone_number.eq.${identifier}`,
      )
      .maybeSingle()

    if (userErr || !user) {
      return json({ error: 'Invalid credentials' }, 401)
    }

    // ── 3. Validate credential ────────────────────────────────────────────
    let credentialValid = false
    if (is_pin && user.pin_hash) {
      credentialValid = await verifyPassword(String(credential), user.pin_hash)
    } else if (user.password_hash) {
      credentialValid = await verifyPassword(String(credential), user.password_hash)
    }

    if (!credentialValid) {
      return json({ error: 'Invalid credentials' }, 401)
    }

    // ── 4. Ensure Supabase Auth user exists (get or create) ───────────────
    // Dealers: created during signup. Workers: created on first login.
    // We do not store supabase_auth_id (not in Prisma schema); look up by email.
    const internalEmail = `${user.id}@internal.fuelos.app`
    const internalPassword = await deriveInternalPassword(user.id, INTERNAL_SALT!)

    const authMeta = {
      fuelos_user_id: user.id,
      station_id: station.id,
      station_code: station.station_code,
      station_name: station.station_name,
      role: user.role,
      full_name: user.full_name,
    }

    // Try to find existing auth user by email
    const { data: existingAuthUsers } = await supabase.auth.admin.listUsers()
    const existingAuthUser = existingAuthUsers?.users?.find(
      (u) => u.email === internalEmail,
    )

    if (existingAuthUser) {
      // Refresh password and metadata to stay in sync
      await supabase.auth.admin.updateUserById(existingAuthUser.id, {
        password: internalPassword,
        user_metadata: authMeta,
      })
    } else {
      // First login for this user (workers, or dealers whose auth user was lost)
      const { error: createErr } = await supabase.auth.admin.createUser({
        email: internalEmail,
        password: internalPassword,
        email_confirm: true,
        user_metadata: authMeta,
      })

      if (createErr) {
        console.error('auth-login: auth.admin.createUser failed:', JSON.stringify({
          name: createErr.name,
          status: (createErr as { status?: number })?.status,
          message: createErr.message,
        }))
        return json({ error: 'auth_user_create_failed', detail: createErr.message }, 500)
      }
    }

    // ── 5. Create session ─────────────────────────────────────────────────
    const anonClient = createClient(SUPABASE_URL!, SUPABASE_ANON_KEY!)

    const { data: sessionData, error: signInErr } =
      await anonClient.auth.signInWithPassword({
        email: internalEmail,
        password: internalPassword,
      })

    if (signInErr || !sessionData?.session) {
      console.error('auth-login: signInWithPassword failed:', signInErr?.message)
      return json({ error: 'session_create_failed', detail: signInErr?.message }, 500)
    }

    // ── 6. Update last_login_at ───────────────────────────────────────────
    await supabase
      .from('User')
      .update({ last_login_at: new Date().toISOString() })
      .eq('id', user.id)

    return json({
      access_token: sessionData.session.access_token,
      refresh_token: sessionData.session.refresh_token,
      user: {
        id: user.id,
        full_name: user.full_name,
        username: user.username,
        employee_id: user.employee_id,
        phone_number: user.phone_number,
        role: user.role,
        station_id: station.id,
        station_code: station.station_code,
        station_name: station.station_name,
      },
    })
  } catch (err) {
    console.error('auth-login: unhandled error:', (err as Error).message)
    return json({ error: 'internal_server_error' }, 500)
  }
})

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
