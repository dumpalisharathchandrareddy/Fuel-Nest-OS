// supabase/functions/create-staff/index.ts
// Creates MANAGER or PUMP_PERSON with exact Prisma column names.
// User: id, station_id, role, full_name, username, employee_id,
//   phone_number, password_hash, active, created_by_id
// SalaryConfig: id, station_id, user_id (unique), base_monthly_salary,
//   effective_from, created_by_id — NO salary_type column.

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

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const {
      full_name,
      phone_number,
      role,
      password,
      station_id,
      employee_id,
      username,
      base_salary,
      created_by,
    } = await req.json()

    if (!full_name || !phone_number || !role || !password || !station_id) {
      return json(
        { error: 'full_name, phone_number, role, password, station_id required' },
        400,
      )
    }

    if (!['MANAGER', 'PUMP_PERSON'].includes(role)) {
      return json({ error: 'role must be MANAGER or PUMP_PERSON' }, 400)
    }

    const SUPABASE_URL = Deno.env.get('SUPABASE_URL')
    const FUELOS_SERVICE_ROLE_KEY = Deno.env.get('FUELOS_SERVICE_ROLE_KEY')
    const missingEnv: string[] = []
    if (!SUPABASE_URL) missingEnv.push('SUPABASE_URL')
    if (!FUELOS_SERVICE_ROLE_KEY) missingEnv.push('FUELOS_SERVICE_ROLE_KEY')
    if (missingEnv.length > 0) {
      console.error('create-staff: missing env vars:', missingEnv.join(', '))
      return json({ error: 'missing_env', missing: missingEnv }, 500)
    }

    const supabase = createClient(SUPABASE_URL!, FUELOS_SERVICE_ROLE_KEY!)

    // Check phone uniqueness within station
    // Prisma: @@unique([station_id, phone_number]) exists on User
    const { data: existing } = await supabase
      .from('User')
      .select('id')
      .eq('station_id', station_id)
      .eq('phone_number', String(phone_number).trim())
      .maybeSingle()

    if (existing) {
      return json(
        { error: 'A staff member with this phone number already exists' },
        409,
      )
    }

    // Validate employee_id uniqueness if provided
    // Prisma: @@unique([station_id, employee_id])
    if (employee_id) {
      const { data: empExists } = await supabase
        .from('User')
        .select('id')
        .eq('station_id', station_id)
        .eq('employee_id', String(employee_id).trim())
        .maybeSingle()

      if (empExists) {
        return json(
          { error: 'Employee ID already assigned to another staff member' },
          409,
        )
      }
    }

    const passwordHash = await hashPassword(String(password))
    const now = new Date().toISOString()
    const userId = crypto.randomUUID()

    // ── Create User row ───────────────────────────────────────────────────────
    const { data: newUser, error: userErr } = await supabase
      .from('User')
      .insert({
        id: userId,
        station_id,
        full_name: String(full_name).trim(),
        phone_number: String(phone_number).trim(),
        role,
        password_hash: passwordHash,
        username: username
          ? String(username).trim()
          : `${String(full_name).toLowerCase().slice(0, 4).replace(/\s/g, '')}@${userId.slice(0, 4)}`,
        employee_id: employee_id ? String(employee_id).trim() : null,
        active: true,
        created_by_id: created_by || null,
        created_at: now,
        updated_at: now,
      })
      .select('id, full_name, role, employee_id, username, phone_number')
      .single()

    if (userErr || !newUser) {
      return json({ error: 'Failed to create user: ' + userErr?.message }, 500)
    }

    // ── Create SalaryConfig if salary provided ────────────────────────────────
    // Prisma SalaryConfig: id, station_id, user_id (unique), base_monthly_salary,
    //   hourly_rate?, effective_from, created_by_id — NO salary_type column.
    if (base_salary && Number(base_salary) > 0) {
      await supabase.from('SalaryConfig').insert({
        station_id,
        user_id: userId,
        base_monthly_salary: Number(base_salary),
        effective_from: now,
        created_by_id: created_by || userId,
        created_at: now,
        updated_at: now,
      }).catch((e: Error) => {
        console.warn('SalaryConfig insert warning:', e.message)
      })
    }

    return json({ user: newUser }, 200)
  } catch (err) {
    console.error('create-staff error:', err)
    return json({ error: 'Internal server error' }, 500)
  }
})

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
