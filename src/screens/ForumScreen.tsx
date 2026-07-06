import React, { useState, useEffect, useCallback } from 'react';
import {
  View,
  Text,
  StyleSheet,
  FlatList,
  TouchableOpacity,
  ActivityIndicator,
  RefreshControl,
  ScrollView,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { useNavigation } from '@react-navigation/native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';

import { useAuth } from '../hooks/useAuth';
import { api } from '../lib/api';
import { haptics } from '../lib/haptics';
import toast from '../lib/toast';
import { COLORS, FONTS, SPACING, BOARDS } from '../constants';
import { RootStackParamList, Thread } from '../types';
import ThreadCard from '../components/ThreadCard';
import FloatingActionButton from '../components/FloatingActionButton';
import RepostActionSheet from '../components/RepostActionSheet';

type NavigationProp = NativeStackNavigationProp<RootStackParamList>;

// ═══════════════════════════════════════════
// FEATURE FLAG — flip to true to enable forum
// ═══════════════════════════════════════════
const FORUM_ENABLED = false;

// ── Coming Soon placeholder ──────────────

function ComingSoonPlaceholder() {
  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <View style={styles.titleBar}>
        <Text style={styles.screenTitle}>Forum</Text>
      </View>

      <View style={styles.comingSoonContent}>
        <View style={styles.comingSoonIcon}>
          <Ionicons name="lock-closed" size={48} color={COLORS.primaryDark} />
        </View>

        <View style={styles.statusBadge}>
          <Text style={styles.statusBadgeText}>COMING SOON</Text>
        </View>

        <Text style={styles.comingSoonHeading}>The Forum is Under Construction</Text>

        <Text style={styles.comingSoonBody}>
          A space for discussion, reading groups, and organisational
          praxis is being prepared. The forum will include threaded debate,
          community boards, and ideological tagging.
        </Text>

        <View style={styles.divider} />

        <View style={styles.featureList}>
          <FeatureRow icon="chatbubbles-outline" label="Threaded discussions across boards" />
          <FeatureRow icon="bookmark-outline" label="Bookmarks and reading lists" />
          <FeatureRow icon="people-outline" label="Community moderation" />
          <FeatureRow icon="flag-outline" label="Ideology-tagged profiles" />
        </View>

        <View style={styles.divider} />

        <Text style={styles.footnote}>
          — The development collective is working on this. Check back soon.
        </Text>
      </View>
    </SafeAreaView>
  );
}

function FeatureRow({ icon, label }: { icon: keyof typeof Ionicons.glyphMap; label: string }) {
  return (
    <View style={styles.featureRow}>
      <Ionicons name={icon} size={18} color={COLORS.textSecondary} />
      <Text style={styles.featureLabel}>{label}</Text>
    </View>
  );
}

// ── Full Forum Feed ──────────────────────

