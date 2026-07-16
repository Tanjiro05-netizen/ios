import React, { useEffect, useRef, useState, useCallback } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  ActivityIndicator,
  ScrollView,
  useWindowDimensions,
} from 'react-native';
import { useNavigation, useRoute, RouteProp } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import { SafeAreaView } from 'react-native-safe-area-context';
import AsyncStorage from '@react-native-async-storage/async-storage';
import * as FileSystem from 'expo-file-system/legacy';
import RenderHtml from 'react-native-render-html';

import { COLORS } from '../constants';
import { api } from '../lib/api';
import { useAuth } from '../hooks/useAuth';
import { Book, RootStackParamList } from '../types';
import { extractAndParseEpub, readChapterHtml, ParsedEpub, TocItem } from '../lib/epubParser';
import { cacheBookEpub } from '../lib/downloads';

type BookReaderRouteProp = RouteProp<RootStackParamList, 'BookReader'>;

const IDLE_TIMEOUT = 3000;

// ── Map EPUB Calibre CSS classes to RN styles ──
const CLASS_STYLES: Record<string, object> = {
  calibre6:  { fontStyle: 'italic' },
  calibre7:  { color: '#f4f4f5', fontWeight: '700' as const },
  calibre10: { color: 'rgba(255,255,255,0.38)' },
  calibre11: { color: 'rgba(255,255,255,0.5)' },
  calibre12: { color: '#d6d3cd' },
  calibre17: { color: 'rgba(255,255,255,0.38)' },
  calibre19: { color: '#93c5fd' },
  calibre20: { color: '#d6d3cd' },
  calibre21: { color: 'rgba(255,255,255,0.5)' },
  calibre22: { color: 'rgba(255,255,255,0.5)' },
  calibre23: { color: '#93c5fd' },
  calibre25: { color: '#d6d3cd' },
  calibre26: { color: 'rgba(255,255,255,0.5)', fontSize: 12 },
  calibre27: { fontStyle: 'italic' as const },
  calibre28: { color: '#f4f4f5', fontWeight: '700' as const },
  calibre35: { color: '#f4f4f5', fontWeight: '700' as const },
  H:         { color: '#f4f4f5', fontWeight: '700' as const, fontSize: 22 },
  H1:        { color: '#f4f4f5', fontWeight: '700' as const, fontSize: 26 },
  H2:        { color: '#f4f4f5', fontWeight: '700' as const, fontSize: 20 },
  H3:        { color: '#f4f4f5', fontWeight: '700' as const, fontSize: 18 },
  indentb:   { borderLeftWidth: 3, borderLeftColor: 'rgba(239,68,68,0.4)', paddingLeft: 18, fontStyle: 'italic' as const, color: '#c9c3b8' },
  quoteb:    { borderLeftWidth: 3, borderLeftColor: 'rgba(239,68,68,0.4)', paddingLeft: 18, color: '#c9c3b8' },
  term:      { color: '#93c5fd', fontWeight: 'bold' as const },
  enote:     { color: '#f87171', fontSize: 12, fontWeight: 'bold' as const },
  inote:     { color: 'rgba(255,255,255,0.38)', fontSize: 13 },
  context:   { color: 'rgba(255,255,255,0.42)', fontStyle: 'italic' as const },
  MsoNormal: { color: '#d6d3cd' },
  MsoToc:    { color: '#c4c0b8' },
  MsoToc1:   { color: '#c4c0b8' },
  MsoToc2:   { color: 'rgba(255,255,255,0.6)' },
};

