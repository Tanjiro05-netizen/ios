import React from 'react';
import { View, Text, StyleSheet, TouchableOpacity } from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { COLORS, SPACING, FONTS } from '../constants';

interface ErrorStateProps {
  title?: string;
  message?: string;
  icon?: keyof typeof Ionicons.glyphMap;
  onRetry?: () => void;
  retryLabel?: string;
  fullScreen?: boolean;
}

/**
 * Error state component with retry button
 * Use for network errors, empty states, and error boundaries
 */
export default function ErrorState({
  title = 'Something went wrong',
  message = 'Please try again later.',
  icon = 'alert-circle-outline',
  onRetry,
  retryLabel = 'Try again',
  fullScreen = false,
}: ErrorStateProps) {
  return (
    <View style={[styles.container, fullScreen && styles.fullScreen]}>
      <View style={styles.iconContainer}>
        <Ionicons name={icon} size={48} color={COLORS.textTertiary} />
      </View>

      <Text style={styles.title}>{title}</Text>
      <Text style={styles.message}>{message}</Text>

      {onRetry && (
        <TouchableOpacity style={styles.retryButton} onPress={onRetry} activeOpacity={0.8}>
          <Ionicons name="refresh-outline" size={18} color="#FFFFFF" />
          <Text style={styles.retryText}>{retryLabel}</Text>
        </TouchableOpacity>
      )}
    </View>
  );
}

// Preset configurations for common error states
export const ErrorPresets = {
  network: {
    title: 'No connection',
    message: 'Check your internet connection and try again.',
    icon: 'cloud-offline-outline' as const,
  },
  notFound: {
    title: 'Not found',
    message: "We couldn't find what you're looking for.",
    icon: 'search-outline' as const,
  },
  serverError: {
    title: 'Server error',
    message: "Something went wrong on our end. We're working on it.",
    icon: 'server-outline' as const,
  },
  unauthorized: {
    title: 'Session expired',
    message: 'Please sign in again to continue.',
    icon: 'lock-closed-outline' as const,
  },
  empty: {
    title: 'Nothing here yet',
    message: 'Be the first to post something!',
    icon: 'document-text-outline' as const,
  },
};

const styles = StyleSheet.create({
  container: {
    alignItems: 'center',
    justifyContent: 'center',
    padding: SPACING.xxxl,
  },
  fullScreen: {
    flex: 1,
    backgroundColor: COLORS.background,
  },
  iconContainer: {
    width: 80,
    height: 80,
    borderRadius: 40,
    backgroundColor: COLORS.backgroundSecondary,
    alignItems: 'center',
    justifyContent: 'center',
    marginBottom: SPACING.lg,
  },
  title: {
    color: COLORS.text,
    fontSize: FONTS.sizes.xl,
    fontWeight: '700',
    textAlign: 'center',
    marginBottom: SPACING.sm,
  },
  message: {
    color: COLORS.textSecondary,
    fontSize: FONTS.sizes.md,
    textAlign: 'center',
    lineHeight: 22,
    maxWidth: 280,
  },
  retryButton: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: COLORS.primary,
    paddingHorizontal: SPACING.xl,
    paddingVertical: SPACING.md,
    borderRadius: 24,
    marginTop: SPACING.xl,
  },
  retryText: {
    color: '#FFFFFF',
    fontSize: FONTS.sizes.md,
    fontWeight: '600',
    marginLeft: SPACING.sm,
  },
});
