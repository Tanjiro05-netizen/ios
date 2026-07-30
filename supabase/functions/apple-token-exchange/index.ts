import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.4'

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })

function base64Url(input: ArrayBuffer | string) {
  const bytes = typeof input === 'string'
    ? new TextEncoder().encode(input)
    : new Uint8Array(input)
  let binary = ''
  for (const byte of bytes) binary += String.fromCharCode(byte)
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '')
}

function decodeBase64(value: string) {
  const normalized = value.replace(/-/g, '+').replace(/_/g, '/')
  const padded = normalized.padEnd(Math.ceil(normalized.length / 4) * 4, '=')
  const binary = atob(padded)
  return Uint8Array.from(binary, (character) => character.charCodeAt(0))
}

function pemToArrayBuffer(pem: string) {
  const normalized = pem
    .replace(/\\n/g, '\n')
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s/g, '')
  return decodeBase64(normalized).buffer
}

async function makeAppleClientSecret() {
  const teamId = Deno.env.get('APPLE_TEAM_ID')
  const keyId = Deno.env.get('APPLE_KEY_ID')
  const clientId = Deno.env.get('APPLE_CLIENT_ID') ?? 'com.marxist.forum'
  const privateKey = Deno.env.get('APPLE_PRIVATE_KEY')
  if (!teamId || !keyId || !privateKey) {
    throw new Error('Apple account lifecycle credentials are not configured')
  }

  const now = Math.floor(Date.now() / 1000)
  const header = base64Url(JSON.stringify({ alg: 'ES256', kid: keyId }))
  const payload = base64Url(JSON.stringify({
    iss: teamId,
    iat: now,
    exp: now + 60 * 60 * 24 * 180,
    aud: 'https://appleid.apple.com',
    sub: clientId,
  }))
  const signingInput = `${header}.${payload}`
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(privateKey),
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign'],
  )
  const signature = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    key,
    new TextEncoder().encode(signingInput),
  )
  return `${signingInput}.${base64Url(signature)}`
}

async function encryptRefreshToken(refreshToken: string) {
  const encodedKey = Deno.env.get('APPLE_TOKEN_ENCRYPTION_KEY')
  if (!encodedKey) throw new Error('APPLE_TOKEN_ENCRYPTION_KEY is not configured')
  const keyBytes = decodeBase64(encodedKey)
  if (keyBytes.byteLength !== 32) {
    throw new Error('APPLE_TOKEN_ENCRYPTION_KEY must contain exactly 32 bytes')
  }
  const key = await crypto.subtle.importKey('raw', keyBytes, 'AES-GCM', false, ['encrypt'])
  const iv = crypto.getRandomValues(new Uint8Array(12))
  const ciphertext = await crypto.subtle.encrypt(
    { name: 'AES-GCM', iv },
    key,
    new TextEncoder().encode(refreshToken),
  )
  return {
    encryptedRefreshToken: base64Url(ciphertext),
    encryptionIV: base64Url(iv.buffer),
  }
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

  const accessToken = req.headers.get('Authorization')?.replace(/^Bearer\s+/i, '').trim()
  if (!accessToken) return json({ error: 'Authorization is required' }, 401)

  try {
    const body = await req.json() as { authorizationCode?: string }
    const authorizationCode = body.authorizationCode?.trim()
    if (!authorizationCode) return json({ error: 'Apple authorization code is required' }, 400)

    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${accessToken}` } },
    })
    const { data: { user }, error: userError } = await userClient.auth.getUser(accessToken)
    if (userError || !user) return json({ error: 'The session is invalid or expired' }, 401)

    const providers = user.app_metadata?.providers as string[] | undefined
    if (user.app_metadata?.provider !== 'apple' && !providers?.includes('apple')) {
      return json({ error: 'This account is not linked to Sign in with Apple' }, 403)
    }

    const clientId = Deno.env.get('APPLE_CLIENT_ID') ?? 'com.marxist.forum'
    const tokenResponse = await fetch('https://appleid.apple.com/auth/token', {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body: new URLSearchParams({
        client_id: clientId,
        client_secret: await makeAppleClientSecret(),
        code: authorizationCode,
        grant_type: 'authorization_code',
      }),
    })
    const tokenPayload = await tokenResponse.json().catch(() => ({})) as {
      refresh_token?: string
      error?: string
      error_description?: string
    }
    if (!tokenResponse.ok || !tokenPayload.refresh_token) {
      const reason = tokenPayload.error_description ?? tokenPayload.error ?? `HTTP ${tokenResponse.status}`
      throw new Error(`Apple authorization exchange failed: ${reason}`)
    }

    const encrypted = await encryptRefreshToken(tokenPayload.refresh_token)
    const admin = createClient(supabaseUrl, serviceRoleKey)
    const { error: storageError } = await admin.from('apple_refresh_tokens').upsert({
      user_id: user.id,
      encrypted_refresh_token: encrypted.encryptedRefreshToken,
      encryption_iv: encrypted.encryptionIV,
      updated_at: new Date().toISOString(),
    }, { onConflict: 'user_id' })
    if (storageError) throw new Error(`Saving Apple revocation credential failed: ${storageError.message}`)

    return json({})
  } catch (error) {
    console.error('[apple-token-exchange]', error instanceof Error ? error.message : error)
    return json({ error: error instanceof Error ? error.message : 'Apple authorization exchange failed' }, 500)
  }
})
