import { createClient, SupabaseClient } from '@supabase/supabase-js';
import AsyncStorage from '@react-native-async-storage/async-storage';

// Replace these with your actual Supabase credentials
// Get them from: https://supabase.com/dashboard → Your Project → Settings → API
const SUPABASE_URL = 'https://yghsprwrzgfegvfbjmkq.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlnaHNwcndyemdmZWd2ZmJqbWtxIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTEyNzc0MTMsImV4cCI6MjA2Njg1MzQxM30.a_jILFYVfP-Z7DVkskrOM9O4Z44qJ20d5tYXwQH09jc';

// Check if Supabase is configured
const isConfigured = SUPABASE_URL.startsWith('https://') && SUPABASE_ANON_KEY.length > 20;

// Create a mock client for development when Supabase isn't configured
const createMockClient = (): SupabaseClient => {
  console.warn(
    '⚠️ Supabase not configured! The app will run with mock data.\n' +
    'To enable real data, update src/lib/supabase.ts with your credentials.'
  );

  // Use a valid-looking Supabase URL format to pass validation
  // The client will fail API calls but won't crash the app on startup
  return createClient(
    'https://xxxxxxxxxxxxx.supabase.co',
    'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBsYWNlaG9sZGVyIiwicm9sZSI6ImFub24iLCJpYXQiOjE2MDAwMDAwMDAsImV4cCI6MTkwMDAwMDAwMH0.placeholder',
    {
      auth: {
        storage: AsyncStorage,
        autoRefreshToken: false,
        persistSession: false,
        detectSessionInUrl: false,
      },
    }
  );
};

export const supabase = isConfigured
  ? createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
    auth: {
      storage: AsyncStorage,
      autoRefreshToken: true,
      persistSession: true,
      detectSessionInUrl: false,
    },
  })
  : createMockClient();

export const isSupabaseConfigured = isConfigured;
