import { supabase } from './supabase';
import {
  Thread, Comment, Profile, Notification, PaginatedResponse, Bookmark, Repost, UserStats,
  Book
} from '../types';

export interface ReadingProgressPayload {
  user_id: string;
  book_id: string;
  title: string;
  author: string | null;
  chapter_title: string | null;
  chapter_index: number;
  chapter_count: number;
  progress: number;
  updated_at: string;
}

export interface ReadingQuotePayload {
  user_id: string;
  quote_id: string;
  text: string;
  source_title: string;
  source_detail: string | null;
  route_book_id: string | null;
  created_at: string;
  updated_at: string;
}

class ForumApiService {
  // ============================================
  // PROFILES
  // ============================================

  async getProfile(userId: string): Promise<Profile | null> {
    try {
      const { data, error } = await supabase
        .from('profiles')
        .select('id, username, avatar_url, bio, ideology, is_certified, role, banner_url, website, updated_at, is_admin')
        .eq('id', userId)
        .single();

      if (error) throw error;
      return data as Profile;
    } catch (err) {
      console.error('Error fetching profile:', err);
      return null;
    }
  }

  async updateProfile(userId: string, updates: Partial<Profile>): Promise<Profile | null> {
    try {
      const { data, error } = await supabase
        .from('profiles')
        .update(updates)
        .eq('id', userId)
        .select()
        .single();

      if (error) throw error;
      return data;
    } catch (err) {
      console.error('Error updating profile:', err);
      throw err;
    }
  }

  // ============================================
  // THREADS
  // ============================================

  async getThreads(options: {
    category?: string;
    page?: number;
    limit?: number;
    sortBy?: 'recent' | 'popular';
  } = {}): Promise<PaginatedResponse<Thread>> {
    const { category, page = 1, limit = 20, sortBy = 'recent' } = options;

    try {
      let query = supabase
        .from('forum_threads')
        .select(`
          *,
          author:profiles!forum_threads_author_id_fkey(id, username, avatar_url, ideology, is_certified)
        `, { count: 'exact' });

      if (category) {
        query = query.eq('category_slug', category);
      }

      query = query.order('is_pinned', { ascending: false });

      if (sortBy === 'popular') {
        query = query.order('like_count', { ascending: false });
      } else {
        query = query.order('created_at', { ascending: false });
      }

      const start = (page - 1) * limit;
      query = query.range(start, start + limit - 1);

      const { data, error, count } = await query;

      if (error) throw error;

      return {
        data: data || [],
        page,
        totalPages: Math.ceil((count || 0) / limit),
        total: count || 0,
      };
    } catch (err) {
      console.error('Error fetching threads:', err);
      return { data: [], page: 1, totalPages: 0, total: 0 };
    }
  }

  async getThread(threadId: string): Promise<Thread | null> {
    try {
      const { data, error } = await supabase
        .from('forum_threads')
        .select(`
          *,
          author:profiles!forum_threads_author_id_fkey(id, username, avatar_url, ideology, is_certified)
        `)
        .eq('id', threadId)
        .single();

      if (error) throw error;

      // Increment view count (fire-and-forget, don't block the read)
      supabase
        .from('forum_threads')
        .update({ view_count: (data.view_count || 0) + 1 })
        .eq('id', threadId)
        .then(({ error: updateError }) => {
          if (updateError) console.warn('Failed to increment view count:', updateError);
        });

      return data;
    } catch (err) {
      console.error('Error fetching thread:', err);
      return null;
    }
  }

  async createThread(threadData: {
    title: string;
    content: string;
    category_slug: string;
    anonymous_name?: string; // For guest posting
  }): Promise<Thread | null> {
    try {
      const { data: { user } } = await supabase.auth.getUser();

      // Allow guest posting with anonymous_name
      if (!user && !threadData.anonymous_name) {
        throw new Error('Not authenticated and no anonymous name provided');
      }

      const insertData: any = {
        title: threadData.title,
        content: threadData.content,
        category_slug: threadData.category_slug,
      };

      if (user) {
        // Authenticated user posting
        insertData.author_id = user.id;
      } else {
        // Guest posting
        insertData.author_id = null;
        insertData.anonymous_name = threadData.anonymous_name;
      }

      const { data, error } = await supabase
        .from('forum_threads')
        .insert(insertData)
        .select(`
          *,
          author:profiles(id, username, avatar_url, ideology, is_certified)
        `)
        .single();

      if (error) throw error;
      return data;
    } catch (err) {
      console.error('Error creating thread:', err);
      throw err;
    }
  }