function ForumFeed() {
  const navigation = useNavigation<NavigationProp>();
  const { user, isGuest } = useAuth();

  const [threads, setThreads] = useState<Thread[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [loadingMore, setLoadingMore] = useState(false);
  const [page, setPage] = useState(1);
  const [totalPages, setTotalPages] = useState(1);
  const [activeBoard, setActiveBoard] = useState<string | null>(null);
  const [sortBy, setSortBy] = useState<'recent' | 'popular'>('recent');

  // Interaction state
  const [likedIds, setLikedIds] = useState<Set<string>>(new Set());
  const [bookmarkedIds, setBookmarkedIds] = useState<Set<string>>(new Set());
  const [repostedIds, setRepostedIds] = useState<Set<string>>(new Set());

  // Repost sheet
  const [repostThread, setRepostThread] = useState<Thread | null>(null);

  const loadThreads = useCallback(
    async (pageNum = 1, append = false) => {
      try {
        const result = await api.getThreads({
          category: activeBoard || undefined,
          page: pageNum,
          limit: 20,
          sortBy,
        });
        if (append) {
          setThreads((prev) => [...prev, ...result.data]);
        } else {
          setThreads(result.data);
        }
        setTotalPages(result.totalPages);
        setPage(pageNum);
      } catch (err) {
        console.error('Error loading threads:', err);
      } finally {
        setLoading(false);
        setRefreshing(false);
        setLoadingMore(false);
      }
    },
    [activeBoard, sortBy],
  );

  const loadInteractionState = useCallback(async () => {
    if (!user) return;
    try {
      const [likes, bookmarks, reposts] = await Promise.all([
        api.getUserLikes(user.id),
        api.getUserBookmarkIds(user.id),
        api.getUserRepostIds(user.id),
      ]);
      setLikedIds(
        new Set(likes.filter((l) => l.target_type === 'thread').map((l) => l.target_id)),
      );
      setBookmarkedIds(new Set(bookmarks));
      setRepostedIds(new Set(reposts));
    } catch {
      // silent
    }
  }, [user]);

  useEffect(() => {
    setLoading(true);
    loadThreads(1);
    loadInteractionState();
  }, [loadThreads, loadInteractionState]);

  const handleRefresh = () => {
    setRefreshing(true);
    loadThreads(1);
    loadInteractionState();
  };

  const handleLoadMore = () => {
    if (loadingMore || page >= totalPages) return;
    setLoadingMore(true);
    loadThreads(page + 1, true);
  };

  // ── Actions ──

  const handleLike = async (threadId: string) => {
    if (!user) {
      toast.info('Sign in to like posts');
      return;
    }
    haptics.selection();
    const wasLiked = likedIds.has(threadId);
    try {
      if (wasLiked) {
        await api.unlike('thread', threadId);
        setLikedIds((prev) => {
          const next = new Set(prev);
          next.delete(threadId);
          return next;
        });
        setThreads((prev) =>
          prev.map((t) =>
            t.id === threadId ? { ...t, like_count: Math.max(0, (t.like_count || 0) - 1) } : t,
          ),
        );
      } else {
        await api.like('thread', threadId);
        setLikedIds((prev) => new Set(prev).add(threadId));
        setThreads((prev) =>
          prev.map((t) =>
            t.id === threadId ? { ...t, like_count: (t.like_count || 0) + 1 } : t,
          ),
        );
      }
    } catch {
      toast.error('Failed to update like');
    }
  };

  const handleBookmark = async (threadId: string) => {
    if (!user) {
      toast.info('Sign in to bookmark posts');
      return;
    }
    haptics.selection();
    const wasBookmarked = bookmarkedIds.has(threadId);
    try {
      if (wasBookmarked) {
        await api.removeBookmark(threadId);
        setBookmarkedIds((prev) => {
          const next = new Set(prev);
          next.delete(threadId);
          return next;
        });
      } else {
        await api.addBookmark(threadId);
        setBookmarkedIds((prev) => new Set(prev).add(threadId));
      }
    } catch {
      toast.error('Failed to update bookmark');
    }
  };

  const handleRepostAction = async (quoteContent?: string) => {
    if (!repostThread || !user) return;
    try {
      await api.repost(repostThread.id, quoteContent);
      setRepostedIds((prev) => new Set(prev).add(repostThread.id));
      setRepostThread(null);
      toast.success('Reposted');
    } catch {
      toast.error('Failed to repost');
    }
  };

  const handleUnrepost = async () => {
    if (!repostThread) return;
    try {
      await api.unrepost(repostThread.id);
      setRepostedIds((prev) => {
        const next = new Set(prev);
        next.delete(repostThread.id);
        return next;
      });
      setRepostThread(null);
      toast.success('Repost removed');
    } catch {
      toast.error('Failed to remove repost');
    }
  };

  // ── Render ──

  const allBoards = [{ slug: null as string | null, fullName: 'All', icon: '🔥' }, ...BOARDS];

  const renderHeader = () => (
    <View>
      {/* Title bar */}
      <View style={styles.titleBar}>
        <Text style={styles.screenTitle}>Forum</Text>
        <TouchableOpacity
          onPress={() => navigation.navigate('Settings')}
          style={styles.settingsBtn}
        >
          <Ionicons name="settings-outline" size={22} color={COLORS.textSecondary} />
        </TouchableOpacity>
      </View>

      {/* Board tabs */}
      <ScrollView
        horizontal
        showsHorizontalScrollIndicator={false}
        style={styles.boardTabs}
        contentContainerStyle={styles.boardTabsContent}
      >
        {allBoards.map((board) => {
          const isActive = activeBoard === board.slug;
          return (
            <TouchableOpacity
              key={board.slug ?? 'all'}
              style={[styles.boardTab, isActive && styles.boardTabActive]}
              onPress={() => {
                setActiveBoard(board.slug);
                haptics.selection();
              }}
            >
              <Text style={styles.boardTabEmoji}>{board.icon}</Text>
              <Text style={[styles.boardTabText, isActive && styles.boardTabTextActive]}>
                {board.fullName}
              </Text>
            </TouchableOpacity>
          );
        })}
      </ScrollView>

      {/* Sort toggle */}
      <View style={styles.sortRow}>
        <TouchableOpacity
          style={[styles.sortBtn, sortBy === 'recent' && styles.sortBtnActive]}
          onPress={() => setSortBy('recent')}
        >
          <Text style={[styles.sortBtnText, sortBy === 'recent' && styles.sortBtnTextActive]}>
            Recent
          </Text>
        </TouchableOpacity>
        <TouchableOpacity
          style={[styles.sortBtn, sortBy === 'popular' && styles.sortBtnActive]}
          onPress={() => setSortBy('popular')}
        >
          <Text style={[styles.sortBtnText, sortBy === 'popular' && styles.sortBtnTextActive]}>
            Popular
          </Text>
        </TouchableOpacity>
      </View>
    </View>
  );

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      {loading ? (
        <View style={styles.loadingContainer}>
          {renderHeader()}
          <View style={{ flex: 1, justifyContent: 'center', alignItems: 'center' }}>
            <ActivityIndicator size="large" color={COLORS.primary} />
          </View>
        </View>
      ) : (
        <FlatList
          data={threads}
          keyExtractor={(item) => item.id}
          ListHeaderComponent={renderHeader}
          renderItem={({ item }) => (
            <ThreadCard
              thread={item}
              onPress={() => navigation.navigate('ThreadDetail', { threadId: item.id })}
              onLike={() => handleLike(item.id)}
              onBookmark={() => handleBookmark(item.id)}
              onRepost={() => setRepostThread(item)}
              isLiked={likedIds.has(item.id)}
              isBookmarked={bookmarkedIds.has(item.id)}
              isReposted={repostedIds.has(item.id)}
            />
          )}
          ListEmptyComponent={
            <View style={styles.emptyContainer}>
              <Ionicons name="chatbubbles-outline" size={48} color={COLORS.textTertiary} />
              <Text style={styles.emptyText}>No threads yet</Text>
              <Text style={styles.emptySubtext}>Be the first to start a discussion</Text>
            </View>
          }
          contentContainerStyle={styles.listContent}
          onEndReached={handleLoadMore}
          onEndReachedThreshold={0.3}
          refreshControl={
            <RefreshControl
              refreshing={refreshing}
              onRefresh={handleRefresh}
              tintColor={COLORS.primary}
            />
          }
          ListFooterComponent={
            loadingMore ? (
              <ActivityIndicator
                size="small"
                color={COLORS.primary}
                style={{ paddingVertical: 20 }}
              />
            ) : null
          }
        />
      )}

      <FloatingActionButton
        onPress={() =>
          navigation.navigate('CreateThread', {
            boardSlug: activeBoard || undefined,
          })
        }
      />

      <RepostActionSheet
        visible={!!repostThread}
        onClose={() => setRepostThread(null)}
        onRepost={handleRepostAction}
        onUnrepost={handleUnrepost}
        isReposted={repostThread ? repostedIds.has(repostThread.id) : false}
        thread={repostThread}
      />
    </SafeAreaView>
  );
}

