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

async function encryptionKey() {
  const encodedKey = Deno.env.get('APPLE_TOKEN_ENCRYPTION_KEY')
  if (!encodedKey) throw new Error('APPLE_TOKEN_ENCRYPTION_KEY is not configured')
  const keyBytes = decodeBase64(encodedKey)
  if (keyBytes.byteLength !== 32) {
    throw new Error('APPLE_TOKEN_ENCRYPTION_KEY must contain exactly 32 bytes')
  }
  return crypto.subtle.importKey('raw', keyBytes, 'AES-GCM', false, ['decrypt'])
}

async function decryptRefreshToken(ciphertext: string, iv: string) {
  const plaintext = await crypto.subtle.decrypt(
    { name: 'AES-GCM', iv: decodeBase64(iv) },
    await encryptionKey(),
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
  if (!response.ok) {
    const message = await response.text()
    throw new Error(`Apple credential revocation failed (${response.status}): ${message}`)
  }
}

async function formerUserHash(userId: string) {
  const salt = Deno.env.get('APPLE_TOKEN_ENCRYPTION_KEY') ?? ''
  const digest = await crypto.subtle.digest('SHA-256', new TextEncoder().encode(`${userId}:${salt}`))
  return base64Url(digest)
}

async function deleteRows(admin: ReturnType<typeof createClient>, table: string, column: string, value: string) {
  const { error } = await admin.from(table).delete().eq(column, value)
  if (error) throw new Error(`Deleting ${table} failed: ${error.message}`)
}

async function nullifyRows(admin: ReturnType<typeof createClient>, table: string, column: string, value: string) {
  const { error } = await admin.from(table).update({ [column]: null }).eq(column, value)
  if (error) throw new Error(`Anonymizing ${table}.${column} failed: ${error.message}`)
}

serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: corsHeaders })
  if (req.method !== 'POST') return json({ error: 'Method not allowed' }, 405)

  const accessToken = req.headers.get('Authorization')?.replace(/^Bearer\s+/i, '').trim()
  if (!accessToken) return json({ error: 'Authorization is required' }, 401)

  try {
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${accessToken}` } },
    })
    const { data: { user }, error: userError } = await userClient.auth.getUser(accessToken)
    if (userError || !user) return json({ error: 'The session is invalid or expired' }, 401)

    const admin = createClient(supabaseUrl, serviceRoleKey)
    const { data: credential, error: credentialError } = await admin
      .from('apple_refresh_tokens')
      .select('encrypted_refresh_token, encryption_iv')
      .eq('user_id', user.id)
      .maybeSingle()
    if (credentialError) {
      console.error('[delete-account] Reading Apple credential failed:', credentialError.message)
    }

    let appleRevocation: Record<string, unknown> = { attempted: false, queued: false }
    if (credential) {
      try {
        const refreshToken = await decryptRefreshToken(
          credential.encrypted_refresh_token,
          credential.encryption_iv,
        )
        await revokeAppleRefreshToken(refreshToken)
        appleRevocation = { attempted: true, queued: false }
      } catch (error) {
        const message = error instanceof Error ? error.message : 'Apple revocation failed'
        appleRevocation = { attempted: true, queued: true }
        const { error: queueError } = await admin.from('apple_revocation_queue').insert({
          former_user_hash: await formerUserHash(user.id),
          encrypted_refresh_token: credential.encrypted_refresh_token,
          encryption_iv: credential.encryption_iv,
          last_error: message.slice(0, 2_000),
        })
        if (queueError) {
          console.error('[delete-account] Unable to queue Apple revocation retry:', queueError.message)
          appleRevocation = { attempted: true, queued: false, requiresManualReview: true }
        }
        console.error('[delete-account] Apple revocation deferred:', message)
      }
    }

    await deleteRows(admin, 'forum_comments', 'author_id', user.id)
    await deleteRows(admin, 'forum_threads', 'author_id', user.id)
    await deleteRows(admin, 'forum_notifications', 'user_id', user.id)
    await nullifyRows(admin, 'forum_notifications', 'source_user_id', user.id)
    await deleteRows(admin, 'social_notifications', 'user_id', user.id)
    await nullifyRows(admin, 'social_notifications', 'source_user_id', user.id)
    await deleteRows(admin, 'push_tokens', 'user_id', user.id)
    await deleteRows(admin, 'reading_progress', 'user_id', user.id)
    await deleteRows(admin, 'reading_quotes', 'user_id', user.id)

    await deleteRows(admin, 'article_submissions', 'user_id', user.id)
    await nullifyRows(admin, 'analysis_cross_references', 'created_by', user.id)
    await nullifyRows(admin, 'analysis_text_collaborators', 'invited_by', user.id)
    await nullifyRows(admin, 'analysis_texts', 'uploaded_by', user.id)
    await nullifyRows(admin, 'audiobooks', 'created_by', user.id)
    await nullifyRows(admin, 'knowledge_cells', 'created_by', user.id)
    await nullifyRows(admin, 'politics_articles', 'author_id', user.id)
    await nullifyRows(admin, 'politics_articles', 'created_by', user.id)
    await nullifyRows(admin, 'politics_articles', 'updated_by', user.id)
    await nullifyRows(admin, 'study_concepts', 'created_by', user.id)
    await nullifyRows(admin, 'study_resources', 'created_by', user.id)
    await nullifyRows(admin, 'knowledge_answers', 'approved_by', user.id)
    await nullifyRows(admin, 'knowledge_questions', 'approved_by', user.id)

    await admin.from('invite_codes').update({ used_by: null }).eq('used_by', user.id)

    const { data: objects, error: objectError } = await admin
      .schema('storage')
      .from('objects')
      .select('bucket_id, name')
      .eq('owner_id', user.id)
    if (objectError) throw new Error(`Finding user files failed: ${objectError.message}`)

    const objectsByBucket = new Map<string, string[]>()
    for (const object of objects ?? []) {
      const paths = objectsByBucket.get(object.bucket_id) ?? []
      paths.push(object.name)
      objectsByBucket.set(object.bucket_id, paths)
    }
    for (const [bucket, paths] of objectsByBucket) {
      const { error } = await admin.storage.from(bucket).remove(paths)
      if (error) throw new Error(`Deleting files from ${bucket} failed: ${error.message}`)
    }

    const { error: profileError } = await admin.from('profiles').delete().eq('id', user.id)
    if (profileError) throw new Error(`Deleting profile failed: ${profileError.message}`)

    const { error: authError } = await admin.auth.admin.deleteUser(user.id)
    if (authError) throw new Error(`Deleting auth user failed: ${authError.message}`)

    return json({ deleted: true, appleRevocation })
  } catch (error) {
    console.error('[delete-account]', error instanceof Error ? error.message : error)
    return json({ error: error instanceof Error ? error.message : 'Account deletion failed' }, 500)
  }
})