  async updateThread(threadId: string, updates: { title?: string; content?: string }): Promise<Thread | null> {
    try {
      const { data, error } = await supabase
        .from('forum_threads')
        .update(updates)
        .eq('id', threadId)
        .select(`
          *,
          author:profiles!forum_threads_author_id_fkey(id, username, avatar_url, ideology, is_certified)
        `)
        .single();

      if (error) throw error;
      return data;
    } catch (err) {
      console.error('Error updating thread:', err);
      throw err;
    }
  }

  async deleteThread(threadId: string): Promise<{ success: boolean }> {
    try {
      const { error } = await supabase
        .from('forum_threads')
        .delete()
        .eq('id', threadId);

      if (error) throw error;
      return { success: true };
    } catch (err) {
      console.error('Error deleting thread:', err);
      return { success: false };
    }
  }

  // ============================================
  // COMMENTS
  // ============================================

  async getComments(threadId: string): Promise<Comment[]> {
    try {
      const { data, error } = await supabase
        .from('forum_comments')
        .select(`
          *,
          author:profiles!forum_comments_author_id_fkey(id, username, avatar_url, ideology, is_certified)
        `)
        .eq('thread_id', threadId)
        .order('created_at', { ascending: true });

      if (error) throw error;
      return data || [];
    } catch (err) {
      console.error('Error fetching comments:', err);
      return [];
    }
  }

  async createComment(commentData: {
    thread_id: string;
    content: string;
    parent_id?: string | null;
    anonymous_name?: string; // For guest posting
  }): Promise<Comment | null> {
    try {
      const { data: { user } } = await supabase.auth.getUser();

      // Allow guest posting with anonymous_name
      if (!user && !commentData.anonymous_name) {
        throw new Error('Not authenticated and no anonymous name provided');
      }

      const insertData: any = {
        thread_id: commentData.thread_id,
        content: commentData.content,
        parent_id: commentData.parent_id || null,
      };

      if (user) {
        // Authenticated user posting
        insertData.author_id = user.id;
      } else {
        // Guest posting
        insertData.author_id = null;
        insertData.anonymous_name = commentData.anonymous_name;
      }

      const { data, error } = await supabase
        .from('forum_comments')
        .insert(insertData)
        .select(`
          *,
          author:profiles!forum_comments_author_id_fkey(id, username, avatar_url, ideology, is_certified)
        `)
        .single();

      if (error) throw error;
      return data;
    } catch (err) {
      console.error('Error creating comment:', err);
      throw err;
    }
  }

  async updateComment(commentId: string, content: string): Promise<Comment | null> {
    try {
      const { data, error } = await supabase
        .from('forum_comments')
        .update({ content })
        .eq('id', commentId)
        .select(`
          *,
          author:profiles!forum_comments_author_id_fkey(id, username, avatar_url, ideology, is_certified)
        `)
        .single();

      if (error) throw error;
      return data;
    } catch (err) {
      console.error('Error updating comment:', err);
      throw err;
    }
  }

  async deleteComment(commentId: string): Promise<{ success: boolean }> {
    try {
      const { error } = await supabase
        .from('forum_comments')
        .delete()
        .eq('id', commentId);

      if (error) throw error;
      return { success: true };
    } catch (err) {
      console.error('Error deleting comment:', err);
      return { success: false };
    }
  }

  // ============================================
  // LIKES
  // ============================================

