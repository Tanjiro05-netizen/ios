import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  Switch,
  ActivityIndicator,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { useNavigation } from '@react-navigation/native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';

import Constants from 'expo-constants';
import { useAuth } from '../hooks/useAuth';
import { api } from '../lib/api';
import { COLORS, SPACING, FONTS } from '../constants';
import { settingsStorage, AppSettings, DEFAULT_SETTINGS } from '../lib/storage';
import { haptics } from '../lib/haptics';
import toast from '../lib/toast';
import { RootStackParamList } from '../types';

type StackNav = NativeStackNavigationProp<RootStackParamList>;

interface SettingRowProps {
  icon: keyof typeof Ionicons.glyphMap;
  label: string;
  onPress?: () => void;
  hasToggle?: boolean;
  toggleValue?: boolean;
  onToggle?: (value: boolean) => void;
  destructive?: boolean;
}

function SettingRow({
  icon,
  label,
  onPress,
  hasToggle,
  toggleValue,
  onToggle,
  destructive,
}: SettingRowProps) {
  const handleToggle = (value: boolean) => {
    haptics.selection();
    onToggle?.(value);
  };

  return (
    <TouchableOpacity
      style={styles.settingRow}
      onPress={onPress}
      disabled={hasToggle}
      activeOpacity={hasToggle ? 1 : 0.7}
    >
      <View style={styles.settingLeft}>
        <Ionicons
          name={icon}
          size={22}
          color={destructive ? COLORS.primary : COLORS.text}
        />
        <Text style={[styles.settingLabel, destructive && styles.settingLabelDestructive]}>
          {label}
        </Text>
      </View>
      {hasToggle ? (
        <Switch
          value={toggleValue}
          onValueChange={handleToggle}
          trackColor={{ false: COLORS.border, true: COLORS.primary }}
          thumbColor={COLORS.text}
        />
      ) : (
        <Ionicons name="chevron-forward" size={20} color={COLORS.textTertiary} />
      )}
    </TouchableOpacity>
  );
}

