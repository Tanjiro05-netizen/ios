import React from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  Image,
  Share,
  Alert,
} from 'react-native';
import * as Clipboard from 'expo-clipboard';
import { Ionicons } from '@expo/vector-icons';
import { Thread } from '../types';
import { COLORS, SPACING, FONTS, getIdeologyColor, getIdeologyAbbrev, formatCount, formatTimeAgo } from '../constants';
import QuotedThread from './QuotedThread';

interface ThreadCardProps {
  thread: Thread;
  onPress: () => void;
  onLike?: () => void;
  onBookmark?: () => void;
  onRepost?: () => void;
  onQuotedThreadPress?: () => void;
  isLiked?: boolean;
  isBookmarked?: boolean;
  isReposted?: boolean;
  hideActions?: boolean;
  showIdeologyBadges?: boolean;
}

export default function ThreadCard({
  thread,
  onPress,
  onLike,
  onBookmark,
  onRepost,
  onQuotedThreadPress,
  isLiked = false,
  isBookmarked = false,
  isReposted = false,
  hideActions = false,
  showIdeologyBadges = true,
}: ThreadCardProps) {
  // Determine display name - use anonymous_name for guest posts, author username otherwise
  const displayName = thread.author?.username || thread.anonymous_name || 'Anonymous';
  const isAnonymousPost = !thread.author && !!thread.anonymous_name;
  const ideologyColor = getIdeologyColor(thread.author?.ideology || null);
  const ideologyAbbrev = getIdeologyAbbrev(thread.author?.ideology || null);

  return (
    <TouchableOpacity
      style={styles.container}
      onPress={onPress}
      activeOpacity={0.5}
    >
      {/* Reposted by header */}
      {thread.reposted_by && (
        <View style={styles.repostedHeader}>
          <Ionicons name="repeat" size={14} color={COLORS.textTertiary} />
          <Text style={styles.repostedText}>
            {thread.reposted_by.username || 'Someone'} reposted
          </Text>
        </View>
      )}

      <View style={styles.mainContent}>
        {/* Avatar column */}
        <View style={styles.avatarColumn}>
          <View style={styles.avatar}>
            {thread.author?.avatar_url ? (
              <Image source={{ uri: thread.author.avatar_url }} style={styles.avatarImage} />
            ) : (
              <View style={[styles.avatarPlaceholder, { backgroundColor: isAnonymousPost ? COLORS.textTertiary : ideologyColor }]}>
                <Text style={styles.avatarText}>
                  {displayName[0]?.toUpperCase() || '?'}
                </Text>
              </View>
            )}
          </View>
        </View>

        {/* Content column */}
        <View style={styles.contentColumn}>
        {/* Header row - X style inline */}
        <View style={styles.header}>
          <Text style={styles.displayName} numberOfLines={1}>
            {displayName}
          </Text>
          {isAnonymousPost && (
            <Text style={styles.guestBadge}>Guest</Text>
          )}
          {thread.author?.is_certified && (
            <Ionicons name="checkmark-circle" size={16} color={COLORS.blue} style={styles.verified} />
          )}
          {showIdeologyBadges && ideologyAbbrev ? (
            <Text style={[styles.ideology, { color: ideologyColor }]}>{ideologyAbbrev}</Text>
          ) : null}
          <Text style={styles.meta}>· {formatTimeAgo(thread.created_at)}</Text>
          <View style={styles.spacer} />
          <TouchableOpacity
            style={styles.moreButton}
            hitSlop={{ top: 10, bottom: 10, left: 10, right: 10 }}
            onPress={() => {
              Alert.alert(thread.title, undefined, [
                {
                  text: 'Copy Link',
                  onPress: async () => {
                    await Clipboard.setStringAsync(`marxistlibrary.app/thread/${thread.id}`);
                    Alert.alert('Copied', 'Link copied to clipboard.');
                  },
                },
                { text: 'Report', onPress: () => Alert.alert('Reported', 'Thank you — we will review this content.') },
                { text: 'Cancel', style: 'cancel' },
              ]);
            }}
          >
            <Ionicons name="ellipsis-horizontal" size={16} color={COLORS.textTertiary} />
          </TouchableOpacity>
        </View>

        {/* Pinned indicator */}
        {thread.is_pinned && (
          <View style={styles.pinnedRow}>
            <Ionicons name="pin" size={12} color={COLORS.textTertiary} />
            <Text style={styles.pinnedText}>Pinned</Text>
          </View>
        )}

        {/* Title - Zhihu style prominent */}
        <Text style={styles.title} numberOfLines={2}>
          {thread.title}
        </Text>

        {/* Preview text */}
          <Text style={styles.preview} numberOfLines={3}>
            {thread.content}
          </Text>

          {/* Quoted thread (for quote reposts) */}
          {thread.quoted_thread && (
            <QuotedThread
              thread={thread.quoted_thread}
              onPress={onQuotedThreadPress}
            />
          )}

          {/* Category tag */}
          <View style={styles.tagRow}>
            <View style={styles.categoryTag}>
              <Text style={styles.categoryText}>{thread.category_slug}</Text>
            </View>
          </View>

          {/* Actions row - X style */}
          {!hideActions && (
            <View style={styles.actions}>
              <TouchableOpacity style={styles.actionButton}>
                <Ionicons name="chatbubble-outline" size={18} color={COLORS.textTertiary} />
                <Text style={styles.actionCount}>{formatCount(thread.comment_count)}</Text>
              </TouchableOpacity>

              <TouchableOpacity style={styles.actionButton} onPress={onRepost}>
                <Ionicons
                  name={isReposted ? 'repeat' : 'repeat-outline'}
                  size={18}
                  color={isReposted ? COLORS.repost : COLORS.textTertiary}
                />
                <Text style={[styles.actionCount, isReposted && { color: COLORS.repost }]}>
                  {formatCount(thread.repost_count)}
                </Text>
              </TouchableOpacity>

              <TouchableOpacity style={styles.actionButton} onPress={onLike}>
                <Ionicons
                  name={isLiked ? 'heart' : 'heart-outline'}
                  size={18}
                  color={isLiked ? COLORS.like : COLORS.textTertiary}
                />
                <Text style={[styles.actionCount, isLiked && { color: COLORS.like }]}>
                  {formatCount(thread.like_count)}
                </Text>
              </TouchableOpacity>

              <TouchableOpacity style={styles.actionButton} onPress={onBookmark}>
                <Ionicons
                  name={isBookmarked ? 'bookmark' : 'bookmark-outline'}
                  size={18}
                  color={isBookmarked ? COLORS.blue : COLORS.textTertiary}
                />
              </TouchableOpacity>

              <TouchableOpacity
                style={styles.actionButton}
                onPress={async () => {
                  try {
                    await Share.share({
                      message: `${thread.title}\n\nmarxistlibrary.app/thread/${thread.id}`,
                    });
                  } catch {}
                }}
              >
                <Ionicons name="share-outline" size={18} color={COLORS.textTertiary} />
              </TouchableOpacity>
            </View>
          )}
        </View>
      </View>
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  container: {
    backgroundColor: COLORS.card,
    borderRadius: 12,
    padding: SPACING.xl,
    marginHorizontal: SPACING.lg,
    marginBottom: SPACING.lg,
    position: 'relative',
    overflow: 'hidden',
  },
  repostedHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: SPACING.md,
  },
  repostedText: {
    fontFamily: FONTS.family.mono,
    color: COLORS.textTertiary,
    fontSize: 10,
    textTransform: 'uppercase',
    letterSpacing: 1,
    marginLeft: SPACING.xs,
  },
  mainContent: {
    flexDirection: 'column',
  },
  avatarColumn: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: SPACING.sm,
  },
  avatar: {
    width: 24,
    height: 24,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
    overflow: 'hidden',
  },
  avatarImage: {
    width: 24,
    height: 24,
    borderRadius: 12,
  },
  avatarPlaceholder: {
    width: 24,
    height: 24,
    borderRadius: 12,
    justifyContent: 'center',
    alignItems: 'center',
  },
  avatarText: {
    color: '#FFFFFF',
    fontFamily: FONTS.family.mono,
    fontSize: 10,
    fontWeight: '700',
  },
  contentColumn: {
    flex: 1,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    flexWrap: 'wrap',
  },
  displayName: {
    fontFamily: FONTS.family.mono,
    color: 'rgba(229, 226, 225, 0.6)',
    fontSize: 12,
    flexShrink: 1,
  },
  verified: {
    marginLeft: 4,
  },
  guestBadge: {
    fontFamily: FONTS.family.mono,
    fontSize: 10,
    textTransform: 'uppercase',
    color: COLORS.textTertiary,
    backgroundColor: COLORS.background,
    paddingHorizontal: SPACING.xs,
    paddingVertical: 2,
    borderRadius: 4,
    marginLeft: 6,
    overflow: 'hidden',
  },
  ideology: {
    fontFamily: FONTS.family.mono,
    fontSize: 10,
    marginLeft: 6,
  },
  meta: {
    fontFamily: FONTS.family.mono,
    color: COLORS.textTertiary,
    fontSize: 10,
    marginLeft: 6,
  },
  spacer: {
    flex: 1,
  },
  moreButton: {
    position: 'absolute',
    top: 0,
    right: 0,
    padding: 4,
  },
  pinnedRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: SPACING.sm,
  },
  pinnedText: {
    fontFamily: FONTS.family.mono,
    color: COLORS.primary,
    fontSize: 10,
    textTransform: 'uppercase',
    letterSpacing: 1,
    marginLeft: 4,
  },
  title: {
    fontFamily: FONTS.family.display,
    color: COLORS.text,
    fontSize: 28,
    lineHeight: 32,
    marginTop: SPACING.sm,
    marginBottom: SPACING.xs,
  },
  preview: {
    fontFamily: FONTS.family.body,
    color: 'rgba(229, 226, 225, 0.7)',
    fontSize: 14,
    lineHeight: 22,
    marginTop: 4,
  },
  tagRow: {
    flexDirection: 'row',
    marginBottom: SPACING.sm,
  },
  categoryTag: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  categoryText: {
    fontFamily: FONTS.family.mono,
    color: 'rgba(229, 226, 225, 0.4)',
    textTransform: 'uppercase',
    letterSpacing: 2,
    fontSize: 10,
  },
  actions: {
    flexDirection: 'row',
    alignItems: 'center',
    marginTop: SPACING.lg,
    gap: SPACING.lg,
  },
  actionButton: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  actionCount: {
    fontFamily: FONTS.family.mono,
    color: 'rgba(229, 226, 225, 0.4)',
    fontSize: 10,
    textTransform: 'uppercase',
    letterSpacing: 1,
    marginLeft: 6,
  },
});
