import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity, Image } from 'react-native';
import { Thread } from '../types';
import { COLORS, SPACING, FONTS, getIdeologyColor } from '../constants';

interface QuotedThreadProps {
  thread: Thread;
  onPress?: () => void;
}

export default function QuotedThread({ thread, onPress }: QuotedThreadProps) {
  const displayName = thread.author?.username || thread.anonymous_name || 'Anonymous';
  const isAnonymousPost = !thread.author && !!thread.anonymous_name;
  const ideologyColor = getIdeologyColor(thread.author?.ideology || null);

  return (
    <TouchableOpacity
      style={styles.container}
      onPress={onPress}
      activeOpacity={0.7}
      disabled={!onPress}
    >
      {/* Author row */}
      <View style={styles.authorRow}>
        <View style={[styles.avatar, { backgroundColor: isAnonymousPost ? COLORS.textTertiary : ideologyColor }]}>
          {thread.author?.avatar_url ? (
            <Image source={{ uri: thread.author.avatar_url }} style={styles.avatarImage} />
          ) : (
            <Text style={styles.avatarText}>{displayName[0]?.toUpperCase() || '?'}</Text>
          )}
        </View>
        <Text style={styles.authorName} numberOfLines={1}>
          {displayName}
        </Text>
        {isAnonymousPost && <Text style={styles.guestBadge}>Guest</Text>}
        {thread.author?.is_certified && (
          <Text style={styles.verified}>✓</Text>
        )}
      </View>

      {/* Thread content */}
      <Text style={styles.title} numberOfLines={2}>
        {thread.title}
      </Text>
      <Text style={styles.content} numberOfLines={3}>
        {thread.content}
      </Text>
    </TouchableOpacity>
  );
}

const styles = StyleSheet.create({
  container: {
    borderWidth: 1,
    borderColor: COLORS.border,
    borderRadius: 12,
    padding: SPACING.md,
    marginTop: SPACING.sm,
    backgroundColor: COLORS.background,
  },
  authorRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: SPACING.xs,
  },
  avatar: {
    width: 20,
    height: 20,
    borderRadius: 10,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: SPACING.xs,
  },
  avatarImage: {
    width: 20,
    height: 20,
    borderRadius: 10,
  },
  avatarText: {
    color: '#FFFFFF',
    fontSize: 10,
    fontWeight: '700',
  },
  authorName: {
    color: COLORS.text,
    fontSize: FONTS.sizes.sm,
    fontWeight: '600',
    flex: 1,
  },
  guestBadge: {
    fontSize: FONTS.sizes.xs,
    color: COLORS.textTertiary,
    backgroundColor: COLORS.backgroundSecondary,
    paddingHorizontal: 4,
    paddingVertical: 1,
    borderRadius: 4,
    marginLeft: 4,
    overflow: 'hidden',
  },
  verified: {
    color: COLORS.blue,
    fontSize: FONTS.sizes.sm,
    marginLeft: 4,
  },
  title: {
    color: COLORS.text,
    fontSize: FONTS.sizes.md,
    fontWeight: '600',
    lineHeight: 20,
    marginBottom: SPACING.xs,
  },
  content: {
    color: COLORS.textSecondary,
    fontSize: FONTS.sizes.sm,
    lineHeight: 18,
  },
});
