import React from 'react';
import { View, StyleSheet } from 'react-native';
import SkeletonBox from './SkeletonBox';
import { COLORS, SPACING } from '../../constants';

interface ThreadCardSkeletonProps {
  count?: number;
}

/**
 * Skeleton loading state for ThreadCard
 * Matches the X-style layout: avatar | content column
 */
function SingleSkeleton() {
  return (
    <View style={styles.container}>
      {/* Avatar column */}
      <View style={styles.avatarColumn}>
        <SkeletonBox width={44} height={44} borderRadius={22} />
      </View>

      {/* Content column */}
      <View style={styles.contentColumn}>
        {/* Header: name, handle, time */}
        <View style={styles.header}>
          <SkeletonBox width={100} height={14} />
          <SkeletonBox width={60} height={12} style={styles.headerItem} />
          <SkeletonBox width={30} height={12} style={styles.headerItem} />
        </View>

        {/* Title */}
        <SkeletonBox width="90%" height={18} style={styles.title} />

        {/* Content lines */}
        <SkeletonBox width="100%" height={14} style={styles.line} />
        <SkeletonBox width="85%" height={14} style={styles.line} />
        <SkeletonBox width="70%" height={14} style={styles.line} />

        {/* Actions row */}
        <View style={styles.actionsRow}>
          <SkeletonBox width={40} height={16} />
          <SkeletonBox width={40} height={16} />
          <SkeletonBox width={40} height={16} />
          <SkeletonBox width={40} height={16} />
        </View>
      </View>
    </View>
  );
}

export default function ThreadCardSkeleton({ count = 3 }: ThreadCardSkeletonProps) {
  return (
    <>
      {Array.from({ length: count }).map((_, index) => (
        <SingleSkeleton key={index} />
      ))}
    </>
  );
}

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    paddingHorizontal: SPACING.lg,
    paddingVertical: SPACING.md,
    borderBottomWidth: 0.5,
    borderBottomColor: COLORS.border,
  },
  avatarColumn: {
    marginRight: SPACING.md,
  },
  contentColumn: {
    flex: 1,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  headerItem: {
    marginLeft: SPACING.sm,
  },
  title: {
    marginTop: SPACING.sm,
  },
  line: {
    marginTop: SPACING.xs,
  },
  actionsRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    marginTop: SPACING.md,
    paddingRight: SPACING.xxxl,
  },
});
