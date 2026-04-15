// supabase/functions/set-user-pin/index.ts
// Hashes a PIN and saves it to the User table.
// Called from StaffManagementScreen when setting a PIN for a staff member.

import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import * as bcrypt from 'https://deno.land/x/bcrypt@v0.4.1/mod.ts'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
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

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    const pinHash = await bcrypt.hash(pin)

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
