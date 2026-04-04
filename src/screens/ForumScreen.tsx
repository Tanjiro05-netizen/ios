import React from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { COLORS, FONTS, SPACING } from '../constants';

export default function ForumScreen() {
  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <View style={styles.titleBar}>
        <Text style={styles.screenTitle}>Forum</Text>
      </View>

      <View style={styles.content}>
        <View style={styles.iconWrapper}>
          <Ionicons name="lock-closed" size={48} color={COLORS.primaryDark} />
        </View>

        <View style={styles.statusBadge}>
          <Text style={styles.statusBadgeText}>COMING SOON</Text>
        </View>

        <Text style={styles.heading}>The Forum is Under Construction</Text>

        <Text style={styles.body}>
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

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: COLORS.background,
  },
  titleBar: {
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
  screenSubtitle: {
    fontFamily: FONTS.family.mono,
    fontSize: 10,
    color: 'rgba(229, 226, 225, 0.5)',
    textTransform: 'uppercase',
    letterSpacing: 2,
    marginTop: 2,
  },
  content: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: SPACING.xl,
    paddingBottom: SPACING.xxxl,
  },
  iconWrapper: {
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
  heading: {
    fontFamily: FONTS.family.display,
    fontSize: 26,
    color: COLORS.text,
    textAlign: 'center',
    marginBottom: SPACING.lg,
    lineHeight: 34,
  },
  body: {
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
