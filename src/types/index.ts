import { NavigatorScreenParams } from '@react-navigation/native';

// Database types based on your Supabase schema

export interface Profile {
  id: string;
  username: string | null;
  avatar_url: string | null;
  website: string | null;
  updated_at: string | null;
  bio: string | null;
  ideology: string | null;
  banner_url: string | null;
  role: string;
  is_certified: boolean | null;
  is_admin: boolean | null;
  has_invite_access: boolean | null;
  invite_code_used: string | null;
}

export interface Thread {
  id: string;
  title: string;
  content: string;
  category_slug: string;
  author_id: string | null; // null for anonymous/guest posts
  created_at: string;
  updated_at: string | null;
  comment_count: number | null;
  like_count: number | null;
  view_count: number | null;
  repost_count: number | null; // Number of times this thread was reposted
  is_pinned: boolean | null;
  is_locked: boolean | null;
  anonymous_name: string | null; // Guest username like "BraveLion42"
  quoted_thread_id: string | null; // If this is a quote repost, the original thread ID
  // Joined data
  author?: Profile;
  quoted_thread?: Thread; // The embedded original thread for quote reposts
  // Display metadata (set by feed queries)
  reposted_by?: Profile; // Who reposted this (for feed display)
  repost_created_at?: string; // When it was reposted (for feed ordering)
}

export interface Comment {
  id: string;
  thread_id: string;
  content: string;
  author_id: string | null; // null for anonymous/guest posts
  parent_id: string | null;
  created_at: string;
  updated_at: string | null;
  like_count: number | null;
  is_deleted: boolean | null;
  anonymous_name: string | null; // Guest username like "BraveLion42"
  // Joined data
  author?: Profile;
}

export interface Like {
  id: string;
  user_id: string;
  target_type: 'thread' | 'comment';
  target_id: string;
  created_at: string;
}

export interface Bookmark {
  id: string;
  user_id: string;
  thread_id: string;
  created_at: string;
  // Joined data
  thread?: Thread;
}

export interface Repost {
  id: string;
  user_id: string;
  thread_id: string;
  quote_thread_id: string | null; // If user created a quote post, this links to it
  created_at: string;
  // Joined data
  thread?: Thread; // The original thread that was reposted
  user?: Profile; // Who reposted
}

export interface UserStats {
  threadCount: number;
  commentCount: number;
  likesReceived: number;
  repostCount: number;
}

export interface Notification {
  id: string;
  user_id: string;
  type: string;
  source_user_id: string | null;
  thread_id: string | null;
  comment_id: string | null;
  content_preview: string | null;
  is_read: boolean | null;
  created_at: string;
  // Joined data
  source_user?: Profile;
}

// Board/Category type
export interface Board {
  slug: string;
  name: string;
  fullName: string;
  description: string;
  icon: string;
}

// Pagination response
export interface PaginatedResponse<T> {
  data: T[];
  page: number;
  totalPages: number;
  total: number;
}

// Navigation param types
export type RootStackParamList = {
  Main: NavigatorScreenParams<MainTabParamList> | undefined;
  Login: undefined;
  SignUp: undefined;
  Settings: undefined;
  BookReader: { bookId: string };
  UserProfile: { userId: string };
  ThreadDetail: { threadId: string };
  CreateThread: { boardSlug?: string };
  ChangePassword: undefined;
  EmailPreferences: undefined;
  Legal: { type: 'terms' | 'privacy' | 'guidelines' };
};

export type MainTabParamList = {
  Library: undefined;
  Audiobooks: undefined;
  Forum: undefined;
  Notifications: undefined;
  Profile: undefined;
};

// ============================================
// AUDIOBOOKS TYPES
// ============================================

export interface AudiobookChapter {
  title: string;
  start_seconds: number;
}

export interface Audiobook {
  id: string;
  title: string;
  author: string | null;
  narrator: string | null;
  description: string | null;
  cover_url: string | null;
  audio_url: string;
  duration_seconds: number | null;
  category: string | null;
  is_featured: boolean;
  sort_order: number;
  chapters: AudiobookChapter[] | null;
  created_at: string;
}

// ============================================
// DIGITAL LIBRARY TYPES
// ============================================

export interface Book {
  id: string;
  title: string;
  author: string | null;
  year: number | null;
  description: string | null;
  cover_image_url: string | null;
  pdf_filename: string | null;
  epub_filename: string | null;
  pages: number | null;
  downloads: number;
  created_at: string;
  category: string | null;
  era: string | null;
  language: string | null;
  // For distinguishing official vs community
  is_official?: boolean;
  uploaded_by?: string | null;
  uploader?: Profile;
}

