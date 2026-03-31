import { serve } from 'https://deno.land/std@0.168.0/http/server.ts';
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const EXPO_PUSH_URL = 'https://exp.host/--/api/v2/push/send';

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

    if (error || !profile?.push_token) {
      return new Response(JSON.stringify({ skipped: 'No push token' }), { status: 200 });
    }

    const notifType = record.type || 'notification';
    const titles: Record<string, string> = {
      like: 'New Like',
      comment: 'New Comment',
      repost: 'Reposted',
      follow: 'New Follower',
      mention: 'You were mentioned',
      reply: 'New Reply',
    };

    const message = {
      to: profile.push_token,
      sound: 'default',
      title: titles[notifType] || 'New Notification',
      body: record.content_preview || 'You have a new notification.',
      data: {
        type: notifType,
        thread_id: record.thread_id,
        comment_id: record.comment_id,
        source_user_id: record.source_user_id,
      },
    };

    const response = await fetch(EXPO_PUSH_URL, {
      method: 'POST',
      headers: {
        'Accept': 'application/json',
        'Accept-Encoding': 'gzip, deflate',
        'Content-Type': 'application/json',
      },
      body: JSON.stringify(message),
    });

    const result = await response.json();
    return new Response(JSON.stringify(result), { status: 200 });
  } catch (err) {
    return new Response(JSON.stringify({ error: String(err) }), { status: 500 });
  }
});
