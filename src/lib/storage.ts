import AsyncStorage from '@react-native-async-storage/async-storage';

// Storage keys
const KEYS = {
  SETTINGS: '@marxist_forum_settings',
  RECENT_SEARCHES: '@marxist_forum_recent_searches',
  DRAFT_THREAD: '@marxist_forum_draft_thread',
  ONBOARDING_COMPLETE: '@marxist_forum_onboarding',
  GUEST_SESSION: '@marxist_forum_guest_session',
};

// Settings interface
export interface AppSettings {
  pushNotifications: boolean;
  emailNotifications: boolean;
  darkMode: boolean;
  autoPlayVideos: boolean;
  dataSaver: boolean;
  showIdeologyBadges: boolean;
  emailMarketingEnabled: boolean;
  emailCommentReplies: boolean;
  emailThreadActivity: boolean;
  emailWeeklyDigest: boolean;
}

// Default settings
export const DEFAULT_SETTINGS: AppSettings = {
  pushNotifications: true,
  emailNotifications: true,
  darkMode: true,
  autoPlayVideos: true,
  dataSaver: false,
  showIdeologyBadges: true,
  emailMarketingEnabled: false,
  emailCommentReplies: true,
  emailThreadActivity: true,
  emailWeeklyDigest: false,
};

// Settings storage
export const settingsStorage = {
  async get(): Promise<AppSettings> {
    try {
      const json = await AsyncStorage.getItem(KEYS.SETTINGS);
      if (json) {
        return { ...DEFAULT_SETTINGS, ...JSON.parse(json) };
      }
      return DEFAULT_SETTINGS;
    } catch (error) {
      console.error('Error loading settings:', error);
      return DEFAULT_SETTINGS;
    }
  },

  async set(settings: Partial<AppSettings>): Promise<void> {
    try {
      const current = await this.get();
      const updated = { ...current, ...settings };
      await AsyncStorage.setItem(KEYS.SETTINGS, JSON.stringify(updated));
    } catch (error) {
      console.error('Error saving settings:', error);
    }
  },

  async clear(): Promise<void> {
    try {
      await AsyncStorage.removeItem(KEYS.SETTINGS);
    } catch (error) {
      console.error('Error clearing settings:', error);
    }
  },
};

// Recent searches storage
export const searchStorage = {
  async getRecent(): Promise<string[]> {
    try {
      const json = await AsyncStorage.getItem(KEYS.RECENT_SEARCHES);
      if (json) {
        return JSON.parse(json);
      }
      return [];
    } catch (error) {
      console.error('Error loading recent searches:', error);
      return [];
    }
  },

  async addRecent(query: string): Promise<void> {
    try {
      const searches = await this.getRecent();
      // Remove if already exists, add to front, limit to 10
      const filtered = searches.filter((s) => s.toLowerCase() !== query.toLowerCase());
      const updated = [query, ...filtered].slice(0, 10);
      await AsyncStorage.setItem(KEYS.RECENT_SEARCHES, JSON.stringify(updated));
    } catch (error) {
      console.error('Error saving recent search:', error);
    }
  },

  async removeRecent(query: string): Promise<void> {
    try {
      const searches = await this.getRecent();
      const updated = searches.filter((s) => s.toLowerCase() !== query.toLowerCase());
      await AsyncStorage.setItem(KEYS.RECENT_SEARCHES, JSON.stringify(updated));
    } catch (error) {
      console.error('Error removing recent search:', error);
    }
  },

  async clear(): Promise<void> {
    try {
      await AsyncStorage.removeItem(KEYS.RECENT_SEARCHES);
    } catch (error) {
      console.error('Error clearing recent searches:', error);
    }
  },
};

// Draft storage for thread composition
export interface DraftThread {
  title: string;
  content: string;
  categorySlug: string;
  savedAt: string;
}

export const draftStorage = {
  async get(): Promise<DraftThread | null> {
    try {
      const json = await AsyncStorage.getItem(KEYS.DRAFT_THREAD);
      if (json) {
        return JSON.parse(json);
      }
      return null;
    } catch (error) {
      console.error('Error loading draft:', error);
      return null;
    }
  },

  async save(draft: Omit<DraftThread, 'savedAt'>): Promise<void> {
    try {
      const data: DraftThread = {
        ...draft,
        savedAt: new Date().toISOString(),
      };
      await AsyncStorage.setItem(KEYS.DRAFT_THREAD, JSON.stringify(data));
    } catch (error) {
      console.error('Error saving draft:', error);
    }
  },

  async clear(): Promise<void> {
    try {
      await AsyncStorage.removeItem(KEYS.DRAFT_THREAD);
    } catch (error) {
      console.error('Error clearing draft:', error);
    }
  },
};

// Onboarding status
export const onboardingStorage = {
  async isComplete(): Promise<boolean> {
    try {
      const value = await AsyncStorage.getItem(KEYS.ONBOARDING_COMPLETE);
      return value === 'true';
    } catch (error) {
      console.error('Error checking onboarding status:', error);
      return false;
    }
  },

  async setComplete(): Promise<void> {
    try {
      await AsyncStorage.setItem(KEYS.ONBOARDING_COMPLETE, 'true');
    } catch (error) {
      console.error('Error saving onboarding status:', error);
    }
  },

  async reset(): Promise<void> {
    try {
      await AsyncStorage.removeItem(KEYS.ONBOARDING_COMPLETE);
    } catch (error) {
      console.error('Error resetting onboarding status:', error);
    }
  },
};

// Guest session storage
export interface GuestSession {
  id: string;
  username: string;
  createdAt: string;
}

export const guestStorage = {
  async get(): Promise<GuestSession | null> {
    try {
      const json = await AsyncStorage.getItem(KEYS.GUEST_SESSION);
      if (json) {
        return JSON.parse(json);
      }
      return null;
    } catch (error) {
      console.error('Error loading guest session:', error);
      return null;
    }
  },

  async save(session: GuestSession): Promise<void> {
    try {
      await AsyncStorage.setItem(KEYS.GUEST_SESSION, JSON.stringify(session));
    } catch (error) {
      console.error('Error saving guest session:', error);
    }
  },

  async clear(): Promise<void> {
    try {
      await AsyncStorage.removeItem(KEYS.GUEST_SESSION);
    } catch (error) {
      console.error('Error clearing guest session:', error);
    }
  },
};
