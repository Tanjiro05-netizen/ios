import React, { useEffect, useRef, useState, useCallback } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  ActivityIndicator,
} from 'react-native';
import { useNavigation, useRoute, RouteProp } from '@react-navigation/native';
import { Ionicons } from '@expo/vector-icons';
import { SafeAreaView } from 'react-native-safe-area-context';
import ePub from 'epubjs';
import { COLORS } from '../constants';
import { api } from '../lib/api';
import { useAuth } from '../hooks/useAuth';
import { Book, RootStackParamList } from '../types';

type BookReaderRouteProp = RouteProp<RootStackParamList, 'BookReader'>;

// ── Flatten nested TOC ──
interface FlatTocItem {
  label: string;
  href: string;
  depth: number;
}

const flattenToc = (items: any[], depth = 0): FlatTocItem[] =>
  (items || []).flatMap((item: any) => [
    { label: item.label?.trim(), href: item.href, depth },
    ...(item.subitems?.length ? flattenToc(item.subitems, depth + 1) : []),
  ]);

// ── Full dark theme matching website EpubReader ──
const applyTheme = (rendition: any, viewMode: string) => {
  const bodyStyles: Record<string, string> = {
    'background': '#050505 !important',
    'color': '#d6d3cd !important',
    'font-family': 'Georgia, "Times New Roman", serif !important',
    'line-height': '1.9 !important',
  };

  if (viewMode === 'scrolled-doc') {
    bodyStyles['padding'] = '80px 8% 100px 8% !important';
    bodyStyles['max-width'] = '680px !important';
    bodyStyles['margin'] = '0 auto !important';
    bodyStyles['overflow-x'] = 'hidden !important';
  } else {
    bodyStyles['padding'] = '40px 5% !important';
  }

  rendition.themes.default({
    'html': { 'background': '#050505 !important' },
    'body': bodyStyles,
    'h1, h2, h3, h4, h5, h6': {
      'color': '#f4f4f5 !important',
      'font-family': 'Georgia, "Times New Roman", serif !important',
      'font-weight': '700 !important',
      'margin-top': '2em !important',
      'margin-bottom': '0.8em !important',
      'line-height': '1.3 !important',
    },
    '.H, .H1, .calibre7, .calibre28, .calibre35': { 'color': '#f4f4f5 !important' },
    'p, .MsoNormal': {
      'color': '#d6d3cd !important',
      'line-height': '1.9 !important',
      'margin-bottom': '1.1em !important',
      'margin-top': '0 !important',
      'text-align': 'left !important',
    },
    '.MsoToc, .MsoToc1, .MsoToc2': { 'color': '#c4c0b8 !important' },
    '.indentb': {
      'color': '#c9c3b8 !important',
      'border-left': '3px solid rgba(239, 68, 68, 0.4) !important',
      'padding-left': '1.4em !important',
      'margin-left': '0 !important',
      'margin-right': '0 !important',
      'font-style': 'italic !important',
    },
    '.quoteb': {
      'color': '#c9c3b8 !important',
      'border-left': '3px solid rgba(239, 68, 68, 0.4) !important',
      'padding-left': '1.4em !important',
      'margin-left': '0 !important',
      'margin-right': '0 !important',
    },
    'a': {
      'color': '#ef4444 !important',
      'text-decoration': 'none !important',
      'border-bottom': '1px solid rgba(239, 68, 68, 0.25) !important',
    },
    'em, i, .calibre6, .calibre27': { 'font-style': 'italic !important', 'color': 'inherit !important' },
    '.inote': { 'color': 'rgba(255,255,255,0.38) !important', 'font-size': '0.88em !important' },
    '.enote': { 'color': '#f87171 !important', 'font-size': '0.78em !important', 'font-weight': 'bold !important', 'font-family': 'inherit !important' },
    '.context': { 'color': 'rgba(255,255,255,0.42) !important', 'font-style': 'italic !important' },
    '.term': { 'color': '#93c5fd !important', 'font-weight': 'bold !important', 'font-family': 'inherit !important' },
    '.calibre10': { 'color': 'rgba(255,255,255,0.38) !important' },
    '.calibre11': { 'color': 'rgba(255,255,255,0.5) !important' },
    '.calibre12': { 'color': '#d6d3cd !important' },
    '.calibre17': { 'color': 'rgba(255,255,255,0.38) !important' },
    '.calibre19': { 'color': '#93c5fd !important' },
    '.calibre20': { 'color': '#d6d3cd !important' },
    '.calibre21': { 'color': 'rgba(255,255,255,0.5) !important' },
    '.calibre22': { 'color': 'rgba(255,255,255,0.5) !important' },
    '.calibre23': { 'color': '#93c5fd !important' },
    '.calibre25': { 'color': '#d6d3cd !important' },
    '.calibre26': { 'color': 'rgba(255,255,255,0.5) !important', 'font-size': '0.75em !important' },
    '::selection': { 'background': 'rgba(239, 68, 68, 0.4) !important' },
    'hr': { 'border': 'none !important', 'border-top': '1px solid rgba(255,255,255,0.08) !important', 'margin': '3em 0 !important' },
    'img': { 'max-width': '100% !important', 'height': 'auto !important', 'border-radius': '8px', 'margin': '2em auto !important', 'display': 'block !important', 'box-shadow': '0 4px 20px rgba(0,0,0,0.5) !important' },
  });
};

