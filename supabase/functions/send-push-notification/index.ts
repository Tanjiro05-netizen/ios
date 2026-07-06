import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const EXPO_PUSH_URL = 'https://exp.host/--/api/v2/push/send';
const IOS_BUNDLE_ID = Deno.env.get('APNS_BUNDLE_ID') ?? 'com.marxist.forum';
const APNS_HOST = Deno.env.get('APNS_USE_SANDBOX') === 'true'
  ? 'https://api.sandbox.push.apple.com'
  : 'https://api.push.apple.com';

function base64Url(input: ArrayBuffer | string) {
  const bytes = typeof input === 'string'
    ? new TextEncoder().encode(input)
    : new Uint8Array(input);
  let binary = '';
  for (const byte of bytes) binary += String.fromCharCode(byte);
  return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function pemToArrayBuffer(pem: string) {
  const normalized = pem
    .replace(/\\n/g, '\n')
    .replace(/-----BEGIN PRIVATE KEY-----/g, '')
    .replace(/-----END PRIVATE KEY-----/g, '')
    .replace(/\s/g, '');
  const binary = atob(normalized);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes.buffer;
}

async function makeApnsJwt() {
  const teamId = Deno.env.get('APNS_TEAM_ID');
  const keyId = Deno.env.get('APNS_KEY_ID');
  const privateKey = Deno.env.get('APNS_PRIVATE_KEY');
  if (!teamId || !keyId || !privateKey) return null;

  const header = base64Url(JSON.stringify({ alg: 'ES256', kid: keyId }));
  const payload = base64Url(JSON.stringify({ iss: teamId, iat: Math.floor(Date.now() / 1000) }));
  const signingInput = `${header}.${payload}`;
  const key = await crypto.subtle.importKey(
    'pkcs8',
    pemToArrayBuffer(privateKey),
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign'],
  );
  const signature = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    key,
    new TextEncoder().encode(signingInput),
  );
  return `${signingInput}.${base64Url(signature)}`;
}

async function sendExpoPush(token: string, message: Record<string, unknown>) {
  const response = await fetch(EXPO_PUSH_URL, {
    method: 'POST',
    headers: {
      'Accept': 'application/json',
      'Accept-Encoding': 'gzip, deflate',
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ to: token, ...message }),
  });
  return response.json();
}

async function sendApnsPush(token: string, message: Record<string, unknown>) {
  const jwt = await makeApnsJwt();
  if (!jwt) {
    return { skipped: 'APNs credentials not configured' };
  }

  const body = {
    aps: {
      alert: {
        title: message.title,
        body: message.body,
      },
      sound: 'default',
      badge: 1,
      category: message.category,
    },
    data: message.data,
  };

  const response = await fetch(`${APNS_HOST}/3/device/${token}`, {
    method: 'POST',
    headers: {
      authorization: `bearer ${jwt}`,
      'apns-topic': IOS_BUNDLE_ID,
      'apns-push-type': 'alert',
      'apns-priority': '10',
      'content-type': 'application/json',
    },
    body: JSON.stringify(body),
  });

  const text = await response.text();
  return {
    provider: 'apns',
    status: response.status,
    body: text ? JSON.parse(text) : null,
  };
}

function categoryForNotification(type: string) {
  if (type === 'article' || type === 'substack') return 'NEW_ARTICLE';
  if (type === 'continue_reading') return 'CONTINUE_READING';
  if (type === 'follow') return 'FOLLOWED_USER_ACTIVITY';
  return 'THREAD_ACTIVITY';
}

function deepLinkForRecord(record: Record<string, unknown>) {
  if (typeof record.thread_id === 'string' && record.thread_id.length > 0) {
    return `marxistforum://thread/${record.thread_id}`;
  }
  if (typeof record.article_slug === 'string' && record.article_slug.length > 0) {
    return `marxistforum://substack/${record.article_slug}`;
  }
  if (typeof record.book_id === 'string' && record.book_id.length > 0) {
    return `marxistforum://book/${record.book_id}`;
  }
  if (typeof record.audiobook_id === 'string' && record.audiobook_id.length > 0) {
    return `marxistforum://audiobook/${record.audiobook_id}`;
  }
  return 'marxistforum://notifications';
}

serve(async (req) => {
  try {
    const payload = await req.json();
    const record = payload.record;

    if (!record || !record.user_id) {
      return new Response(JSON.stringify({ error: 'No record provided' }), { status: 400 });
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
    );

    const { data: profile, error } = await supabase
      .from('profiles')
      .select('push_token')
      .eq('id', record.user_id)
      .single();

    const { data: tokens, error: tokenError } = await supabase
      .from('push_tokens')
      .select('provider, token')
      .eq('user_id', record.user_id)
      .eq('enabled', true);

    const notifType = record.type || 'notification';
    const category = categoryForNotification(notifType);
    const deepLink = deepLinkForRecord(record);
    const titles: Record<string, string> = {
      like: 'New Like',
      comment: 'New Comment',
      repost: 'Reposted',
      follow: 'New Follower',
      mention: 'You were mentioned',
      reply: 'New Reply',
    };

    const message: Record<string, unknown> = {
      sound: 'default',
      title: titles[notifType] || 'New Notification',
      body: record.content_preview || 'You have a new notification.',
      category,
      data: {
        type: notifType,
        thread_id: record.thread_id,
        comment_id: record.comment_id,
        source_user_id: record.source_user_id,
        article_slug: record.article_slug,
        book_id: record.book_id,
        audiobook_id: record.audiobook_id,
        deep_link: deepLink,
      },
    };

    const deliveries: Promise<unknown>[] = [];

    if (!error && profile?.push_token) {
      deliveries.push(sendExpoPush(profile.push_token, message));
    }

    if (!tokenError && Array.isArray(tokens)) {
      for (const token of tokens) {
        if (token.provider === 'expo') {
          deliveries.push(sendExpoPush(token.token, message));
        }
        if (token.provider === 'apns') {
          deliveries.push(sendApnsPush(token.token, message));
        }
      }
    }

    if (deliveries.length === 0) {
      return new Response(JSON.stringify({ skipped: 'No push token' }), { status: 200 });
    }

    const result = await Promise.all(deliveries);
    return new Response(JSON.stringify({ delivered: result }), { status: 200 });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), { status: 500 });
  }
});