const makeTagStyles = (fontSize: number) => ({
  body:    { backgroundColor: '#050505', padding: 0, margin: 0 },
  p:       { color: '#d6d3cd', fontSize, lineHeight: fontSize * 1.7, marginBottom: fontSize * 0.7, marginTop: 0, textAlign: 'left' as const },
  h1:      { color: '#f4f4f5', fontSize: Math.round(fontSize * 1.5), fontWeight: '700' as const, marginTop: fontSize * 1.5, marginBottom: fontSize * 0.5 },
  h2:      { color: '#f4f4f5', fontSize: Math.round(fontSize * 1.3), fontWeight: '700' as const, marginTop: fontSize * 1.3, marginBottom: fontSize * 0.4 },
  h3:      { color: '#f4f4f5', fontSize: Math.round(fontSize * 1.15), fontWeight: '700' as const, marginTop: fontSize, marginBottom: fontSize * 0.3 },
  h4:      { color: '#f4f4f5', fontSize: Math.round(fontSize * 1.05), fontWeight: '700' as const },
  em:      { fontStyle: 'italic' as const, color: '#d6d3cd' },
  i:       { fontStyle: 'italic' as const, color: '#d6d3cd' },
  strong:  { fontWeight: 'bold' as const, color: '#f4f4f5' },
  b:       { fontWeight: 'bold' as const, color: '#f4f4f5' },
  a:       { color: '#ef4444', textDecorationLine: 'none' as const },
  hr:      { borderTopWidth: 1, borderTopColor: 'rgba(255,255,255,0.08)', marginVertical: fontSize * 2 },
  img:     { maxWidth: '100%', height: 'auto', borderRadius: 8, marginVertical: fontSize },
  blockquote: { borderLeftWidth: 3, borderLeftColor: 'rgba(239,68,68,0.4)', paddingLeft: 18, color: '#c9c3b8', fontStyle: 'italic' as const, marginVertical: fontSize },
  li:      { color: '#d6d3cd', fontSize, lineHeight: fontSize * 1.6, marginBottom: 4 },
  ul:      { marginVertical: fontSize * 0.5 },
  ol:      { marginVertical: fontSize * 0.5 },
  span:    { color: '#d6d3cd', fontSize },
  div:     { color: '#d6d3cd', fontSize },
});

