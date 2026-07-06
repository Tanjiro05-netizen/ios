import React, { useState, useEffect, useCallback } from 'react';
import {
  View,
  Text,
  StyleSheet,
  FlatList,
  TouchableOpacity,
  ActivityIndicator,
  RefreshControl,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { useNavigation } from '@react-navigation/native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';

import { useAuth } from '../hooks/useAuth';
import { api } from '../lib/api';
import { COLORS, FONTS, SPACING, formatTimeAgo } from '../constants';
import { Notification, RootStackParamList } from '../types';

type NavigationProp = NativeStackNavigationProp<RootStackParamList>;

const NOTIFICATION_ICONS: Record<string, keyof typeof Ionicons.glyphMap> = {
  like: 'heart',
  comment: 'chatbubble',
  repost: 'repeat',
  follow: 'person-add',
  mention: 'at',
  reply: 'return-down-forward',
  default: 'notifications',
};

const NOTIFICATION_LABELS: Record<string, string> = {
  like: 'liked your post',
  comment: 'commented on your post',
  repost: 'reposted your post',
  follow: 'followed you',
  mention: 'mentioned you',
  reply: 'replied to your comment',
};

export default function NotificationsScreen() {
  const navigation = useNavigation<NavigationProp>();
  const { user, isGuest } = useAuth();

  const [notifications, setNotifications] = useState<Notification[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);

  const loadNotifications = useCallback(async () => {
    if (!user) return;
    try {
      const data = await api.getNotifications(user.id);
      setNotifications(data);
    } catch (err) {
      console.error('Error loading notifications:', err);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  }, [user]);

  useEffect(() => {
    loadNotifications();
  }, [loadNotifications]);

  const handleRefresh = () => {
    setRefreshing(true);
    loadNotifications();
  };

  const handleNotificationPress = async (notification: Notification) => {
    if (!notification.is_read) {
      await api.markNotificationRead(notification.id);
      setNotifications(prev =>
        prev.map(n => n.id === notification.id ? { ...n, is_read: true } : n)
      );
    }
    if (notification.source_user?.id) {
      navigation.navigate('UserProfile', { userId: notification.source_user.id });
    }
  };

  const handleMarkAllRead = async () => {
    if (!user) return;
    await api.markAllNotificationsRead(user.id);
    setNotifications(prev => prev.map(n => ({ ...n, is_read: true })));
  };

  const unreadCount = notifications.filter(n => !n.is_read).length;

  if (isGuest) {
    return (
      <SafeAreaView style={styles.container} edges={['top']}>
        <View style={styles.titleBar}>
          <Text style={styles.screenTitle}>Notifications</Text>
        </View>
        <View style={styles.emptyContainer}>
          <Ionicons name="notifications-off-outline" size={64} color={COLORS.textTertiary} />
          <Text style={styles.emptyTitle}>Sign in for Notifications</Text>
          <Text style={styles.emptySubtitle}>
            Create an account to receive likes, replies, and mentions.
          </Text>
        </View>
      </SafeAreaView>
    );
  }

  const renderNotification = ({ item }: { item: Notification }) => {
    const iconName = NOTIFICATION_ICONS[item.type] || NOTIFICATION_ICONS.default;
    const label = NOTIFICATION_LABELS[item.type] || item.type;
    const isUnread = !item.is_read;

    return (
      <TouchableOpacity
        style={[styles.notifRow, isUnread && styles.notifRowUnread]}
        onPress={() => handleNotificationPress(item)}
        activeOpacity={0.7}
      >
        <View style={[styles.iconCircle, isUnread && styles.iconCircleUnread]}>
          <Ionicons
            name={iconName}
            size={18}
            color={isUnread ? COLORS.primary : COLORS.textSecondary}
          />
        </View>
        <View style={styles.notifContent}>
          <Text style={styles.notifText} numberOfLines={2}>
            <Text style={styles.notifUsername}>
              {item.source_user?.username || 'Someone'}
            </Text>
            {' '}{label}
          </Text>
          {item.content_preview ? (
            <Text style={styles.notifPreview} numberOfLines={1}>
              "{item.content_preview}"
            </Text>
          ) : null}
          <Text style={styles.notifTime}>{formatTimeAgo(item.created_at)}</Text>
        </View>
        {isUnread && <View style={styles.unreadDot} />}
      </TouchableOpacity>
    );
  };

  const renderEmpty = () => (
    <View style={styles.emptyContainer}>
      <Ionicons name="notifications-outline" size={64} color={COLORS.textTertiary} />
      <Text style={styles.emptyTitle}>No Notifications Yet</Text>
      <Text style={styles.emptySubtitle}>
        Activity on your posts will appear here.
      </Text>
    </View>
  );

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <View style={styles.titleBar}>
        <View style={{ flex: 1 }}>
          <Text style={styles.screenTitle}>Notifications</Text>
          <Text style={styles.screenSubtitle}>
            {unreadCount > 0 ? `${unreadCount} unread` : 'All caught up'}
          </Text>
        </View>
        {unreadCount > 0 && (
          <TouchableOpacity style={styles.markAllBtn} onPress={handleMarkAllRead}>
            <Text style={styles.markAllText}>Mark all read</Text>
          </TouchableOpacity>
        )}
      </View>

      {loading ? (
        <View style={styles.loadingContainer}>
          <ActivityIndicator size="large" color={COLORS.primary} />
        </View>
      ) : (
        <FlatList
          data={notifications}
          renderItem={renderNotification}
          keyExtractor={(item) => item.id}
          ListEmptyComponent={renderEmpty}
          refreshControl={
            <RefreshControl
              refreshing={refreshing}
              onRefresh={handleRefresh}
              tintColor={COLORS.primary}
            />
          }
          contentContainerStyle={notifications.length === 0 ? { flex: 1 } : { paddingBottom: 40 }}
        />
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: COLORS.background,
  },
  titleBar: {
    paddingHorizontal: 24,
    paddingVertical: 16,
    borderBottomWidth: 1,
    borderBottomColor: COLORS.border,
    flexDirection: 'row',
    alignItems: 'center',
  },
  screenTitle: {
    fontFamily: FONTS.family.display,
    fontSize: 38,
    fontWeight: '400',
    color: COLORS.text,
    letterSpacing: -1,
  },
  screenSubtitle: {
    fontFamily: FONTS.family.mono,
    fontSize: 10,
    color: 'rgba(229, 226, 225, 0.5)',
    textTransform: 'uppercase',
    letterSpacing: 2,
    marginTop: 2,
  },
  markAllBtn: {
    paddingHorizontal: 12,
    paddingVertical: 6,
    borderRadius: 4,
    backgroundColor: COLORS.backgroundSecondary,
    borderWidth: 1,
    borderColor: COLORS.border,
  },
  markAllText: {
    fontFamily: FONTS.family.mono,
    fontSize: 10,
    color: COLORS.textSecondary,
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  loadingContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  notifRow: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: SPACING.xl,
    paddingVertical: SPACING.md,
    borderBottomWidth: 1,
    borderBottomColor: COLORS.border,
    gap: SPACING.md,
  },
  notifRowUnread: {
    backgroundColor: 'rgba(200, 30, 30, 0.04)',
  },
  iconCircle: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: COLORS.backgroundSecondary,
    alignItems: 'center',
    justifyContent: 'center',
    flexShrink: 0,
  },
  iconCircleUnread: {
    backgroundColor: 'rgba(200, 30, 30, 0.1)',
  },
  notifContent: {
    flex: 1,
  },
  notifText: {
    fontFamily: FONTS.family.body,
    fontSize: 14,
    color: COLORS.text,
    lineHeight: 20,
  },
  notifUsername: {
    fontWeight: '700',
    color: COLORS.text,
  },
  notifPreview: {
    fontFamily: FONTS.family.mono,
    fontSize: 11,
    color: COLORS.textSecondary,
    marginTop: 2,
    fontStyle: 'italic',
  },
  notifTime: {
    fontFamily: FONTS.family.mono,
    fontSize: 10,
    color: COLORS.textTertiary,
    textTransform: 'uppercase',
    letterSpacing: 1,
    marginTop: 4,
  },
  unreadDot: {
    width: 8,
    height: 8,
    borderRadius: 4,
    backgroundColor: COLORS.primary,
    flexShrink: 0,
  },
  emptyContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingHorizontal: SPACING.xxxl,
  },
  emptyTitle: {
    fontFamily: FONTS.family.display,
    fontSize: 22,
    color: COLORS.text,
    marginTop: SPACING.lg,
    textAlign: 'center',
  },
  emptySubtitle: {
    fontFamily: FONTS.family.body,
    fontSize: 14,
    color: COLORS.textSecondary,
    textAlign: 'center',
    marginTop: SPACING.sm,
    lineHeight: 20,
  },
});
