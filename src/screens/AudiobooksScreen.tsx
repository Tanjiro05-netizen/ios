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
import { StackNavigationProp } from '@react-navigation/stack';

import { supabase } from '../lib/supabase';
import { Audiobook, RootStackParamList } from '../types';
import { COLORS, FONTS, SPACING } from '../constants';
import AudioPlayer from '../components/AudioPlayer';

type NavigationProp = StackNavigationProp<RootStackParamList>;

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
      
      setAudiobooks(data as Audiobook[] || []);
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
            .includes(q)
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
          <Ionicons name="search" size={20} color={COLORS.textSecondary} style={styles.searchIcon} />
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
               style={[
                 styles.categoryPill,
                 activeCategory === cat && styles.categoryPillActive
               ]}
               onPress={() => setActiveCategory(cat)}
             >
               <Text 
                 style={[
                   styles.categoryText,
                   activeCategory === cat && styles.categoryTextActive
                 ]}
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
    return (
      <TouchableOpacity
        style={[styles.bookCard, isActive && styles.bookCardActive]}
        onPress={() => setSelectedId(isActive ? null : item.id)}
        activeOpacity={0.7}
      >
        <View style={styles.bookRow}>
          {item.cover_url ? (
            <Image source={{ uri: item.cover_url }} style={styles.bookCover} />
          ) : (
             <View style={styles.bookPlaceholder}>
               <Ionicons name="headset" size={24} color="#c81e1e" />
             </View>
          )}
          <View style={styles.bookInfo}>
            <Text style={[styles.bookTitle, isActive && { color: '#ffcccc' }]} numberOfLines={1}>
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
        </View>
      </TouchableOpacity>
    );
  };

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      {loading ? (
        <View style={styles.centerContainer}>
          <ActivityIndicator size="large" color="#c81e1e" />
        </View>
      ) : (
        <View style={styles.contentWrapper}>
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
                    ? "No audiobooks available yet."
                    : "No audiobooks match your search."}
                </Text>
              </View>
            }
            refreshControl={
              <RefreshControl
                refreshing={refreshing}
                onRefresh={handleRefresh}
                tintColor="#c81e1e"
              />
            }
          />
          
          {selectedBook && (
            <View style={styles.playerPanel}>
              <AudioPlayer audiobook={selectedBook} onClose={() => setSelectedId(null)} />
            </View>
          )}
        </View>
      )}
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#090909',
  },
  centerContainer: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: '#090909',
  },
  contentWrapper: {
    flex: 1,
  },
  listContent: {
    paddingBottom: 160, // Space for player if open
  },
  headerContainer: {
    paddingHorizontal: SPACING.md,
    paddingTop: SPACING.md,
    paddingBottom: SPACING.lg,
  },
  backLink: {
    flexDirection: 'row',
    alignItems: 'center',
    marginBottom: SPACING.lg,
    gap: 4,
  },
  backText: {
    fontFamily: FONTS.family.mono,
    color: COLORS.textSecondary,
    fontSize: 10,
    textTransform: 'uppercase',
    letterSpacing: 1,
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
    backgroundColor: 'rgba(255,255,255,0.05)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
    borderRadius: 12,
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
    backgroundColor: COLORS.card,
  },
  categoryPillActive: {
    backgroundColor: COLORS.cardHover,
    borderColor: COLORS.primaryLight,
  },
  categoryText: {
    fontFamily: FONTS.family.mono,
    color: 'rgba(229, 226, 225, 0.4)',
    fontSize: 10,
    textTransform: 'uppercase',
    letterSpacing: 1,
  },
  categoryTextActive: {
    color: COLORS.text,
  },
  bookCard: {
    backgroundColor: COLORS.card,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.05)',
    borderRadius: 16,
    padding: SPACING.lg,
    marginHorizontal: SPACING.lg,
    marginBottom: SPACING.md,
  },
  bookCardActive: {
    backgroundColor: COLORS.cardHover,
    borderColor: COLORS.primaryLight,
  },
  bookRow: {
    flexDirection: 'row',
    alignItems: 'flex-start',
    gap: SPACING.md,
  },
  bookCover: {
    width: 64,
    height: 64,
    borderRadius: 8,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
  },
  bookPlaceholder: {
    width: 64,
    height: 64,
    borderRadius: 8,
    backgroundColor: 'rgba(200,30,30,0.2)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  bookInfo: {
    flex: 1,
  },
  bookTitle: {
    fontFamily: FONTS.family.display,
    color: COLORS.text,
    fontSize: 22,
    marginBottom: 4,
  },
  bookAuthor: {
    fontFamily: FONTS.family.mono,
    color: COLORS.textSecondary,
    fontSize: 10,
    textTransform: 'uppercase',
    letterSpacing: 1,
    marginBottom: 12,
  },
  badgesRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: SPACING.xs,
  },
  badgeCategory: {
    backgroundColor: 'rgba(255,255,255,0.05)',
    paddingHorizontal: 8,
    paddingVertical: 4,
    borderRadius: 4,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
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
    borderRadius: 4,
    borderWidth: 1,
    borderColor: COLORS.primaryLight,
  },
  badgeFeaturedText: {
    fontFamily: FONTS.family.mono,
    color: COLORS.primaryLight,
    fontSize: 8,
    textTransform: 'uppercase',
    letterSpacing: 1,
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
  playerPanel: {
    position: 'absolute',
    bottom: SPACING.md,
    left: SPACING.md,
    right: SPACING.md,
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 10 },
    shadowOpacity: 0.5,
    shadowRadius: 20,
    elevation: 10,
  },
});