export default function BookReaderScreen() {
  const navigation = useNavigation();
  const route = useRoute<BookReaderRouteProp>();
  const { bookId } = route.params;
  const { width: windowWidth } = useWindowDimensions();
  const { user } = useAuth();

  const [book, setBook] = useState<Book | null>(null);
  const [parsed, setParsed] = useState<ParsedEpub | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const [chapterIndex, setChapterIndex] = useState(0);
  const [chapterHtml, setChapterHtml] = useState('');
  const [chapterLoading, setChapterLoading] = useState(false);

  const [showUI, setShowUI] = useState(true);
  const [showToc, setShowToc] = useState(false);
  const [showSettings, setShowSettings] = useState(false);
  const [fontSize, setFontSize] = useState(17);
  const [viewMode, setViewMode] = useState<'scroll' | 'paginated'>('scroll');

  const scrollRef = useRef<ScrollView>(null);
  const hideTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const readingSyncKeyRef = useRef<string | null>(null);
  const readingSyncReadyRef = useRef(false);

  useEffect(() => {
    if (!user?.id) {
      readingSyncKeyRef.current = null;
      readingSyncReadyRef.current = false;
    }
  }, [user?.id]);

  // ── Idle timer ──
  const resetIdle = useCallback(() => {
    setShowUI(true);
    if (hideTimer.current) clearTimeout(hideTimer.current);
    if (!showToc && !showSettings) {
      hideTimer.current = setTimeout(() => setShowUI(false), IDLE_TIMEOUT);
    }
  }, [showToc, showSettings]);

  // ── Load book & parse EPUB ──
  useEffect(() => {
    let cancelled = false;

    (async () => {
      try {
        const bookData = await api.getBook(bookId);
        if (!bookData?.epub_filename) {
          if (!cancelled) setError('No EPUB available');
          return;
        }
        if (!cancelled) setBook(bookData);

        // Check if EPUB is already cached locally
        const cacheDir = `${FileSystem.documentDirectory}epub_cache/`;
        const localPath = `${cacheDir}${bookData.epub_filename}`;
        const fileInfo = await FileSystem.getInfoAsync(localPath);

        let epubPath: string;
        if (fileInfo.exists) {
          epubPath = localPath;
        } else {
          // Download via existing cacheBookEpub helper
          const epubUrl = api.getBookEpubUrl(bookData.epub_filename);
          const cached = await cacheBookEpub(
            bookId,
            bookData.title,
            bookData.author ?? undefined,
            bookData.epub_filename,
            epubUrl,
          );
          epubPath = cached.localPath;
        }

        // Extract & parse
        const cacheKey = bookData.epub_filename.replace(/[^a-z0-9]/gi, '_');
        const result = await extractAndParseEpub(epubPath, cacheKey);
        if (cancelled) return;
        setParsed(result);

        // Restore position
        const savedChapter = await AsyncStorage.getItem(`epub-chapter::${bookData.epub_filename}`);
        const startChapter = savedChapter ? parseInt(savedChapter, 10) : 0;
        setChapterIndex(Math.min(startChapter, result.chapters.length - 1));

        // Restore settings
        const fs = await AsyncStorage.getItem('epub-fontsize-native');
        const vm = await AsyncStorage.getItem('epub-viewmode-native');
        if (fs) setFontSize(parseInt(fs, 10));
        if (vm && (vm === 'scroll' || vm === 'paginated')) setViewMode(vm as any);
      } catch (e: any) {
        if (!cancelled) setError(e?.message || 'Failed to load book');
      } finally {
        if (!cancelled) setLoading(false);
      }
    })();

    return () => { cancelled = true; };
  }, [bookId]);

  // Hydrate the local chapter position from Supabase once the EPUB is ready.
  // The local cache remains the offline fallback; the newest timestamp wins.
  useEffect(() => {
    if (!book || !parsed || !user?.id) return;

    const syncKey = `${user.id}:${book.id}`;
    if (readingSyncKeyRef.current === syncKey) return;
    readingSyncKeyRef.current = syncKey;
    readingSyncReadyRef.current = false;
    let cancelled = false;

    (async () => {
      const chapterKey = `epub-chapter::${book.epub_filename}`;
      const timestampKey = `epub-chapter-updated::${book.epub_filename}`;
      try {
        const [localChapterValue, localUpdatedAt, remoteRows] = await Promise.all([
          AsyncStorage.getItem(chapterKey),
          AsyncStorage.getItem(timestampKey),
          api.getReadingProgress(user.id),
        ]);
        if (cancelled) return;

        const localChapter = localChapterValue ? parseInt(localChapterValue, 10) : 0;
        const remote = remoteRows.find(row => row.book_id === book.id);
        const remoteDate = remote ? Date.parse(remote.updated_at) : 0;
        const localDate = localUpdatedAt ? Date.parse(localUpdatedAt) : 0;

        if (remote && remoteDate > localDate) {
          const nextChapter = Math.min(Math.max(remote.chapter_index, 0), parsed.chapters.length - 1);
          await AsyncStorage.multiSet([
            [chapterKey, String(nextChapter)],
            [timestampKey, remote.updated_at],
          ]);
          setChapterIndex(nextChapter);
        } else {
          const chapterCount = Math.max(parsed.chapters.length, 1);
          await api.upsertReadingProgress({
            user_id: user.id,
            book_id: book.id,
            title: book.title,
            author: book.author,
            chapter_title: parsed.chapters[localChapter]?.title ?? null,
            chapter_index: Math.min(Math.max(localChapter, 0), chapterCount - 1),
            chapter_count: chapterCount,
            progress: (Math.min(Math.max(localChapter, 0), chapterCount - 1) + 1) / chapterCount,
            updated_at: localUpdatedAt || new Date().toISOString(),
          });
          if (!localUpdatedAt) await AsyncStorage.setItem(timestampKey, new Date().toISOString());
        }
      } catch (error) {
        // Reading must remain usable offline; sync retries on the next app/session visit.
        console.warn('Reading progress sync unavailable:', error);
      } finally {
        if (!cancelled) readingSyncReadyRef.current = true;
      }
    })();

    return () => { cancelled = true; };
  }, [book, parsed, user?.id]);

  // Persist meaningful chapter changes locally and remotely after hydration.
  useEffect(() => {
    if (!book || !parsed) return;
    const chapterCount = Math.max(parsed.chapters.length, 1);
    const safeIndex = Math.min(Math.max(chapterIndex, 0), chapterCount - 1);
    const chapterKey = `epub-chapter::${book.epub_filename}`;
    const timestampKey = `epub-chapter-updated::${book.epub_filename}`;
    const updatedAt = new Date().toISOString();
    const canSync = !user?.id || readingSyncReadyRef.current;

    AsyncStorage.setItem(chapterKey, String(safeIndex)).catch(() => {});
    if (!canSync) return;
    AsyncStorage.setItem(timestampKey, updatedAt).catch(() => {});
    if (!user?.id) return;

    api.upsertReadingProgress({
      user_id: user.id,
      book_id: book.id,
      title: book.title,
      author: book.author,
      chapter_title: parsed.chapters[safeIndex]?.title ?? null,
      chapter_index: safeIndex,
      chapter_count: chapterCount,
      progress: (safeIndex + 1) / chapterCount,
      updated_at: updatedAt,
    }).catch(error => console.warn('Could not save reading progress:', error));
  }, [chapterIndex, book, parsed, user?.id]);

  // ── Load chapter content ──
  useEffect(() => {
    if (!parsed) return;
    let cancelled = false;

    setChapterLoading(true);
    const chapter = parsed.chapters[chapterIndex];
    if (!chapter) {
      setChapterLoading(false);
      return;
    }

    readChapterHtml(chapter.href, parsed.basePath)
      .then(html => {
        if (cancelled) return;
        setChapterHtml(html);
        scrollRef.current?.scrollTo({ y: 0, animated: false });
      })
      .catch(err => {
        if (!cancelled) {
          console.error('Chapter load error:', err);
          setChapterHtml('<p style="color:#ef4444">Failed to load chapter content.</p>');
        }
      })
      .finally(() => {
        if (!cancelled) setChapterLoading(false);
      });

    return () => { cancelled = true; };
  }, [chapterIndex, parsed]);

  const goNext = useCallback(() => {
    if (parsed && chapterIndex < parsed.chapters.length - 1) {
      setChapterIndex(i => i + 1);
      resetIdle();
    }
  }, [parsed, chapterIndex, resetIdle]);

  const goPrev = useCallback(() => {
    if (chapterIndex > 0) {
      setChapterIndex(i => i - 1);
      resetIdle();
    }
  }, [chapterIndex, resetIdle]);

  const adjustFont = useCallback(async (delta: number) => {
    const next = Math.min(26, Math.max(12, fontSize + delta));
    setFontSize(next);
    await AsyncStorage.setItem('epub-fontsize-native', String(next));
  }, [fontSize]);

  const goToChapter = useCallback((idx: number) => {
    setChapterIndex(idx);
    setShowToc(false);
    resetIdle();
  }, [resetIdle]);

  const handleReaderPress = useCallback(() => {
    if (showToc || showSettings) {
      setShowToc(false);
      setShowSettings(false);
    }
    setShowUI(prev => !prev);
    resetIdle();
  }, [showToc, showSettings, resetIdle]);

  // ── Loading ──
  if (loading) {
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.center}>
          <ActivityIndicator size="large" color="#ef4444" />
          <Text style={styles.loadingText}>Unpacking book...</Text>
        </View>
      </SafeAreaView>
    );
  }

  if (error || !book || !parsed) {
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.center}>
          <Ionicons name="alert-circle" size={64} color={COLORS.textSecondary} />
          <Text style={styles.errorText}>{error || 'Book not found'}</Text>
          <TouchableOpacity style={styles.retryButton} onPress={() => navigation.goBack()}>
            <Text style={styles.retryText}>Go Back</Text>
          </TouchableOpacity>
        </View>
      </SafeAreaView>
    );
  }

  const currentChapterLabel =
    parsed.toc.find(t => t.chapterIndex === chapterIndex)?.label
    ?? parsed.chapters[chapterIndex]?.title
    ?? book.title;

  const progress = Math.round(((chapterIndex + 1) / parsed.chapters.length) * 100);
  const uiVisible = showUI || showToc || showSettings;
  const tagStyles = makeTagStyles(fontSize);

  return (
    <View style={styles.container}>
      {/* ── Main reading area ── */}
      <ScrollView
        ref={scrollRef}
        style={styles.reader}
        contentContainerStyle={[
          styles.readerContent,
          { paddingHorizontal: 20, paddingTop: 72, paddingBottom: 80 },
        ]}
        scrollEventThrottle={200}
        onScroll={resetIdle}
        showsVerticalScrollIndicator={false}
      >
        <TouchableOpacity
          activeOpacity={1}
          onPress={handleReaderPress}
          style={{ flex: 1 }}
        >
          {chapterLoading ? (
            <View style={styles.center}>
              <ActivityIndicator size="large" color="#ef4444" />
            </View>
          ) : (
            <RenderHtml
              contentWidth={windowWidth - 40}
              source={{ html: `<div style="background:#050505">${chapterHtml}</div>` }}
              tagsStyles={tagStyles as any}
              classesStyles={CLASS_STYLES as any}
              baseStyle={{ backgroundColor: '#050505' }}
              enableExperimentalMarginCollapsing
              systemFonts={['Georgia', 'Times New Roman', 'serif']}
              defaultTextProps={{ selectable: true }}
            />
          )}
        </TouchableOpacity>
      </ScrollView>

      {/* ── Floating toolbar ── */}
      {uiVisible && (
        <View style={styles.toolbar} pointerEvents="box-none">
          <View style={styles.toolbarInner}>
            <TouchableOpacity style={styles.toolbarBtn} onPress={() => navigation.goBack()}>
              <Ionicons name="arrow-back" size={18} color="rgba(255,255,255,0.6)" />
            </TouchableOpacity>

            <View style={styles.divider} />

            <TouchableOpacity
              style={styles.toolbarBtn}
              onPress={() => { setShowToc(!showToc); setShowSettings(false); }}
            >
              <Ionicons name="list" size={18} color={showToc ? '#ef4444' : 'rgba(255,255,255,0.6)'} />
            </TouchableOpacity>

            <View style={styles.divider} />

            <Text style={styles.chapterLabel} numberOfLines={1}>
              {currentChapterLabel}
            </Text>

            <View style={styles.divider} />

            <TouchableOpacity
              style={styles.toolbarBtn}
              onPress={() => { setShowSettings(!showSettings); setShowToc(false); }}
            >
              <Ionicons
                name="settings-outline"
                size={18}
                color={showSettings ? '#ef4444' : 'rgba(255,255,255,0.6)'}
              />
            </TouchableOpacity>
          </View>
        </View>
      )}

      {/* ── Settings panel ── */}
      {showSettings && (
        <TouchableOpacity
          activeOpacity={1}
          style={styles.overlay}
          onPress={() => setShowSettings(false)}
        >
          <View style={styles.settingsPanel}>
            <Text style={styles.settingsLabel}>FONT SIZE</Text>
            <View style={styles.fontRow}>
              <TouchableOpacity style={styles.fontBtn} onPress={() => adjustFont(-1)}>
                <Ionicons name="remove" size={16} color="rgba(255,255,255,0.8)" />
              </TouchableOpacity>
              <Text style={styles.fontValue}>{fontSize}px</Text>
              <TouchableOpacity style={styles.fontBtn} onPress={() => adjustFont(1)}>
                <Ionicons name="add" size={16} color="rgba(255,255,255,0.8)" />
              </TouchableOpacity>
            </View>
          </View>
        </TouchableOpacity>
      )}

      {/* ── TOC panel ── */}
      {showToc && (
        <View style={styles.tocOverlay}>
          <TouchableOpacity
            style={styles.tocBackdrop}
            onPress={() => setShowToc(false)}
          />
          <View style={styles.tocPanel}>
            <View style={styles.tocHeader}>
              <Text style={styles.tocTitle}>Contents</Text>
              <TouchableOpacity onPress={() => setShowToc(false)}>
                <Ionicons name="close" size={20} color="rgba(255,255,255,0.6)" />
              </TouchableOpacity>
            </View>
            <ScrollView style={{ flex: 1 }} showsVerticalScrollIndicator={false}>
              {parsed.toc.map((item, idx) => (
                <TouchableOpacity
                  key={idx}
                  style={[
                    styles.tocItem,
                    item.chapterIndex === chapterIndex && styles.tocItemActive,
                  ]}
                  onPress={() => goToChapter(item.chapterIndex)}
                >
                  <Text
                    style={[
                      styles.tocItemText,
                      item.chapterIndex === chapterIndex && { color: '#ef4444' },
                    ]}
                    numberOfLines={2}
                  >
                    {item.label}
                  </Text>
                </TouchableOpacity>
              ))}
              {parsed.toc.length === 0 && (
                <Text style={styles.tocEmpty}>No table of contents</Text>
              )}
            </ScrollView>
          </View>
        </View>
      )}

      {/* ── Chapter nav buttons ── */}
      {uiVisible && (
        <View style={styles.chapterNav}>
          <TouchableOpacity
            style={[styles.chapterNavBtn, chapterIndex === 0 && styles.navBtnDisabled]}
            onPress={goPrev}
            disabled={chapterIndex === 0}
          >
            <Ionicons
              name="chevron-back"
              size={18}
              color={chapterIndex === 0 ? 'rgba(255,255,255,0.2)' : '#fff'}
            />
            <Text style={[styles.navBtnText, chapterIndex === 0 && styles.navBtnDisabledText]}>Prev</Text>
          </TouchableOpacity>

          <Text style={styles.progressLabel}>{progress}%</Text>

          <TouchableOpacity
            style={[
              styles.chapterNavBtn,
              chapterIndex === parsed.chapters.length - 1 && styles.navBtnDisabled,
            ]}
            onPress={goNext}
            disabled={chapterIndex === parsed.chapters.length - 1}
          >
            <Text
              style={[
                styles.navBtnText,
                chapterIndex === parsed.chapters.length - 1 && styles.navBtnDisabledText,
              ]}
            >
              Next
            </Text>
            <Ionicons
              name="chevron-forward"
              size={18}
              color={chapterIndex === parsed.chapters.length - 1 ? 'rgba(255,255,255,0.2)' : '#fff'}
            />
          </TouchableOpacity>
        </View>
      )}

      {/* ── Progress bar ── */}
      <View style={styles.progressWrap}>
        <View style={[styles.progressBar, { width: `${progress}%` }]} />
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    backgroundColor: '#050505',
  },
  center: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 32,
  },
  loadingText: {
    marginTop: 12,
    fontSize: 13,
    color: 'rgba(255,255,255,0.35)',
  },
  errorText: {
    fontSize: 18,
    fontWeight: '600',
    color: '#f4f4f5',
    marginTop: 16,
    textAlign: 'center',
  },
  retryButton: {
    marginTop: 20,
    paddingHorizontal: 24,
    paddingVertical: 12,
    backgroundColor: '#ef4444',
    borderRadius: 8,
  },
  retryText: {
    fontSize: 16,
    fontWeight: '600',
    color: '#fff',
  },
  reader: {
    flex: 1,
    backgroundColor: '#050505',
  },
  readerContent: {
    maxWidth: 720,
    alignSelf: 'center',
    width: '100%',
  },
  toolbar: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    zIndex: 50,
    alignItems: 'center',
    paddingTop: 8,
  },
  toolbarInner: {
    flexDirection: 'row',
    alignItems: 'center',
    paddingHorizontal: 10,
    paddingVertical: 6,
    backgroundColor: 'rgba(20,20,22,0.85)',
    borderRadius: 100,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
  },
  toolbarBtn: {
    width: 36,
    height: 36,
    borderRadius: 18,
    alignItems: 'center',
    justifyContent: 'center',
  },
  divider: {
    width: 1,
    height: 18,
    backgroundColor: 'rgba(255,255,255,0.1)',
    marginHorizontal: 4,
  },
  chapterLabel: {
    fontSize: 13,
    fontWeight: '500',
    color: 'rgba(255,255,255,0.85)',
    maxWidth: 160,
    paddingHorizontal: 6,
  },
  overlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    zIndex: 60,
    backgroundColor: 'rgba(0,0,0,0.6)',
    justifyContent: 'flex-start',
    alignItems: 'center',
    paddingTop: 72,
  },
  settingsPanel: {
    width: 260,
    backgroundColor: 'rgba(20,20,22,0.97)',
    borderRadius: 20,
    padding: 20,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
  },
  settingsLabel: {
    fontSize: 11,
    color: 'rgba(255,255,255,0.4)',
    fontWeight: '700',
    letterSpacing: 1,
    marginBottom: 12,
  },
  fontRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    backgroundColor: 'rgba(255,255,255,0.03)',
    padding: 8,
    borderRadius: 12,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.05)',
  },
  fontBtn: {
    padding: 8,
    backgroundColor: 'rgba(255,255,255,0.05)',
    borderRadius: 8,
  },
  fontValue: {
    fontSize: 14,
    color: '#fff',
    fontWeight: '500',
    minWidth: 44,
    textAlign: 'center',
  },
  tocOverlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    zIndex: 61,
    flexDirection: 'row',
  },
  tocBackdrop: {
    flex: 1,
    backgroundColor: 'rgba(0,0,0,0.7)',
  },
  tocPanel: {
    width: 300,
    maxWidth: '80%',
    backgroundColor: 'rgba(12,12,14,0.98)',
    borderRightWidth: 1,
    borderRightColor: 'rgba(255,255,255,0.08)',
    paddingBottom: 16,
  },
  tocHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: 20,
    paddingBottom: 12,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(255,255,255,0.05)',
  },
  tocTitle: {
    fontSize: 16,
    fontWeight: '600',
    color: '#f4f4f5',
  },
  tocItem: {
    paddingHorizontal: 20,
    paddingVertical: 12,
  },
  tocItemActive: {
    backgroundColor: 'rgba(239,68,68,0.08)',
  },
  tocItemText: {
    fontSize: 14,
    color: 'rgba(255,255,255,0.7)',
    lineHeight: 20,
  },
  tocEmpty: {
    padding: 24,
    color: 'rgba(255,255,255,0.4)',
    fontSize: 14,
    textAlign: 'center',
  },
  chapterNav: {
    position: 'absolute',
    bottom: 12,
    left: 0,
    right: 0,
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingHorizontal: 20,
    zIndex: 40,
  },
  chapterNavBtn: {
    flexDirection: 'row',
    alignItems: 'center',
    backgroundColor: 'rgba(20,20,22,0.8)',
    paddingHorizontal: 16,
    paddingVertical: 10,
    borderRadius: 20,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    gap: 6,
  },
  navBtnDisabled: {
    opacity: 0.4,
  },
  navBtnText: {
    color: '#fff',
    fontSize: 13,
    fontWeight: '500',
  },
  navBtnDisabledText: {
    color: 'rgba(255,255,255,0.3)',
  },
  progressLabel: {
    fontSize: 12,
    color: 'rgba(255,255,255,0.35)',
    fontWeight: '500',
  },
  progressWrap: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    height: 2,
    backgroundColor: 'rgba(255,255,255,0.04)',
    zIndex: 45,
  },
  progressBar: {
    height: '100%',
    backgroundColor: 'rgba(239,68,68,0.7)',
  },
});
