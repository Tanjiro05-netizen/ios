import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

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

function pemToArrayBuffer(pem: string) {
  const normalized = pem
    .replace(/\\n/g, '\n')
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s/g, '')
  const binary = atob(normalized)
  const bytes = new Uint8Array(binary.length)
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index)
  }
  return bytes.buffer
}

async function makeAppleClientSecret() {
  const teamId = Deno.env.get('APPLE_TEAM_ID')
  const keyId = Deno.env.get('APPLE_KEY_ID')
  const clientId = Deno.env.get('APPLE_CLIENT_ID') ?? 'com.marxist.forum'
  const privateKey = Deno.env.get('APPLE_PRIVATE_KEY')
  if (!teamId || !keyId || !privateKey) return null

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

async function revokeAppleAuthorizationCode(code: string | null) {
  if (!code) return { attempted: false, reason: 'No authorization code was supplied' }

  const clientSecret = await makeAppleClientSecret()
  const clientId = Deno.env.get('APPLE_CLIENT_ID') ?? 'com.marxist.forum'
  if (!clientSecret) {
    console.warn('[delete-account] Apple revocation skipped: Apple credentials are not configured')
    return { attempted: false, reason: 'Apple credentials are not configured' }
  }

  const body = new URLSearchParams({
    client_id: clientId,
    client_secret: clientSecret,
    token: code,
    token_type_hint: 'code',
  })
  const response = await fetch('https://appleid.apple.com/auth/revoke', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body,
  })
  if (!response.ok) {
    const message = await response.text()
    throw new Error(`Apple credential revocation failed (${response.status}): ${message}`)
  }
  return { attempted: true, reason: 'Apple authorization revoked' }
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

  const authorization = req.headers.get('Authorization')
  const accessToken = authorization?.replace(/^Bearer\s+/i, '').trim()
  if (!accessToken) return json({ error: 'Authorization is required' }, 401)

  try {
    const payload = await req.json().catch(() => ({})) as { appleAuthorizationCode?: string | null }
    const supabaseUrl = Deno.env.get('SUPABASE_URL')!
    const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!
    const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

    const userClient = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: `Bearer ${accessToken}` } },
    })
    const { data: { user }, error: userError } = await userClient.auth.getUser(accessToken)
    if (userError || !user) return json({ error: 'The session is invalid or expired' }, 401)

    // Revoke Apple before removing the user so that the provider identity is
    // still available if Apple rejects the request and the user needs to retry.
    const appleRevocation = await revokeAppleAuthorizationCode(payload.appleAuthorizationCode ?? null)
    const admin = createClient(supabaseUrl, serviceRoleKey)

    // Remove content and user-owned rows before deleting the profile/auth user.
    await deleteRows(admin, 'forum_comments', 'author_id', user.id)
    await deleteRows(admin, 'forum_threads', 'author_id', user.id)
    await deleteRows(admin, 'forum_notifications', 'user_id', user.id)
    await nullifyRows(admin, 'forum_notifications', 'source_user_id', user.id)
    await deleteRows(admin, 'social_notifications', 'user_id', user.id)
    await nullifyRows(admin, 'social_notifications', 'source_user_id', user.id)
    await deleteRows(admin, 'push_tokens', 'user_id', user.id)
    await deleteRows(admin, 'reading_progress', 'user_id', user.id)
    await deleteRows(admin, 'reading_quotes', 'user_id', user.id)

    // Preserve shared/public content while removing the account reference.
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

    // Avoid leaving a foreign-key reference from a redeemed invite code.
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
    console.error('[delete-account]', error)
    return json({ error: error instanceof Error ? error.message : 'Account deletion failed' }, 500)
  }
})
