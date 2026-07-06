import React, { useEffect, useState, useRef, useMemo, useCallback } from 'react';
import {
  View,
  Text,
  StyleSheet,
  TouchableOpacity,
  Image,
  Dimensions,
  Animated,
  Easing,
  ScrollView,
} from 'react-native';
import { Ionicons } from '@expo/vector-icons';
import { Audio } from 'expo-av';
import { Audiobook } from '../types';
import SoundwaveVisualizer from './SoundwaveVisualizer';

interface AudioPlayerProps {
  audiobook: Audiobook;
  compact?: boolean;
  onClose?: () => void;
}

const formatTime = (seconds: number | null) => {
  if (seconds === null || isNaN(seconds)) return '0:00';
  const safe = Math.max(0, Math.floor(seconds));
  const h = Math.floor(safe / 3600);
  const m = Math.floor((safe % 3600) / 60);
  const s = safe % 60;
  return h > 0
    ? `${h}:${String(m).padStart(2, '0')}:${String(s).padStart(2, '0')}`
    : `${m}:${String(s).padStart(2, '0')}`;
};

const normalizeSeconds = (seconds: any) => {
  const parsed = Number(seconds);
  if (!Number.isFinite(parsed)) return 0;
  return Math.max(0, parsed);
};

const { width: SCREEN_WIDTH } = Dimensions.get('window');
const COVER_SIZE = Math.min(SCREEN_WIDTH - 80, 300);