// ── Exported screen ──────────────────────

export default function ForumScreen() {
  if (!FORUM_ENABLED) {
    return <ComingSoonPlaceholder />;
  }
  return <ForumFeed />;
}

// ── Styles ───────────────────────────────

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: COLORS.background,
  },
  loadingContainer: {
    flex: 1,
  },

  // ── Title bar ──
  titleBar: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: 24,
    paddingVertical: 16,
    borderBottomWidth: 1,
    borderBottomColor: COLORS.border,
  },
  screenTitle: {
    fontFamily: FONTS.family.display,
    fontSize: 38,
    fontWeight: '400',
    color: COLORS.text,
    letterSpacing: -1,
  },
  settingsBtn: {
    padding: 4,
  },

  // ── Board tabs ──
  boardTabs: {
    maxHeight: 48,
    borderBottomWidth: 1,
    borderBottomColor: COLORS.border,
  },
  boardTabsContent: {
    paddingHorizontal: SPACING.lg,
    gap: 6,
    alignItems: 'center',
    paddingVertical: 8,
  },
  boardTab: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
    paddingHorizontal: 14,
    paddingVertical: 6,
    borderRadius: 20,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.05)',
    backgroundColor: 'rgba(255,255,255,0.02)',
  },
  boardTabActive: {
    backgroundColor: 'rgba(200,30,30,0.12)',
    borderColor: 'rgba(200,30,30,0.3)',
  },
  boardTabEmoji: {
    fontSize: 13,
  },
  boardTabText: {
    fontFamily: FONTS.family.mono,
    fontSize: 10,
    color: 'rgba(229,226,225,0.4)',
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  boardTabTextActive: {
    color: '#fff',
  },

  // ── Sort row ──
  sortRow: {
    flexDirection: 'row',
    paddingHorizontal: SPACING.lg,
    paddingVertical: SPACING.sm,
    gap: 8,
    borderBottomWidth: 1,
    borderBottomColor: COLORS.border,
  },
  sortBtn: {
    paddingHorizontal: 12,
    paddingVertical: 4,
    borderRadius: 6,
  },
  sortBtnActive: {
    backgroundColor: 'rgba(255,255,255,0.06)',
  },
  sortBtnText: {
    fontFamily: FONTS.family.mono,
    fontSize: 10,
    color: COLORS.textTertiary,
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  sortBtnTextActive: {
    color: COLORS.text,
  },

  // ── List ──
  listContent: {
    paddingTop: SPACING.md,
    paddingBottom: 100,
  },
  emptyContainer: {
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 80,
    gap: SPACING.md,
  },
  emptyText: {
    fontFamily: FONTS.family.mono,
    fontSize: 14,
    color: COLORS.textSecondary,
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  emptySubtext: {
    fontFamily: FONTS.family.body,
    fontSize: 13,
    color: COLORS.textTertiary,
  },

  // ── Coming Soon ──
  comingSoonContent: {
    flex: 1,
    alignItems: 'center',
    paddingHorizontal: SPACING.xl,
    paddingTop: SPACING.xxxl,
    paddingBottom: SPACING.xxxl,
  },
  comingSoonIcon: {
    width: 96,
    height: 96,
    borderRadius: 24,
    backgroundColor: '#1a0f0f',
    borderWidth: 1,
    borderColor: 'rgba(200, 30, 30, 0.2)',
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: SPACING.xl,
  },
  statusBadge: {
    backgroundColor: 'rgba(200, 30, 30, 0.1)',
    borderWidth: 1,
    borderColor: COLORS.primaryDark,
    borderRadius: 4,
    paddingHorizontal: 12,
    paddingVertical: 4,
    marginBottom: SPACING.lg,
  },
  statusBadgeText: {
    fontFamily: FONTS.family.mono,
    fontSize: 10,
    color: COLORS.primaryLight,
    textTransform: 'uppercase',
    letterSpacing: 3,
  },
  comingSoonHeading: {
    fontFamily: FONTS.family.display,
    fontSize: 26,
    color: COLORS.text,
    textAlign: 'center',
    marginBottom: SPACING.lg,
    lineHeight: 34,
  },
  comingSoonBody: {
    fontFamily: FONTS.family.body,
    fontSize: 14,
    color: COLORS.textSecondary,
    textAlign: 'center',
    lineHeight: 22,
    marginBottom: SPACING.xl,
  },
  divider: {
    width: '100%',
    height: 1,
    backgroundColor: COLORS.border,
    marginVertical: SPACING.xl,
  },
  featureList: {
    width: '100%',
    gap: SPACING.md,
  },
  featureRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: SPACING.md,
  },
  featureLabel: {
    fontFamily: FONTS.family.mono,
    fontSize: 11,
    color: COLORS.textSecondary,
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  footnote: {
    fontFamily: FONTS.family.mono,
    fontSize: 10,
    color: COLORS.textTertiary,
    textAlign: 'center',
    fontStyle: 'italic',
    letterSpacing: 1,
  },
});
