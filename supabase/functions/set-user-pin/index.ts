// supabase/functions/set-user-pin/index.ts
// Hashes a PIN and saves it to the User table.
// Called from StaffManagementScreen when setting a PIN for a staff member.

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
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
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })

  try {
    const { user_id, pin } = await req.json()

    if (!user_id || !pin) {
      return json({ error: 'user_id and pin required' }, 400)
    }

    if (!/^\d{4,6}$/.test(pin)) {
      return json({ error: 'PIN must be 4–6 digits' }, 400)
    }

    const SUPABASE_URL = Deno.env.get('SUPABASE_URL')
    const FUELOS_SERVICE_ROLE_KEY = Deno.env.get('FUELOS_SERVICE_ROLE_KEY')
    const missingEnv: string[] = []
    if (!SUPABASE_URL) missingEnv.push('SUPABASE_URL')
    if (!FUELOS_SERVICE_ROLE_KEY) missingEnv.push('FUELOS_SERVICE_ROLE_KEY')
    if (missingEnv.length > 0) {
      console.error('set-user-pin: missing env vars:', missingEnv.join(', '))
      return json({ error: 'missing_env', missing: missingEnv }, 500)
    }

    const supabase = createClient(SUPABASE_URL!, FUELOS_SERVICE_ROLE_KEY!)

    const pinHash = await hashPassword(pin)

    const { error } = await supabase.from('User').update({
      pin_hash: pinHash,
      updated_at: new Date().toISOString(),
    }).eq('id', user_id)

    if (error) return json({ error: error.message }, 500)

    return json({ success: true })
  } catch (err) {
    console.error('set-user-pin error:', err)
    return json({ error: 'Internal server error' }, 500)
  }
})

function json(data: unknown, status = 200) {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