export default function SettingsScreen() {
  const { signOut, user } = useAuth();
  const navigation = useNavigation<StackNav>();
  const [settings, setSettings] = useState<AppSettings>(DEFAULT_SETTINGS);
  const [loading, setLoading] = useState(true);

  // Load settings on mount
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

  // Update a setting and persist
  const updateSetting = async <K extends keyof AppSettings>(
    key: K,
    value: AppSettings[K]
  ) => {
    const newSettings = { ...settings, [key]: value };
    setSettings(newSettings);
    await settingsStorage.set({ [key]: value });
  };

  const handleSignOut = async () => {
    haptics.medium();
    if (user) {
      await api.deletePushToken(user.id);
    }
    await signOut();
  };

  const handleEditProfile = () => {
    navigation.navigate('Main', { screen: 'Profile' });
  };

  if (loading) {
    return (
      <View style={styles.loadingContainer}>
        <ActivityIndicator size="large" color={COLORS.primary} />
      </View>
    );
  }

  return (
    <ScrollView style={styles.container} contentContainerStyle={styles.content}>
      {/* Account */}
      <Text style={styles.sectionTitle}>ACCOUNT</Text>
      <View style={styles.section}>
        <SettingRow
          icon="person-outline"
          label="Edit Profile"
          onPress={handleEditProfile}
        />
        <SettingRow
          icon="lock-closed-outline"
          label="Change Password"
          onPress={() => navigation.navigate('ChangePassword')}
        />
        <SettingRow
          icon="mail-outline"
          label="Email Preferences"
          onPress={() => navigation.navigate('EmailPreferences')}
        />
      </View>

      {/* Appearance */}
      <Text style={styles.sectionTitle}>APPEARANCE</Text>
      <View style={styles.section}>
        <SettingRow
          icon="moon-outline"
          label="Dark Mode"
          hasToggle
          toggleValue={settings.darkMode}
          onToggle={(value) => updateSetting('darkMode', value)}
        />
        <SettingRow
          icon="play-circle-outline"
          label="Auto-play Videos"
          hasToggle
          toggleValue={settings.autoPlayVideos}
          onToggle={(value) => updateSetting('autoPlayVideos', value)}
        />
        <SettingRow
          icon="flag-outline"
          label="Show Ideology Badges"
          hasToggle
          toggleValue={settings.showIdeologyBadges}
          onToggle={(value) => updateSetting('showIdeologyBadges', value)}
        />
      </View>

      {/* Notifications */}
      <Text style={styles.sectionTitle}>NOTIFICATIONS</Text>
      <View style={styles.section}>
        <SettingRow
          icon="notifications-outline"
          label="Push Notifications"
          hasToggle
          toggleValue={settings.pushNotifications}
          onToggle={(value) => updateSetting('pushNotifications', value)}
        />
        <SettingRow
          icon="mail-outline"
          label="Email Notifications"
          hasToggle
          toggleValue={settings.emailNotifications}
          onToggle={(value) => updateSetting('emailNotifications', value)}
        />
      </View>

      {/* Data */}
      <Text style={styles.sectionTitle}>DATA & PRIVACY</Text>
      <View style={styles.section}>
        <SettingRow
          icon="cellular-outline"
          label="Data Saver Mode"
          hasToggle
          toggleValue={settings.dataSaver}
          onToggle={(value) => updateSetting('dataSaver', value)}
        />
      </View>

      {/* About */}
      <Text style={styles.sectionTitle}>ABOUT</Text>
      <View style={styles.section}>
        <SettingRow
          icon="information-circle-outline"
          label="About Marxist Library"
          onPress={() => toast.info('Marxist Library', 'A platform for accessing dialectical texts and audiobooks.')}
        />
        <SettingRow
          icon="document-text-outline"
          label="Terms of Service"
          onPress={() => navigation.navigate('Legal', { type: 'terms' })}
        />
        <SettingRow
          icon="shield-checkmark-outline"
          label="Privacy Policy"
          onPress={() => navigation.navigate('Legal', { type: 'privacy' })}
        />
        <SettingRow
          icon="people-outline"
          label="Community Guidelines"
          onPress={() => navigation.navigate('Legal', { type: 'guidelines' })}
        />
      </View>

      {/* Sign out */}
      <View style={[styles.section, styles.sectionLast]}>
        <SettingRow
          icon="log-out-outline"
          label="Sign Out"
          onPress={handleSignOut}
          destructive
        />
      </View>

      {/* Version */}
      <Text style={styles.version}>
        Version {Constants.expoConfig?.version ?? '1.0.0'} ({Constants.expoConfig?.android?.versionCode ?? 1})
      </Text>
    </ScrollView>
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
    backgroundColor: COLORS.background,
  },
  content: {
    paddingHorizontal: SPACING.lg,
    paddingBottom: SPACING.xxxl,
  },
  sectionTitle: {
    color: COLORS.textSecondary,
    fontSize: FONTS.sizes.xs,
    fontWeight: '600',
    letterSpacing: 1,
    marginTop: SPACING.xl,
    marginBottom: SPACING.sm,
    marginLeft: SPACING.sm,
  },
  section: {
    backgroundColor: COLORS.backgroundSecondary,
    borderRadius: 12,
    overflow: 'hidden',
  },
  sectionLast: {
    marginTop: SPACING.xl,
  },
  settingRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: SPACING.md,
    paddingVertical: SPACING.md,
    borderBottomWidth: 0.5,
    borderBottomColor: COLORS.border,
  },
  settingLeft: {
    flexDirection: 'row',
    alignItems: 'center',
  },
  settingLabel: {
    color: COLORS.text,
    fontSize: FONTS.sizes.md,
    marginLeft: SPACING.md,
  },
  settingLabelDestructive: {
    color: COLORS.primary,
  },
  version: {
    color: COLORS.textTertiary,
    fontSize: FONTS.sizes.sm,
    textAlign: 'center',
    marginTop: SPACING.xl,
  },
});