  async like(targetType: 'thread' | 'comment', targetId: string): Promise<void> {
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      const { error } = await supabase
        .from('forum_likes')
        .insert({
          user_id: user.id,
          target_type: targetType,
          target_id: targetId,
        });

      if (error && error.code !== '23505') throw error;
    } catch (err) {
      console.error('Error liking:', err);
      throw err;
    }
  }

  async unlike(targetType: 'thread' | 'comment', targetId: string): Promise<void> {
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      const { error } = await supabase
        .from('forum_likes')
        .delete()
        .eq('user_id', user.id)
        .eq('target_type', targetType)
        .eq('target_id', targetId);

      if (error) throw error;
    } catch (err) {
      console.error('Error unliking:', err);
      throw err;
    }
  }

  async getUserLikes(userId: string): Promise<{ target_type: string; target_id: string }[]> {
    try {
      const { data, error } = await supabase
        .from('forum_likes')
        .select('target_type, target_id')
        .eq('user_id', userId);

      if (error) throw error;
      return data || [];
    } catch (err) {
      console.error('Error fetching user likes:', err);
      return [];
    }
  }

  // ============================================
  // BOOKMARKS
  // ============================================

  async getBookmarks(userId: string): Promise<Bookmark[]> {
    try {
      const { data, error } = await supabase
        .from('forum_bookmarks')
        .select(`
          id,
          created_at,
          thread:forum_threads(
            id,
            title,
            content,
            category_slug,
            created_at,
            comment_count,
            like_count,
            author:profiles!forum_threads_author_id_fkey(id, username, avatar_url)
          )
        `)
        .eq('user_id', userId)
        .order('created_at', { ascending: false });

      if (error) throw error;
      return (data as any) || [];
    } catch (err) {
      console.error('Error fetching bookmarks:', err);
      return [];
    }
  }

  async addBookmark(threadId: string): Promise<{ success: boolean }> {
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      const { error } = await supabase
        .from('forum_bookmarks')
        .insert({
          user_id: user.id,
          thread_id: threadId,
        });

      if (error && error.code !== '23505') throw error;
      return { success: true };
    } catch (err) {
      console.error('Error adding bookmark:', err);
      return { success: false };
    }
  }

  async removeBookmark(threadId: string): Promise<{ success: boolean }> {
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      const { error } = await supabase
        .from('forum_bookmarks')
        .delete()
        .eq('user_id', user.id)
        .eq('thread_id', threadId);

      if (error) throw error;
      return { success: true };
    } catch (err) {
      console.error('Error removing bookmark:', err);
      return { success: false };
    }
  }

  async getUserBookmarkIds(userId: string): Promise<string[]> {
    try {
      const { data, error } = await supabase
        .from('forum_bookmarks')
        .select('thread_id')
        .eq('user_id', userId);

      if (error) throw error;
      return (data || []).map(b => b.thread_id);
    } catch (err) {
      console.error('Error fetching bookmark IDs:', err);
      return [];
    }
  }

  // ============================================
  // USER CONTENT (For Profile Tabs)
  // ============================================

  async getUserThreads(userId: string): Promise<Thread[]> {
    try {
      const { data, error } = await supabase
        .from('forum_threads')
        .select(`
          *,
          author:profiles!forum_threads_author_id_fkey(id, username, avatar_url, ideology, is_certified)
        `)
        .eq('author_id', userId)
        .order('created_at', { ascending: false });

      if (error) throw error;
      return data || [];
    } catch (err) {
      console.error('Error fetching user threads:', err);
      return [];
    }
  }

  async getUserComments(userId: string): Promise<Comment[]> {
    try {
      const { data, error } = await supabase
        .from('forum_comments')
        .select(`
          *,
          author:profiles!forum_comments_author_id_fkey(id, username, avatar_url, ideology, is_certified)
        `)
        .eq('author_id', userId)
        .order('created_at', { ascending: false });

      if (error) throw error;
      return data || [];
    } catch (err) {
      console.error('Error fetching user comments:', err);
      return [];
    }
  }

  async getUserLikedThreads(userId: string): Promise<Thread[]> {
    try {
      // First get the thread IDs the user has liked
      const { data: likes, error: likesError } = await supabase
        .from('forum_likes')
        .select('target_id')
        .eq('user_id', userId)
        .eq('target_type', 'thread');

      if (likesError) throw likesError;
      if (!likes || likes.length === 0) return [];

      const threadIds = likes.map(l => l.target_id);

      // Then fetch the full thread data
      const { data: threads, error: threadsError } = await supabase
        .from('forum_threads')
        .select(`
          *,
          author:profiles!forum_threads_author_id_fkey(id, username, avatar_url, ideology, is_certified)
        `)
        .in('id', threadIds)
        .order('created_at', { ascending: false });

      if (threadsError) throw threadsError;
      return threads || [];
    } catch (err) {
      console.error('Error fetching liked threads:', err);
      return [];
    }
  }

  async getUserStats(userId: string): Promise<UserStats> {
    try {
      // Get thread count
      const { count: threadCount } = await supabase
        .from('forum_threads')
        .select('id', { count: 'exact', head: true })
        .eq('author_id', userId);

      // Get comment count
      const { count: commentCount } = await supabase
        .from('forum_comments')
        .select('id', { count: 'exact', head: true })
        .eq('author_id', userId);

      // Get total likes received on user's threads
      const { data: userThreads } = await supabase
        .from('forum_threads')
        .select('id')
        .eq('author_id', userId);

      let likesReceived = 0;
      if (userThreads && userThreads.length > 0) {
        const threadIds = userThreads.map(t => t.id);
        const { count: threadLikes } = await supabase
          .from('forum_likes')
          .select('id', { count: 'exact', head: true })
          .eq('target_type', 'thread')
          .in('target_id', threadIds);
        likesReceived = threadLikes || 0;
      }

      // Get repost count
      const { count: repostCount } = await supabase
        .from('forum_reposts')
        .select('id', { count: 'exact', head: true })
        .eq('user_id', userId);

      return {
        threadCount: threadCount || 0,
        commentCount: commentCount || 0,
        likesReceived,
        repostCount: repostCount || 0,
      };
    } catch (err) {
      console.error('Error fetching user stats:', err);
      return { threadCount: 0, commentCount: 0, likesReceived: 0, repostCount: 0 };
    }
  }

  // ============================================
  // REPOSTS
  // ============================================

  async repost(threadId: string, quoteContent?: string): Promise<{ success: boolean }> {
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      const insertData: any = {
        user_id: user.id,
        thread_id: threadId,
      };

      if (quoteContent && quoteContent.trim()) {
        insertData.quote_content = quoteContent.trim();
      }

      const { error } = await supabase
        .from('forum_reposts')
        .insert(insertData);

      if (error && error.code !== '23505') throw error;

      return { success: true };
    } catch (err) {
      console.error('Error reposting:', err);
      return { success: false };
    }
  }

  async unrepost(threadId: string): Promise<{ success: boolean }> {
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) throw new Error('Not authenticated');

      const { error } = await supabase
        .from('forum_reposts')
        .delete()
        .eq('user_id', user.id)
        .eq('thread_id', threadId);

      if (error) throw error;

      // Decrement repost count on the thread
      await supabase.rpc('decrement_repost_count', { thread_id: threadId });

      return { success: true };
    } catch (err) {
      console.error('Error removing repost:', err);
      return { success: false };
    }
  }

  async isReposted(threadId: string): Promise<boolean> {
    try {
      const { data: { user } } = await supabase.auth.getUser();
      if (!user) return false;

      const { data, error } = await supabase
        .from('forum_reposts')
        .select('id')
        .eq('user_id', user.id)
        .eq('thread_id', threadId)
        .maybeSingle();

      if (error) throw error;
      return !!data;
    } catch (err) {
      console.error('Error checking repost status:', err);
      return false;
    }
  }

  async getUserReposts(userId: string): Promise<Thread[]> {
    try {
      const { data, error } = await supabase
        .from('forum_reposts')
        .select(`
          id,
          created_at,
          thread:forum_threads(
            *,
            author:profiles!forum_threads_author_id_fkey(id, username, avatar_url, ideology, is_certified)
          )
        `)
        .eq('user_id', userId)
        .order('created_at', { ascending: false });

      if (error) throw error;

      // Flatten the thread data
      return (data || [])
        .filter(r => r.thread)
        .map(r => ({
          ...(r.thread as any),
          repost_created_at: r.created_at,
        }));
    } catch (err) {
      console.error('Error fetching user reposts:', err);
      return [];
    }
  }

  async getUserRepostIds(userId: string): Promise<string[]> {
    try {
      const { data, error } = await supabase
        .from('forum_reposts')
        .select('thread_id')
        .eq('user_id', userId);

      if (error) throw error;
      return (data || []).map(r => r.thread_id);
    } catch (err) {
      console.error('Error fetching repost IDs:', err);
      return [];
    }
  }

  // ============================================
  // NOTIFICATIONS
  // ============================================

  async getNotifications(userId: string, limit = 50): Promise<Notification[]> {
    try {
      const { data, error } = await supabase
        .from('forum_notifications')
        .select(`
          id,
          type,
          content_preview,
          is_read,
          created_at,
          thread_id,
          comment_id,
          source_user:profiles!forum_notifications_source_user_id_fkey(id, username, avatar_url)
        `)
        .eq('user_id', userId)
        .order('created_at', { ascending: false })
        .limit(limit);

      if (error) throw error;
      return (data as any) || [];
    } catch (err) {
      console.error('Error fetching notifications:', err);
      return [];
    }
  }

  async getUnreadCount(userId: string): Promise<number> {
    try {
      const { count, error } = await supabase
        .from('forum_notifications')
        .select('id', { count: 'exact', head: true })
        .eq('user_id', userId)
        .eq('is_read', false);

      if (error) throw error;
      return count || 0;
    } catch (err) {
      console.error('Error fetching unread count:', err);
      return 0;
    }
  }

  async markNotificationRead(notificationId: string): Promise<void> {
    try {
      const { error } = await supabase
        .from('forum_notifications')
        .update({ is_read: true })
        .eq('id', notificationId);

      if (error) throw error;
    } catch (err) {
      console.error('Error marking notification read:', err);
    }
  }

  async markAllNotificationsRead(userId: string): Promise<void> {
    try {
      const { error } = await supabase
        .from('forum_notifications')
        .update({ is_read: true })
        .eq('user_id', userId)
        .eq('is_read', false);

      if (error) throw error;
    } catch (err) {
      console.error('Error marking all notifications read:', err);
    }
  }


  // ============================================
  // DIGITAL LIBRARY
  // ============================================

  // Get all books (currently using single table, filtering by is_official if column exists)
  async getBooks(options: {
    filter?: 'all' | 'official' | 'community';
    category?: string;
    era?: string;
    language?: string;
    search?: string;
    page?: number;
    limit?: number;
  } = {}): Promise<PaginatedResponse<Book>> {
    const { filter = 'all', category, era, language, search, page = 1, limit = 20 } = options;

    try {
      let query = supabase
        .from('digital_library_books')
        .select('*', { count: 'exact' });

      if (filter === 'official') {
        query = query.eq('is_official', true);
      } else if (filter === 'community') {
        query = query.eq('is_official', false);
      }

      if (category) {
        query = query.eq('category', category);
      }

      if (era) {
        query = query.eq('era', era);
      }

      if (language) {
        query = query.eq('language', language);
      }

      if (search) {
        query = query.or(`title.ilike.%${search}%,author.ilike.%${search}%,description.ilike.%${search}%`);
      }

      const start = (page - 1) * limit;
      query = query
        .order('created_at', { ascending: false })
        .range(start, start + limit - 1);

      const { data, error, count } = await query;

      if (error) throw error;

      return {
        data: data || [],
        page,
        totalPages: Math.ceil((count || 0) / limit),
        total: count || 0,
      };
    } catch (err) {
      console.error('Error fetching books:', err);
      return { data: [], page: 1, totalPages: 0, total: 0 };
    }
  }

  // Get a specific book by ID
  async getBook(bookId: string): Promise<Book | null> {
    try {
      const { data, error } = await supabase
        .from('digital_library_books')
        .select('*')
        .eq('id', bookId)
        .single();

      if (error) throw error;
      return data;
    } catch (err) {
      console.error('Error fetching book:', err);
      return null;
    }
  }

  // Increment download count
  async incrementDownloadCount(bookId: string): Promise<void> {
    try {
      const { error } = await supabase.rpc('increment_book_downloads', { book_id: bookId });
      if (error) {
        // Fallback: manual increment if RPC doesn't exist
        const { data: book } = await supabase
          .from('digital_library_books')
          .select('downloads')
          .eq('id', bookId)
          .single();

        if (book) {
          await supabase
            .from('digital_library_books')
            .update({ downloads: (book.downloads || 0) + 1 })
            .eq('id', bookId);
        }
      }
    } catch (err) {
      console.error('Error incrementing download count:', err);
    }
  }

  // Get unique categories for filtering
  async getBookCategories(): Promise<string[]> {
    try {
      const { data, error } = await supabase
        .from('digital_library_books')
        .select('category')
        .not('category', 'is', null);

      if (error) throw error;

      const categories = [...new Set(data?.map(d => d.category).filter(Boolean))] as string[];
      return categories.sort();
    } catch (err) {
      console.error('Error fetching book categories:', err);
      return [];
    }
  }

  // Get unique eras for filtering
  async getBookEras(): Promise<string[]> {
    try {
      const { data, error } = await supabase
        .from('digital_library_books')
        .select('era')
        .not('era', 'is', null);

      if (error) throw error;

      const eras = [...new Set(data?.map(d => d.era).filter(Boolean))] as string[];
      return eras.sort();
    } catch (err) {
      console.error('Error fetching book eras:', err);
      return [];
    }
  }

  // Get unique languages for filtering
  async getBookLanguages(): Promise<string[]> {
    try {
      const { data, error } = await supabase
        .from('digital_library_books')
        .select('language')
        .not('language', 'is', null);

      if (error) throw error;

      const languages = [...new Set(data?.map(d => d.language).filter(Boolean))] as string[];
      return languages.sort();
    } catch (err) {
      console.error('Error fetching book languages:', err);
      return [];
    }
  }

  // Get book PDF URL from storage
  getBookPdfUrl(pdfFilename: string): string {
    const { data } = supabase.storage.from('library').getPublicUrl(pdfFilename);
    return data.publicUrl;
  }

  // Get book EPUB URL from storage
  getBookEpubUrl(epubFilename: string): string {
    const { data } = supabase.storage.from('library').getPublicUrl(epubFilename);
    return data.publicUrl;
  }

  // ============================================
  // READING PROGRESS
  // ============================================

  async getReadingProgress(userId: string): Promise<ReadingProgressPayload[]> {
    const { data, error } = await supabase
      .from('reading_progress')
      .select('user_id, book_id, title, author, chapter_title, chapter_index, chapter_count, progress, updated_at')
      .eq('user_id', userId)
      .order('updated_at', { ascending: false });

    if (error) throw error;
    return (data || []) as ReadingProgressPayload[];
  }

  async upsertReadingProgress(payload: ReadingProgressPayload): Promise<void> {
    const { error } = await supabase
      .from('reading_progress')
      .upsert(payload, { onConflict: 'user_id,book_id' });

    if (error) throw error;
  }

  async getReadingQuotes(userId: string): Promise<ReadingQuotePayload[]> {
    const { data, error } = await supabase
      .from('reading_quotes')
      .select('user_id, quote_id, text, source_title, source_detail, route_book_id, created_at, updated_at')
      .eq('user_id', userId)
      .order('updated_at', { ascending: false });

    if (error) throw error;
    return (data || []) as ReadingQuotePayload[];
  }

  async upsertReadingQuote(payload: ReadingQuotePayload): Promise<void> {
    const { error } = await supabase
      .from('reading_quotes')
      .upsert(payload, { onConflict: 'user_id,quote_id' });

    if (error) throw error;
  }

  async deleteReadingQuote(userId: string, quoteId: string): Promise<void> {
    const { error } = await supabase
      .from('reading_quotes')
      .delete()
      .eq('user_id', userId)
      .eq('quote_id', quoteId);

    if (error) throw error;
  }


  // ============================================
  // PUSH TOKENS
  // ============================================

  async savePushToken(userId: string, token: string): Promise<void> {
    try {
      const { error } = await supabase
        .from('profiles')
        .update({ push_token: token })
        .eq('id', userId);

      if (error) throw error;
    } catch (err) {
      console.error('Error saving push token:', err);
    }
  }

  async deletePushToken(userId: string): Promise<void> {
    try {
      const { error } = await supabase
        .from('profiles')
        .update({ push_token: null })
        .eq('id', userId);

      if (error) throw error;
    } catch (err) {
      console.error('Error deleting push token:', err);
    }
  }

  // ============================================
  // AUDIOBOOKS
  // ============================================

  async getAudiobooks(): Promise<import('../types').Audiobook[]> {
    try {
      const { data, error } = await supabase
        .from('audiobooks')
        .select('*')
        .order('sort_order');

      if (error) throw error;
      return (data as import('../types').Audiobook[]) || [];
    } catch (err) {
      console.error('Error fetching audiobooks:', err);
      return [];
    }
  }

  // ============================================
  // AUTH
  // ============================================

  async signIn(email: string, password: string) {
    return supabase.auth.signInWithPassword({ email, password });
  }

  async signUp(email: string, password: string) {
    return supabase.auth.signUp({ email, password });
  }

  async signOut() {
    return supabase.auth.signOut();
  }

  async getCurrentUser() {
    return supabase.auth.getUser();
  }

  onAuthStateChange(callback: (event: string, session: any) => void) {
    return supabase.auth.onAuthStateChange(callback);
  }
}

export const api = new ForumApiService();
export default api;
