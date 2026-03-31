import React, { useState } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  Image,
  Modal,
  TouchableWithoutFeedback,
  TextInput,
  Alert,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { Comment } from '../types';
import {
  COLORS,
  SPACING,
  FONTS,
  getIdeologyColor,
  getIdeologyAbbrev,
  formatTimeAgo,
  formatCount,
} from '../constants';

interface CommentCardProps {
  comment: Comment;
  onLike?: () => void;
  onReply?: () => void;
  onEdit?: (commentId: string, content: string) => Promise<void>;
  onDelete?: (commentId: string) => Promise<void>;
  isLiked?: boolean;
  isNested?: boolean;
  isOwner?: boolean;
  canDelete?: boolean;
}

export default function CommentCard({
  comment,
  onLike,
  onReply,
  onEdit,
  onDelete,
  isLiked = false,
  isNested = false,
  isOwner = false,
  canDelete = false,
}: CommentCardProps) {
  const [showMoreMenu, setShowMoreMenu] = useState(false);
  const [showEditModal, setShowEditModal] = useState(false);
  const [editContent, setEditContent] = useState(comment.content);

  // Determine display name - use anonymous_name for guest posts, author username otherwise
  const displayName = comment.author?.username || comment.anonymous_name || 'Anonymous';
  const isAnonymousPost = !comment.author && !!comment.anonymous_name;
  const ideologyColor = getIdeologyColor(comment.author?.ideology || null);
  const ideologyAbbrev = getIdeologyAbbrev(comment.author?.ideology || null);

  const handleMorePress = () => {
    setShowMoreMenu(true);
  };

  const handleEditPress = () => {
    setEditContent(comment.content);
    setShowMoreMenu(false);
    setShowEditModal(true);
  };

  const handleEditSubmit = async () => {
    if (!editContent.trim()) return;

    try {
      await onEdit?.(comment.id, editContent.trim());
      setShowEditModal(false);
    } catch (err) {
      console.error('Error updating comment:', err);
      Alert.alert('Error', 'Failed to update comment');
    }
  };

  const handleDeletePress = () => {
    setShowMoreMenu(false);
    Alert.alert(
      'Delete Comment',
      'Are you sure you want to delete this comment?',
      [
        { text: 'Cancel', style: 'cancel' },
        {
          text: 'Delete',
          style: 'destructive',
          onPress: async () => {
            try {
              await onDelete?.(comment.id);
            } catch (err) {
              console.error('Error deleting comment:', err);
              Alert.alert('Error', 'Failed to delete comment');
            }
          },
        },
      ]
    );
  };

  if (comment.is_deleted) {
    return (
      <View style={[styles.container, isNested && styles.nested]}>
        <View style={styles.deletedContainer}>
          <Ionicons name="trash-outline" size={16} color={COLORS.textTertiary} />
          <Text style={styles.deletedText}>This comment was deleted</Text>
        </View>
      </View>
    );
  }

  return (
    <View style={[styles.container, isNested && styles.nested]}>
      {/* Avatar column */}
      <View style={styles.avatarColumn}>
        <TouchableOpacity>
          <View style={styles.avatar}>
            {comment.author?.avatar_url ? (
              <Image source={{ uri: comment.author.avatar_url }} style={styles.avatarImage} />
            ) : (
              <Text style={styles.avatarText}>
                {displayName[0]?.toUpperCase() || '?'}
              </Text>
            )}
          </View>
        </TouchableOpacity>
        {isNested && <View style={styles.threadLine} />}
      </View>

      {/* Content column */}
      <View style={styles.contentColumn}>
        {/* Header - X style inline */}
        <View style={styles.header}>
          <View style={styles.headerLeft}>
            <Text style={styles.displayName} numberOfLines={1}>
              {displayName}
            </Text>
            {isAnonymousPost && (
              <Text style={styles.guestBadge}>Guest</Text>
            )}
            {comment.author?.is_certified && (
              <Ionicons
                name="checkmark-circle"
                size={14}
                color={COLORS.blue}
                style={styles.verifiedIcon}
              />
            )}
            {ideologyAbbrev && (
              <Text style={[styles.ideology, { color: ideologyColor }]}>{ideologyAbbrev}</Text>
            )}
            <Text style={styles.separator}>·</Text>
            <Text style={styles.timestamp}>{formatTimeAgo(comment.created_at)}</Text>
          </View>
          <TouchableOpacity style={styles.moreButton} onPress={handleMorePress}>
            <Ionicons name="ellipsis-horizontal" size={16} color={COLORS.textTertiary} />
          </TouchableOpacity>
        </View>

        {/* Content */}
        <Text style={styles.content}>{comment.content}</Text>

        {/* Actions - X style */}
        <View style={styles.actionsRow}>
          <TouchableOpacity style={styles.actionButton} onPress={onReply}>
            <Ionicons name="chatbubble-outline" size={16} color={COLORS.textSecondary} />
          </TouchableOpacity>

          <TouchableOpacity style={styles.actionButton} onPress={onLike}>
            <Ionicons
              name={isLiked ? 'heart' : 'heart-outline'}
              size={16}
              color={isLiked ? COLORS.like : COLORS.textSecondary}
            />
            {(comment.like_count || 0) > 0 && (
              <Text style={[styles.actionCount, isLiked && styles.actionCountLiked]}>
                {formatCount(comment.like_count || 0)}
              </Text>
            )}
          </TouchableOpacity>

          <TouchableOpacity style={styles.actionButton}>
            <Ionicons name="share-outline" size={16} color={COLORS.textSecondary} />
          </TouchableOpacity>
        </View>
      </View>

      {/* More Menu Modal */}
      <Modal
        visible={showMoreMenu}
        transparent
        animationType="fade"
        onRequestClose={() => setShowMoreMenu(false)}
      >
        <TouchableWithoutFeedback onPress={() => setShowMoreMenu(false)}>
          <View style={styles.modalOverlay}>
            <TouchableWithoutFeedback>
              <View style={styles.moreMenuSheet}>
                <View style={styles.moreMenuHandle} />

                {(isOwner || canDelete) && (
                  <>
                    {isOwner && (
                      <TouchableOpacity style={styles.moreMenuItem} onPress={handleEditPress}>
                        <Ionicons name="pencil-outline" size={20} color={COLORS.text} />
                        <Text style={styles.moreMenuText}>Edit</Text>
                      </TouchableOpacity>
                    )}

                    <TouchableOpacity style={styles.moreMenuItem} onPress={handleDeletePress}>
                      <Ionicons name="trash-outline" size={20} color={COLORS.error} />
                      <Text style={[styles.moreMenuText, { color: COLORS.error }]}>Delete</Text>
                    </TouchableOpacity>
                  </>
                )}

                <TouchableOpacity style={styles.moreMenuItem} onPress={() => setShowMoreMenu(false)}>
                  <Ionicons name="flag-outline" size={20} color={COLORS.text} />
                  <Text style={styles.moreMenuText}>Report</Text>
                </TouchableOpacity>

                <TouchableOpacity
                  style={styles.moreMenuCancel}
                  onPress={() => setShowMoreMenu(false)}
                >
                  <Text style={styles.moreMenuCancelText}>Cancel</Text>
                </TouchableOpacity>
              </View>
            </TouchableWithoutFeedback>
          </View>
        </TouchableWithoutFeedback>
      </Modal>

      {/* Edit Comment Modal */}
      <Modal
        visible={showEditModal}
        transparent
        animationType="slide"
        onRequestClose={() => setShowEditModal(false)}
      >
        <View style={styles.editModalOverlay}>
          <View style={styles.editModalSheet}>
            <View style={styles.editModalHeader}>
              <TouchableOpacity onPress={() => setShowEditModal(false)}>
                <Text style={styles.editModalCancel}>Cancel</Text>
              </TouchableOpacity>
              <Text style={styles.editModalTitle}>Edit Comment</Text>
              <TouchableOpacity onPress={handleEditSubmit}>
                <Text style={styles.editModalSave}>Save</Text>
              </TouchableOpacity>
            </View>

            <TextInput
              style={styles.editInput}
              value={editContent}
              onChangeText={setEditContent}
              placeholder="Edit your comment..."
              placeholderTextColor={COLORS.textTertiary}
              multiline
              autoFocus
              textAlignVertical="top"
            />
          </View>
        </View>
      </Modal>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flexDirection: 'row',
    paddingHorizontal: SPACING.lg,
    paddingVertical: SPACING.md,
    borderBottomWidth: 0.5,
    borderBottomColor: COLORS.border,
  },
  nested: {
    paddingLeft: SPACING.lg + 44,
    backgroundColor: COLORS.background,
  },
  avatarColumn: {
    marginRight: SPACING.md,
    alignItems: 'center',
  },
  avatar: {
    width: 36,
    height: 36,
    borderRadius: 18,
    backgroundColor: COLORS.backgroundSecondary,
    justifyContent: 'center',
    alignItems: 'center',
  },
  avatarImage: {
    width: 36,
    height: 36,
    borderRadius: 18,
  },
  avatarText: {
    color: COLORS.text,
    fontSize: FONTS.sizes.sm,
    fontWeight: '600',
  },
  threadLine: {
    width: 2,
    flex: 1,
    backgroundColor: COLORS.border,
    marginTop: SPACING.xs,
  },
  contentColumn: {
    flex: 1,
  },
  header: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
  },
  headerLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    flex: 1,
    flexWrap: 'wrap',
  },
  displayName: {
    color: COLORS.text,
    fontSize: FONTS.sizes.md,
    fontWeight: '700',
    marginRight: 4,
  },
  verifiedIcon: {
    marginRight: 4,
  },
  guestBadge: {
    fontSize: FONTS.sizes.xs,
    color: COLORS.textTertiary,
    backgroundColor: COLORS.backgroundSecondary,
    paddingHorizontal: SPACING.xs,
    paddingVertical: 1,
    borderRadius: 4,
    marginLeft: 4,
    marginRight: 4,
    overflow: 'hidden',
  },
  ideology: {
    fontSize: FONTS.sizes.xs,
    fontWeight: '600',
    marginRight: 4,
  },
  separator: {
    color: COLORS.textTertiary,
    marginHorizontal: 4,
  },
  timestamp: {
    color: COLORS.textSecondary,
    fontSize: FONTS.sizes.sm,
  },
  moreButton: {
    padding: SPACING.xs,
  },
  content: {
    color: COLORS.text,
    fontSize: FONTS.sizes.md,
    lineHeight: 20,
    marginTop: SPACING.xs,
  },
  actionsRow: {
    flexDirection: 'row',
    marginTop: SPACING.sm,
    marginLeft: -SPACING.sm,
  },
  actionButton: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: SPACING.xs,
    paddingHorizontal: SPACING.sm,
    marginRight: SPACING.lg,
  },
  actionCount: {
    color: COLORS.textSecondary,
    fontSize: FONTS.sizes.xs,
    marginLeft: 4,
  },
  actionCountLiked: {
    color: COLORS.like,
  },
  deletedContainer: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingVertical: SPACING.sm,
  },
  deletedText: {
    color: COLORS.textTertiary,
    fontSize: FONTS.sizes.sm,
    fontStyle: 'italic',
    marginLeft: SPACING.sm,
  },

  // More Menu Modal styles
  modalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.6)',
    justifyContent: 'flex-end',
  },
  moreMenuSheet: {
    backgroundColor: COLORS.backgroundSecondary,
    borderTopLeftRadius: 20,
    borderTopRightRadius: 20,
    paddingBottom: 34,
    alignItems: 'center',
  },
  moreMenuHandle: {
    width: 36,
    height: 5,
    backgroundColor: COLORS.border,
    borderRadius: 3,
    marginVertical: SPACING.md,
  },
  moreMenuItem: {
    flexDirection: 'row',
    alignItems: 'center',
    width: '100%',
    paddingVertical: SPACING.md,
    paddingHorizontal: SPACING.xl,
  },
  moreMenuText: {
    color: COLORS.text,
    fontSize: FONTS.sizes.md,
    marginLeft: SPACING.md,
  },
  moreMenuCancel: {
    width: '100%',
    paddingVertical: SPACING.md,
    marginTop: SPACING.sm,
    borderTopWidth: 0.5,
    borderTopColor: COLORS.border,
    alignItems: 'center',
  },
  moreMenuCancelText: {
    color: COLORS.textSecondary,
    fontSize: FONTS.sizes.md,
    fontWeight: '600',
  },

  // Edit Modal styles
  editModalOverlay: {
    flex: 1,
    backgroundColor: 'rgba(0, 0, 0, 0.6)',
    justifyContent: 'flex-end',
  },
  editModalSheet: {
    backgroundColor: COLORS.background,
    borderTopLeftRadius: 20,
    borderTopRightRadius: 20,
    maxHeight: '70%',
    paddingBottom: 34,
  },
  editModalHeader: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingHorizontal: SPACING.lg,
    paddingVertical: SPACING.md,
    borderBottomWidth: 0.5,
    borderBottomColor: COLORS.border,
  },
  editModalCancel: {
    color: COLORS.text,
    fontSize: FONTS.sizes.md,
  },
  editModalTitle: {
    color: COLORS.text,
    fontSize: FONTS.sizes.lg,
    fontWeight: '700',
  },
  editModalSave: {
    color: COLORS.primary,
    fontSize: FONTS.sizes.md,
    fontWeight: '600',
  },
  editInput: {
    color: COLORS.text,
    fontSize: FONTS.sizes.md,
    padding: SPACING.lg,
    minHeight: 120,
    lineHeight: 22,
  },
});
