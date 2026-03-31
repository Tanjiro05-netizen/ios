import React, { useState, useEffect, createContext, useContext, ReactNode } from 'react';
import { Session, User } from '@supabase/supabase-js';
import { supabase } from '../lib/supabase';
import { Profile } from '../types';
import api from '../lib/api';
import { guestStorage, GuestSession } from '../lib/storage';
import { generateGuestUsername, generateGuestId } from '../lib/guestUsername';

interface AuthContextType {
  user: User | null;
  profile: Profile | null;
  session: Session | null;
  loading: boolean;
  isGuest: boolean;
  guestSession: GuestSession | null;
  signIn: (email: string, password: string) => Promise<{ error: Error | null }>;
  signUp: (email: string, password: string, options?: { inviteCode?: string; username?: string; ideology?: string }) => Promise<{ error: Error | null }>;
  signOut: () => Promise<void>;
  refreshProfile: () => Promise<void>;
  browseAsGuest: () => Promise<void>;
  regenerateGuestUsername: () => Promise<string>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export function useAuthProvider() {
  const [user, setUser] = useState<User | null>(null);
  const [profile, setProfile] = useState<Profile | null>(null);
  const [session, setSession] = useState<Session | null>(null);
  const [loading, setLoading] = useState(true);
  const [isGuest, setIsGuest] = useState(false);
  const [guestSession, setGuestSession] = useState<GuestSession | null>(null);

  const fetchProfile = async (userId: string) => {
    const profileData = await api.getProfile(userId);
    setProfile(profileData);
  };

  // Create a guest profile object
  const createGuestProfile = (guest: GuestSession): Profile => ({
    id: guest.id,
    username: guest.username,
    avatar_url: null,
    website: null,
    updated_at: guest.createdAt,
    bio: 'Browsing as guest',
    ideology: null,
    banner_url: null,
    role: 'guest',
    is_certified: false,
    is_admin: false,
    has_invite_access: false,
    invite_code_used: null,
  });

  useEffect(() => {
    const initAuth = async () => {
      // First check for existing guest session
      const existingGuest = await guestStorage.get();
      if (existingGuest) {
        setIsGuest(true);
        setGuestSession(existingGuest);
        setProfile(createGuestProfile(existingGuest));
        setLoading(false);
        return;
      }

      // Get Supabase session
      const { data: { session } } = await supabase.auth.getSession();
      setSession(session);
      setUser(session?.user ?? null);
      if (session?.user) {
        await fetchProfile(session.user.id);
      }
      setLoading(false);
    };

    initAuth();

    // Listen for auth changes
    const { data: { subscription } } = supabase.auth.onAuthStateChange(
      async (event, session) => {
        // If user logs in, clear guest session
        if (session?.user) {
          setIsGuest(false);
          setGuestSession(null);
          await guestStorage.clear();
        }

        setSession(session);
        setUser(session?.user ?? null);
        if (session?.user) {
          await fetchProfile(session.user.id);
        } else if (!isGuest) {
          setProfile(null);
        }
        setLoading(false);
      }
    );

    return () => subscription.unsubscribe();
  }, []);

  const signIn = async (email: string, password: string) => {
    const { error } = await supabase.auth.signInWithPassword({ email, password });
    return { error: error as Error | null };
  };

  const signUp = async (email: string, password: string, options?: { inviteCode?: string; username?: string; ideology?: string }) => {
    const { error } = await supabase.auth.signUp({
      email,
      password,
      options: {
        data: {
          invite_code: options?.inviteCode,
          user_name: options?.username,
          ideology: options?.ideology,
        },
      },
    });
    return { error: error as Error | null };
  };

  const signOut = async () => {
    // Clear guest session if exists
    if (isGuest) {
      await guestStorage.clear();
      setIsGuest(false);
      setGuestSession(null);
    }

    await supabase.auth.signOut();
    setUser(null);
    setProfile(null);
    setSession(null);
  };

  const refreshProfile = async () => {
    if (user) {
      await fetchProfile(user.id);
    } else if (isGuest && guestSession) {
      setProfile(createGuestProfile(guestSession));
    }
  };

  // Browse as guest - creates a temporary session with random username
  const browseAsGuest = async () => {
    const newGuestSession: GuestSession = {
      id: generateGuestId(),
      username: generateGuestUsername(),
      createdAt: new Date().toISOString(),
    };

    await guestStorage.save(newGuestSession);
    setIsGuest(true);
    setGuestSession(newGuestSession);
    setProfile(createGuestProfile(newGuestSession));
  };

  // Regenerate guest username (useful if user doesn't like their random name)
  const regenerateGuestUsername = async (): Promise<string> => {
    if (!guestSession) {
      throw new Error('No guest session active');
    }

    const newUsername = generateGuestUsername();
    const updatedSession: GuestSession = {
      ...guestSession,
      username: newUsername,
    };

    await guestStorage.save(updatedSession);
    setGuestSession(updatedSession);
    setProfile(createGuestProfile(updatedSession));

    return newUsername;
  };

  return {
    user,
    profile,
    session,
    loading,
    isGuest,
    guestSession,
    signIn,
    signUp,
    signOut,
    refreshProfile,
    browseAsGuest,
    regenerateGuestUsername,
  };
}

export function AuthProvider({ children }: { children: ReactNode }) {
  const auth = useAuthProvider();
  return <AuthContext.Provider value={auth}>{children}</AuthContext.Provider>;
}

export function useAuth() {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
}
