import React, { useState, useEffect } from 'react';
import {
  View,
  Text,
  StyleSheet,
  ScrollView,
  TouchableOpacity,
  Image,
  TextInput,
  ActivityIndicator,
  Alert,
  KeyboardAvoidingView,
  Platform,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import * as ImagePicker from 'expo-image-picker';
import { useNavigation } from '@react-navigation/native';
import { StackNavigationProp } from '@react-navigation/stack';

import { useAuth } from '../hooks/useAuth';
import { api } from '../lib/api';
import { supabase } from '../lib/supabase';
import { COLORS, FONTS, SPACING, IDEOLOGIES, LIMITS, getIdeologyColor, getIdeologyAbbrev } from '../constants';
import { RootStackParamList, Profile } from '../types';
import toast from '../lib/toast';

type NavigationProp = StackNavigationProp<RootStackParamList>;

export default function ProfileScreen() {
  const navigation = useNavigation<NavigationProp>();
  const { user, profile, refreshProfile, isGuest } = useAuth();

  const [editing, setEditing] = useState(false);
  const [saving, setSaving] = useState(false);
  const [uploading, setUploading] = useState(false);

  const [username, setUsername] = useState('');
  const [bio, setBio] = useState('');
  const [ideology, setIdeology] = useState<string>('Unaffiliated');
  const [showIdeologyPicker, setShowIdeologyPicker] = useState(false);

  useEffect(() => {
    if (profile) {
      setUsername(profile.username || '');
      setBio(profile.bio || '');
      setIdeology(profile.ideology || 'Unaffiliated');
    }
  }, [profile]);

  const handleStartEdit = () => {
    setEditing(true);
    setShowIdeologyPicker(false);
  };

  const handleCancelEdit = () => {
    if (profile) {
      setUsername(profile.username || '');
      setBio(profile.bio || '');
      setIdeology(profile.ideology || 'Unaffiliated');
    }
    setEditing(false);
    setShowIdeologyPicker(false);
  };

  const handleSave = async () => {
    if (!user) return;
    if (username.trim().length < LIMITS.USERNAME_MIN) {
      Alert.alert('Invalid Username', `Username must be at least ${LIMITS.USERNAME_MIN} characters.`);
      return;
    }
    if (username.trim().length > LIMITS.USERNAME_MAX) {
      Alert.alert('Invalid Username', `Username must be at most ${LIMITS.USERNAME_MAX} characters.`);
      return;
    }

    setSaving(true);
    try {
      await api.updateProfile(user.id, {
        username: username.trim(),
        bio: bio.trim(),
        ideology,
      });
      await refreshProfile();
      setEditing(false);
      toast.success('Profile updated');
    } catch (err: any) {
      Alert.alert('Error', err?.message || 'Could not save profile.');
    } finally {
      setSaving(false);
    }
  };

  const handlePickAvatar = async () => {
    if (!user) return;
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ['images'],
      allowsEditing: true,
      aspect: [1, 1],
      quality: 0.8,
    });
    if (result.canceled) return;
    await uploadImage(result.assets[0].uri, 'avatar');
  };

  const handlePickBanner = async () => {
    if (!user) return;
    const result = await ImagePicker.launchImageLibraryAsync({
      mediaTypes: ['images'],
      allowsEditing: true,
      aspect: [3, 1],
      quality: 0.8,
    });
    if (result.canceled) return;
    await uploadImage(result.assets[0].uri, 'banner');
  };

  const uploadImage = async (uri: string, type: 'avatar' | 'banner') => {
    if (!user) return;
    setUploading(true);
    try {
      const ext = uri.split('.').pop() || 'jpg';
      const fileName = `${user.id}_${type}_${Date.now()}.${ext}`;
      const bucket = 'avatars';

      const response = await fetch(uri);
      const blob = await response.blob();
      const arrayBuffer = await new Response(blob).arrayBuffer();

      const { error: uploadError } = await supabase.storage
        .from(bucket)
        .upload(fileName, arrayBuffer, { contentType: `image/${ext}`, upsert: true });

      if (uploadError) throw uploadError;

      const { data } = supabase.storage.from(bucket).getPublicUrl(fileName);
      const publicUrl = data.publicUrl;

      const updateField = type === 'avatar' ? { avatar_url: publicUrl } : { banner_url: publicUrl };
      await api.updateProfile(user.id, updateField);
      await refreshProfile();
      toast.success(type === 'avatar' ? 'Avatar updated' : 'Banner updated');
    } catch (err: any) {
      Alert.alert('Upload Failed', err?.message || 'Could not upload image.');
    } finally {
      setUploading(false);
    }
  };

  if (isGuest) {
    return (
      <SafeAreaView style={styles.container} edges={['top']}>
        <View style={styles.titleBar}>
          <Text style={styles.screenTitle}>Profile</Text>
        </View>
        <View style={styles.guestContainer}>
          <Ionicons name="person-circle-outline" size={80} color={COLORS.textTertiary} />
          <Text style={styles.guestTitle}>Browsing as Guest</Text>
          <Text style={styles.guestSubtitle}>Create an account to have a profile.</Text>
        </View>
      </SafeAreaView>
    );
  }

  if (!profile) {
    return (
      <SafeAreaView style={styles.container} edges={['top']}>
        <View style={styles.loadingContainer}>
          <ActivityIndicator size="large" color={COLORS.primary} />
        </View>
      </SafeAreaView>
    );
  }

  const ideologyColor = getIdeologyColor(profile.ideology);
  const ideologyAbbrev = getIdeologyAbbrev(profile.ideology);

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <KeyboardAvoidingView
        style={{ flex: 1 }}
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      >
        <ScrollView contentContainerStyle={styles.scrollContent}>
          {/* Banner */}
          <TouchableOpacity
            style={styles.bannerContainer}
            onPress={editing ? handlePickBanner : undefined}
            activeOpacity={editing ? 0.7 : 1}
          >
            {profile.banner_url ? (
              <Image source={{ uri: profile.banner_url }} style={styles.banner} />
            ) : (
              <View style={styles.bannerPlaceholder} />
            )}
            {editing && (
              <View style={styles.bannerEditOverlay}>
                <Ionicons name="camera" size={24} color="#fff" />
                <Text style={styles.editOverlayText}>Change Banner</Text>
              </View>
            )}
          </TouchableOpacity>

          {/* Avatar */}
          <View style={styles.avatarRow}>
            <TouchableOpacity
              style={styles.avatarWrapper}
              onPress={editing ? handlePickAvatar : undefined}
              activeOpacity={editing ? 0.7 : 1}
            >
              {profile.avatar_url ? (
                <Image source={{ uri: profile.avatar_url }} style={styles.avatar} />
              ) : (
                <View style={[styles.avatarPlaceholder]}>
                  <Ionicons name="person" size={36} color={COLORS.textTertiary} />
                </View>
              )}
              {editing && (
                <View style={styles.avatarEditOverlay}>
                  <Ionicons name="camera" size={16} color="#fff" />
                </View>
              )}
              {uploading && (
                <View style={styles.uploadingOverlay}>
                  <ActivityIndicator size="small" color="#fff" />
                </View>
              )}
            </TouchableOpacity>

            <View style={styles.headerActions}>
              {!editing ? (
                <>
                  <TouchableOpacity
                    style={styles.editBtn}
                    onPress={handleStartEdit}
                  >
                    <Ionicons name="pencil-outline" size={16} color={COLORS.text} />
                    <Text style={styles.editBtnText}>Edit Profile</Text>
                  </TouchableOpacity>
                  <TouchableOpacity
                    style={styles.settingsBtn}
                    onPress={() => navigation.navigate('Settings')}
                  >
                    <Ionicons name="settings-outline" size={20} color={COLORS.textSecondary} />
                  </TouchableOpacity>
                </>
              ) : (
                <>
                  <TouchableOpacity
                    style={[styles.editBtn, styles.saveBtn]}
                    onPress={handleSave}
                    disabled={saving}
                  >
                    {saving ? (
                      <ActivityIndicator size="small" color="#fff" />
                    ) : (
                      <Text style={[styles.editBtnText, { color: '#fff' }]}>Save</Text>
                    )}
                  </TouchableOpacity>
                  <TouchableOpacity
                    style={styles.cancelBtn}
                    onPress={handleCancelEdit}
                    disabled={saving}
                  >
                    <Text style={styles.cancelBtnText}>Cancel</Text>
                  </TouchableOpacity>
                </>
              )}
            </View>
          </View>

          {/* Username & Ideology */}
          <View style={styles.profileInfo}>
            {editing ? (
              <TextInput
                style={styles.usernameInput}
                value={username}
                onChangeText={setUsername}
                placeholder="Username"
                placeholderTextColor={COLORS.textTertiary}
                maxLength={LIMITS.USERNAME_MAX}
                autoCapitalize="none"
              />
            ) : (
              <View style={styles.usernameRow}>
                <Text style={styles.username}>{profile.username || 'Anonymous'}</Text>
                {profile.is_certified && (
                  <Ionicons name="checkmark-circle" size={18} color={COLORS.primary} />
                )}
              </View>
            )}

            {/* Ideology badge */}
            {editing ? (
              <>
                <TouchableOpacity
                  style={[styles.ideologyBadge, { borderColor: ideologyColor }]}
                  onPress={() => setShowIdeologyPicker(v => !v)}
                >
                  <Text style={[styles.ideologyBadgeText, { color: ideologyColor }]}>
                    {ideology || 'Select ideology'}
                  </Text>
                  <Ionicons name="chevron-down" size={12} color={ideologyColor} />
                </TouchableOpacity>
                {showIdeologyPicker && (
                  <View style={styles.ideologyPicker}>
                    {IDEOLOGIES.map(item => (
                      <TouchableOpacity
                        key={item.value}
                        style={[
                          styles.ideologyOption,
                          ideology === item.value && styles.ideologyOptionSelected,
                        ]}
                        onPress={() => {
                          setIdeology(item.value);
                          setShowIdeologyPicker(false);
                        }}
                      >
                        <View style={[styles.ideologyDot, { backgroundColor: item.color }]} />
                        <Text style={styles.ideologyOptionText}>{item.label}</Text>
                      </TouchableOpacity>
                    ))}
                  </View>
                )}
              </>
            ) : (
              profile.ideology && profile.ideology !== 'Unaffiliated' && (
                <View style={[styles.ideologyBadge, { borderColor: ideologyColor }]}>
                  <View style={[styles.ideologyDot, { backgroundColor: ideologyColor }]} />
                  <Text style={[styles.ideologyBadgeText, { color: ideologyColor }]}>
                    {ideologyAbbrev || profile.ideology}
                  </Text>
                </View>
              )
            )}

            {/* Role badge */}
            {profile.role && profile.role !== 'user' && (
              <View style={styles.roleBadge}>
                <Text style={styles.roleBadgeText}>{profile.role.toUpperCase()}</Text>
              </View>
            )}
          </View>

          {/* Bio */}
          <View style={styles.bioSection}>
            {editing ? (
              <>
                <TextInput
                  style={styles.bioInput}
                  value={bio}
                  onChangeText={setBio}
                  placeholder="Write a bio..."
                  placeholderTextColor={COLORS.textTertiary}
                  multiline
                  maxLength={LIMITS.BIO_MAX}
                  textAlignVertical="top"
                />
                <Text style={styles.charCount}>
                  {bio.length}/{LIMITS.BIO_MAX}
                </Text>
              </>
            ) : (
              profile.bio ? (
                <Text style={styles.bio}>{profile.bio}</Text>
              ) : (
                <Text style={styles.bioPhoeholder}>No bio yet. Tap Edit Profile to add one.</Text>
              )
            )}
          </View>

          {/* Divider */}
          <View style={styles.divider} />

          {/* Meta info */}
          <View style={styles.metaSection}>
            {profile.website ? (
              <View style={styles.metaRow}>
                <Ionicons name="globe-outline" size={14} color={COLORS.textSecondary} />
                <Text style={styles.metaText}>{profile.website}</Text>
              </View>
            ) : null}
            {profile.updated_at ? (
              <View style={styles.metaRow}>
                <Ionicons name="calendar-outline" size={14} color={COLORS.textSecondary} />
                <Text style={styles.metaText}>
                  Joined {new Date(profile.updated_at).toLocaleDateString('en-US', { month: 'long', year: 'numeric' })}
                </Text>
              </View>
            ) : null}
          </View>
        </ScrollView>
      </KeyboardAvoidingView>
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
    alignItems: 'center',
    justifyContent: 'center',
  },
  titleBar: {
    paddingHorizontal: 24,
    paddingVertical: 16,
  },
  screenTitle: {
    fontFamily: FONTS.family.display,
    fontSize: 38,
    fontWeight: '400',
    color: COLORS.text,
    letterSpacing: -1,
  },
  scrollContent: {
    paddingBottom: SPACING.xxxl,
  },
  bannerContainer: {
    height: 140,
    position: 'relative',
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
  bannerEditOverlay: {
    ...StyleSheet.absoluteFillObject,
    backgroundColor: 'rgba(0,0,0,0.5)',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 4,
  },
  editOverlayText: {
    fontFamily: FONTS.family.mono,
    fontSize: 11,
    color: '#fff',
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  avatarRow: {
    flexDirection: 'row',
    alignItems: 'flex-end',
    paddingHorizontal: SPACING.xl,
    marginTop: -40,
    marginBottom: SPACING.md,
    justifyContent: 'space-between',
  },
  avatarWrapper: {
    position: 'relative',
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
  avatarEditOverlay: {
    position: 'absolute',
    bottom: 0,
    right: 0,
    width: 28,
    height: 28,
    borderRadius: 14,
    backgroundColor: COLORS.primary,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 2,
    borderColor: COLORS.background,
  },
  uploadingOverlay: {
    ...StyleSheet.absoluteFillObject,
    borderRadius: 44,
    backgroundColor: 'rgba(0,0,0,0.5)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  headerActions: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: SPACING.sm,
  },
  editBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 20,
    borderWidth: 1,
    borderColor: COLORS.borderLight,
    backgroundColor: COLORS.backgroundSecondary,
  },
  saveBtn: {
    backgroundColor: COLORS.primary,
    borderColor: COLORS.primary,
  },
  editBtnText: {
    fontFamily: FONTS.family.mono,
    fontSize: 11,
    color: COLORS.text,
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  cancelBtn: {
    paddingHorizontal: 14,
    paddingVertical: 8,
    borderRadius: 20,
    borderWidth: 1,
    borderColor: COLORS.border,
  },
  cancelBtnText: {
    fontFamily: FONTS.family.mono,
    fontSize: 11,
    color: COLORS.textSecondary,
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  settingsBtn: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: COLORS.backgroundSecondary,
    alignItems: 'center',
    justifyContent: 'center',
    borderWidth: 1,
    borderColor: COLORS.border,
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
  usernameInput: {
    fontFamily: FONTS.family.display,
    fontSize: 26,
    color: COLORS.text,
    borderBottomWidth: 1,
    borderBottomColor: COLORS.borderLight,
    paddingBottom: 4,
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
  ideologyPicker: {
    backgroundColor: COLORS.card,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: COLORS.borderLight,
    overflow: 'hidden',
    marginTop: 4,
  },
  ideologyOption: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 10,
    paddingHorizontal: SPACING.md,
    paddingVertical: 12,
    borderBottomWidth: 1,
    borderBottomColor: COLORS.border,
  },
  ideologyOptionSelected: {
    backgroundColor: COLORS.cardHover,
  },
  ideologyOptionText: {
    fontFamily: FONTS.family.mono,
    fontSize: 12,
    color: COLORS.text,
    textTransform: 'uppercase',
    letterSpacing: 1,
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
  bioPhoeholder: {
    fontFamily: FONTS.family.body,
    fontSize: 14,
    color: COLORS.textTertiary,
    fontStyle: 'italic',
  },
  bioInput: {
    fontFamily: FONTS.family.body,
    fontSize: 15,
    color: COLORS.text,
    borderWidth: 1,
    borderColor: COLORS.borderLight,
    borderRadius: 8,
    padding: SPACING.md,
    minHeight: 80,
    lineHeight: 22,
  },
  charCount: {
    fontFamily: FONTS.family.mono,
    fontSize: 10,
    color: COLORS.textTertiary,
    textAlign: 'right',
    marginTop: 4,
    letterSpacing: 1,
  },
  divider: {
    height: 1,
    backgroundColor: COLORS.border,
    marginHorizontal: SPACING.xl,
    marginBottom: SPACING.md,
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
  guestContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: SPACING.xxxl,
  },
  guestTitle: {
    fontFamily: FONTS.family.display,
    fontSize: 24,
    color: COLORS.text,
    marginTop: SPACING.lg,
    textAlign: 'center',
  },
  guestSubtitle: {
    fontFamily: FONTS.family.body,
    fontSize: 14,
    color: COLORS.textSecondary,
    textAlign: 'center',
    marginTop: SPACING.sm,
    lineHeight: 20,
  },
});