const IDLE_TIMEOUT = 3000;

export default function BookReaderScreen() {
  const navigation = useNavigation();
  const route = useRoute<BookReaderRouteProp>();
  const { bookId } = route.params;
  const { user } = useAuth();

  const viewerRef = useRef<HTMLDivElement | null>(null);
  const bookRef = useRef<any>(null);
  const renditionRef = useRef<any>(null);
  const locationRef = useRef<string | null>(null);
  const tocRef = useRef<FlatTocItem[]>([]);
  const touchStartXRef = useRef<number | null>(null);
  const hideTimerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const readingSyncKeyRef = useRef<string | null>(null);
  const readingSyncReadyRef = useRef(false);

  const [book, setBook] = useState<Book | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [isRendered, setIsRendered] = useState(false);

  // UI state
  const [showUI, setShowUI] = useState(true);
  const [showToc, setShowToc] = useState(false);
  const [showSettings, setShowSettings] = useState(false);
  const [tocItems, setTocItems] = useState<FlatTocItem[]>([]);
  const [currentChapter, setCurrentChapter] = useState('');
  const [atStart, setAtStart] = useState(true);
  const [atEnd, setAtEnd] = useState(false);
  const [readingProgress, setReadingProgress] = useState(0);

  // Reader settings (persisted)
  const [fontSize, setFontSize] = useState(() => {
    try { const s = localStorage.getItem('epub-fontsize'); return s ? parseInt(s, 10) : 100; } catch { return 100; }
  });
  const [viewMode, setViewMode] = useState(() => {
    try { return localStorage.getItem('epub-viewmode') || 'paginated'; } catch { return 'paginated'; }
  });

  // ── Auto-hide UI after idle ──
  const resetIdleTimer = useCallback(() => {
    setShowUI(true);
    if (hideTimerRef.current) clearTimeout(hideTimerRef.current);
    hideTimerRef.current = setTimeout(() => {
      if (!showToc && !showSettings) setShowUI(false);
    }, IDLE_TIMEOUT);
  }, [showToc, showSettings]);

  useEffect(() => {
    resetIdleTimer();
    return () => { if (hideTimerRef.current) clearTimeout(hideTimerRef.current); };
  }, [resetIdleTimer]);

  // Keep UI visible while panels are open
  useEffect(() => {
    if (showToc || showSettings) {
      if (hideTimerRef.current) clearTimeout(hideTimerRef.current);
      setShowUI(true);
    } else {
      resetIdleTimer();
    }
  }, [showToc, showSettings]);

  // ── Load book data ──
  useEffect(() => {
    loadBook();
  }, [bookId]);

  const loadBook = async () => {
    try {
      setLoading(true);
      setError(null);
      const bookData = await api.getBook(bookId);
      if (!bookData) { setError('Book not found'); return; }
      setBook(bookData);
      if (!bookData.epub_filename) { setError('No EPUB available for this book'); return; }
    } catch (err: any) {
      setError(err?.message || 'Failed to load book');
    } finally {
      setLoading(false);
    }
  };

  // ── Storage key for position persistence ──
  const storageKey = book?.epub_filename ? `epub-cfi::${book.epub_filename}` : null;
  const updatedStorageKey = book?.epub_filename ? `epub-cfi-updated::${book.epub_filename}` : null;

  const findSpineIndex = useCallback((href: string | undefined): number => {
    if (!href || !bookRef.current?.spine?.spineItems) return -1;
    return bookRef.current.spine.spineItems.findIndex((item: any) => {
      try { return bookRef.current.canonical(item.href) === bookRef.current.canonical(href); } catch { return false; }
    });
  }, []);

  useEffect(() => {
    readingSyncKeyRef.current = null;
    readingSyncReadyRef.current = false;
  }, [book?.id, user?.id]);

  // ── Initialize / re-initialize EPUB rendition ──
  const goNext = useCallback(() => {
    if (renditionRef.current && viewMode === 'paginated') renditionRef.current.next();
  }, [viewMode]);

  const goPrev = useCallback(() => {
    if (renditionRef.current && viewMode === 'paginated') renditionRef.current.prev();
  }, [viewMode]);

  // Book structure — load once
  useEffect(() => {
    if (!book?.epub_filename) return;
    setLoadError(null);

    const savedCfi = storageKey ? localStorage.getItem(storageKey) : null;
    if (savedCfi) locationRef.current = savedCfi;

    const epubUrl = api.getBookEpubUrl(book.epub_filename);
    const epubBook = ePub(epubUrl);
    bookRef.current = epubBook;

    epubBook.loaded.navigation.then((nav: any) => {
      const flat = flattenToc(nav.toc || []);
      setTocItems(flat);
      tocRef.current = flat;
    }).catch(() => setLoadError('Failed to load table of contents.'));

    epubBook.loaded.spine.catch(() => setLoadError('Failed to load book content.'));

    return () => {
      epubBook.destroy();
      bookRef.current = null;
    };
  }, [book?.epub_filename]);

  // Rendition — recreate when viewMode changes
  useEffect(() => {
    if (!viewerRef.current || !bookRef.current || !book?.epub_filename) return;
    setIsRendered(false);

    if (renditionRef.current) {
      try { renditionRef.current.destroy(); } catch (e) {}
    }

    const options: any = { width: '100%', height: '100%', spread: 'none', flow: viewMode };
    if (viewMode === 'scrolled-doc') options.manager = 'continuous';

    const rendition = bookRef.current.renderTo(viewerRef.current, options);
    renditionRef.current = rendition;

    applyTheme(rendition, viewMode);
    rendition.themes.fontSize(`${fontSize}%`);

    const startLoc = locationRef.current || undefined;
    rendition.display(startLoc).then(() => setIsRendered(true)).catch(() => {
      rendition.display().then(() => setIsRendered(true)).catch(() => setLoadError('Failed to render book.'));
    });

    rendition.on('locationChanged', (loc: any) => {
      locationRef.current = loc.start.cfi;
      if (storageKey) localStorage.setItem(storageKey, loc.start.cfi);
      const spineIndex = findSpineIndex(loc.start.href);
      setAtStart(loc.atStart || false);
      setAtEnd(loc.atEnd || false);

      let chapterTitle = book.title;
      if (bookRef.current && tocRef.current.length) {
        const match = tocRef.current.find((item: FlatTocItem) => {
          const base = item.href.split('#')[0];
          try { return bookRef.current.canonical(base) === bookRef.current.canonical(loc.start.href); } catch { return false; }
        });
        if (match) {
          chapterTitle = match.label;
          setCurrentChapter(match.label);
        }
      }

      const chapterCount = bookRef.current?.spine?.spineItems?.length || 1;
      if (spineIndex >= 0) {
        setReadingProgress(Math.round(((spineIndex + 1) / chapterCount) * 100));
      }

      if (user?.id && readingSyncReadyRef.current && spineIndex >= 0) {
        const updatedAt = new Date().toISOString();
        if (updatedStorageKey) localStorage.setItem(updatedStorageKey, updatedAt);
        api.upsertReadingProgress({
          user_id: user.id,
          book_id: book.id,
          title: book.title,
          author: book.author,
          chapter_title: chapterTitle,
          chapter_index: spineIndex,
          chapter_count: chapterCount,
          progress: (spineIndex + 1) / chapterCount,
          updated_at: updatedAt,
        }).catch(error => console.warn('Could not save reading progress:', error));
      }
    });

    // Bubble keys from iframe
    rendition.on('keyup', (e: any) => {
      resetIdleTimer();
      if (e.key === 'ArrowRight') goNext();
      if (e.key === 'ArrowLeft') goPrev();
      if (e.key === 'Escape') { setShowSettings(false); setShowToc(false); }
    });

    rendition.on('click', () => {
      resetIdleTimer();
      setShowSettings(false);
      setShowToc(false);
    });

    // Touch/swipe inside iframe
    rendition.on('rendered', (_section: any, view: any) => {
      if (!view?.window) return;
      const win = view.window;
      win.addEventListener('mousemove', () => resetIdleTimer(), { passive: true });
      win.addEventListener('touchstart', (e: any) => {
        resetIdleTimer();
        touchStartXRef.current = e.touches[0]?.clientX ?? null;
      }, { passive: true });
      win.addEventListener('touchend', (e: any) => {
        if (touchStartXRef.current === null) return;
        const dx = (e.changedTouches[0]?.clientX ?? 0) - touchStartXRef.current;
        touchStartXRef.current = null;
        if (Math.abs(dx) > 50 && viewMode === 'paginated') {
          if (dx < 0) goNext(); else goPrev();
        }
      }, { passive: true });
    });
  }, [book?.epub_filename, book?.id, book?.title, book?.author, user?.id, updatedStorageKey, viewMode, goNext, goPrev, resetIdleTimer, findSpineIndex]);

  // Hydrate the web reader from Supabase after the EPUB rendition has a spine.
  useEffect(() => {
    if (!book?.id || !book.epub_filename || !user?.id || !isRendered || !renditionRef.current) return;
    const syncKey = `${user.id}:${book.id}`;
    if (readingSyncKeyRef.current === syncKey) return;
    readingSyncKeyRef.current = syncKey;
    readingSyncReadyRef.current = false;
    let cancelled = false;

    (async () => {
      try {
        const [remoteRows, localUpdatedAt] = await Promise.all([
          api.getReadingProgress(user.id),
          Promise.resolve(updatedStorageKey ? localStorage.getItem(updatedStorageKey) : null),
        ]);
        if (cancelled) return;

        const remote = remoteRows.find(row => row.book_id === book.id);
        const remoteDate = remote ? Date.parse(remote.updated_at) : 0;
        const localDate = localUpdatedAt ? Date.parse(localUpdatedAt) : 0;
        const currentLocation = renditionRef.current.currentLocation?.();
        const localIndex = findSpineIndex(currentLocation?.start?.href) >= 0
          ? findSpineIndex(currentLocation?.start?.href)
          : 0;
        const chapterCount = bookRef.current?.spine?.spineItems?.length || 1;

        if (remote && remoteDate > localDate) {
          const targetIndex = Math.min(Math.max(remote.chapter_index, 0), chapterCount - 1);
          const target = bookRef.current?.spine?.spineItems?.[targetIndex];
          if (target?.href) await renditionRef.current.display(target.href);
          if (updatedStorageKey) localStorage.setItem(updatedStorageKey, remote.updated_at);
          setReadingProgress(Math.round(((targetIndex + 1) / chapterCount) * 100));
        } else {
          const updatedAt = localUpdatedAt || new Date().toISOString();
          const safeIndex = Math.min(Math.max(localIndex, 0), chapterCount - 1);
          await api.upsertReadingProgress({
            user_id: user.id,
            book_id: book.id,
            title: book.title,
            author: book.author,
            chapter_title: currentChapter || book.title,
            chapter_index: safeIndex,
            chapter_count: chapterCount,
            progress: (safeIndex + 1) / chapterCount,
            updated_at: updatedAt,
          });
          if (updatedStorageKey) localStorage.setItem(updatedStorageKey, updatedAt);
        }
      } catch (error) {
        console.warn('Reading progress sync unavailable:', error);
      } finally {
        if (!cancelled) readingSyncReadyRef.current = true;
      }
    })();

    return () => { cancelled = true; };
  }, [book, user?.id, isRendered, updatedStorageKey, findSpineIndex, currentChapter]);

  // Dynamic font size
  useEffect(() => {
    if (renditionRef.current && isRendered) {
      renditionRef.current.themes.fontSize(`${fontSize}%`);
    }
  }, [fontSize, isRendered]);

  // Top-level keyboard
  useEffect(() => {
    const handleKey = (e: KeyboardEvent) => {
      resetIdleTimer();
      if (e.key === 'ArrowRight') goNext();
      if (e.key === 'ArrowLeft') goPrev();
      if (e.key === 'Escape') { setShowSettings(false); setShowToc(false); }
    };
    const handleMove = () => resetIdleTimer();
    window.addEventListener('keydown', handleKey);
    window.addEventListener('mousemove', handleMove);
    window.addEventListener('touchstart', handleMove, { passive: true });
    return () => {
      window.removeEventListener('keydown', handleKey);
      window.removeEventListener('mousemove', handleMove);
      window.removeEventListener('touchstart', handleMove);
    };
  }, [goNext, goPrev, resetIdleTimer]);

  const goToChapter = useCallback((href: string) => {
    if (renditionRef.current) { renditionRef.current.display(href); setShowToc(false); }
  }, []);

  // ── Loading state ──
  if (loading) {
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.center}>
          <ActivityIndicator size="large" color="#ef4444" />
          <Text style={styles.loadingText}>Loading book...</Text>
        </View>
      </SafeAreaView>
    );
  }

  // ── Error state ──
  if (error || !book) {
    return (
      <SafeAreaView style={styles.container}>
        <View style={styles.headerBar}>
          <TouchableOpacity style={styles.backButton} onPress={() => navigation.goBack()}>
            <Ionicons name="arrow-back" size={24} color={COLORS.text} />
          </TouchableOpacity>
        </View>
        <View style={styles.center}>
          <Ionicons name="alert-circle" size={64} color={COLORS.textSecondary} />
          <Text style={styles.errorText}>{error || 'Book not found'}</Text>
          <TouchableOpacity style={styles.retryButton} onPress={loadBook}>
            <Text style={styles.retryText}>Try Again</Text>
          </TouchableOpacity>
        </View>
      </SafeAreaView>
    );
  }

  const pdfDownloadUrl = book.pdf_filename ? api.getBookPdfUrl(book.pdf_filename) : null;
  const uiVisible = showUI || showToc || showSettings;

  return (
    <View style={styles.container}>
      {/* ── Floating toolbar ── */}
      {uiVisible && (
        <div style={{
          position: 'absolute', top: 24, left: '50%', transform: 'translateX(-50%)', zIndex: 50,
          display: 'flex', alignItems: 'center', gap: 8, padding: '6px 10px',
          background: 'rgba(20,20,22,0.65)', backdropFilter: 'blur(20px)', WebkitBackdropFilter: 'blur(20px)',
          border: '1px solid rgba(255,255,255,0.08)', borderRadius: 100, boxShadow: '0 20px 40px rgba(0,0,0,0.4)',
        }}>
          {/* Back */}
          <TouchableOpacity style={styles.toolbarBtn} onPress={() => navigation.goBack()}>
            <Ionicons name="arrow-back" size={18} color="rgba(255,255,255,0.6)" />
          </TouchableOpacity>

          <div style={{ width: 1, height: 18, background: 'rgba(255,255,255,0.1)' }} />

          {/* TOC */}
          <TouchableOpacity style={styles.toolbarBtn} onPress={() => { setShowToc(!showToc); setShowSettings(false); }}>
            <Ionicons name="list" size={18} color={showToc ? '#ef4444' : 'rgba(255,255,255,0.6)'} />
          </TouchableOpacity>

          <div style={{ width: 1, height: 18, background: 'rgba(255,255,255,0.1)' }} />

          {/* Chapter name */}
          <span style={{
            fontSize: 13, fontWeight: 500, color: 'rgba(255,255,255,0.85)', maxWidth: 220, textAlign: 'center',
            overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', padding: '0 6px', letterSpacing: '-0.01em',
          }}>
            {currentChapter || book.title}
          </span>

          <div style={{ width: 1, height: 18, background: 'rgba(255,255,255,0.1)' }} />

          {/* Settings */}
          <TouchableOpacity style={styles.toolbarBtn} onPress={() => { setShowSettings(!showSettings); setShowToc(false); }}>
            <Ionicons name="settings-outline" size={18} color={showSettings ? '#ef4444' : 'rgba(255,255,255,0.6)'} />
          </TouchableOpacity>

          {/* PDF download */}
          {pdfDownloadUrl && (
            <>
              <div style={{ width: 1, height: 18, background: 'rgba(255,255,255,0.1)' }} />
              <TouchableOpacity style={styles.toolbarBtn} onPress={() => { (window as any).open(pdfDownloadUrl, '_blank'); }}>
                <Ionicons name="download-outline" size={18} color="rgba(255,255,255,0.6)" />
              </TouchableOpacity>
            </>
          )}
        </div>
      )}

      {/* ── Settings dropdown ── */}
      {showSettings && (
        <>
          <div onClick={() => setShowSettings(false)} style={{ position: 'absolute', inset: 0, zIndex: 50, background: 'transparent' }} />
          <div style={{
            position: 'absolute', top: 84, left: '50%', transform: 'translateX(-50%)', zIndex: 51,
            background: 'rgba(20,20,22,0.85)', backdropFilter: 'blur(30px)', WebkitBackdropFilter: 'blur(30px)',
            border: '1px solid rgba(255,255,255,0.1)', borderRadius: 20, padding: 20,
            display: 'flex', flexDirection: 'column', gap: 24, width: 280, boxShadow: '0 30px 60px rgba(0,0,0,0.6)',
          }}>
            {/* Reading Mode */}
            <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
              <span style={{ fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.06em', color: 'rgba(255,255,255,0.4)', fontWeight: 700 }}>Reading Mode</span>
              <div style={{ display: 'flex', gap: 8, background: 'rgba(0,0,0,0.3)', padding: 4, borderRadius: 12 }}>
                <button
                  onClick={() => { setViewMode('paginated'); localStorage.setItem('epub-viewmode', 'paginated'); }}
                  style={{
                    flex: 1, padding: '10px 8px', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
                    background: viewMode === 'paginated' ? 'rgba(255,255,255,0.1)' : 'transparent',
                    color: viewMode === 'paginated' ? '#fff' : 'rgba(255,255,255,0.5)',
                    border: 'none', borderRadius: 8, cursor: 'pointer', fontSize: 13, fontWeight: 500,
                  }}
                >
                  <Ionicons name="swap-horizontal" size={16} color={viewMode === 'paginated' ? '#fff' : 'rgba(255,255,255,0.5)'} />
                  Pages
                </button>
                <button
                  onClick={() => { setViewMode('scrolled-doc'); localStorage.setItem('epub-viewmode', 'scrolled-doc'); }}
                  style={{
                    flex: 1, padding: '10px 8px', display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
                    background: viewMode === 'scrolled-doc' ? 'rgba(255,255,255,0.1)' : 'transparent',
                    color: viewMode === 'scrolled-doc' ? '#fff' : 'rgba(255,255,255,0.5)',
                    border: 'none', borderRadius: 8, cursor: 'pointer', fontSize: 13, fontWeight: 500,
                  }}
                >
                  <Ionicons name="swap-vertical" size={16} color={viewMode === 'scrolled-doc' ? '#fff' : 'rgba(255,255,255,0.5)'} />
                  Scroll
                </button>
              </div>
            </div>

            {/* Typography */}
            <div style={{ display: 'flex', flexDirection: 'column', gap: 12 }}>
              <span style={{ fontSize: 11, textTransform: 'uppercase', letterSpacing: '0.06em', color: 'rgba(255,255,255,0.4)', fontWeight: 700 }}>Typography</span>
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', background: 'rgba(255,255,255,0.03)', padding: '8px 12px', borderRadius: 12, border: '1px solid rgba(255,255,255,0.05)' }}>
                <button
                  onClick={() => setFontSize((s: number) => { const n = Math.max(60, s - 10); localStorage.setItem('epub-fontsize', String(n)); return n; })}
                  style={{ padding: 6, background: 'rgba(255,255,255,0.05)', border: 'none', borderRadius: 8, color: 'rgba(255,255,255,0.8)', cursor: 'pointer' }}
                >
                  <Ionicons name="remove" size={16} color="rgba(255,255,255,0.8)" />
                </button>
                <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                  <Ionicons name="text" size={14} color="rgba(255,255,255,0.4)" />
                  <span style={{ fontSize: 14, color: '#fff', fontWeight: 500, minWidth: 44, textAlign: 'center' }}>{fontSize}%</span>
                </div>
                <button
                  onClick={() => setFontSize((s: number) => { const n = Math.min(200, s + 10); localStorage.setItem('epub-fontsize', String(n)); return n; })}
                  style={{ padding: 6, background: 'rgba(255,255,255,0.05)', border: 'none', borderRadius: 8, color: 'rgba(255,255,255,0.8)', cursor: 'pointer' }}
                >
                  <Ionicons name="add" size={16} color="rgba(255,255,255,0.8)" />
                </button>
              </div>
            </div>
          </div>
        </>
      )}

      {/* ── Main reading area ── */}
      <View style={styles.readerArea}>

        {/* TOC sidebar overlay */}
        {showToc && (
          <>
            <div onClick={() => setShowToc(false)} style={{
              position: 'absolute', inset: 0, background: 'rgba(0,0,0,0.7)', backdropFilter: 'blur(4px)', zIndex: 60,
            }} />
            <div style={{
              position: 'absolute', top: 0, left: 0, bottom: 0, width: 320, maxWidth: '85vw', zIndex: 61,
              background: 'rgba(12,12,14,0.95)', backdropFilter: 'blur(30px)', borderRight: '1px solid rgba(255,255,255,0.08)',
              display: 'flex', flexDirection: 'column', boxShadow: '20px 0 60px rgba(0,0,0,0.6)',
            }}>
              <div style={{ padding: 24, paddingBottom: 16, display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                <span style={{ fontSize: 16, fontWeight: 600, color: '#f4f4f5', letterSpacing: '-0.01em' }}>Table of Contents</span>
                <button onClick={() => setShowToc(false)} style={{
                  background: 'rgba(255,255,255,0.05)', padding: 6, borderRadius: '50%', border: 'none', color: 'rgba(255,255,255,0.6)', cursor: 'pointer',
                }}>
                  <Ionicons name="close" size={16} color="rgba(255,255,255,0.6)" />
                </button>
              </div>
              <div style={{ flex: 1, overflowY: 'auto', padding: '0 12px 24px' }}>
                {tocItems.map((item, idx) => {
                  const isActive = currentChapter === item.label;
                  return (
                    <button
                      key={idx}
                      onClick={() => goToChapter(item.href)}
                      style={{
                        display: 'block', width: '100%', textAlign: 'left',
                        padding: `10px 16px 10px ${16 + item.depth * 14}px`,
                        background: isActive ? 'rgba(239,68,68,0.1)' : 'transparent',
                        border: 'none', borderRadius: 12,
                        color: isActive ? '#ef4444' : item.depth === 0 ? 'rgba(255,255,255,0.7)' : 'rgba(255,255,255,0.45)',
                        fontWeight: isActive ? 600 : item.depth === 0 ? 500 : 400,
                        fontSize: item.depth === 0 ? 14 : 12.5, lineHeight: '1.5', cursor: 'pointer',
                        marginBottom: 2,
                      }}
                    >
                      {item.label}
                    </button>
                  );
                })}
                {tocItems.length === 0 && (
                  <div style={{ padding: '24px 16px', color: 'rgba(255,255,255,0.4)', fontSize: 14, textAlign: 'center' }}>
                    No table of contents available
                  </div>
                )}
              </div>
            </div>
          </>
        )}

        {/* Loading overlay */}
        {!isRendered && !loadError && book?.epub_filename && (
          <View style={styles.loadingOverlay}>
            <ActivityIndicator size="large" color="#ef4444" />
            <Text style={styles.loadingText}>Loading...</Text>
          </View>
        )}

        {/* Error overlay */}
        {loadError && (
          <View style={styles.loadingOverlay}>
            <Ionicons name="alert-circle" size={26} color="#ef4444" />
            <Text style={styles.loadingText}>{loadError}</Text>
          </View>
        )}

        {/* EPUB viewer */}
        <div ref={viewerRef} style={{ position: 'absolute', inset: 0, zIndex: 1, width: '100%', height: '100%' }} />

        {/* Nav buttons (paginated only) */}
        {viewMode === 'paginated' && uiVisible && (
          <>
            {/* Left */}
            <div
              onClick={atStart ? undefined : goPrev}
              style={{
                position: 'absolute', left: 0, top: 0, bottom: 0, width: '15%', minWidth: 60, zIndex: 10,
                display: 'flex', alignItems: 'center', justifyContent: 'flex-start', padding: '0 0 0 30px',
                cursor: atStart ? 'default' : 'pointer', pointerEvents: atStart ? 'none' : 'auto', opacity: atStart ? 0 : 1,
              }}
            >
              <div style={{
                width: 56, height: 56, borderRadius: '50%', background: 'rgba(20,20,22,0.5)',
                backdropFilter: 'blur(12px)', WebkitBackdropFilter: 'blur(12px)',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                color: '#fff', border: '1px solid rgba(255,255,255,0.05)', boxShadow: '0 10px 40px rgba(0,0,0,0.5)',
              }}>
                <Ionicons name="chevron-back" size={28} color="#fff" />
              </div>
            </div>
            {/* Right */}
            <div
              onClick={atEnd ? undefined : goNext}
              style={{
                position: 'absolute', right: 0, top: 0, bottom: 0, width: '15%', minWidth: 60, zIndex: 10,
                display: 'flex', alignItems: 'center', justifyContent: 'flex-end', padding: '0 30px 0 0',
                cursor: atEnd ? 'default' : 'pointer', pointerEvents: atEnd ? 'none' : 'auto', opacity: atEnd ? 0 : 1,
              }}
            >
              <div style={{
                width: 56, height: 56, borderRadius: '50%', background: 'rgba(20,20,22,0.5)',
                backdropFilter: 'blur(12px)', WebkitBackdropFilter: 'blur(12px)',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
                color: '#fff', border: '1px solid rgba(255,255,255,0.05)', boxShadow: '0 10px 40px rgba(0,0,0,0.5)',
              }}>
                <Ionicons name="chevron-forward" size={28} color="#fff" />
              </div>
            </div>
          </>
        )}
      </View>

      {/* ── Bottom progress bar ── */}
      {readingProgress > 0 && (
        <View style={styles.bottomProgressWrap}>
          <View style={[styles.bottomProgressBar, { width: `${readingProgress}%` }]} />
        </View>
      )}
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
    color: COLORS.text,
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
  headerBar: {
    flexDirection: 'row',
    alignItems: 'center',
    padding: 16,
    borderBottomWidth: 1,
    borderBottomColor: COLORS.border,
  },
  backButton: {
    padding: 6,
    marginRight: 8,
  },
  toolbarBtn: {
    width: 36,
    height: 36,
    borderRadius: 18,
    alignItems: 'center',
    justifyContent: 'center',
  },
  readerArea: {
    flex: 1,
    position: 'relative',
  },
  loadingOverlay: {
    position: 'absolute',
    top: 0,
    left: 0,
    right: 0,
    bottom: 0,
    zIndex: 20,
    backgroundColor: '#050505',
    alignItems: 'center',
    justifyContent: 'center',
  },
  bottomProgressWrap: {
    position: 'absolute',
    bottom: 0,
    left: 0,
    right: 0,
    height: 2,
    backgroundColor: 'rgba(255,255,255,0.04)',
    zIndex: 30,
  },
  bottomProgressBar: {
    height: '100%',
    backgroundColor: 'rgba(239, 68, 68, 0.7)',
  },
});
