import React, { useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  Modal,
  TouchableOpacity,
  TouchableWithoutFeedback,
  TextInput,
  KeyboardAvoidingView,
  Platform,
  ActivityIndicator,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { COLORS, SPACING, FONTS } from '../constants';
import { Thread } from '../types';

interface RepostActionSheetProps {
  visible: boolean;
  onClose: () => void;
  onRepost: (quoteContent?: string) => void;
  onUnrepost?: () => void;
  isReposted?: boolean;
  thread?: Thread | null;
}

export default function RepostActionSheet({
  visible,
  onClose,
  onRepost,
  onUnrepost,
  isReposted = false,
  thread,
}: RepostActionSheetProps) {
  const [showQuoteInput, setShowQuoteInput] = useState(false);
  const [quoteContent, setQuoteContent] = useState('');
  const [isSubmitting, setIsSubmitting] = useState(false);

  const handleClose = () => {
    setShowQuoteInput(false);
    setQuoteContent('');
    setIsSubmitting(false);
    onClose();
  };

  const handleSimpleRepost = () => {
    onRepost();
    handleClose();
  };

  const handleQuotePress = () => {
    setShowQuoteInput(true);
  };

  const handleQuoteSubmit = async () => {
    if (!quoteContent.trim()) {
      // If no quote entered, just do simple repost
      onRepost();
      handleClose();
      return;
    }

    setIsSubmitting(true);
    onRepost(quoteContent.trim());
    handleClose();
  };

  const handleUnrepost = () => {
    onUnrepost?.();
    handleClose();
  };

  // Quote input view
  if (showQuoteInput) {
    return (
      <Modal
        visible={visible}
        transparent
        animationType="slide"
        onRequestClose={handleClose}
      >
        <KeyboardAvoidingView
          behavior={Platform.OS === 'ios' ? 'padding' : 'height'}
          style={styles.overlay}
        >
          <TouchableWithoutFeedback onPress={handleClose}>
            <View style={styles.overlayFill} />
          </TouchableWithoutFeedback>

          <View style={styles.quoteSheet}>
            {/* Header */}
            <View style={styles.quoteHeader}>
              <TouchableOpacity onPress={handleClose} style={styles.headerButton}>
                <Text style={styles.headerButtonText}>Cancel</Text>
              </TouchableOpacity>
              <Text style={styles.quoteTitle}>Quote Repost</Text>
              <TouchableOpacity
                onPress={handleQuoteSubmit}
                style={[styles.headerButton, styles.postButton]}
                disabled={isSubmitting}
              >
                {isSubmitting ? (
                  <ActivityIndicator size="small" color={COLORS.text} />
                ) : (
                  <Text style={[styles.headerButtonText, styles.postButtonText]}>Post</Text>
                )}
              </TouchableOpacity>
            </View>

            {/* Quote input */}
            <TextInput
              style={styles.quoteInput}
              placeholder="Add your thoughts..."
              placeholderTextColor={COLORS.textTertiary}
              multiline
              maxLength={500}
              value={quoteContent}
              onChangeText={setQuoteContent}
              autoFocus
            />

            {/* Character count */}
            <View style={styles.charCount}>
              <Text style={styles.charCountText}>
                {quoteContent.length}/500
              </Text>
            </View>

            {/* Thread preview */}
            {thread && (
              <View style={styles.threadPreview}>
                <View style={styles.previewHeader}>
                  <Ionicons name="repeat" size={14} color={COLORS.textTertiary} />
                  <Text style={styles.previewLabel}>Quoting</Text>
                </View>
                <View style={styles.previewContent}>
                  <Text style={styles.previewAuthor} numberOfLines={1}>
                    {thread.author?.username || thread.anonymous_name || 'Anonymous'}
                  </Text>
                  <Text style={styles.previewTitle} numberOfLines={2}>
                    {thread.title}
                  </Text>
                  <Text style={styles.previewText} numberOfLines={2}>
                    {thread.content}
                  </Text>
                </View>
              </View>
            )}
          </View>
        </KeyboardAvoidingView>
      </Modal>
    );
  }

  // Main action sheet
  return (
    <Modal
      visible={visible}
      transparent
      animationType="fade"
      onRequestClose={handleClose}
    >
      <TouchableWithoutFeedback onPress={handleClose}>
        <View style={styles.overlay}>
          <TouchableWithoutFeedback>
            <View style={styles.sheet}>
              {/* Header */}
              <View style={styles.header}>
                <View style={styles.handle} />
              </View>

              {/* Options */}
              {isReposted ? (
                // Already reposted - show undo option
                <TouchableOpacity
                  style={styles.option}
                  onPress={handleUnrepost}
                >
                  <View style={[styles.iconContainer, styles.iconUndo]}>
                    <Ionicons name="close" size={24} color={COLORS.error} />
                  </View>
                  <View style={styles.optionText}>
                    <Text style={styles.optionTitle}>Undo Repost</Text>
                    <Text style={styles.optionDescription}>
                      Remove this from your profile
                    </Text>
                  </View>
                </TouchableOpacity>
              ) : (
                <>
                  {/* Repost option */}
                  <TouchableOpacity
                    style={styles.option}
                    onPress={handleSimpleRepost}
                  >
                    <View style={[styles.iconContainer, styles.iconRepost]}>
                      <Ionicons name="repeat" size={24} color={COLORS.repost} />
                    </View>
                    <View style={styles.optionText}>
                      <Text style={styles.optionTitle}>Repost</Text>
                      <Text style={styles.optionDescription}>
                        Share to your profile instantly
                      </Text>
                    </View>
                  </TouchableOpacity>

                  {/* Quote option */}
                  <TouchableOpacity
                    style={styles.option}
                    onPress={handleQuotePress}
                  >
                    <View style={[styles.iconContainer, styles.iconQuote]}>
                      <Ionicons name="pencil" size={24} color={COLORS.blue} />
                    </View>
                    <View style={styles.optionText}>
                      <Text style={styles.optionTitle}>Quote</Text>
                      <Text style={styles.optionDescription}>
                        Add your thoughts with the original post
                      </Text>
                    </View>
                  </TouchableOpacity>
                </>
              )}

              {/* Cancel button */}
              <TouchableOpacity style={styles.cancelButton} onPress={handleClose}>
                <Text style={styles.cancelText}>Cancel</Text>
              </TouchableOpacity>
            </View>
          </TouchableWithoutFeedback>
        </View>
      </TouchableWithoutFeedback>
    </Modal>
  );
}

const styles = StyleSheet.create({
  overlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.6)',
    justifyContent: 'flex-end',
  },
  overlayFill: {
    flex: 1,
  },
  sheet: {
    backgroundColor: COLORS.backgroundSecondary,
    borderTopLeftRadius: 20,
    borderTopRightRadius: 20,
    paddingBottom: 34, // Safe area
  },
  header: {
    alignItems: 'center',
    paddingVertical: SPACING.md,
  },
  handle: {
    width: 36,
    height: 5,
    backgroundColor: COLORS.border,
    borderRadius: 3,
  },
  option: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: SPACING.lg,
    paddingVertical: SPACING.md,
  },
  iconContainer: {
    width: 48,
    height: 48,
    borderRadius: 24,
    justifyContent: 'center',
    alignItems: 'center',
    marginRight: SPACING.md,
  },
  iconRepost: {
    backgroundColor: COLORS.repost + '20',
  },
  iconQuote: {
    backgroundColor: COLORS.blue + '20',
  },
  iconUndo: {
    backgroundColor: COLORS.error + '20',
  },
  optionText: {
    flex: 1,
  },
  optionTitle: {
    color: COLORS.text,
    fontSize: FONTS.sizes.lg,
    fontWeight: '600',
    marginBottom: 2,
  },
  optionDescription: {
    color: COLORS.textSecondary,
    fontSize: FONTS.sizes.sm,
  },
  cancelButton: {
    marginTop: SPACING.sm,
    marginHorizontal: SPACING.lg,
    paddingVertical: SPACING.md,
    backgroundColor: COLORS.background,
    borderRadius: 12,
    alignItems: 'center',
  },
  cancelText: {
    color: COLORS.text,
    fontSize: FONTS.sizes.md,
    fontWeight: '600',
  },

  // Quote input styles
  quoteSheet: {
    backgroundColor: COLORS.background,
    borderTopLeftRadius: 20,
    borderTopRightRadius: 20,
    paddingBottom: 34,
    maxHeight: '80%',
  },
  quoteHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: SPACING.md,
    paddingVertical: SPACING.md,
    borderBottomWidth: 0.5,
    borderBottomColor: COLORS.border,
  },
  headerButton: {
    paddingHorizontal: SPACING.sm,
    paddingVertical: SPACING.xs,
  },
  headerButtonText: {
    color: COLORS.text,
    fontSize: FONTS.sizes.md,
  },
  postButton: {
    backgroundColor: COLORS.primary,
    borderRadius: 16,
    paddingHorizontal: SPACING.md,
  },
  postButtonText: {
    fontWeight: '600',
  },
  quoteTitle: {
    color: COLORS.text,
    fontSize: FONTS.sizes.lg,
    fontWeight: '600',
  },
  quoteInput: {
    color: COLORS.text,
    fontSize: FONTS.sizes.md,
    paddingHorizontal: SPACING.lg,
    paddingVertical: SPACING.md,
    minHeight: 100,
    maxHeight: 150,
    textAlignVertical: 'top',
  },
  charCount: {
    paddingHorizontal: SPACING.lg,
    alignItems: 'flex-end',
  },
  charCountText: {
    color: COLORS.textTertiary,
    fontSize: FONTS.sizes.sm,
  },
  threadPreview: {
    marginHorizontal: SPACING.lg,
    marginTop: SPACING.md,
    backgroundColor: COLORS.backgroundSecondary,
    borderRadius: 12,
    padding: SPACING.md,
    borderWidth: 1,
    borderColor: COLORS.border,
  },
  previewHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: SPACING.sm,
  },
  previewLabel: {
    color: COLORS.textTertiary,
    fontSize: FONTS.sizes.sm,
    marginLeft: SPACING.xs,
  },
  previewContent: {},
  previewAuthor: {
    color: COLORS.textSecondary,
    fontSize: FONTS.sizes.sm,
    fontWeight: '500',
  },
  previewTitle: {
    color: COLORS.text,
    fontSize: FONTS.sizes.md,
    fontWeight: '600',
    marginTop: 2,
  },
  previewText: {
    color: COLORS.textSecondary,
    fontSize: FONTS.sizes.sm,
    marginTop: 4,
    lineHeight: 18,
  },
});
