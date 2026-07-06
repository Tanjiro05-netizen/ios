import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  Image,
  ActivityIndicator,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { useNavigation, useRoute, RouteProp } from '@react-navigation/native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';

import { api } from '../lib/api';
import { COLORS, FONTS, SPACING, getIdeologyColor, getIdeologyAbbrev } from '../constants';
import { RootStackParamList, Profile, UserStats } from '../types';

type NavigationProp = NativeStackNavigationProp<RootStackParamList>;
type RouteType = RouteProp<RootStackParamList, 'UserProfile'>;

export default function UserProfileScreen() {
  const navigation = useNavigation<NavigationProp>();
  const route = useRoute<RouteType>();
  const { userId } = route.params;

  const [profile, setProfile] = useState<Profile | null>(null);
  const [stats, setStats] = useState<UserStats | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    const load = async () => {
      try {
        const [profileData, statsData] = await Promise.all([
          api.getProfile(userId),
          api.getUserStats(userId),
        ]);
        setProfile(profileData);
        setStats(statsData);
      } catch (err) {
        console.error('Error loading user profile:', err);
      } finally {
        setLoading(false);
      }
    };
    load();
  }, [userId]);

  if (loading) {
    return (
      <SafeAreaView style={styles.container} edges={['top']}>
        <View style={styles.loadingContainer}>
          <ActivityIndicator size="large" color={COLORS.primary} />
        </View>
      </SafeAreaView>
    );
  }

  if (!profile) {
    return (
      <SafeAreaView style={styles.container} edges={['top']}>
        <TouchableOpacity style={styles.backBtn} onPress={() => navigation.goBack()}>
          <Ionicons name="arrow-back" size={24} color={COLORS.text} />
        </TouchableOpacity>
        <View style={styles.errorContainer}>
          <Ionicons name="person-remove-outline" size={64} color={COLORS.textTertiary} />
          <Text style={styles.errorTitle}>User Not Found</Text>
          <Text style={styles.errorSubtitle}>This profile may have been removed.</Text>
        </View>
      </SafeAreaView>
    );
  }

  const ideologyColor = getIdeologyColor(profile.ideology);
  const ideologyAbbrev = getIdeologyAbbrev(profile.ideology);

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      {/* Back button */}
      <TouchableOpacity style={styles.backBtn} onPress={() => navigation.goBack()}>
        <Ionicons name="arrow-back" size={24} color={COLORS.text} />
      </TouchableOpacity>

      <ScrollView contentContainerStyle={styles.scrollContent}>
        {/* Banner */}
        <View style={styles.bannerContainer}>
          {profile.banner_url ? (
            <Image source={{ uri: profile.banner_url }} style={styles.banner} />
          ) : (
            <View style={styles.bannerPlaceholder} />
          )}
        </View>

        {/* Avatar + badges row */}
        <View style={styles.avatarRow}>
          <View style={styles.avatarWrapper}>
            {profile.avatar_url ? (
              <Image source={{ uri: profile.avatar_url }} style={styles.avatar} />
            ) : (
              <View style={styles.avatarPlaceholder}>
                <Ionicons name="person" size={36} color={COLORS.textTertiary} />
              </View>
            )}
          </View>
        </View>

        {/* Profile info */}
        <View style={styles.profileInfo}>
          <View style={styles.usernameRow}>
            <Text style={styles.username}>{profile.username || 'Anonymous'}</Text>
            {profile.is_certified && (
              <Ionicons name="checkmark-circle" size={18} color={COLORS.primary} />
            )}
          </View>

          {profile.ideology && profile.ideology !== 'Unaffiliated' && (
            <View style={[styles.ideologyBadge, { borderColor: ideologyColor }]}>
              <View style={[styles.ideologyDot, { backgroundColor: ideologyColor }]} />
              <Text style={[styles.ideologyBadgeText, { color: ideologyColor }]}>
                {ideologyAbbrev || profile.ideology}
              </Text>
            </View>
          )}

          {profile.role && profile.role !== 'user' && (
            <View style={styles.roleBadge}>
              <Text style={styles.roleBadgeText}>{profile.role.toUpperCase()}</Text>
            </View>
          )}
        </View>

        {/* Bio */}
        {profile.bio ? (
          <View style={styles.bioSection}>
            <Text style={styles.bio}>{profile.bio}</Text>
          </View>
        ) : null}

        {/* Stats */}
        {stats && (
          <View style={styles.statsRow}>
            <StatCell label="Posts" value={stats.threadCount} />
            <View style={styles.statDivider} />
            <StatCell label="Comments" value={stats.commentCount} />
            <View style={styles.statDivider} />
            <StatCell label="Likes" value={stats.likesReceived} />
            <View style={styles.statDivider} />
            <StatCell label="Reposts" value={stats.repostCount} />
          </View>
        )}

        {/* Meta */}
        {profile.website ? (
          <View style={styles.metaSection}>
            <View style={styles.metaRow}>
              <Ionicons name="globe-outline" size={14} color={COLORS.textSecondary} />
              <Text style={styles.metaText}>{profile.website}</Text>
            </View>
          </View>
        ) : null}
      </ScrollView>
    </SafeAreaView>
  );
}