export default function AudioPlayer({ audiobook, compact = false, onClose }: AudioPlayerProps) {
  const [sound, setSound] = useState<Audio.Sound | null>(null);
  const [playing, setPlaying] = useState(false);
  const [currentTime, setCurrentTime] = useState(0);
  const [duration, setDuration] = useState(0);
  const [showChapters, setShowChapters] = useState(false);
  const [speed, setSpeed] = useState(1.0);
  const [isLoaded, setIsLoaded] = useState(false);

  // Animations
  const pulseAnim = useRef(new Animated.Value(0)).current;
  const dotAnim = useRef(new Animated.Value(0.5)).current;

  const chapters = useMemo(
    () =>
      (Array.isArray(audiobook?.chapters) ? audiobook.chapters : [])
        .map((chapter, index) => ({
          ...chapter,
          title: chapter.title?.trim() ? chapter.title.trim() : `Chapter ${index + 1}`,
          start_seconds: normalizeSeconds(chapter.start_seconds),
          sort_index: index,
        }))
        .sort((a, b) => a.start_seconds - b.start_seconds || a.sort_index - b.sort_index),
    [audiobook?.chapters],
  );

  const effectiveDuration = duration > 0 ? duration : normalizeSeconds(audiobook?.duration_seconds);

  useEffect(() => {
    return () => {
      if (sound) {
        sound.unloadAsync();
      }
    };
  }, [sound]);

  useEffect(() => {
    loadAudio();
  }, [audiobook.id]);

  useEffect(() => {
    if (playing) {
      Animated.loop(
        Animated.sequence([
          Animated.timing(pulseAnim, { toValue: 1, duration: 2500, easing: Easing.out(Easing.ease), useNativeDriver: true }),
          Animated.timing(pulseAnim, { toValue: 0, duration: 2500, easing: Easing.in(Easing.ease), useNativeDriver: true }),
        ]),
      ).start();

      Animated.loop(
        Animated.sequence([
          Animated.timing(dotAnim, { toValue: 1, duration: 1500, useNativeDriver: true }),
          Animated.timing(dotAnim, { toValue: 0.5, duration: 1500, useNativeDriver: true }),
        ]),
      ).start();
    } else {
      pulseAnim.stopAnimation();
      pulseAnim.setValue(0);
      dotAnim.stopAnimation();
      dotAnim.setValue(0.5);
    }
  }, [playing]);

  const loadAudio = async () => {
    try {
      setIsLoaded(false);
      setPlaying(false);
      setCurrentTime(0);

      const { sound: newSound } = await Audio.Sound.createAsync(
        { uri: audiobook.audio_url },
        { shouldPlay: false, rate: speed, shouldCorrectPitch: true },
        onPlaybackStatusUpdate,
      );
      setSound(newSound);
      setIsLoaded(true);
      const status = await newSound.getStatusAsync();
      if (status.isLoaded && status.durationMillis) {
        setDuration(status.durationMillis / 1000);
      } else {
        setDuration(normalizeSeconds(audiobook.duration_seconds));
      }
    } catch (error) {
      console.error('Error loading audio:', error);
    }
  };

  const onPlaybackStatusUpdate = (status: any) => {
    if (status.isLoaded) {
      setCurrentTime(status.positionMillis / 1000);
      if (status.durationMillis) {
        setDuration(status.durationMillis / 1000);
      }
      setPlaying(status.isPlaying);
      if (status.didJustFinish) {
        setPlaying(false);
        setCurrentTime(0);
      }
    }
  };

  const togglePlay = async () => {
    if (!sound) return;
    if (playing) {
      await sound.pauseAsync();
    } else {
      await sound.playAsync();
    }
  };

  const seekTo = async (seconds: number) => {
    if (!sound) return;
    const clamped = Math.max(0, Math.min(effectiveDuration, seconds));
    await sound.setPositionAsync(clamped * 1000);
  };

  const skipBy = async (delta: number) => {
    if (!sound) return;
    const nextTime = Math.max(0, Math.min(effectiveDuration, currentTime + delta));
    await sound.setPositionAsync(nextTime * 1000);
  };

  const currentChapterIndex = useMemo(() => {
    if (chapters.length === 0) return -1;
    for (let i = chapters.length - 1; i >= 0; i--) {
      if (currentTime >= chapters[i].start_seconds) return i;
    }
    return 0;
  }, [chapters, currentTime]);

  const currentChapter = currentChapterIndex >= 0 ? chapters[currentChapterIndex] : null;
  const previousChapter = currentChapterIndex > 0 ? chapters[currentChapterIndex - 1] : null;
  const nextChapter =
    currentChapterIndex >= 0 && currentChapterIndex < chapters.length - 1
      ? chapters[currentChapterIndex + 1]
      : null;

  const jumpToChapter = (index: number) => {
    const ch = chapters[index];
    if (ch) seekTo(ch.start_seconds);
  };

  const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];
  const cycleSpeed = async () => {
    const idx = speeds.indexOf(speed);
    const nextSpeed = speeds[(idx + 1) % speeds.length];
    setSpeed(nextSpeed);
    if (sound) {
      await sound.setRateAsync(nextSpeed, true);
    }
  };

  const progress = effectiveDuration > 0 ? currentTime / effectiveDuration : 0;
  const elapsed = formatTime(currentTime);
  const remaining = '-' + formatTime(Math.max(0, effectiveDuration - currentTime));

  const handleSeek = useCallback(
    (pct: number) => {
      if (effectiveDuration > 0) {
        seekTo(pct * effectiveDuration);
      }
    },
    [effectiveDuration, sound],
  );

  // ── Compact variant ──
  if (compact) {
    return (
      <View style={styles.compactContainer}>
        <View style={styles.compactRow}>
          {audiobook.cover_url ? (
            <Image source={{ uri: audiobook.cover_url }} style={styles.compactCover} />
          ) : (
            <View style={styles.compactPlaceholder}>
              <Ionicons name="headset" size={20} color="#c81e1e" />
            </View>
          )}
          <View style={styles.compactInfo}>
            <Text style={styles.compactTitle} numberOfLines={1}>
              {audiobook.title}
            </Text>
            {audiobook.author && (
              <Text style={styles.compactAuthor} numberOfLines={1}>
                {audiobook.author}
              </Text>
            )}
          </View>
          <TouchableOpacity style={styles.compactPlayBtn} onPress={togglePlay} disabled={!isLoaded}>
            {playing ? (
              <Ionicons name="pause" size={16} color="#fff" />
            ) : (
              <Ionicons name="play" size={16} color="#fff" style={{ marginLeft: 2 }} />
            )}
          </TouchableOpacity>
        </View>
        <View style={styles.compactProgressWrapper}>
          <View style={styles.compactProgressBarBg}>
            <View style={[styles.compactProgressBarFill, { width: `${progress * 100}%` }]} />
          </View>
          <View style={styles.compactProgressTextRow}>
            <Text style={styles.compactProgressText}>{elapsed}</Text>
            <Text style={styles.compactProgressText}>{formatTime(effectiveDuration)}</Text>
          </View>
        </View>
        {currentChapter && (
          <Text style={styles.compactChapterText} numberOfLines={1}>
            {currentChapter.title}
          </Text>
        )}
      </View>
    );
  }

  // ── Full-screen player ──
  const pulseScale = pulseAnim.interpolate({ inputRange: [0, 1], outputRange: [1, 1.15] });
  const pulseOpacity = pulseAnim.interpolate({ inputRange: [0, 1], outputRange: [0.35, 0] });

  return (
    <View style={styles.root}>
      <ScrollView
        style={styles.scrollView}
        contentContainerStyle={styles.scrollContent}
        showsVerticalScrollIndicator={false}
        bounces={false}
      >
        {/* ── Header ── */}
        <View style={styles.header}>
          <TouchableOpacity style={styles.headerBtn} onPress={onClose}>
            <Ionicons name="chevron-down" size={22} color="rgba(255,255,255,0.5)" />
          </TouchableOpacity>
          <View style={styles.headerCenter}>
            <View style={styles.nowPlaying}>
              <Animated.View
                style={[
                  styles.dot,
                  {
                    backgroundColor: playing ? '#c81e1e' : 'rgba(255,255,255,0.2)',
                    opacity: playing ? dotAnim : 1,
                  },
                ]}
              />
              <Text style={styles.nowPlayingText}>
                {playing ? 'NOW PLAYING' : 'PAUSED'}
              </Text>
            </View>
          </View>
          <TouchableOpacity
            style={styles.headerBtn}
            onPress={() => setShowChapters(!showChapters)}
          >
            <Ionicons
              name="list"
              size={20}
              color={showChapters ? '#c81e1e' : 'rgba(255,255,255,0.5)'}
            />
          </TouchableOpacity>
        </View>

        {/* ── Cover Art ── */}
        <View style={styles.coverSection}>
          <View style={[styles.coverWrapper, { width: COVER_SIZE, height: COVER_SIZE }]}>
            {playing && (
              <Animated.View
                style={[
                  styles.pulseRing,
                  {
                    width: COVER_SIZE + 40,
                    height: COVER_SIZE + 40,
                    borderRadius: (COVER_SIZE + 40) / 2,
                    transform: [{ scale: pulseScale }],
                    opacity: pulseOpacity,
                  },
                ]}
              />
            )}
            <View style={[styles.cover, { borderRadius: 20 }]}>
              {audiobook.cover_url ? (
                <Image source={{ uri: audiobook.cover_url }} style={styles.coverImage} />
              ) : (
                <View style={styles.coverFallback}>
                  <Text style={styles.coverFallbackAuthor}>
                    {(audiobook.author || '').toUpperCase()}
                  </Text>
                  <View style={styles.coverDivider} />
                  <Text style={styles.coverFallbackTitle} numberOfLines={3}>
                    {(audiobook.title || '').toUpperCase()}
                  </Text>
                  <View style={styles.coverDivider} />
                  {audiobook.category && (
                    <Text style={styles.coverFallbackSub}>
                      {audiobook.category.toUpperCase()}
                    </Text>
                  )}
                </View>
              )}
            </View>
          </View>
        </View>

        {/* ── Title + Author + Chapter ── */}
        <View style={styles.infoBlock}>
          <Text style={styles.title} numberOfLines={2}>
            {audiobook.title}
          </Text>
          <Text style={styles.author}>
            {audiobook.author || audiobook.narrator || ''}
          </Text>
          {currentChapter && (
            <View style={styles.chapterIndicator}>
              <Text style={styles.chapterLabel}>
                CH {String(currentChapterIndex + 1).padStart(2, '0')}
              </Text>
              <Text style={styles.chapterDash}>—</Text>
              <Text style={styles.chapterNameInline} numberOfLines={1}>
                {currentChapter.title}
              </Text>
            </View>
          )}
        </View>

        {/* ── Waveform Visualizer ── */}
        <View style={styles.waveformSection}>
          <SoundwaveVisualizer
            progress={progress}
            isPlaying={playing}
            onSeek={handleSeek}
            height={56}
          />
          <View style={styles.timeRow}>
            <Text style={styles.time}>{elapsed}</Text>
            <Text style={styles.time}>{remaining}</Text>
          </View>
        </View>

        {/* ── Transport Controls ── */}
        <View style={styles.transport}>
          <TouchableOpacity style={styles.smallBtn} onPress={cycleSpeed}>
            <Text style={styles.speedText}>{speed}×</Text>
          </TouchableOpacity>

          <TouchableOpacity
            style={styles.transportBtn}
            onPress={() => skipBy(-30)}
            disabled={!isLoaded}
          >
            <Ionicons name="play-back" size={22} color="rgba(255,255,255,0.5)" />
          </TouchableOpacity>

          <TouchableOpacity
            style={styles.transportBtn}
            onPress={() => previousChapter && jumpToChapter(currentChapterIndex - 1)}
            disabled={!previousChapter}
          >
            <Ionicons name="play-skip-back" size={24} color="rgba(255,255,255,0.7)" />
          </TouchableOpacity>

          <TouchableOpacity
            style={[styles.playBtn, playing && styles.playBtnActive]}
            onPress={togglePlay}
            disabled={!isLoaded}
          >
            {playing ? (
              <Ionicons name="pause" size={32} color="#fff" />
            ) : (
              <Ionicons name="play" size={32} color="#fff" style={{ marginLeft: 4 }} />
            )}
          </TouchableOpacity>

          <TouchableOpacity
            style={styles.transportBtn}
            onPress={() => nextChapter && jumpToChapter(currentChapterIndex + 1)}
            disabled={!nextChapter}
          >
            <Ionicons name="play-skip-forward" size={24} color="rgba(255,255,255,0.7)" />
          </TouchableOpacity>

          <TouchableOpacity
            style={styles.transportBtn}
            onPress={() => skipBy(30)}
            disabled={!isLoaded}
          >
            <Ionicons name="play-forward" size={22} color="rgba(255,255,255,0.5)" />
          </TouchableOpacity>
        </View>

        {/* ── Chapter List ── */}
        {showChapters && chapters.length > 0 && (
          <View style={styles.chapterPanel}>
            <View style={styles.chapterPanelHeader}>
              <Text style={styles.chapterPanelTitle}>CHAPTERS</Text>
              <Text style={styles.chapterPanelMeta}>
                {chapters.length} · {formatTime(effectiveDuration)}
              </Text>
            </View>
            {chapters.map((ch, idx) => {
              const isActive = idx === currentChapterIndex;
              const nextStart =
                idx < chapters.length - 1
                  ? chapters[idx + 1].start_seconds
                  : effectiveDuration;
              const chProgress =
                currentTime >= ch.start_seconds
                  ? Math.min(
                      100,
                      ((currentTime - ch.start_seconds) /
                        (nextStart - ch.start_seconds || 1)) *
                        100,
                    )
                  : 0;

              return (
                <TouchableOpacity
                  key={idx}
                  style={[styles.chapterRow, isActive && styles.chapterRowActive]}
                  onPress={() => jumpToChapter(idx)}
                >
                  <View style={styles.chapterRowLeft}>
                    <Text style={[styles.chNum, isActive && styles.chNumActive]}>
                      {String(idx + 1).padStart(2, '0')}
                    </Text>
                    <View style={styles.chTextBlock}>
                      <Text
                        style={[styles.chName, isActive && styles.chNameActive]}
                        numberOfLines={1}
                      >
                        {ch.title}
                      </Text>
                      <Text style={styles.chDur}>
                        {formatTime(nextStart - ch.start_seconds)}
                      </Text>
                    </View>
                  </View>
                  {chProgress > 0 && isActive && (
                    <View style={styles.chBar}>
                      <View style={[styles.chBarFill, { width: `${chProgress}%` }]} />
                    </View>
                  )}
                </TouchableOpacity>
              );
            })}
          </View>
        )}
      </ScrollView>
    </View>
  );
}

