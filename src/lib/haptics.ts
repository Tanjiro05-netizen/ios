import * as Haptics from 'expo-haptics';
import { Platform } from 'react-native';

/**
 * Haptic feedback utilities for the app.
 * Only works on iOS physical devices and some Android devices.
 */

// Light impact - for button presses, toggles
export const lightImpact = () => {
  if (Platform.OS === 'ios') {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Light);
  }
};

// Medium impact - for significant actions like like, bookmark
export const mediumImpact = () => {
  if (Platform.OS === 'ios') {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Medium);
  }
};

// Heavy impact - for major actions like post, delete
export const heavyImpact = () => {
  if (Platform.OS === 'ios') {
    Haptics.impactAsync(Haptics.ImpactFeedbackStyle.Heavy);
  }
};

// Selection feedback - for picker/tab changes
export const selectionFeedback = () => {
  if (Platform.OS === 'ios') {
    Haptics.selectionAsync();
  }
};

// Success notification - for completed actions
export const successNotification = () => {
  if (Platform.OS === 'ios') {
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Success);
  }
};

// Warning notification - for warnings
export const warningNotification = () => {
  if (Platform.OS === 'ios') {
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Warning);
  }
};

// Error notification - for errors
export const errorNotification = () => {
  if (Platform.OS === 'ios') {
    Haptics.notificationAsync(Haptics.NotificationFeedbackType.Error);
  }
};

// Convenience object for importing all at once
export const haptics = {
  light: lightImpact,
  medium: mediumImpact,
  heavy: heavyImpact,
  selection: selectionFeedback,
  success: successNotification,
  warning: warningNotification,
  error: errorNotification,
};

export default haptics;
