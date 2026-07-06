import React, { useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TextInput,
  TouchableOpacity,
  ScrollView,
  KeyboardAvoidingView,
  Platform,
  ActivityIndicator,
  Alert,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { useNavigation } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';

import { NativeStackNavigationProp } from '@react-navigation/native-stack';
import { useAuth } from '../hooks/useAuth';
import { supabase } from '../lib/supabase';
import { COLORS, SPACING, FONTS, IDEOLOGIES } from '../constants';
import { RootStackParamList } from '../types';

type NavigationProp = NativeStackNavigationProp<RootStackParamList>;

export default function SignUpScreen() {
  const navigation = useNavigation<NavigationProp>();
  const { signUp, browseAsGuest } = useAuth();

  const [username, setUsername] = useState('');
  const [inviteCode, setInviteCode] = useState('');
  const [email, setEmail] = useState('');
  const [password, setPassword] = useState('');
  const [confirmPassword, setConfirmPassword] = useState('');
  const [ideology, setIdeology] = useState('');
  const [showIdeologyPicker, setShowIdeologyPicker] = useState(false);
  const [agreedToTerms, setAgreedToTerms] = useState(false);
  const [loading, setLoading] = useState(false);
  const [guestLoading, setGuestLoading] = useState(false);

  const isValid =
    username.length >= 3 &&
    inviteCode.length > 0 &&
    email.includes('@') &&
    password.length >= 8 &&
    password === confirmPassword &&
    agreedToTerms;

  const handleSignUp = async () => {
    if (!isValid) return;

    setLoading(true);
    try {
      // Pre-validate invite code before signup
      const { data: validation, error: valError } = await supabase.rpc('validate_invite_code', {
        p_code: inviteCode.toUpperCase(),
      });
      if (valError || !validation?.valid) {
        Alert.alert('Invalid Code', 'This invite code is invalid or has already been used.');
        setLoading(false);
        return;
      }

      const { error } = await signUp(email, password, {
        inviteCode: inviteCode.toUpperCase(),
        username,
        ideology: ideology || undefined,
      });
      if (error) {
        Alert.alert('Sign Up Failed', error.message);
      } else {
        Alert.alert(
          'Account Created',
          'Please check your email to verify your account.',
          [{ text: 'OK', onPress: () => navigation.goBack() }]
        );
      }
    } catch (err) {
      Alert.alert('Error', 'An unexpected error occurred.');
    } finally {
      setLoading(false);
    }
  };

  const handleGuestBrowse = async () => {
    setGuestLoading(true);
    try {
      await browseAsGuest();
    } catch (err) {
      Alert.alert('Error', 'Could not start guest session.');
    } finally {
      setGuestLoading(false);
    }
  };

  return (
    <SafeAreaView style={styles.container} edges={['bottom']}>
      <KeyboardAvoidingView
        style={styles.keyboardView}
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      >
        <ScrollView
          style={styles.scrollView}
          contentContainerStyle={styles.scrollContent}
          keyboardShouldPersistTaps="handled"
        >
          {/* Header */}
          <View style={styles.header}>
            <Text style={styles.title}>Create Account</Text>
            <Text style={styles.subtitle}>Join the collective</Text>
          </View>

          {/* Form */}
          <View style={styles.form}>
            {/* Username */}
            <View style={styles.inputGroup}>
              <Text style={styles.label}>Username</Text>
              <View style={styles.inputContainer}>
                <TextInput
                  style={styles.input}
                  placeholder="Choose a username"
                  placeholderTextColor={COLORS.textTertiary}
                  value={username}
                  onChangeText={setUsername}
                  autoCapitalize="none"
                  maxLength={30}
                />
              </View>
              {username.length > 0 && username.length < 3 && (
                <Text style={styles.errorText}>Username must be at least 3 characters</Text>
              )}
            </View>

            {/* Invite Code */}
            <View style={styles.inputGroup}>
              <Text style={styles.label}>Invite Code (Required for Beta)</Text>
              <View style={styles.inputContainer}>
                <TextInput
                  style={styles.input}
                  placeholder="Enter your invite code"
                  placeholderTextColor={COLORS.textTertiary}
                  value={inviteCode}
                  onChangeText={setInviteCode}
                  autoCapitalize="characters"
                  maxLength={10}
                />
              </View>
            </View>

            {/* Email */}
            <View style={styles.inputGroup}>
              <Text style={styles.label}>Email</Text>
              <View style={styles.inputContainer}>
                <TextInput
                  style={styles.input}
                  placeholder="your@email.com"
                  placeholderTextColor={COLORS.textTertiary}
                  value={email}
                  onChangeText={setEmail}
                  autoCapitalize="none"
                  keyboardType="email-address"
                  autoComplete="email"
                />
              </View>
            </View>

            {/* Password */}
            <View style={styles.inputGroup}>
              <Text style={styles.label}>Password</Text>
              <View style={styles.inputContainer}>
                <TextInput
                  style={styles.input}
                  placeholder="Min 8 characters"
                  placeholderTextColor={COLORS.textTertiary}
                  value={password}
                  onChangeText={setPassword}
                  secureTextEntry
                />
              </View>
            </View>

            {/* Confirm Password */}
            <View style={styles.inputGroup}>
              <Text style={styles.label}>Confirm Password</Text>
              <View style={styles.inputContainer}>
                <TextInput
                  style={styles.input}
                  placeholder="Repeat password"
                  placeholderTextColor={COLORS.textTertiary}
                  value={confirmPassword}
                  onChangeText={setConfirmPassword}
                  secureTextEntry
                />
              </View>
              {confirmPassword && password !== confirmPassword && (
                <Text style={styles.errorText}>Passwords don't match</Text>
              )}
            </View>

            {/* Ideology (optional) */}
            <View style={styles.inputGroup}>
              <Text style={styles.label}>Ideology (optional)</Text>
              <TouchableOpacity
                style={styles.inputContainer}
                onPress={() => setShowIdeologyPicker(!showIdeologyPicker)}
              >
                <Text style={ideology ? styles.input : styles.placeholder}>
                  {ideology || 'Select...'}
                </Text>
                <Ionicons
                  name={showIdeologyPicker ? 'chevron-up' : 'chevron-down'}
                  size={20}
                  color={COLORS.textSecondary}
                />
              </TouchableOpacity>

              {showIdeologyPicker && (
                <View style={styles.picker}>
                  {IDEOLOGIES.map((item) => (
                    <TouchableOpacity
                      key={item.value}
                      style={styles.pickerOption}
                      onPress={() => {
                        setIdeology(item.value);
                        setShowIdeologyPicker(false);
                      }}
                    >
                      <View style={[styles.ideologyDot, { backgroundColor: item.color }]} />
                      <Text style={styles.pickerOptionText}>{item.label}</Text>
                      {ideology === item.value && (
                        <Ionicons name="checkmark" size={18} color={COLORS.primary} />
                      )}
                    </TouchableOpacity>
                  ))}
                </View>
              )}
            </View>

            {/* Terms checkbox */}
            <TouchableOpacity
              style={styles.checkboxRow}
              onPress={() => setAgreedToTerms(!agreedToTerms)}
            >
              <View style={[styles.checkbox, agreedToTerms && styles.checkboxChecked]}>
                {agreedToTerms && <Ionicons name="checkmark" size={16} color={COLORS.text} />}
              </View>
              <Text style={styles.checkboxText}>
                I agree to the{' '}
                <Text style={styles.link} onPress={() => navigation.navigate('Legal', { type: 'terms' })}>Terms of Service</Text>
                {' '}and{' '}
                <Text style={styles.link} onPress={() => navigation.navigate('Legal', { type: 'guidelines' })}>Community Guidelines</Text>
              </Text>
            </TouchableOpacity>

            {/* Submit button */}
            <TouchableOpacity
              style={[styles.submitButton, !isValid && styles.submitButtonDisabled]}
              onPress={handleSignUp}
              disabled={!isValid || loading}
            >
              {loading ? (
                <ActivityIndicator color={COLORS.text} />
              ) : (
                <Text style={styles.submitButtonText}>Create Account</Text>
              )}
            </TouchableOpacity>

            {/* Divider */}
            <View style={styles.divider}>
              <View style={styles.dividerLine} />
              <Text style={styles.dividerText}>or skip for now</Text>
              <View style={styles.dividerLine} />
            </View>

            {/* Guest Browse */}
            <TouchableOpacity
              style={[styles.guestButton, guestLoading && styles.guestButtonDisabled]}
              onPress={handleGuestBrowse}
              disabled={guestLoading}
            >
              {guestLoading ? (
                <ActivityIndicator color={COLORS.textSecondary} size="small" />
              ) : (
                <>
                  <Text style={styles.guestIcon}>👤</Text>
                  <Text style={styles.guestButtonText}>Browse as Guest</Text>
                </>
              )}
            </TouchableOpacity>
            <Text style={styles.guestNote}>
              You'll get a random username like "BraveLion42"
            </Text>
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
  keyboardView: {
    flex: 1,
  },
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    paddingHorizontal: SPACING.xl,
    paddingBottom: SPACING.xxxl,
  },
  header: {
    marginTop: SPACING.xl,
    marginBottom: SPACING.xxl,
  },
  title: {
    fontSize: FONTS.sizes.xxxl,
    fontWeight: '700',
    color: COLORS.text,
  },
  subtitle: {
    fontSize: FONTS.sizes.md,
    color: COLORS.textSecondary,
    marginTop: SPACING.sm,
  },
  form: {},
  inputGroup: {
    marginBottom: SPACING.lg,
  },
  label: {
    color: COLORS.textSecondary,
    fontSize: FONTS.sizes.sm,
    fontWeight: '500',
    marginBottom: SPACING.sm,
  },
  inputContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: COLORS.card,
    borderRadius: 12,
    paddingHorizontal: SPACING.md,
  },
  input: {
    flex: 1,
    color: COLORS.text,
    fontSize: FONTS.sizes.md,
    paddingVertical: SPACING.md,
  },
  placeholder: {
    flex: 1,
    color: COLORS.textTertiary,
    fontSize: FONTS.sizes.md,
    paddingVertical: SPACING.md,
  },
  errorText: {
    color: COLORS.primary,
    fontSize: FONTS.sizes.xs,
    marginTop: SPACING.xs,
  },
  picker: {
    backgroundColor: COLORS.card,
    borderRadius: 12,
    marginTop: SPACING.sm,
    overflow: 'hidden',
  },
  pickerOption: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: SPACING.md,
    paddingVertical: SPACING.md,
    borderBottomWidth: 0.5,
    borderBottomColor: COLORS.border,
  },
  ideologyDot: {
    width: 12,
    height: 12,
    borderRadius: 6,
    marginRight: SPACING.sm,
  },
  pickerOptionText: {
    flex: 1,
    color: COLORS.text,
    fontSize: FONTS.sizes.md,
  },
  checkboxRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    marginVertical: SPACING.lg,
  },
  checkbox: {
    width: 22,
    height: 22,
    borderRadius: 6,
    borderWidth: 2,
    borderColor: COLORS.border,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: SPACING.sm,
  },
  checkboxChecked: {
    backgroundColor: COLORS.primary,
    borderColor: COLORS.primary,
  },
  checkboxText: {
    flex: 1,
    color: COLORS.textSecondary,
    fontSize: FONTS.sizes.sm,
    lineHeight: 20,
  },
  link: {
    color: COLORS.blue,
  },
  submitButton: {
    backgroundColor: COLORS.primary,
    borderRadius: 12,
    paddingVertical: SPACING.lg,
    alignItems: 'center',
    marginTop: SPACING.md,
  },
  submitButtonDisabled: {
    backgroundColor: COLORS.textTertiary,
  },
  submitButtonText: {
    color: COLORS.text,
    fontSize: FONTS.sizes.md,
    fontWeight: '600',
  },
  divider: {
    flexDirection: 'row',
    alignItems: 'center',
    marginVertical: SPACING.xl,
  },
  dividerLine: {
    flex: 1,
    height: 1,
    backgroundColor: COLORS.border,
  },
  dividerText: {
    color: COLORS.textSecondary,
    fontSize: FONTS.sizes.sm,
    marginHorizontal: SPACING.md,
  },
  guestButton: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: 'transparent',
    borderRadius: 12,
    paddingVertical: SPACING.lg,
    borderWidth: 1,
    borderColor: COLORS.border,
    borderStyle: 'dashed',
  },
  guestButtonDisabled: {
    opacity: 0.7,
  },
  guestIcon: {
    fontSize: 18,
    marginRight: SPACING.sm,
  },
  guestButtonText: {
    color: COLORS.textSecondary,
    fontSize: FONTS.sizes.md,
    fontWeight: '500',
  },
  guestNote: {
    color: COLORS.textTertiary,
    fontSize: FONTS.sizes.xs,
    textAlign: 'center',
    marginTop: SPACING.sm,
    fontStyle: 'italic',
  },
});
