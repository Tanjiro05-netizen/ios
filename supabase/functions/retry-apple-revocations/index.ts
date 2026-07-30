import { serve } from 'https://deno.land/std@0.224.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2.49.4'

const json = (body: Record<string, unknown>, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
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
  return decodeBase64(
    pem
      .replace(/\\n/g, '\n')
      .replace(/-----BEGIN PRIVATE KEY-----/g, '')
      .replace(/-----END PRIVATE KEY-----/g, '')
      .replace(/\s/g, ''),
  ).buffer
}

async function makeAppleClientSecret() {
  const teamId = Deno.env.get('APPLE_TEAM_ID')
  const keyId = Deno.env.get('APPLE_KEY_ID')
  const clientId = Deno.env.get('APPLE_CLIENT_ID') ?? 'com.marxist.forum'
  const privateKey = Deno.env.get('APPLE_PRIVATE_KEY')
  if (!teamId || !keyId || !privateKey) throw new Error('Apple lifecycle credentials are not configured')

  const now = Math.floor(Date.now() / 1_000)
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

async function decryptRefreshToken(ciphertext: string, iv: string) {
  const encodedKey = Deno.env.get('APPLE_TOKEN_ENCRYPTION_KEY')
  if (!encodedKey) throw new Error('APPLE_TOKEN_ENCRYPTION_KEY is not configured')
  const keyBytes = decodeBase64(encodedKey)
  if (keyBytes.byteLength !== 32) throw new Error('APPLE_TOKEN_ENCRYPTION_KEY must contain 32 bytes')
  const key = await crypto.subtle.importKey('raw', keyBytes, 'AES-GCM', false, ['decrypt'])
  const plaintext = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv: decodeBase64(iv) },
    key,
    decodeBase64(ciphertext),
  )
  return new TextDecoder().decode(plaintext)
}

async function revokeAppleRefreshToken(refreshToken: string) {
  const response = await fetch('https://appleid.apple.com/auth/revoke', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      client_id: Deno.env.get('APPLE_CLIENT_ID') ?? 'com.marxist.forum',
      client_secret: await makeAppleClientSecret(),
      token: refreshToken,
      token_type_hint: 'refresh_token',
    }),
  })
  if (!response.ok) throw new Error(`Apple returned HTTP ${response.status}`)
}

function secretsMatch(received: string | null, expected: string) {
  if (!received || received.length !== expected.length) return false
  let difference = 0
  for (let index = 0; index < expected.length; index += 1) {
    difference |= received.charCodeAt(index) ^ expected.charCodeAt(index)
  }
  return difference === 0
}

serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)
  const retrySecret = Deno.env.get('APPLE_REVOCATION_RETRY_SECRET')
  if (!retrySecret || !secretsMatch(req.headers.get('x-revocation-secret'), retrySecret)) {
    return json({ error: 'Unauthorized' }, 401)
  }

  try {
    const admin = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )
    const now = new Date().toISOString()
    const { data: records, error } = await admin
      .from('apple_revocation_queue')
      .select('id, encrypted_refresh_token, encryption_iv, attempt_count')
      .lte('next_attempt_at', now)
      .order('next_attempt_at', { ascending: true })
      .limit(25)
    if (error) throw new Error(`Loading revocation queue failed: ${error.message}`)

    let revoked = 0
    let deferred = 0
    for (const record of records ?? []) {
      try {
        const token = await decryptRefreshToken(record.encrypted_refresh_token, record.encryption_iv)
        await revokeAppleRefreshToken(token)
        const { error: deleteError } = await admin
          .from('apple_revocation_queue')
          .delete()
          .eq('id', record.id)
        if (deleteError) throw new Error(`Deleting completed retry failed: ${deleteError.message}`)
        revoked += 1
      } catch (recordError) {
        const attemptCount = record.attempt_count + 1
        const delayMinutes = Math.min(24 * 60, 2 ** Math.min(attemptCount, 10))
        const nextAttemptAt = new Date(Date.now() + delayMinutes * 60_000).toISOString()
        const message = recordError instanceof Error ? recordError.message : 'Revocation retry failed'
        const { error: updateError } = await admin
          .from('apple_revocation_queue')
          .update({
            attempt_count: attemptCount,
            last_error: message.slice(0, 2_000),
            next_attempt_at: nextAttemptAt,
            updated_at: now,
          })
          .eq('id', record.id)
        if (updateError) console.error('[retry-apple-revocations] Queue update failed:', updateError.message)
        deferred += 1
      }
    }
    return json({ processed: (records ?? []).length, revoked, deferred })
  } catch (error) {
    console.error('[retry-apple-revocations]', error instanceof Error ? error.message : error)
    return json({ error: 'Revocation retry failed' }, 500)
  }
})
