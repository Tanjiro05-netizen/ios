import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  Switch,
  ActivityIndicator,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';

import { COLORS, SPACING, FONTS } from '../constants';
import { settingsStorage, AppSettings, DEFAULT_SETTINGS } from '../lib/storage';
import { haptics } from '../lib/haptics';

interface PrefRowProps {
  icon: keyof typeof Ionicons.glyphMap;
  label: string;
  description: string;
  value: boolean;
  onToggle: (value: boolean) => void;
}

function PrefRow({ icon, label, description, value, onToggle }: PrefRowProps) {
  const handleToggle = (v: boolean) => {
    haptics.selection();
    onToggle(v);
  };

  return (
    <View style={styles.prefRow}>
      <View style={styles.prefLeft}>
        <Ionicons name={icon} size={20} color={COLORS.textSecondary} />
        <View style={styles.prefTextCol}>
          <Text style={styles.prefLabel}>{label}</Text>
          <Text style={styles.prefDescription}>{description}</Text>
        </View>
      </View>
      <Switch
        value={value}
        onValueChange={handleToggle}
        trackColor={{ false: COLORS.border, true: COLORS.primary }}
        thumbColor={COLORS.text}
      />
    </View>
  );
}

export default function EmailPreferencesScreen() {
  const [settings, setSettings] = useState<AppSettings>(DEFAULT_SETTINGS);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    loadSettings();
  }, []);

  const loadSettings = async () => {
    try {
      const saved = await settingsStorage.get();
      setSettings(saved);
    } catch (error) {
      console.error('Error loading settings:', error);
    } finally {
      setLoading(false);
    }
  };

  const updateSetting = async <K extends keyof AppSettings>(
    key: K,
    value: AppSettings[K]
  ) => {
    const newSettings = { ...settings, [key]: value };
    setSettings(newSettings);
    await settingsStorage.set({ [key]: value });
  };

  if (loading) {
    return (
      <SafeAreaView style={styles.container} edges={['bottom']}>
        <View style={styles.loadingContainer}>
          <ActivityIndicator size="large" color={COLORS.primary} />
        </View>
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.container} edges={['bottom']}>
      <ScrollView style={styles.scrollView} contentContainerStyle={styles.scrollContent}>
        <View style={styles.infoBox}>
          <Ionicons name="mail-outline" size={20} color={COLORS.textSecondary} />
          <Text style={styles.infoText}>
            Choose which emails you'd like to receive. You can change these at any time.
          </Text>
        </View>

        <Text style={styles.sectionTitle}>ACTIVITY</Text>
        <View style={styles.section}>
          <PrefRow
            icon="chatbubble-outline"
            label="Comment Replies"
            description="When someone replies to your comment"
            value={settings.emailCommentReplies}
            onToggle={(v) => updateSetting('emailCommentReplies', v)}
          />
          <PrefRow
            icon="pulse-outline"
            label="Thread Activity"
            description="Updates on threads you've posted or interacted with"
            value={settings.emailThreadActivity}
            onToggle={(v) => updateSetting('emailThreadActivity', v)}
          />
        </View>

        <Text style={styles.sectionTitle}>DIGEST</Text>
        <View style={styles.section}>
          <PrefRow
            icon="calendar-outline"
            label="Weekly Digest"
            description="A summary of top posts and activity each week"
            value={settings.emailWeeklyDigest}
            onToggle={(v) => updateSetting('emailWeeklyDigest', v)}
          />
        </View>

        <Text style={styles.sectionTitle}>MARKETING</Text>
        <View style={styles.section}>
          <PrefRow
            icon="megaphone-outline"
            label="Announcements"
            description="New features, events, and platform updates"
            value={settings.emailMarketingEnabled}
            onToggle={(v) => updateSetting('emailMarketingEnabled', v)}
          />
        </View>
      </ScrollView>
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
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    paddingHorizontal: SPACING.lg,
    paddingTop: SPACING.xl,
    paddingBottom: SPACING.xxxl,
  },
  infoBox: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: SPACING.sm,
    backgroundColor: COLORS.backgroundSecondary,
    borderRadius: 12,
    padding: SPACING.md,
    marginBottom: SPACING.xl,
    borderWidth: 1,
    borderColor: COLORS.border,
  },
  infoText: {
    flex: 1,
    fontFamily: FONTS.family.body,
    fontSize: FONTS.sizes.sm,
    color: COLORS.textSecondary,
    lineHeight: 20,
  },
  sectionTitle: {
    color: COLORS.textSecondary,
    fontSize: FONTS.sizes.xs,
    fontWeight: '600',
    letterSpacing: 1,
    marginTop: SPACING.lg,
    marginBottom: SPACING.sm,
    marginLeft: SPACING.sm,
  },
  section: {
    backgroundColor: COLORS.backgroundSecondary,
    borderRadius: 12,
    overflow: 'hidden',
  },
  prefRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: SPACING.md,
    paddingVertical: SPACING.md,
    borderBottomWidth: 0.5,
    borderBottomColor: COLORS.border,
  },
  prefLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    flex: 1,
    marginRight: SPACING.md,
    gap: SPACING.sm,
  },
  prefTextCol: {
    flex: 1,
  },
  prefLabel: {
    color: COLORS.text,
    fontSize: FONTS.sizes.md,
    marginBottom: 2,
  },
  prefDescription: {
    color: COLORS.textTertiary,
    fontSize: FONTS.sizes.xs,
    lineHeight: 16,
  },
});
