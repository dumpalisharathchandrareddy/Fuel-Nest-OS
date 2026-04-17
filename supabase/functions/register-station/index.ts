// supabase/functions/register-station/index.ts
// Deploy target: CENTRAL REGISTRY project (manuhbjwasbpbuggkhgq)
//   supabase functions deploy register-station --project-ref manuhbjwasbpbuggkhgq
// JWT verification is disabled (no-verify-jwt) so the anon Flutter client can call
// this without a logged-in user session. Protection comes from server-side field
// validation and the service role key never leaving this function.
import { serve } from 'https://deno.land/std@0.177.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const SUPABASE_URL = Deno.env.get('SUPABASE_URL')
  const FUELOS_SERVICE_ROLE_KEY = Deno.env.get('FUELOS_SERVICE_ROLE_KEY')

  const missingEnv: string[] = []
  if (!SUPABASE_URL) missingEnv.push('SUPABASE_URL')
  if (!FUELOS_SERVICE_ROLE_KEY) missingEnv.push('FUELOS_SERVICE_ROLE_KEY')
  if (missingEnv.length > 0) {
    console.error('register-station: missing env vars:', missingEnv.join(', '))
    return json({ error: 'missing_env', missing: missingEnv }, 500)
  }

  let body: Record<string, unknown>
  try {
    body = await req.json()
  } catch {
    return json({ error: 'invalid_json' }, 400)
  }

  const { station_code, station_name, supabase_url, anon_key } = body as {
    station_code?: string
    station_name?: string
    supabase_url?: string
    anon_key?: string
  }

  const missing: string[] = []
  if (!station_code) missing.push('station_code')
  if (!station_name) missing.push('station_name')
  if (!supabase_url) missing.push('supabase_url')
  if (!anon_key) missing.push('anon_key')
  if (missing.length > 0) {
    return json({ error: 'missing_fields', missing }, 400)
  }

  const cleanCode = String(station_code).trim().toUpperCase()
  const supabase = createClient(SUPABASE_URL!, FUELOS_SERVICE_ROLE_KEY!)

  const { error } = await supabase.from('station_registry').upsert({
    station_code: cleanCode,
    station_name: String(station_name).trim(),
    supabase_url: String(supabase_url).trim(),
    anon_key: String(anon_key).trim(),
    active: true,
    registered_at: new Date().toISOString(),
  })

  if (error) {
    console.error('register-station: upsert error:', error.message)
    return json({ error: 'registry_write_failed', detail: error.message }, 500)
  }

  return json({ success: true, station_code: cleanCode })
})
