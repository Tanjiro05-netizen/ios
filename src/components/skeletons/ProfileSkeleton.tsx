import React from 'react';
import { View, StyleSheet } from 'react-native';
import SkeletonBox from './SkeletonBox';
import { COLORS, SPACING } from '../../constants';

/**
 * Skeleton loading state for Profile screen
 * Matches the X-style profile layout with banner, avatar, stats
 */
export default function ProfileSkeleton() {
  return (
    <View style={styles.container}>
      {/* Banner */}
      <SkeletonBox width="100%" height={120} borderRadius={0} />

      {/* Profile section */}
      <View style={styles.profileSection}>
        {/* Avatar + Edit button row */}
        <View style={styles.avatarRow}>
          <View style={styles.avatarWrapper}>
            <SkeletonBox width={88} height={88} borderRadius={44} />
          </View>
          <SkeletonBox width={100} height={34} borderRadius={17} style={styles.editButton} />
        </View>

        {/* Name and handle */}
        <SkeletonBox width={140} height={22} style={styles.name} />
        <SkeletonBox width={100} height={16} style={styles.handle} />

        {/* Ideology badge */}
        <SkeletonBox width={80} height={28} borderRadius={14} style={styles.badge} />

        {/* Bio lines */}
        <SkeletonBox width="100%" height={14} style={styles.bio} />
        <SkeletonBox width="80%" height={14} style={styles.bioLine} />

        {/* Joined date */}
        <SkeletonBox width={120} height={14} style={styles.joined} />

        {/* Stats row */}
        <View style={styles.statsRow}>
          <SkeletonBox width={80} height={14} />
          <SkeletonBox width={80} height={14} style={styles.stat} />
        </View>
      </View>

      {/* Tabs */}
      <View style={styles.tabBar}>
        <SkeletonBox width={60} height={16} />
        <SkeletonBox width={60} height={16} />
        <SkeletonBox width={60} height={16} />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: COLORS.background,
  },
  profileSection: {
    paddingHorizontal: SPACING.lg,
  },
  avatarRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'flex-end',
    marginTop: -44,
  },
  avatarWrapper: {
    borderWidth: 4,
    borderColor: COLORS.background,
    borderRadius: 48,
  },
  editButton: {
    marginBottom: SPACING.sm,
  },
  name: {
    marginTop: SPACING.md,
  },
  handle: {
    marginTop: SPACING.xs,
  },
  badge: {
    marginTop: SPACING.md,
  },
  bio: {
    marginTop: SPACING.md,
  },
  bioLine: {
    marginTop: SPACING.xs,
  },
  joined: {
    marginTop: SPACING.md,
  },
  statsRow: {
    flexDirection: 'row',
    marginTop: SPACING.md,
    paddingBottom: SPACING.md,
  },
  stat: {
    marginLeft: SPACING.lg,
  },
  tabBar: {
    flexDirection: 'row',
    justifyContent: 'space-around',
    paddingVertical: SPACING.md,
    borderTopWidth: 0.5,
    borderTopColor: COLORS.border,
    borderBottomWidth: 0.5,
    borderBottomColor: COLORS.border,
  },
});
