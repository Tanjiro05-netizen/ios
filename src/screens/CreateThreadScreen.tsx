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
import { Ionicons } from '@expo/vector-icons';
import { useNavigation, useRoute, RouteProp } from '@react-navigation/native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';

import { useAuth } from '../hooks/useAuth';
import { api } from '../lib/api';
import { haptics } from '../lib/haptics';
import toast from '../lib/toast';
import { COLORS, FONTS, SPACING, BOARDS, LIMITS } from '../constants';
import { RootStackParamList } from '../types';

type NavigationProp = NativeStackNavigationProp<RootStackParamList>;
type RouteType = RouteProp<RootStackParamList, 'CreateThread'>;

export default function CreateThreadScreen() {
  const navigation = useNavigation<NavigationProp>();
  const route = useRoute<RouteType>();
  const { user, isGuest, guestSession } = useAuth();

  const [title, setTitle] = useState('');
  const [content, setContent] = useState('');
  const [selectedBoard, setSelectedBoard] = useState(route.params?.boardSlug || BOARDS[0].slug);
  const [showBoardPicker, setShowBoardPicker] = useState(false);
  const [submitting, setSubmitting] = useState(false);

  const selectedBoardObj = BOARDS.find((b) => b.slug === selectedBoard) || BOARDS[0];

  const isValid =
    title.trim().length >= LIMITS.TITLE_MIN &&
    title.trim().length <= LIMITS.TITLE_MAX &&
    content.trim().length >= LIMITS.CONTENT_MIN &&
    content.trim().length <= LIMITS.CONTENT_MAX;

  const handleSubmit = async () => {
    if (!isValid) {
      Alert.alert(
        'Incomplete',
        `Title needs ${LIMITS.TITLE_MIN}–${LIMITS.TITLE_MAX} chars, body needs ${LIMITS.CONTENT_MIN}+ chars.`,
      );
      return;
    }

    setSubmitting(true);
    try {
      const threadData: {
        title: string;
        content: string;
        category_slug: string;
        anonymous_name?: string;
      } = {
        title: title.trim(),
        content: content.trim(),
        category_slug: selectedBoard,
      };

      if (isGuest && guestSession) {
        threadData.anonymous_name = guestSession.username;
      }

      const newThread = await api.createThread(threadData);
      if (newThread) {
        haptics.success();
        toast.success('Thread posted');
        navigation.goBack();
      }
    } catch (err) {
      toast.error('Failed to post thread');
      console.error('Error creating thread:', err);
    } finally {
      setSubmitting(false);
    }
  };

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      {/* Header */}
      <View style={styles.header}>
        <TouchableOpacity onPress={() => navigation.goBack()} style={styles.backBtn}>
          <Ionicons name="close" size={22} color={COLORS.text} />
        </TouchableOpacity>
        <Text style={styles.headerTitle}>New Thread</Text>
        <TouchableOpacity
          style={[styles.postBtn, !isValid && styles.postBtnDisabled]}
          onPress={handleSubmit}
          disabled={!isValid || submitting}
        >
          {submitting ? (
            <ActivityIndicator size="small" color="#fff" />
          ) : (
            <Text style={[styles.postBtnText, !isValid && styles.postBtnTextDisabled]}>Post</Text>
          )}
        </TouchableOpacity>
      </View>

      <KeyboardAvoidingView
        style={{ flex: 1 }}
        behavior={Platform.OS === 'ios' ? 'padding' : undefined}
      >
        <ScrollView
          style={styles.scrollView}
          contentContainerStyle={styles.scrollContent}
          keyboardShouldPersistTaps="handled"
        >
          {/* Board picker */}
          <TouchableOpacity
            style={styles.boardSelector}
            onPress={() => setShowBoardPicker(!showBoardPicker)}
          >
            <Text style={styles.boardSelectorLabel}>Board</Text>
            <View style={styles.boardSelectorValue}>
              <Text style={styles.boardEmoji}>{selectedBoardObj.icon}</Text>
              <Text style={styles.boardName}>{selectedBoardObj.fullName}</Text>
              <Ionicons
                name={showBoardPicker ? 'chevron-up' : 'chevron-down'}
                size={16}
                color={COLORS.textSecondary}
              />
            </View>
          </TouchableOpacity>

          {showBoardPicker && (
            <View style={styles.boardList}>
              {BOARDS.map((board) => {
                const isSelected = board.slug === selectedBoard;
                return (
                  <TouchableOpacity
                    key={board.slug}
                    style={[styles.boardOption, isSelected && styles.boardOptionActive]}
                    onPress={() => {
                      setSelectedBoard(board.slug);
                      setShowBoardPicker(false);
                    }}
                  >
                    <Text style={styles.boardOptionEmoji}>{board.icon}</Text>
                    <View style={styles.boardOptionInfo}>
                      <Text style={[styles.boardOptionName, isSelected && styles.boardOptionNameActive]}>
                        {board.fullName}
                      </Text>
                      <Text style={styles.boardOptionDesc}>{board.description}</Text>
                    </View>
                    {isSelected && (
                      <Ionicons name="checkmark" size={18} color={COLORS.primary} />
                    )}
                  </TouchableOpacity>
                );
              })}
            </View>
          )}

          {/* Guest indicator */}
          {isGuest && guestSession && (
            <View style={styles.guestBanner}>
              <Ionicons name="person-outline" size={14} color={COLORS.textSecondary} />
              <Text style={styles.guestBannerText}>
                Posting as {guestSession.username}
              </Text>
            </View>
          )}

          {/* Title input */}
          <TextInput
            style={styles.titleInput}
            placeholder="Title"
            placeholderTextColor={COLORS.textTertiary}
            value={title}
            onChangeText={setTitle}
            maxLength={LIMITS.TITLE_MAX}
            multiline
          />

          {/* Char count */}
          <Text style={styles.charCount}>
            {title.length}/{LIMITS.TITLE_MAX}
          </Text>

          {/* Content input */}
          <TextInput
            style={styles.contentInput}
            placeholder="What's on your mind?"
            placeholderTextColor={COLORS.textTertiary}
            value={content}
            onChangeText={setContent}
            maxLength={LIMITS.CONTENT_MAX}
            multiline
            textAlignVertical="top"
          />

          <Text style={styles.charCount}>
            {content.length}/{LIMITS.CONTENT_MAX}
          </Text>
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
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: SPACING.lg,
    paddingVertical: SPACING.md,
    borderBottomWidth: 1,
    borderBottomColor: COLORS.border,
  },
  backBtn: {
    width: 40,
    height: 40,
    borderRadius: 20,
    alignItems: 'center',
    justifyContent: 'center',
  },
  headerTitle: {
    fontFamily: FONTS.family.mono,
    fontSize: 11,
    color: COLORS.textSecondary,
    textTransform: 'uppercase',
    letterSpacing: 2,
  },
  postBtn: {
    backgroundColor: COLORS.primary,
    paddingHorizontal: 20,
    paddingVertical: 8,
    borderRadius: 20,
    minWidth: 70,
    alignItems: 'center',
  },
  postBtnDisabled: {
    backgroundColor: COLORS.textTertiary,
  },
  postBtnText: {
    fontFamily: FONTS.family.mono,
    fontSize: 12,
    color: '#fff',
    fontWeight: '600',
    letterSpacing: 1,
    textTransform: 'uppercase',
  },
  postBtnTextDisabled: {
    opacity: 0.5,
  },
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    padding: SPACING.xl,
    paddingBottom: 60,
  },

  // ── Board picker ──
  boardSelector: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: 'rgba(255,255,255,0.03)',
    borderWidth: 1,
    borderColor: COLORS.border,
    borderRadius: 12,
    paddingHorizontal: SPACING.lg,
    paddingVertical: SPACING.md,
    marginBottom: SPACING.md,
  },
  boardSelectorLabel: {
    fontFamily: FONTS.family.mono,
    fontSize: 10,
    color: COLORS.textTertiary,
    textTransform: 'uppercase',
    letterSpacing: 1.5,
  },
  boardSelectorValue: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  boardEmoji: {
    fontSize: 16,
  },
  boardName: {
    fontFamily: FONTS.family.mono,
    fontSize: 12,
    color: COLORS.text,
  },
  boardList: {
    backgroundColor: 'rgba(255,255,255,0.02)',
    borderWidth: 1,
    borderColor: COLORS.border,
    borderRadius: 12,
    overflow: 'hidden',
    marginBottom: SPACING.lg,
  },
  boardOption: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: SPACING.md,
    paddingHorizontal: SPACING.lg,
    borderBottomWidth: 1,
    borderBottomColor: COLORS.border,
    gap: 12,
  },
  boardOptionActive: {
    backgroundColor: 'rgba(200,30,30,0.06)',
  },
  boardOptionEmoji: {
    fontSize: 18,
    width: 28,
    textAlign: 'center',
  },
  boardOptionInfo: {
    flex: 1,
  },
  boardOptionName: {
    fontFamily: FONTS.family.mono,
    fontSize: 12,
    color: COLORS.text,
    marginBottom: 2,
  },
  boardOptionNameActive: {
    color: COLORS.primary,
  },
  boardOptionDesc: {
    fontFamily: FONTS.family.mono,
    fontSize: 9,
    color: COLORS.textTertiary,
    letterSpacing: 0.5,
  },

  // ── Guest banner ──
  guestBanner: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
    backgroundColor: 'rgba(255,255,255,0.03)',
    borderRadius: 8,
    paddingHorizontal: 12,
    paddingVertical: 8,
    marginBottom: SPACING.lg,
  },
  guestBannerText: {
    fontFamily: FONTS.family.mono,
    fontSize: 10,
    color: COLORS.textSecondary,
    letterSpacing: 0.5,
  },

  // ── Inputs ──
  titleInput: {
    fontFamily: FONTS.family.display,
    fontSize: 26,
    color: COLORS.text,
    lineHeight: 34,
    paddingVertical: SPACING.md,
    borderBottomWidth: 1,
    borderBottomColor: COLORS.border,
    marginBottom: 4,
  },
  charCount: {
    fontFamily: FONTS.family.mono,
    fontSize: 9,
    color: COLORS.textTertiary,
    textAlign: 'right',
    marginBottom: SPACING.lg,
    letterSpacing: 0.5,
  },
  contentInput: {
    fontFamily: FONTS.family.body,
    fontSize: 16,
    color: COLORS.text,
    lineHeight: 24,
    minHeight: 200,
    paddingVertical: SPACING.md,
  },
});
