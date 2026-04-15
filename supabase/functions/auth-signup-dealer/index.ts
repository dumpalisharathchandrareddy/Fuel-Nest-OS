// supabase/functions/auth-signup-dealer/index.ts
// Creates a new dealer station with exact Prisma schema column names.
// FuelStation.owner_user_id, address_line_1, station_name, station_code.

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
    const {
      station_code,
      station_name,
      owner_name,
      phone,
      password,
      address_line_1,  // Prisma: address_line_1 (NOT address)
      address_line_2,
      city,
      state,
      postal_code,
    } = await req.json()

    // Required fields
    if (!station_code || !station_name || !owner_name || !phone || !password) {
      return json(
        {
          error:
            'station_code, station_name, owner_name, phone, password are required',
        },
        400,
      )
    }

    if (String(password).length < 6) {
      return json({ error: 'Password must be at least 6 characters' }, 400)
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    const cleanCode = String(station_code).toUpperCase().trim().replace(/\s/g, '')

    // ── Check station code not taken ──────────────────────────────────────────
    const { data: existing } = await supabase
      .from('FuelStation')
      .select('id')
      .eq('station_code', cleanCode)
      .maybeSingle()

    if (existing) {
      return json({ error: 'Station code already registered' }, 409)
    }

    const now = new Date().toISOString()
    const stationId = crypto.randomUUID()
    const userId = crypto.randomUUID()

    // ── 1. Create FuelStation ─────────────────────────────────────────────────
    // Exact Prisma columns: id, station_code, station_name, owner_user_id,
    //   address_line_1, address_line_2, city, state, postal_code, country,
    //   phone_number, active, created_at, updated_at
    const { error: stationErr } = await supabase.from('FuelStation').insert({
      id: stationId,
      station_code: cleanCode,
      station_name: String(station_name).trim(),
      owner_user_id: userId,          // NOT owner_id
      address_line_1: address_line_1  // NOT address
        ? String(address_line_1).trim()
        : null,
      address_line_2: address_line_2
        ? String(address_line_2).trim()
        : null,
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
      return json(
        { error: 'Failed to create station: ' + stationErr.message },
        500,
      )
    }

    // ── 2. Hash password ──────────────────────────────────────────────────────
    const passwordHash = await bcrypt.hash(String(password))

    // Derive a username from phone digits
    const username = String(phone).replace(/\D/g, '').slice(-10)

    // ── 3. Create User ────────────────────────────────────────────────────────
    // Exact Prisma columns: id, station_id, role, full_name, username,
    //   phone_number, password_hash, active, created_at, updated_at
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
      // Rollback station
      await supabase.from('FuelStation').delete().eq('id', stationId)
      return json({ error: 'Failed to create user: ' + userErr.message }, 500)
    }

    // ── 4. Create Supabase Auth user ──────────────────────────────────────────
    const internalEmail = `${userId}@internal.fuelos.app`
    const internalPassword =
      userId + (Deno.env.get('INTERNAL_SALT') ?? 'fuelos_salt_2025')

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

    if (authErr || !authData.user) {
      // Rollback both
      await supabase.from('User').delete().eq('id', userId)
      await supabase.from('FuelStation').delete().eq('id', stationId)
      return json(
        { error: 'Auth user creation failed: ' + authErr?.message },
        500,
      )
    }

    // Store supabase_auth_id
    await supabase
      .from('User')
      .update({ supabase_auth_id: authData.user.id })
      .eq('id', userId)

    // ── 5. Create default StationSettings ────────────────────────────────────
    await supabase.from('StationSettings').insert({
      station_id: stationId,
      manager_can_edit_fuel_rates: false,
      shift_whatsapp_share_policy: 'OPTIONAL',
      inventory_dip_check_enabled: true,
      testing_fuel_default: 5,
      created_at: now,
      updated_at: now,
    }).catch(() => {}) // Non-fatal if settings already exist

    // ── 6. Sign in to get session ─────────────────────────────────────────────
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
      // Station is created but session failed — still success, they can log in
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
    console.error('auth-signup-dealer error:', err)
    return json({ error: 'Internal server error' }, 500)
  }
})

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
