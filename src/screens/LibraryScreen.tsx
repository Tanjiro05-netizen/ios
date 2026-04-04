import React, { useState, useEffect, useCallback } from 'react';
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
  Dimensions,
  Alert,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { useNavigation, useFocusEffect } from '@react-navigation/native';
import { StackNavigationProp } from '@react-navigation/stack';
import { COLORS, FONTS, SPACING } from '../constants';
import { api } from '../lib/api';
import { Book, RootStackParamList } from '../types';
import { downloadsStorage, downloadBookPdf, DownloadedBook } from '../lib/downloads';
import toast from '../lib/toast';

type NavigationProp = StackNavigationProp<RootStackParamList>;

const { width } = Dimensions.get('window');
const CARD_WIDTH = (width - 48) / 2; // 2 columns with padding

type TabType = 'official' | 'community';

export default function LibraryScreen() {
  const navigation = useNavigation<NavigationProp>();
  const [activeTab, setActiveTab] = useState<TabType>('official');
  const [books, setBooks] = useState<Book[]>([]);
  const [loading, setLoading] = useState(true);
  const [refreshing, setRefreshing] = useState(false);
  const [searchQuery, setSearchQuery] = useState('');
  const [page, setPage] = useState(1);
  const [hasMore, setHasMore] = useState(true);
  const [loadingMore, setLoadingMore] = useState(false);

  // Filter states
  const [categories, setCategories] = useState<string[]>([]);
  const [selectedCategory, setSelectedCategory] = useState<string | null>(null);
  const [showFilters, setShowFilters] = useState(false);

  // Download states
  const [downloadedIds, setDownloadedIds] = useState<Set<string>>(new Set());
  const [downloadingId, setDownloadingId] = useState<string | null>(null);
  const [downloadProgress, setDownloadProgress] = useState(0);

  // Refresh downloaded list when screen focuses
  useFocusEffect(
    useCallback(() => {
      refreshDownloadedIds();
    }, [])
  );

  const refreshDownloadedIds = async () => {
    const all = await downloadsStorage.getAll();
    setDownloadedIds(new Set(all.map((d) => d.bookId)));
  };

  const handleDownload = async (book: Book) => {
    if (!book.pdf_filename) {
      Alert.alert('Not Available', 'This book does not have a downloadable PDF.');
      return;
    }
    if (downloadedIds.has(book.id)) {
      Alert.alert(
        'Already Downloaded',
        `"${book.title}" is saved for offline reading.`,
        [
          { text: 'Read Now', onPress: () => handleBookPress(book) },
          {
            text: 'Remove Download',
            style: 'destructive',
            onPress: async () => {
              await downloadsStorage.remove(book.id);
              await refreshDownloadedIds();
              toast.info('Download removed', `"${book.title}" removed from offline storage.`);
            },
          },
          { text: 'Cancel', style: 'cancel' },
        ],
      );
      return;
    }

    try {
      setDownloadingId(book.id);
      setDownloadProgress(0);
      const remoteUrl = api.getBookPdfUrl(book.pdf_filename);
      await downloadBookPdf(
        book.id,
        book.title,
        book.author ?? undefined,
        book.pdf_filename,
        remoteUrl,
        (progress) => setDownloadProgress(progress),
      );
      await refreshDownloadedIds();
      toast.success('Downloaded!', `"${book.title}" saved for offline reading.`);
    } catch (err) {
      console.error('Download error:', err);
      toast.error('Download failed', 'Please check your connection and try again.');
    } finally {
      setDownloadingId(null);
      setDownloadProgress(0);
    }
  };

  const loadBooks = useCallback(async (reset = false) => {
    if (reset) {
      setLoading(true);
      setPage(1);
    }

    try {
      const response = await api.getBooks({
        filter: activeTab,
        category: selectedCategory || undefined,
        search: searchQuery || undefined,
        page: reset ? 1 : page,
        limit: 20,
      });

      if (reset) {
        setBooks(response.data);
      } else {
        setBooks(prev => [...prev, ...response.data]);
      }

      setHasMore(page < response.totalPages);
    } catch (error) {
      console.error('Error loading books:', error);
    } finally {
      setLoading(false);
      setRefreshing(false);
      setLoadingMore(false);
    }
  }, [activeTab, selectedCategory, searchQuery, page]);

  // Load categories on mount
  useEffect(() => {
    const loadCategories = async () => {
      const cats = await api.getBookCategories();
      setCategories(cats);
    };
    loadCategories();
  }, []);

  // Reload when tab or filters change
  useEffect(() => {
    loadBooks(true);
  }, [activeTab, selectedCategory]);

  // Debounced search
  useEffect(() => {
    const timer = setTimeout(() => {
      if (searchQuery !== '') {
        loadBooks(true);
      }
    }, 500);
    return () => clearTimeout(timer);
  }, [searchQuery]);

  const handleRefresh = () => {
    setRefreshing(true);
    loadBooks(true);
  };

  const handleLoadMore = () => {
    if (!loadingMore && hasMore) {
      setLoadingMore(true);
      setPage(prev => prev + 1);
      loadBooks(false);
    }
  };

  const handleBookPress = (book: Book) => {
    navigation.navigate('BookReader', { bookId: book.id });
  };

  const renderBookCard = ({ item }: { item: Book }) => {
    const isDownloaded = downloadedIds.has(item.id);
    const isDownloading = downloadingId === item.id;

    return (
      <TouchableOpacity
        style={styles.bookCard}
        onPress={() => handleBookPress(item)}
        activeOpacity={0.7}
      >
        <View style={styles.coverContainer}>
          {item.cover_image_url ? (
            <Image
              source={{ uri: item.cover_image_url }}
              style={styles.coverImage}
              resizeMode="cover"
            />
          ) : (
            <View style={styles.placeholderCover}>
              <Ionicons name="book" size={40} color={COLORS.textTertiary} />
            </View>
          )}
          {isDownloaded && (
            <View style={styles.downloadedBadge}>
              <Ionicons name="checkmark-circle" size={14} color="#00BA7C" />
            </View>
          )}
        </View>
        <View style={styles.bookInfo}>
          <Text style={styles.bookTitle} numberOfLines={2}>
            {item.title}
          </Text>
          <Text style={styles.bookAuthor} numberOfLines={1}>
            {item.author || 'Unknown Author'}
          </Text>
          {item.year && (
            <Text style={styles.bookYear}>{item.year}</Text>
          )}
          <View style={styles.bookMeta}>
            <View style={styles.metaItem}>
              <Ionicons name="document-text-outline" size={12} color={COLORS.textSecondary} />
              <Text style={styles.metaText}>{item.pages || '?'} pages</Text>
            </View>
            <TouchableOpacity
              style={styles.downloadBtn}
              onPress={(e) => {
                e.stopPropagation?.();
                handleDownload(item);
              }}
              disabled={isDownloading}
              hitSlop={{ top: 8, bottom: 8, left: 8, right: 8 }}
            >
              {isDownloading ? (
                <View style={styles.downloadingRow}>
                  <ActivityIndicator size="small" color={COLORS.primary} />
                  <Text style={styles.downloadProgressText}>{downloadProgress}%</Text>
                </View>
              ) : (
                <Ionicons
                  name={isDownloaded ? 'cloud-done' : 'cloud-download-outline'}
                  size={18}
                  color={isDownloaded ? '#00BA7C' : COLORS.primary}
                />
              )}
            </TouchableOpacity>
          </View>
        </View>
      </TouchableOpacity>
    );
  };

  const renderHeader = () => (
    <View style={styles.header}>
      {/* Search Bar / Controls */}
      <View style={styles.controlsRow}>
        <View style={styles.searchContainer}>
          <Ionicons name="search" size={16} color={COLORS.textTertiary} style={styles.searchIcon} />
          <TextInput
            style={styles.searchInput}
            placeholder="QUERY ARCHIVE..."
            placeholderTextColor="rgba(229, 226, 225, 0.3)"
            value={searchQuery}
            onChangeText={setSearchQuery}
          />
          {searchQuery !== '' && (
            <TouchableOpacity onPress={() => setSearchQuery('')}>
              <Ionicons name="close-circle" size={16} color={COLORS.textTertiary} />
            </TouchableOpacity>
          )}
        </View>
        
        <TouchableOpacity
          style={styles.filterButton}
          onPress={() => setShowFilters(!showFilters)}
        >
          <Ionicons
            name="options-outline"
            size={20}
            color={selectedCategory ? COLORS.primary : COLORS.textTertiary}
          />
        </TouchableOpacity>
      </View>

      {/* Tabs */}
      <View style={styles.tabContainer}>
        <TouchableOpacity
          style={[styles.tab, activeTab === 'official' && styles.activeTab]}
          onPress={() => setActiveTab('official')}
        >
          <Text style={[styles.tabText, activeTab === 'official' && styles.activeTabText]}>
            Library
          </Text>
        </TouchableOpacity>
        <TouchableOpacity
          style={[styles.tab, activeTab === 'community' && styles.activeTab]}
          onPress={() => setActiveTab('community')}
        >
          <Text style={[styles.tabText, activeTab === 'community' && styles.activeTabText]}>
            Community
          </Text>
        </TouchableOpacity>
      </View>

      {/* Filter Pills */}
      {showFilters && categories.length > 0 && (
        <View style={styles.filterContainer}>
          <TouchableOpacity
            style={[styles.filterPill, !selectedCategory && styles.activeFilterPill]}
            onPress={() => setSelectedCategory(null)}
          >
            <Text style={[styles.filterPillText, !selectedCategory && styles.activeFilterPillText]}>
              All Eras
            </Text>
          </TouchableOpacity>
          {categories.map(category => (
            <TouchableOpacity
              key={category}
              style={[styles.filterPill, selectedCategory === category && styles.activeFilterPill]}
              onPress={() => setSelectedCategory(category)}
            >
              <Text style={[styles.filterPillText, selectedCategory === category && styles.activeFilterPillText]}>
                {category}
              </Text>
            </TouchableOpacity>
          ))}
        </View>
      )}
    </View>
  );

  const renderEmpty = () => (
    <View style={styles.emptyContainer}>
      <Ionicons name="library-outline" size={64} color={COLORS.textSecondary} />
      <Text style={styles.emptyTitle}>No Books Found</Text>
      <Text style={styles.emptySubtitle}>
        {searchQuery
          ? 'Try a different search term'
          : activeTab === 'official'
            ? 'Official library books will appear here'
            : 'Community uploads will appear here'}
      </Text>
    </View>
  );

  const renderFooter = () => {
    if (!loadingMore) return null;
    return (
      <View style={styles.loadingMore}>
        <ActivityIndicator size="small" color={COLORS.primary} />
      </View>
    );
  };

  return (
    <SafeAreaView style={styles.container} edges={['top']}>
      <View style={styles.titleBar}>
        <View style={{ flex: 1 }}>
          <Text style={styles.screenTitle}>Digital Collection</Text>
        </View>
        <TouchableOpacity onPress={() => navigation.navigate('Settings')}>
          <Ionicons name="settings-outline" size={24} color={COLORS.textSecondary} />
        </TouchableOpacity>
      </View>

      {loading && page === 1 ? (
        <View style={styles.loadingContainer}>
          <ActivityIndicator size="large" color={COLORS.primary} />
          <Text style={styles.loadingText}>Loading books...</Text>
        </View>
      ) : (
        <FlatList
          data={books}
          renderItem={renderBookCard}
          keyExtractor={(item) => item.id}
          numColumns={2}
          columnWrapperStyle={styles.row}
          contentContainerStyle={styles.listContent}
          ListHeaderComponent={renderHeader}
          ListEmptyComponent={renderEmpty}
          ListFooterComponent={renderFooter}
          refreshControl={
            <RefreshControl
              refreshing={refreshing}
              onRefresh={handleRefresh}
              tintColor={COLORS.primary}
            />
          }
          onEndReached={handleLoadMore}
          onEndReachedThreshold={0.5}
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
    borderBottomWidth: 0,
    flexDirection: 'row',
    alignItems: 'baseline',
    gap: 16,
    flexWrap: 'wrap',
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
  },
  header: {
    paddingHorizontal: 16,
    paddingTop: 12,
  },
  controlsRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    marginBottom: 20,
  },
  searchContainer: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: COLORS.backgroundSecondary,
    borderRadius: 24,
    paddingHorizontal: 16,
  },
  searchIcon: {
    marginRight: 12,
  },
  searchInput: {
    flex: 1,
    height: 48,
    fontFamily: FONTS.family.mono,
    fontSize: 10,
    letterSpacing: 2,
    color: COLORS.text,
    textTransform: 'uppercase',
  },
  filterButton: {
    width: 48,
    height: 48,
    backgroundColor: COLORS.backgroundSecondary,
    borderRadius: 24,
    alignItems: 'center',
    justifyContent: 'center',
  },
  tabContainer: {
    flexDirection: 'row',
    gap: 8,
    marginBottom: 16,
  },
  tab: {
    paddingHorizontal: 20,
    paddingVertical: 10,
    backgroundColor: COLORS.backgroundSecondary,
    borderRadius: 24,
  },
  activeTab: {
    backgroundColor: COLORS.primary,
  },
  tabText: {
    fontFamily: FONTS.family.mono,
    fontSize: 10,
    fontWeight: '600',
    textTransform: 'uppercase',
    letterSpacing: 1,
    color: COLORS.textSecondary,
  },
  activeTabText: {
    color: '#fff',
  },
  filterContainer: {
    flexDirection: 'row',
    flexWrap: 'wrap',
    gap: 8,
    marginBottom: 16,
  },
  filterPill: {
    paddingHorizontal: 16,
    paddingVertical: 8,
    borderRadius: 20,
    backgroundColor: COLORS.backgroundSecondary,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.05)',
  },
  activeFilterPill: {
    backgroundColor: COLORS.cardHover,
    borderColor: COLORS.primaryLight,
  },
  filterPillText: {
    fontFamily: FONTS.family.mono,
    fontSize: 10,
    textTransform: 'uppercase',
    letterSpacing: 1,
    color: 'rgba(229, 226, 225, 0.4)',
  },
  activeFilterPillText: {
    color: COLORS.text,
  },
  listContent: {
    paddingBottom: 40,
  },
  row: {
    justifyContent: 'space-between',
    paddingHorizontal: 16,
    marginTop: 16,
  },
  bookCard: {
    width: CARD_WIDTH,
    backgroundColor: COLORS.card,
    borderRadius: 12,
    overflow: 'hidden',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.05)',
  },
  coverContainer: {
    position: 'relative',
    height: CARD_WIDTH * 1.33,
  },
  coverImage: {
    width: '100%',
    height: '100%',
    opacity: 0.85,
  },
  placeholderCover: {
    width: '100%',
    height: '100%',
    backgroundColor: COLORS.border,
    alignItems: 'center',
    justifyContent: 'center',
  },
  bookInfo: {
    padding: 16,
  },
  bookTitle: {
    fontFamily: FONTS.family.display,
    fontSize: 22,
    color: COLORS.text,
    marginBottom: 4,
    lineHeight: 24,
  },
  bookAuthor: {
    fontFamily: FONTS.family.mono,
    fontSize: 10,
    textTransform: 'uppercase',
    letterSpacing: 1,
    color: COLORS.textSecondary,
    marginBottom: 12,
  },
  bookYear: {
    fontFamily: FONTS.family.mono,
    fontSize: 10,
    color: COLORS.textSecondary,
    marginBottom: 6,
  },
  bookMeta: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    borderTopWidth: 1,
    borderTopColor: 'rgba(255,255,255,0.05)',
    paddingTop: 12,
    marginTop: 4,
  },
  metaItem: {
    flexDirection: 'column',
    alignItems: 'flex-start',
    gap: 4,
  },
  metaText: {
    fontFamily: FONTS.family.mono,
    fontSize: 9,
    color: COLORS.textSecondary,
    textTransform: 'uppercase',
  },
  downloadBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    padding: 4,
  },
  downloadingRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 4,
  },
  downloadProgressText: {
    fontFamily: FONTS.family.mono,
    fontSize: 8,
    color: COLORS.primary,
    letterSpacing: 1,
  },
  downloadedBadge: {
    position: 'absolute',
    bottom: 8,
    right: 8,
    backgroundColor: 'rgba(0,0,0,0.7)',
    borderRadius: 12,
    padding: 4,
  },
  loadingContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
  },
  loadingText: {
    marginTop: 12,
    fontSize: 16,
    color: COLORS.textSecondary,
  },
  loadingMore: {
    paddingVertical: 20,
    alignItems: 'center',
  },
  emptyContainer: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    paddingTop: 80,
    paddingHorizontal: 32,
  },
  emptyTitle: {
    fontSize: 18,
    fontWeight: '600',
    color: COLORS.text,
    marginTop: 16,
  },
  emptySubtitle: {
    fontSize: 14,
    color: COLORS.textSecondary,
    textAlign: 'center',
    marginTop: 8,
  },
});