const styles = StyleSheet.create({
  root: {
    flex: 1,
    backgroundColor: '#050505',
  },
  scrollView: {
    flex: 1,
  },
  scrollContent: {
    paddingHorizontal: 24,
    paddingTop: 16,
    paddingBottom: 40,
  },

  // ── Header ──
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingBottom: 32,
  },
  headerBtn: {
    width: 40,
    height: 40,
    borderRadius: 20,
    backgroundColor: 'rgba(255,255,255,0.05)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.06)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  headerCenter: {
    alignItems: 'center',
    justifyContent: 'center',
  },
  nowPlaying: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  dot: {
    width: 6,
    height: 6,
    borderRadius: 3,
  },
  nowPlayingText: {
    fontSize: 10,
    fontWeight: '600',
    letterSpacing: 2.5,
    color: 'rgba(255,255,255,0.3)',
    fontFamily: 'Courier',
  },

  // ── Cover ──
  coverSection: {
    alignItems: 'center',
    paddingBottom: 36,
  },
  coverWrapper: {
    position: 'relative',
    alignItems: 'center',
    justifyContent: 'center',
  },
  pulseRing: {
    position: 'absolute',
    backgroundColor: 'rgba(200,30,30,0.25)',
  },
  cover: {
    width: '100%',
    height: '100%',
    overflow: 'hidden',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    backgroundColor: '#0f0f0f',
    shadowColor: '#000',
    shadowOffset: { width: 0, height: 20 },
    shadowOpacity: 0.6,
    shadowRadius: 40,
    elevation: 20,
  },
  coverImage: {
    width: '100%',
    height: '100%',
  },
  coverFallback: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 24,
    backgroundColor: '#110a0a',
  },
  coverFallbackAuthor: {
    fontSize: 9,
    fontWeight: '500',
    letterSpacing: 4,
    color: 'rgba(200,30,30,0.5)',
    fontFamily: 'Courier',
  },
  coverDivider: {
    width: 32,
    height: 1,
    backgroundColor: 'rgba(200,30,30,0.2)',
    marginVertical: 10,
  },
  coverFallbackTitle: {
    fontSize: 28,
    fontWeight: '300',
    letterSpacing: 2,
    color: 'rgba(255,255,255,0.9)',
    textAlign: 'center',
    fontFamily: 'Georgia',
  },
  coverFallbackSub: {
    fontSize: 7,
    fontWeight: '400',
    letterSpacing: 5,
    color: 'rgba(255,255,255,0.2)',
    fontFamily: 'Courier',
  },

  // ── Info ──
  infoBlock: {
    alignItems: 'center',
    paddingBottom: 28,
  },
  title: {
    fontSize: 24,
    fontWeight: '600',
    color: '#fff',
    letterSpacing: 0.3,
    marginBottom: 6,
    textAlign: 'center',
    fontFamily: 'Georgia',
  },
  author: {
    fontSize: 15,
    fontWeight: '400',
    color: 'rgba(255,255,255,0.4)',
    marginBottom: 14,
  },
  chapterIndicator: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
    backgroundColor: 'rgba(200,30,30,0.08)',
    paddingHorizontal: 14,
    paddingVertical: 6,
    borderRadius: 20,
  },
  chapterLabel: {
    fontSize: 10,
    fontWeight: '600',
    letterSpacing: 1.5,
    color: '#c81e1e',
    fontFamily: 'Courier',
  },
  chapterDash: {
    color: 'rgba(255,255,255,0.12)',
    fontSize: 12,
  },
  chapterNameInline: {
    fontSize: 12,
    fontWeight: '400',
    color: 'rgba(255,255,255,0.5)',
    fontFamily: 'Courier',
    flexShrink: 1,
  },

  // ── Waveform ──
  waveformSection: {
    paddingBottom: 8,
  },
  timeRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingTop: 10,
    paddingHorizontal: 2,
  },
  time: {
    fontSize: 11,
    color: 'rgba(255,255,255,0.3)',
    fontFamily: 'Courier',
    fontWeight: '400',
  },

  // ── Transport ──
  transport: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 16,
    paddingTop: 16,
    paddingBottom: 24,
  },
  smallBtn: {
    width: 38,
    height: 38,
    borderRadius: 19,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.08)',
    backgroundColor: 'rgba(255,255,255,0.03)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  speedText: {
    fontSize: 11,
    color: 'rgba(255,255,255,0.5)',
    fontFamily: 'Courier',
    fontWeight: '500',
  },
  transportBtn: {
    width: 48,
    height: 48,
    borderRadius: 24,
    alignItems: 'center',
    justifyContent: 'center',
  },
  playBtn: {
    width: 68,
    height: 68,
    borderRadius: 34,
    backgroundColor: '#c81e1e',
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: '#c81e1e',
    shadowOffset: { width: 0, height: 4 },
    shadowOpacity: 0.3,
    shadowRadius: 16,
    elevation: 8,
  },
  playBtnActive: {
    shadowOpacity: 0.5,
    shadowRadius: 30,
    elevation: 16,
  },

  // ── Chapters ──
  chapterPanel: {
    backgroundColor: 'rgba(255,255,255,0.02)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.05)',
    borderRadius: 16,
    overflow: 'hidden',
  },
  chapterPanelHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingTop: 16,
    paddingHorizontal: 20,
    paddingBottom: 12,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(255,255,255,0.04)',
  },
  chapterPanelTitle: {
    fontSize: 10,
    fontWeight: '600',
    letterSpacing: 2.5,
    color: 'rgba(255,255,255,0.35)',
    fontFamily: 'Courier',
  },
  chapterPanelMeta: {
    fontSize: 10,
    color: 'rgba(255,255,255,0.2)',
    fontFamily: 'Courier',
  },
  chapterRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: 12,
    paddingHorizontal: 20,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(255,255,255,0.03)',
  },
  chapterRowActive: {
    backgroundColor: 'rgba(200,30,30,0.08)',
  },
  chapterRowLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 16,
    flex: 1,
  },
  chNum: {
    fontSize: 12,
    fontWeight: '500',
    fontFamily: 'Courier',
    color: 'rgba(255,255,255,0.2)',
    width: 24,
    textAlign: 'center',
  },
  chNumActive: {
    color: '#c81e1e',
  },
  chTextBlock: {
    flex: 1,
  },
  chName: {
    fontSize: 15,
    fontWeight: '400',
    fontFamily: 'Georgia',
    color: 'rgba(255,255,255,0.55)',
  },
  chNameActive: {
    color: '#fff',
  },
  chDur: {
    fontSize: 10,
    color: 'rgba(255,255,255,0.18)',
    fontFamily: 'Courier',
    marginTop: 3,
  },
  chBar: {
    width: 40,
    height: 3,
    backgroundColor: 'rgba(255,255,255,0.06)',
    borderRadius: 1.5,
    marginLeft: 8,
  },
  chBarFill: {
    height: '100%',
    backgroundColor: '#c81e1e',
    borderRadius: 1.5,
  },

  // ── Compact ──
  compactContainer: {
    gap: 12,
    backgroundColor: '#090909',
    padding: 14,
    borderRadius: 14,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.06)',
  },
  compactRow: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 12,
  },
  compactCover: {
    width: 48,
    height: 48,
    borderRadius: 10,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
  },
  compactPlaceholder: {
    width: 48,
    height: 48,
    borderRadius: 10,
    backgroundColor: 'rgba(200,30,30,0.15)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  compactInfo: {
    flex: 1,
    justifyContent: 'center',
  },
  compactTitle: {
    color: '#fff',
    fontSize: 14,
    fontWeight: '600',
    fontFamily: 'Georgia',
  },
  compactAuthor: {
    color: 'rgba(255,255,255,0.4)',
    fontSize: 11,
    marginTop: 2,
  },
  compactPlayBtn: {
    width: 38,
    height: 38,
    borderRadius: 19,
    backgroundColor: '#c81e1e',
    alignItems: 'center',
    justifyContent: 'center',
  },
  compactProgressWrapper: {
    gap: 4,
  },
  compactProgressBarBg: {
    height: 4,
    backgroundColor: 'rgba(255,255,255,0.1)',
    borderRadius: 2,
  },
  compactProgressBarFill: {
    height: '100%',
    backgroundColor: '#c81e1e',
    borderRadius: 2,
  },
  compactProgressTextRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
  },
  compactProgressText: {
    color: 'rgba(255,255,255,0.3)',
    fontSize: 9,
    fontFamily: 'Courier',
  },
  compactChapterText: {
    color: '#c81e1e',
    fontSize: 10,
    fontFamily: 'Courier',
  },
});
