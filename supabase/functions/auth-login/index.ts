// supabase/functions/auth-login/index.ts
// Validates credentials and returns a real Supabase Auth session.
// Column names match Prisma schema exactly.

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import * as bcrypt from 'https://deno.land/x/bcrypt@v0.4.1/mod.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
}

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { identifier, credential, role, is_pin, station_code } =
      await req.json()

    if (!identifier || !credential || !role) {
      return json({ error: 'identifier, credential, role required' }, 400)
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    // ── 1. Verify the station exists ──────────────────────────────────────────
    // FuelStation schema: id, station_code, station_name, owner_user_id, active
    const { data: station, error: stationErr } = await supabase
      .from('FuelStation')
      .select('id, station_code, station_name')
      .eq('station_code', (station_code as string).toUpperCase().trim())
      .eq('active', true)
      .single()

    if (stationErr || !station) {
      return json({ error: 'Station not found' }, 401)
    }

    // ── 2. Find the user ──────────────────────────────────────────────────────
    // User schema: id, station_id, role, full_name, username, employee_id,
    //   phone_number, password_hash, active, supabase_auth_id, pin_hash
    // Identifier can be username, employee_id, or phone_number
    const { data: user, error: userErr } = await supabase
      .from('User')
      .select(
        'id, full_name, username, employee_id, phone_number, role, ' +
        'password_hash, pin_hash, active, station_id, supabase_auth_id',
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

    // ── 3. Validate credential ────────────────────────────────────────────────
    let credentialValid = false
    if (is_pin && user.pin_hash) {
      credentialValid = await bcrypt.compare(String(credential), user.pin_hash)
    } else if (user.password_hash) {
      credentialValid = await bcrypt.compare(
        String(credential),
        user.password_hash,
      )
    }

    if (!credentialValid) {
      return json({ error: 'Invalid credentials' }, 401)
    }

    // ── 4. Get or create Supabase Auth user ───────────────────────────────────
    const internalEmail = `${user.id}@internal.fuelos.app`
    const salt = Deno.env.get('INTERNAL_SALT')
    if (!salt) {
      return json({ error: 'Server misconfiguration' }, 500)
    }
    const internalPassword = user.id + salt
    let supabaseAuthId = user.supabase_auth_id

    const authMeta = {
      fuelos_user_id: user.id,
      station_id: station.id,
      station_code: station.station_code,
      station_name: station.station_name,
      role: user.role,
      full_name: user.full_name,
    }

    if (!supabaseAuthId) {
      // Create Supabase Auth user first time
      const { data: authData, error: createErr } =
        await supabase.auth.admin.createUser({
          email: internalEmail,
          password: internalPassword,
          email_confirm: true,
          user_metadata: authMeta,
        })

      if (createErr || !authData.user) {
        return json(
          { error: 'Auth user creation failed: ' + createErr?.message },
          500,
        )
      }
      supabaseAuthId = authData.user.id

      // Persist supabase_auth_id back to our User row
      await supabase
        .from('User')
        .update({ supabase_auth_id: supabaseAuthId })
        .eq('id', user.id)
    } else {
      // Update metadata to keep it fresh
      await supabase.auth.admin.updateUserById(supabaseAuthId, {
        password: internalPassword,
        user_metadata: authMeta,
      })
    }

    // ── 5. Create session ─────────────────────────────────────────────────────
    const anonClient = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_ANON_KEY')!,
    )

    const { data: sessionData, error: signInErr } =
      await anonClient.auth.signInWithPassword({
        email: internalEmail,
        password: internalPassword,
      })

    if (signInErr || !sessionData.session) {
      return json(
        { error: 'Session creation failed: ' + signInErr?.message },
        500,
      )
    }

    // ── 6. Update last_login_at ───────────────────────────────────────────────
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
    console.error('auth-login error:', err)
    return json({ error: 'Internal server error' }, 500)
  }
})

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
