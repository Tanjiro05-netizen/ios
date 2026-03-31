import React from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { ToastConfig } from 'react-native-toast-message';
import { COLORS, FONTS, SPACING } from '../constants';

// Icon component that uses text emoji (avoids expo font loading issues)
const ToastIcon = ({ type }: { type: 'success' | 'error' | 'info' }) => {
  const icons = {
    success: '✓',
    error: '!',
    info: 'i',
  };
  const colors = {
    success: '#00BA7C',
    error: COLORS.primary,
    info: COLORS.blue,
  };
  return (
    <View style={[styles.iconCircle, { backgroundColor: colors[type] + '20' }]}>
      <Text style={[styles.iconText, { color: colors[type] }]}>{icons[type]}</Text>
    </View>
  );
};

// Custom toast configuration for X/Zhihu style
export const toastConfig: ToastConfig = {
  success: (props) => (
    <View style={[styles.container, styles.success]}>
      <View style={styles.iconContainer}>
        <ToastIcon type="success" />
      </View>
      <View style={styles.textContainer}>
        <Text style={styles.text1}>{props.text1}</Text>
        {props.text2 && <Text style={styles.text2}>{props.text2}</Text>}
      </View>
    </View>
  ),

  error: (props) => (
    <View style={[styles.container, styles.error]}>
      <View style={styles.iconContainer}>
        <ToastIcon type="error" />
      </View>
      <View style={styles.textContainer}>
        <Text style={styles.text1}>{props.text1}</Text>
        {props.text2 && <Text style={styles.text2}>{props.text2}</Text>}
      </View>
    </View>
  ),

  info: (props) => (
    <View style={[styles.container, styles.info]}>
      <View style={styles.iconContainer}>
        <ToastIcon type="info" />
      </View>
      <View style={styles.textContainer}>
        <Text style={styles.text1}>{props.text1}</Text>
        {props.text2 && <Text style={styles.text2}>{props.text2}</Text>}
      </View>
    </View>
  ),
};

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    alignItems: 'center',
    width: '90%',
    maxWidth: 400,
    paddingHorizontal: SPACING.lg,
    paddingVertical: SPACING.md,
    borderRadius: 12,
    backgroundColor: COLORS.backgroundSecondary,
    borderWidth: 1,
    // Shadow
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 8,
    elevation: 8,
  },
  success: {
    borderColor: '#00BA7C33',
  },
  error: {
    borderColor: COLORS.primary + '33',
  },
  info: {
    borderColor: COLORS.blue + '33',
  },
  iconContainer: {
    marginRight: SPACING.md,
  },
  iconCircle: {
    width: 24,
    height: 24,
    borderRadius: 12,
    alignItems: 'center',
    justifyContent: 'center',
  },
  iconText: {
    fontSize: 14,
    fontWeight: '700',
  },
  textContainer: {
    flex: 1,
  },
  text1: {
    color: COLORS.text,
    fontSize: FONTS.sizes.md,
    fontWeight: '600',
  },
  text2: {
    color: COLORS.textSecondary,
    fontSize: FONTS.sizes.sm,
    marginTop: 2,
  },
});

export default toastConfig;