function StatCell({ label, value }: { label: string; value: number }) {
  return (
    <View style={styles.statCell}>
      <Text style={styles.statValue}>{value}</Text>
      <Text style={styles.statLabel}>{label}</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: COLORS.background,
  },
  loadingContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  errorContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: SPACING.xxxl,
  },
  errorTitle: {
    fontFamily: FONTS.family.display,
    fontSize: 22,
    color: COLORS.text,
    marginTop: SPACING.lg,
    textAlign: 'center',
  },
  errorSubtitle: {
    fontFamily: FONTS.family.body,
    fontSize: 14,
    color: COLORS.textSecondary,
    textAlign: 'center',
    marginTop: SPACING.sm,
  },
  backBtn: {
    position: 'absolute',
    top: 56,
    left: 16,
    zIndex: 10,
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: 'rgba(0,0,0,0.5)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  scrollContent: {
    paddingBottom: SPACING.xxxl,
  },
  bannerContainer: {
    height: 140,
    backgroundColor: COLORS.backgroundSecondary,
  },
  banner: {
    width: '100%',
    height: '100%',
  },
  bannerPlaceholder: {
    width: '100%',
    height: '100%',
    backgroundColor: 'rgba(200,30,30,0.08)',
  },
  avatarRow: {
    paddingHorizontal: SPACING.xl,
    marginTop: -44,
    marginBottom: SPACING.md,
  },
  avatarWrapper: {
    alignSelf: 'flex-start',
  },
  avatar: {
    width: 88,
    height: 88,
    borderRadius: 44,
    borderWidth: 3,
    borderColor: COLORS.background,
  },
  avatarPlaceholder: {
    width: 88,
    height: 88,
    borderRadius: 44,
    backgroundColor: COLORS.backgroundSecondary,
    borderWidth: 3,
    borderColor: COLORS.background,
    alignItems: 'center',
    justifyContent: 'center',
  },
  profileInfo: {
    paddingHorizontal: SPACING.xl,
    gap: SPACING.sm,
    marginBottom: SPACING.md,
  },
  usernameRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  username: {
    fontFamily: FONTS.family.display,
    fontSize: 26,
    color: COLORS.text,
    fontWeight: '400',
  },
  ideologyBadge: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    alignSelf: 'flex-start',
    paddingHorizontal: 10,
    paddingVertical: 4,
    borderRadius: 4,
    borderWidth: 1,
    backgroundColor: 'rgba(0,0,0,0.3)',
  },
  ideologyBadgeText: {
    fontFamily: FONTS.family.mono,
    fontSize: 10,
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  ideologyDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
  },
  roleBadge: {
    alignSelf: 'flex-start',
    paddingHorizontal: 8,
    paddingVertical: 3,
    borderRadius: 4,
    backgroundColor: 'rgba(255,255,255,0.05)',
    borderWidth: 1,
    borderColor: COLORS.border,
  },
  roleBadgeText: {
    fontFamily: FONTS.family.mono,
    fontSize: 9,
    color: COLORS.textSecondary,
    letterSpacing: 2,
  },
  bioSection: {
    paddingHorizontal: SPACING.xl,
    marginBottom: SPACING.md,
  },
  bio: {
    fontFamily: FONTS.family.body,
    fontSize: 15,
    color: COLORS.text,
    lineHeight: 22,
  },
  statsRow: {
    flexDirection: 'row',
    alignItems: 'center',
    marginHorizontal: SPACING.xl,
    marginBottom: SPACING.xl,
    backgroundColor: COLORS.backgroundSecondary,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: COLORS.border,
    paddingVertical: SPACING.md,
  },
  statCell: {
    flex: 1,
    alignItems: 'center',
  },
  statValue: {
    fontFamily: FONTS.family.display,
    fontSize: 22,
    color: COLORS.text,
  },
  statLabel: {
    fontFamily: FONTS.family.mono,
    fontSize: 9,
    color: COLORS.textSecondary,
    textTransform: 'uppercase',
    letterSpacing: 1,
    marginTop: 2,
  },
  statDivider: {
    width: 1,
    height: 32,
    backgroundColor: COLORS.border,
  },
  metaSection: {
    paddingHorizontal: SPACING.xl,
    gap: SPACING.sm,
  },
  metaRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: SPACING.sm,
  },
  metaText: {
    fontFamily: FONTS.family.mono,
    fontSize: 11,
    color: COLORS.textSecondary,
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
});
