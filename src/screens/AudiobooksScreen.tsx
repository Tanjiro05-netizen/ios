import React, { useState, useEffect, useMemo } from 'react';
import {
  View,
  Text,
  StyleSheet,
  FlatList,
  TouchableOpacity,
  Image,
  TextInput,
  ActivityIndicator,
  RefreshControl,
  ScrollView,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { useNavigation } from '@react-navigation/native';
import { NativeStackNavigationProp } from '@react-navigation/native-stack';

import { supabase } from '../lib/supabase';
import { Audiobook, RootStackParamList } from '../types';
import { COLORS, FONTS, SPACING } from '../constants';
import AudioPlayer from '../components/AudioPlayer';

type NavigationProp = NativeStackNavigationProp<RootStackParamList>;

const formatDuration = (seconds: number | null) => {
  if (!seconds || isNaN(seconds)) return null;
  const h = Math.floor(seconds / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m`;
};

export default function AudiobooksScreen() {
  const navigation = useNavigation<NavigationProp>();

  const [audiobooks, setAudiobooks] = useState<Audiobook[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [selectedId, setSelectedId] = useState<string | null>(null);
  const [activeCategory, setActiveCategory] = useState<string>('All');

  const fetchAudiobooks = async () => {
    try {
      const { data, error } = await supabase
        .from('audiobooks')
        .select('*')
        .order('sort_order');

      if (error) {
        console.error('Supabase error fetching audiobooks:', error);
        return;
      }

      setAudiobooks((data as Audiobook[]) || []);
    } catch (err) {
      console.error('Error fetching audiobooks:', err);
    } finally {
      setLoading(false);
      setRefreshing(false);
    }
  };

  useEffect(() => {
    fetchAudiobooks();
  }, []);

  const handleRefresh = () => {
    setRefreshing(true);
    fetchAudiobooks();
  };

  // Derive categories
  const categories = useMemo(() => {
    const cats = new Set(audiobooks.map((a) => a.category).filter(Boolean) as string[]);
    return ['All', ...Array.from(cats).sort()];
  }, [audiobooks]);

  // Filter list
  const filtered = useMemo(() => {
    let list = audiobooks;
    if (activeCategory !== 'All') {
      list = list.filter((a) => a.category === activeCategory);
    }
    if (searchQuery.trim()) {
      const q = searchQuery.trim().toLowerCase();
      list = list.filter(
        (a) =>
          `${a.title} ${a.author || ''} ${a.narrator || ''} ${a.category || ''} ${a.description || ''}`
            .toLowerCase()
            .includes(q),
      );
    }
    return list;
  }, [audiobooks, activeCategory, searchQuery]);

  const selectedBook = audiobooks.find((a) => a.id === selectedId) || null;

  const renderHeader = () => (
    <View style={styles.headerContainer}>
      <View style={{ flexDirection: 'row', justifyContent: 'flex-end', marginBottom: SPACING.lg }}>
        <TouchableOpacity onPress={() => navigation.navigate('Settings')}>
          <Ionicons name="settings-outline" size={24} color={COLORS.textSecondary} />
        </TouchableOpacity>
      </View>

      <View style={styles.heroRow}>
        <View style={styles.heroIconWrapper}>
          <Ionicons name="headset" size={28} color="#c81e1e" />
        </View>
        <View style={styles.heroTextWrapper}>
          <Text style={styles.heroTitle}>Audiobooks</Text>
          <Text style={styles.heroSubtitle}>
            Listen to foundational Marxist texts narrated for study
          </Text>
        </View>
      </View>

      <View style={styles.searchSection}>
        <View style={styles.searchInputWrapper}>
          <Ionicons
            name="search"
            size={20}
            color={COLORS.textSecondary}
            style={styles.searchIcon}
          />
          <TextInput
            style={styles.searchInput}
            placeholder="Search audiobooks..."
            placeholderTextColor={COLORS.textSecondary}
            value={searchQuery}
            onChangeText={setSearchQuery}
          />
          {searchQuery !== '' && (
            <TouchableOpacity onPress={() => setSearchQuery('')} style={styles.clearSearchBtn}>
              <Ionicons name="close-circle" size={18} color={COLORS.textSecondary} />
            </TouchableOpacity>
          )}
        </View>

        <ScrollView
          horizontal
          showsHorizontalScrollIndicator={false}
          style={styles.categoriesScroll}
          contentContainerStyle={styles.categoriesContainer}
        >
          {categories.map((cat) => (
            <TouchableOpacity
              key={cat}
              style={[styles.categoryPill, activeCategory === cat && styles.categoryPillActive]}
              onPress={() => setActiveCategory(cat)}
            >
              <Text
                style={[styles.categoryText, activeCategory === cat && styles.categoryTextActive]}
              >
                {cat}
              </Text>
            </TouchableOpacity>
          ))}
        </ScrollView>
      </View>
    </View>
  );

  const renderBookItem = ({ item }: { item: Audiobook }) => {
    const isActive = selectedId === item.id;
    const dur = formatDuration(item.duration_seconds);

    return (
      <TouchableOpacity
        style={[styles.bookCard, isActive && styles.bookCardActive]}
        onPress={() => setSelectedId(item.id)}
        activeOpacity={0.7}
      >
        <View style={styles.bookRow}>
          {/* Cover */}
          <View style={styles.coverContainer}>
            {item.cover_url ? (
              <Image source={{ uri: item.cover_url }} style={styles.bookCover} />
            ) : (
              <View style={styles.bookPlaceholder}>
                <Ionicons name="headset" size={36} color="#c81e1e" />
              </View>
            )}
            {/* Now-playing indicator */}
            {isActive && (
              <View style={styles.nowPlayingBadge}>
                <View style={styles.nowPlayingDot} />
              </View>
            )}
            {/* Duration badge */}
            {dur && (
              <View style={styles.durationBadge}>
                <Text style={styles.durationText}>{dur}</Text>
              </View>
            )}
          </View>

          {/* Info */}
          <View style={styles.bookInfo}>
            <Text
              style={[styles.bookTitle, isActive && { color: '#ffcccc' }]}
              numberOfLines={2}
            >
              {item.title}
            </Text>
            {item.author && (
              <Text style={styles.bookAuthor} numberOfLines={1}>
                {item.author}
              </Text>
            )}
            <View style={styles.badgesRow}>
              {item.category && (
                <View style={styles.badgeCategory}>
                  <Text style={styles.badgeCategoryText}>{item.category}</Text>
                </View>
              )}
              {item.is_featured && (
                <View style={styles.badgeFeatured}>
                  <Text style={styles.badgeFeaturedText}>FEATURED</Text>
                </View>
              )}
            </View>
          </View>

          {/* Play icon hint */}
          <View style={styles.playHint}>
            <Ionicons
              name={isActive ? 'pause-circle' : 'play-circle'}
              size={32}
              color={isActive ? '#c81e1e' : 'rgba(255,255,255,0.15)'}
            />
          </View>
        </View>
      </TouchableOpacity>
    );
  };

  // ── Full-screen player ──
  if (selectedBook) {
    return (
      <SafeAreaView style={styles.container} edges={['top']}>
        <AudioPlayer audiobook={selectedBook} onClose={() => setSelectedId(null)} />
      </SafeAreaView>
    );
  }

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      {loading ? (
        <View style={styles.centerContainer}>
          <ActivityIndicator size="large" color="#c81e1e" />
        </View>
      ) : (
        <FlatList
          data={filtered}
          keyExtractor={(item) => item.id}
          renderItem={renderBookItem}
          ListHeaderComponent={renderHeader}
          contentContainerStyle={styles.listContent}
          ListEmptyComponent={
            <View style={styles.emptyContainer}>
              <Ionicons name="headset-outline" size={48} color={COLORS.textSecondary} />
              <Text style={styles.emptyText}>
                {audiobooks.length === 0
                  ? 'No audiobooks available yet.'
                  : 'No audiobooks match your search.'}
              </Text>
            </View>
          }
          refreshControl={
            <RefreshControl refreshing={refreshing} onRefresh={handleRefresh} tintColor="#c81e1e" />
          }
        />
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#050505',
  },
  centerContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
  },
  listContent: {
    paddingBottom: 40,
  },
  headerContainer: {
    paddingHorizontal: SPACING.md,
    paddingTop: SPACING.md,
    paddingBottom: SPACING.lg,
  },
  heroRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: SPACING.md,
    marginBottom: SPACING.lg,
  },
  heroIconWrapper: {
    width: 64,
    height: 64,
    borderRadius: 16,
    backgroundColor: 'rgba(200,30,30,0.15)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  heroTextWrapper: {
    flex: 1,
  },
  heroTitle: {
    fontFamily: FONTS.family.display,
    color: COLORS.text,
    fontSize: 32,
    fontWeight: '400',
    marginBottom: 4,
  },
  heroSubtitle: {
    fontFamily: FONTS.family.body,
    color: COLORS.textSecondary,
    fontSize: 14,
    lineHeight: 20,
  },
  searchSection: {
    gap: SPACING.md,
  },
  searchInputWrapper: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(255,255,255,0.04)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    borderRadius: 14,
    paddingHorizontal: SPACING.md,
  },
  searchIcon: {
    marginRight: SPACING.sm,
  },
  searchInput: {
    flex: 1,
    height: 48,
    fontFamily: FONTS.family.mono,
    color: COLORS.text,
    fontSize: 10,
    textTransform: 'uppercase',
    letterSpacing: 2,
  },
  clearSearchBtn: {
    padding: SPACING.xs,
  },
  categoriesScroll: {
    maxHeight: 40,
  },
  categoriesContainer: {
    gap: SPACING.sm,
    paddingRight: SPACING.md,
  },
  categoryPill: {
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 20,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.05)',
    backgroundColor: 'rgba(255,255,255,0.03)',
  },
  categoryPillActive: {
    backgroundColor: 'rgba(200,30,30,0.12)',
    borderColor: 'rgba(200,30,30,0.3)',
  },
  categoryText: {
    fontFamily: FONTS.family.mono,
    color: 'rgba(229, 226, 225, 0.4)',
    fontSize: 10,
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  categoryTextActive: {
    color: '#fff',
  },

  // ── Book cards ──
  bookCard: {
    backgroundColor: 'rgba(255,255,255,0.02)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.05)',
    borderRadius: 16,
    padding: 16,
    marginHorizontal: SPACING.md,
    marginBottom: 12,
  },
  bookCardActive: {
    backgroundColor: 'rgba(200,30,30,0.06)',
    borderColor: 'rgba(200,30,30,0.2)',
  },
  bookRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 16,
  },
  coverContainer: {
    position: 'relative',
  },
  bookCover: {
    width: 100,
    height: 100,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
  },
  bookPlaceholder: {
    width: 100,
    height: 100,
    borderRadius: 14,
    backgroundColor: 'rgba(200,30,30,0.12)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  nowPlayingBadge: {
    position: 'absolute',
    top: 6,
    left: 6,
    width: 12,
    height: 12,
    borderRadius: 6,
    backgroundColor: 'rgba(0,0,0,0.6)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  nowPlayingDot: {
    width: 6,
    height: 6,
    borderRadius: 3,
    backgroundColor: '#c81e1e',
  },
  durationBadge: {
    position: 'absolute',
    bottom: 6,
    right: 6,
    backgroundColor: 'rgba(0,0,0,0.7)',
    paddingHorizontal: 6,
    paddingVertical: 2,
    borderRadius: 6,
  },
  durationText: {
    fontSize: 9,
    fontWeight: '600',
    color: 'rgba(255,255,255,0.7)',
    fontFamily: 'Courier',
    letterSpacing: 0.5,
  },
  bookInfo: {
    flex: 1,
    justifyContent: 'center',
  },
  bookTitle: {
    fontFamily: FONTS.family.display,
    color: COLORS.text,
    fontSize: 18,
    fontWeight: '500',
    marginBottom: 4,
    lineHeight: 22,
  },
  bookAuthor: {
    fontFamily: FONTS.family.mono,
    color: COLORS.textSecondary,
    fontSize: 10,
    textTransform: 'uppercase',
    letterSpacing: 1,
    marginBottom: 10,
  },
  badgesRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 6,
  },
  badgeCategory: {
    backgroundColor: 'rgba(255,255,255,0.05)',
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 6,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
  },
  badgeCategoryText: {
    fontFamily: FONTS.family.mono,
    color: COLORS.textSecondary,
    fontSize: 8,
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  badgeFeatured: {
    backgroundColor: 'rgba(200,30,30,0.1)',
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 6,
    borderWidth: 1,
    borderColor: 'rgba(200,30,30,0.3)',
  },
  badgeFeaturedText: {
    fontFamily: FONTS.family.mono,
    color: '#ef4444',
    fontSize: 8,
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  playHint: {
    paddingLeft: 4,
  },
  emptyContainer: {
    alignItems: 'center',
    justifyContent: 'center',
    paddingVertical: 60,
  },
  emptyText: {
    fontFamily: FONTS.family.mono,
    color: COLORS.textSecondary,
    fontSize: 12,
    marginTop: SPACING.md,
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
});
