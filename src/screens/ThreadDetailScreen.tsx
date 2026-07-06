import React, { useState, useEffect, useCallback } from 'react';
import {
  View,
  Text,
  StyleSheet,
  FlatList,
  TouchableOpacity,
  TextInput,
  ActivityIndicator,
  KeyboardAvoidingView,
  Platform,
  Alert,
  Image,
  RefreshControl,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { useNavigation, useRoute, RouteProp } from '@react-navigation/native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';

import { useAuth } from '../hooks/useAuth';
import { api } from '../lib/api';
import { haptics } from '../lib/haptics';
import toast from '../lib/toast';
import {
  COLORS,
  FONTS,
  SPACING,
  BOARDS,
  formatTimeAgo,
  formatCount,
  getIdeologyColor,
  getIdeologyAbbrev,
} from '../constants';
import { RootStackParamList, Thread, Comment } from '../types';
import CommentCard from '../components/CommentCard';
import RepostActionSheet from '../components/RepostActionSheet';

type NavigationProp = NativeStackNavigationProp<RootStackParamList>;
type RouteType = RouteProp<RootStackParamList, 'ThreadDetail'>;

export default function ThreadDetailScreen() {
  const navigation = useNavigation<NavigationProp>();
  const route = useRoute<RouteType>();
  const { threadId } = route.params;
  const { user, isGuest, guestSession } = useAuth();

  const [thread, setThread] = useState<Thread | null>(null);
  const [comments, setComments] = useState<Comment[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [commentText, setCommentText] = useState('');
  const [submitting, setSubmitting] = useState(false);
  const [replyTo, setReplyTo] = useState<Comment | null>(null);

  // Interaction state
  const [isLiked, setIsLiked] = useState(false);
  const [isBookmarked, setIsBookmarked] = useState(false);
  const [isReposted, setIsReposted] = useState(false);
  const [likeCount, setLikeCount] = useState(0);
  const [showRepostSheet, setShowRepostSheet] = useState(false);

  // Comment likes
  const [likedCommentIds, setLikedCommentIds] = useState<Set<string>>(new Set());

  const loadThread = useCallback(async () => {
    try {
      const [threadData, commentsData] = await Promise.all([
        api.getThread(threadId),
        api.getComments(threadId),
      ]);
      setThread(threadData);
      setComments(commentsData);
      setLikeCount(threadData?.like_count || 0);

      // Load interaction state for authenticated users
      if (user) {
        const [likes, bookmarkIds, repostIds] = await Promise.all([
          api.getUserLikes(user.id),
          api.getUserBookmarkIds(user.id),
          api.getUserRepostIds(user.id),
        ]);
        setIsLiked(likes.some((l) => l.target_type === 'thread' && l.target_id === threadId));
        setIsBookmarked(bookmarkIds.includes(threadId));
        setIsReposted(repostIds.includes(threadId));

        const commentLikeIds = new Set(
          likes.filter((l) => l.target_type === 'comment').map((l) => l.target_id),
        );
        setLikedCommentIds(commentLikeIds);
      }
    } catch (err) {
      console.error('Error loading thread:', err);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [threadId, user]);

  useEffect(() => {
    loadThread();
  }, [loadThread]);

  const handleRefresh = () => {
    setRefreshing(true);
    loadThread();
  };

  // ── Actions ──

  const handleLike = async () => {
    if (!user) {
      toast.info('Sign in to like posts');
      return;
    }
    haptics.selection();
    try {
      if (isLiked) {
        await api.unlike('thread', threadId);
        setIsLiked(false);
        setLikeCount((c) => Math.max(0, c - 1));
      } else {
        await api.like('thread', threadId);
        setIsLiked(true);
        setLikeCount((c) => c + 1);
      }
    } catch {
      toast.error('Failed to update like');
    }
  };

  const handleBookmark = async () => {
    if (!user) {
      toast.info('Sign in to bookmark posts');
      return;
    }
    haptics.selection();
    try {
      if (isBookmarked) {
        await api.removeBookmark(threadId);
        setIsBookmarked(false);
        toast.success('Bookmark removed');
      } else {
        await api.addBookmark(threadId);
        setIsBookmarked(true);
        toast.success('Bookmarked');
      }
    } catch {
      toast.error('Failed to update bookmark');
    }
  };

  const handleRepost = async (quoteContent?: string) => {
    if (!user) {
      toast.info('Sign in to repost');
      return;
    }
    try {
      await api.repost(threadId, quoteContent);
      setIsReposted(true);
      setShowRepostSheet(false);
      toast.success('Reposted');
    } catch {
      toast.error('Failed to repost');
    }
  };

  const handleUnrepost = async () => {
    try {
      await api.unrepost(threadId);
      setIsReposted(false);
      setShowRepostSheet(false);
      toast.success('Repost removed');
    } catch {
      toast.error('Failed to remove repost');
    }
  };

  const handleCommentLike = async (commentId: string) => {
    if (!user) return;
    haptics.selection();
    try {
      const wasLiked = likedCommentIds.has(commentId);
      if (wasLiked) {
        await api.unlike('comment', commentId);
        setLikedCommentIds((prev) => {
          const next = new Set(prev);
          next.delete(commentId);
          return next;
        });
      } else {
        await api.like('comment', commentId);
        setLikedCommentIds((prev) => new Set(prev).add(commentId));
      }
    } catch {
      // silent
    }
  };

  const handleDeleteComment = async (commentId: string) => {
    Alert.alert('Delete Comment', 'Are you sure?', [
      { text: 'Cancel', style: 'cancel' },
      {
        text: 'Delete',
        style: 'destructive',
        onPress: async () => {
          const result = await api.deleteComment(commentId);
          if (result.success) {
            setComments((prev) => prev.filter((c) => c.id !== commentId));
            toast.success('Comment deleted');
          }
        },
      },
    ]);
  };

  const handleEditComment = async (commentId: string, content: string) => {
    const updated = await api.updateComment(commentId, content);
    if (updated) {
      setComments((prev) => prev.map((c) => (c.id === commentId ? updated : c)));
      toast.success('Comment updated');
    }
  };

  const handleSubmitComment = async () => {
    const text = commentText.trim();
    if (!text) return;

    setSubmitting(true);
    try {
      const commentData: {
        thread_id: string;
        content: string;
        parent_id?: string;
        anonymous_name?: string;
      } = {
        thread_id: threadId,
        content: text,
      };

      if (replyTo) {
        commentData.parent_id = replyTo.id;
      }

      if (isGuest && guestSession) {
        commentData.anonymous_name = guestSession.username;
      }

      const newComment = await api.createComment(commentData);
      if (newComment) {
        setComments((prev) => [...prev, newComment]);
        setCommentText('');
        setReplyTo(null);
        haptics.success();
      }
    } catch {
      toast.error('Failed to post comment');
    } finally {
      setSubmitting(false);
    }
  };

  // ── Render ──

  if (loading) {
    return (
      <SafeAreaView style={styles.container} edges={['top']}>
        <View style={styles.loadingContainer}>
          <ActivityIndicator size="large" color={COLORS.primary} />
        </View>
      </SafeAreaView>
    );
  }

  if (!thread) {
    return (
      <SafeAreaView style={styles.container} edges={['top']}>
        <View style={styles.header}>
          <TouchableOpacity onPress={() => navigation.goBack()} style={styles.backBtn}>
            <Ionicons name="arrow-back" size={22} color={COLORS.text} />
          </TouchableOpacity>
        </View>
        <View style={styles.loadingContainer}>
          <Text style={styles.emptyText}>Thread not found</Text>
        </View>
      </SafeAreaView>
    );
  }

  const displayName = thread.author?.username || thread.anonymous_name || 'Anonymous';
  const isAnonymousPost = !thread.author && !!thread.anonymous_name;
  const ideologyColor = getIdeologyColor(thread.author?.ideology || null);
  const ideologyAbbrev = getIdeologyAbbrev(thread.author?.ideology || null);
  const board = BOARDS.find((b) => b.slug === thread.category_slug);

  const renderHeader = () => (
    <View style={styles.threadContent}>
      {/* Board tag */}
      {board && (
        <View style={styles.boardTag}>
          <Text style={styles.boardTagText}>
            {board.icon} {board.fullName}
          </Text>
        </View>
      )}

      {/* Title */}
      <Text style={styles.threadTitle}>{thread.title}</Text>

      {/* Author row */}
      <View style={styles.authorRow}>
        <TouchableOpacity
          style={styles.authorInfo}
          onPress={() =>
            thread.author?.id && navigation.navigate('UserProfile', { userId: thread.author.id })
          }
          disabled={!thread.author?.id}
        >
          <View style={styles.avatar}>
            {thread.author?.avatar_url ? (
              <Image source={{ uri: thread.author.avatar_url }} style={styles.avatarImage} />
            ) : (
              <View
                style={[
                  styles.avatarPlaceholder,
                  { backgroundColor: isAnonymousPost ? COLORS.textTertiary : ideologyColor },
                ]}
              >
                <Text style={styles.avatarText}>{displayName[0]?.toUpperCase() || '?'}</Text>
              </View>
            )}
          </View>
          <Text style={styles.authorName}>{displayName}</Text>
          {isAnonymousPost && <Text style={styles.guestBadge}>Guest</Text>}
          {ideologyAbbrev ? (
            <Text style={[styles.ideologyBadge, { color: ideologyColor }]}>{ideologyAbbrev}</Text>
          ) : null}
        </TouchableOpacity>
        <Text style={styles.threadMeta}>{formatTimeAgo(thread.created_at)}</Text>
      </View>

      {/* Body */}
      <Text style={styles.threadBody}>{thread.content}</Text>

      {/* Stats row */}
      <View style={styles.statsRow}>
        <Text style={styles.statText}>
          {formatCount(thread.view_count)} <Text style={styles.statLabel}>views</Text>
        </Text>
        <Text style={styles.statDot}>·</Text>
        <Text style={styles.statText}>
          {formatCount(likeCount)} <Text style={styles.statLabel}>likes</Text>
        </Text>
        <Text style={styles.statDot}>·</Text>
        <Text style={styles.statText}>
          {formatCount(thread.comment_count)} <Text style={styles.statLabel}>replies</Text>
        </Text>
        <Text style={styles.statDot}>·</Text>
        <Text style={styles.statText}>
          {formatCount(thread.repost_count)} <Text style={styles.statLabel}>reposts</Text>
        </Text>
      </View>

      {/* Action buttons */}
      <View style={styles.actionBar}>
        <TouchableOpacity style={styles.actionBtn} onPress={handleLike}>
          <Ionicons
            name={isLiked ? 'heart' : 'heart-outline'}
            size={20}
            color={isLiked ? COLORS.like : COLORS.textTertiary}
          />
        </TouchableOpacity>
        <TouchableOpacity style={styles.actionBtn} onPress={() => setShowRepostSheet(true)}>
          <Ionicons
            name={isReposted ? 'repeat' : 'repeat-outline'}
            size={20}
            color={isReposted ? COLORS.repost : COLORS.textTertiary}
          />
        </TouchableOpacity>
        <TouchableOpacity style={styles.actionBtn} onPress={handleBookmark}>
          <Ionicons
            name={isBookmarked ? 'bookmark' : 'bookmark-outline'}
            size={20}
            color={isBookmarked ? COLORS.blue : COLORS.textTertiary}
          />
        </TouchableOpacity>
      </View>

      {/* Comments header */}
      <View style={styles.commentsHeader}>
        <Text style={styles.commentsTitle}>
          {comments.length > 0 ? `${comments.length} REPLIES` : 'NO REPLIES YET'}
        </Text>
      </View>
    </View>
  );

  const topLevelComments = comments.filter((c) => !c.parent_id);
  const getReplies = (parentId: string) => comments.filter((c) => c.parent_id === parentId);

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      {/* Header bar */}
      <View style={styles.header}>
        <TouchableOpacity onPress={() => navigation.goBack()} style={styles.backBtn}>
          <Ionicons name="arrow-back" size={22} color={COLORS.text} />
        </TouchableOpacity>
        <Text style={styles.headerTitle}>Thread</Text>
        <View style={{ width: 40 }} />
      </View>

      <KeyboardAvoidingView
        style={{ flex: 1 }}
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
        keyboardVerticalOffset={0}
      >
        <FlatList
          data={topLevelComments}
          keyExtractor={(item) => item.id}
          ListHeaderComponent={renderHeader}
          renderItem={({ item }) => {
            const replies = getReplies(item.id);
            return (
              <View>
                <CommentCard
                  comment={item}
                  isLiked={likedCommentIds.has(item.id)}
                  onLike={() => handleCommentLike(item.id)}
                  onReply={() => setReplyTo(item)}
                  onEdit={handleEditComment}
                  onDelete={() => handleDeleteComment(item.id)}
                  isOwner={!!user && item.author_id === user.id}
                  canDelete={!!user && (item.author_id === user.id)}
                />
                {replies.map((reply) => (
                  <CommentCard
                    key={reply.id}
                    comment={reply}
                    isNested
                    isLiked={likedCommentIds.has(reply.id)}
                    onLike={() => handleCommentLike(reply.id)}
                    onReply={() => setReplyTo(reply)}
                    onEdit={handleEditComment}
                    onDelete={() => handleDeleteComment(reply.id)}
                    isOwner={!!user && reply.author_id === user.id}
                    canDelete={!!user && (reply.author_id === user.id)}
                  />
                ))}
              </View>
            );
          }}
          contentContainerStyle={styles.listContent}
          refreshControl={
            <RefreshControl refreshing={refreshing} onRefresh={handleRefresh} tintColor={COLORS.primary} />
          }
        />

        {/* Comment input */}
        <View style={styles.inputBar}>
          {replyTo && (
            <View style={styles.replyBanner}>
              <Text style={styles.replyText} numberOfLines={1}>
                Replying to {replyTo.author?.username || replyTo.anonymous_name || 'Anonymous'}
              </Text>
              <TouchableOpacity onPress={() => setReplyTo(null)}>
                <Ionicons name="close" size={16} color={COLORS.textSecondary} />
              </TouchableOpacity>
            </View>
          )}
          <View style={styles.inputRow}>
            <TextInput
              style={styles.commentInput}
              placeholder={replyTo ? 'Write a reply...' : 'Add a comment...'}
              placeholderTextColor={COLORS.textTertiary}
              value={commentText}
              onChangeText={setCommentText}
              multiline
              maxLength={10000}
            />
            <TouchableOpacity
              style={[styles.sendBtn, !commentText.trim() && styles.sendBtnDisabled]}
              onPress={handleSubmitComment}
              disabled={!commentText.trim() || submitting}
            >
              {submitting ? (
                <ActivityIndicator size="small" color="#fff" />
              ) : (
                <Ionicons name="send" size={18} color="#fff" />
              )}
            </TouchableOpacity>
          </View>
        </View>
      </KeyboardAvoidingView>

      <RepostActionSheet
        visible={showRepostSheet}
        onClose={() => setShowRepostSheet(false)}
        onRepost={handleRepost}
        onUnrepost={handleUnrepost}
        isReposted={isReposted}
        thread={thread}
      />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: COLORS.background,
  },
  loadingContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: SPACING.lg,
    paddingVertical: SPACING.md,
    borderBottomWidth: 1,
    borderBottomColor: COLORS.border,
  },
  backBtn: {
    width: 40,
    height: 40,
    borderRadius: 20,
    alignItems: 'center',
    justifyContent: 'center',
  },
  headerTitle: {
    fontFamily: FONTS.family.mono,
    fontSize: 11,
    color: COLORS.textSecondary,
    textTransform: 'uppercase',
    letterSpacing: 2,
  },
  listContent: {
    paddingBottom: 16,
  },

  // ── Thread content ──
  threadContent: {
    paddingHorizontal: SPACING.xl,
    paddingTop: SPACING.xl,
  },
  boardTag: {
    alignSelf: 'flex-start',
    backgroundColor: 'rgba(255,255,255,0.04)',
    borderWidth: 1,
    borderColor: COLORS.border,
    borderRadius: 6,
    paddingHorizontal: 10,
    paddingVertical: 4,
    marginBottom: SPACING.md,
  },
  boardTagText: {
    fontFamily: FONTS.family.mono,
    fontSize: 10,
    color: COLORS.textSecondary,
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  threadTitle: {
    fontFamily: FONTS.family.display,
    fontSize: 28,
    color: COLORS.text,
    lineHeight: 34,
    marginBottom: SPACING.lg,
  },
  authorRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    marginBottom: SPACING.xl,
  },
  authorInfo: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  avatar: {
    width: 28,
    height: 28,
    borderRadius: 14,
    overflow: 'hidden',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
  },
  avatarImage: {
    width: 28,
    height: 28,
    borderRadius: 14,
  },
  avatarPlaceholder: {
    width: 28,
    height: 28,
    borderRadius: 14,
    justifyContent: 'center',
    alignItems: 'center',
  },
  avatarText: {
    color: '#fff',
    fontFamily: FONTS.family.mono,
    fontSize: 11,
    fontWeight: '700',
  },
  authorName: {
    fontFamily: FONTS.family.mono,
    fontSize: 12,
    color: COLORS.text,
  },
  guestBadge: {
    fontFamily: FONTS.family.mono,
    fontSize: 9,
    textTransform: 'uppercase',
    color: COLORS.textTertiary,
    backgroundColor: COLORS.backgroundSecondary,
    paddingHorizontal: 4,
    paddingVertical: 2,
    borderRadius: 3,
  },
  ideologyBadge: {
    fontFamily: FONTS.family.mono,
    fontSize: 10,
  },
  threadMeta: {
    fontFamily: FONTS.family.mono,
    fontSize: 10,
    color: COLORS.textTertiary,
  },
  threadBody: {
    fontFamily: FONTS.family.body,
    fontSize: 16,
    color: 'rgba(229,226,225,0.85)',
    lineHeight: 26,
    marginBottom: SPACING.xl,
  },
  statsRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: SPACING.md,
    borderTopWidth: 1,
    borderTopColor: COLORS.border,
    gap: 6,
  },
  statText: {
    fontFamily: FONTS.family.mono,
    fontSize: 11,
    color: COLORS.text,
  },
  statLabel: {
    color: COLORS.textTertiary,
  },
  statDot: {
    color: COLORS.textTertiary,
    fontSize: 10,
  },
  actionBar: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-around',
    paddingVertical: SPACING.md,
    borderTopWidth: 1,
    borderTopColor: COLORS.border,
    borderBottomWidth: 1,
    borderBottomColor: COLORS.border,
  },
  actionBtn: {
    padding: 8,
  },
  commentsHeader: {
    paddingTop: SPACING.lg,
    paddingBottom: SPACING.md,
  },
  commentsTitle: {
    fontFamily: FONTS.family.mono,
    fontSize: 10,
    color: COLORS.textSecondary,
    letterSpacing: 2,
    textTransform: 'uppercase',
  },
  emptyText: {
    fontFamily: FONTS.family.mono,
    fontSize: 12,
    color: COLORS.textSecondary,
    textTransform: 'uppercase',
    letterSpacing: 1,
  },

  // ── Input bar ──
  inputBar: {
    borderTopWidth: 1,
    borderTopColor: COLORS.border,
    backgroundColor: COLORS.background,
    paddingHorizontal: SPACING.lg,
    paddingVertical: SPACING.sm,
  },
  replyBanner: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: 6,
    paddingHorizontal: 8,
    backgroundColor: 'rgba(200,30,30,0.08)',
    borderRadius: 6,
    marginBottom: 6,
  },
  replyText: {
    fontFamily: FONTS.family.mono,
    fontSize: 10,
    color: COLORS.primary,
    letterSpacing: 0.5,
    flex: 1,
  },
  inputRow: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    gap: 8,
  },
  commentInput: {
    flex: 1,
    fontFamily: FONTS.family.body,
    fontSize: 14,
    color: COLORS.text,
    backgroundColor: 'rgba(255,255,255,0.04)',
    borderWidth: 1,
    borderColor: COLORS.border,
    borderRadius: 12,
    paddingHorizontal: 14,
    paddingVertical: 10,
    maxHeight: 120,
  },
  sendBtn: {
    width: 38,
    height: 38,
    borderRadius: 19,
    backgroundColor: COLORS.primary,
    alignItems: 'center',
    justifyContent: 'center',
  },
  sendBtnDisabled: {
    backgroundColor: COLORS.textTertiary,
  },
});
