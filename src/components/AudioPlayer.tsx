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
  ScrollView
} from 'react-native';
import { Feather, Ionicons } from '@expo/vector-icons';
import { Audio } from 'expo-av';
import { Audiobook, AudiobookChapter } from '../types';

interface AudioPlayerProps {
  audiobook: Audiobook;
  compact?: boolean;
  onClose?: () => void;
}

const formatTime = (seconds: number | null) => {
  if (seconds === null || isNaN(seconds)) return "0:00";
  const safe = Math.max(0, Math.floor(seconds));
  const h = Math.floor(safe / 3600);
  const m = Math.floor((safe % 3600) / 60);
  const s = safe % 60;
  return h > 0
    ? `${h}:${String(m).padStart(2, "0")}:${String(s).padStart(2, "0")}`
    : `${m}:${String(s).padStart(2, "0")}`;
};

const normalizeSeconds = (seconds: any) => {
  const parsed = Number(seconds);
  if (!Number.isFinite(parsed)) return 0;
  return Math.max(0, parsed);
};

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
    [audiobook?.chapters]
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
          Animated.timing(pulseAnim, { toValue: 1, duration: 2000, easing: Easing.out(Easing.ease), useNativeDriver: true }),
          Animated.timing(pulseAnim, { toValue: 0, duration: 2000, easing: Easing.in(Easing.ease), useNativeDriver: true })
        ])
      ).start();

      Animated.loop(
        Animated.sequence([
          Animated.timing(dotAnim, { toValue: 1, duration: 1500, useNativeDriver: true }),
          Animated.timing(dotAnim, { toValue: 0.5, duration: 1500, useNativeDriver: true })
        ])
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
        onPlaybackStatusUpdate
      );
      setSound(newSound);
      setIsLoaded(true);
      // Wait for duration to be set correctly
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
  const nextChapter = currentChapterIndex >= 0 && currentChapterIndex < chapters.length - 1 ? chapters[currentChapterIndex + 1] : null;

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

  const progress = effectiveDuration > 0 ? (currentTime / effectiveDuration) * 100 : 0;
  const elapsed = formatTime(currentTime);
  const remaining = "-" + formatTime(Math.max(0, effectiveDuration - currentTime));

  if (compact) {
    return (
      <View style={styles.compactContainer}>
        <View style={styles.compactRow}>
          {audiobook.cover_url ? (
            <Image source={{ uri: audiobook.cover_url }} style={styles.compactCover} />
          ) : (
            <View style={styles.compactPlaceholder}>
              <Feather name="headphones" size={20} color="#a855f7" />
            </View>
          )}
          <View style={styles.compactInfo}>
            <Text style={styles.compactTitle} numberOfLines={1}>{audiobook.title}</Text>
            {audiobook.author && (
              <Text style={styles.compactAuthor} numberOfLines={1}>{audiobook.author}</Text>
            )}
          </View>
          <TouchableOpacity 
            style={styles.compactPlayBtn} 
            onPress={togglePlay}
            disabled={!isLoaded}
          >
            {playing ? (
              <Ionicons name="pause" size={16} color="#fff" />
            ) : (
              <Ionicons name="play" size={16} color="#fff" style={{ marginLeft: 2 }} />
            )}
          </TouchableOpacity>
        </View>

        <View style={styles.compactProgressWrapper}>
          <View style={styles.compactProgressBarBg}>
            <View style={[styles.compactProgressBarFill, { width: `${progress}%` }]} />
          </View>
          <View style={styles.compactProgressTextRow}>
            <Text style={styles.compactProgressText}>{elapsed}</Text>
            <Text style={styles.compactProgressText}>{formatTime(effectiveDuration)}</Text>
          </View>
        </View>

        {currentChapter && (
           <Text style={styles.compactChapterText} numberOfLines={1}>
             ♫ {currentChapter.title}
           </Text>
        )}
      </View>
    );
  }

  const pulseScale = pulseAnim.interpolate({ inputRange: [0, 1], outputRange: [1, 1.3] });
  const pulseOpacity = pulseAnim.interpolate({ inputRange: [0, 1], outputRange: [0.3, 0] });

  return (
    <View style={styles.root}>
      {/* Container to match the web maxWidth */}
      <View style={styles.container}>
        
        {/* Header bar */}
        <View style={styles.header}>
          <TouchableOpacity style={styles.headerBtn} onPress={onClose}>
            <Ionicons name="close" size={16} color="rgba(255,255,255,0.4)" />
          </TouchableOpacity>
          <View style={styles.headerCenter}>
            <View style={styles.nowPlaying}>
              <Animated.View style={[styles.dot, { 
                backgroundColor: playing ? '#c81e1e' : 'rgba(255,255,255,0.2)',
                opacity: playing ? dotAnim : 1
              }]} />
              <Text style={styles.nowPlayingText}>{playing ? "PLAYING" : "PAUSED"}</Text>
            </View>
          </View>
          <TouchableOpacity 
            style={styles.headerBtn}
            onPress={() => setShowChapters(!showChapters)}
          >
            <Feather name="list" size={16} color={showChapters ? "#c81e1e" : "rgba(255,255,255,0.4)"} />
          </TouchableOpacity>
        </View>

        {/* Cover + Pulse */}
        <View style={styles.coverSection}>
          <View style={styles.coverWrapper}>
            {playing && (
              <Animated.View style={[styles.pulseRing, { transform: [{ scale: pulseScale }], opacity: pulseOpacity }]} />
            )}
            <View style={styles.cover}>
              {audiobook.cover_url ? (
                <Image source={{ uri: audiobook.cover_url }} style={styles.coverImage} />
              ) : (
                <View style={styles.coverBg}>
                  <Text style={styles.coverAuthorFallback}>{(audiobook.author || "").toUpperCase()}</Text>
                  <View style={styles.coverDivider} />
                  <Text style={styles.coverTitleTopFallback}>
                    {audiobook.title ? audiobook.title.split(" ").slice(0, 1).join(" ").toUpperCase() : ""}
                  </Text>
                  <Text style={styles.coverTitleBotFallback}>
                    {audiobook.title ? audiobook.title.split(" ").slice(1).join(" ").toUpperCase() : ""}
                  </Text>
                  <View style={styles.coverDivider} />
                  {audiobook.category && (
                    <Text style={styles.coverSubFallback}>{audiobook.category.toUpperCase()}</Text>
                  )}
                </View>
              )}
            </View>
          </View>
        </View>

        {/* Title + Chapter */}
        <View style={styles.infoBlock}>
          <Text style={styles.title} numberOfLines={2}>{audiobook.title}</Text>
          <Text style={styles.author}>{audiobook.author || audiobook.narrator || ""}</Text>
          
          {currentChapter && (
            <View style={styles.chapterIndicator}>
              <Text style={styles.chapterLabel}>
                CH {String(currentChapterIndex + 1).padStart(2, "0")}
              </Text>
              <Text style={styles.chapterDash}>—</Text>
              <Text style={styles.chapterNameInline} numberOfLines={1}>
                {currentChapter.title}
              </Text>
            </View>
          )}
        </View>

        {/* Pseudo-Waveform Progress */}
        <View style={styles.waveformSection}>
          <TouchableOpacity 
            style={styles.waveformContainer}
            activeOpacity={0.9}
            // A simple pseudo progress bar to match the height and feel of the canvas
          >
            <View style={styles.progressBg}>
               <View style={[styles.progressFill, { width: `${progress}%` }]} />
            </View>
          </TouchableOpacity>
          <View style={styles.timeRow}>
            <Text style={styles.time}>{elapsed}</Text>
            <Text style={styles.time}>{remaining}</Text>
          </View>
        </View>

        {/* Transport Controls */}
        <View style={styles.transport}>
          <TouchableOpacity style={styles.smallBtn} onPress={cycleSpeed}>
            <Text style={styles.speedText}>{speed}×</Text>
          </TouchableOpacity>

          <TouchableOpacity style={styles.transportBtn} onPress={() => skipBy(-30)} disabled={!isLoaded}>
            <Ionicons name="play-back" size={20} color="rgba(255,255,255,0.5)" />
            <Text style={styles.skipNum}>30</Text>
          </TouchableOpacity>

          <TouchableOpacity style={styles.transportBtn} onPress={() => previousChapter && jumpToChapter(currentChapterIndex - 1)} disabled={!previousChapter}>
            <Ionicons name="play-skip-back" size={22} color="rgba(255,255,255,0.7)" />
          </TouchableOpacity>

          <TouchableOpacity 
            style={[styles.playBtn, playing && styles.playBtnActive]} 
            onPress={togglePlay}
            disabled={!isLoaded}
          >
            {playing ? (
              <Ionicons name="pause" size={28} color="#fff" />
            ) : (
              <Ionicons name="play" size={28} color="#fff" style={{ marginLeft: 4 }} />
            )}
          </TouchableOpacity>

          <TouchableOpacity style={styles.transportBtn} onPress={() => nextChapter && jumpToChapter(currentChapterIndex + 1)} disabled={!nextChapter}>
            <Ionicons name="play-skip-forward" size={22} color="rgba(255,255,255,0.7)" />
          </TouchableOpacity>

          <TouchableOpacity style={styles.transportBtn} onPress={() => skipBy(30)} disabled={!isLoaded}>
            <Ionicons name="play-forward" size={20} color="rgba(255,255,255,0.5)" />
            <Text style={styles.skipNum}>30</Text>
          </TouchableOpacity>

        </View>

        {/* Chapter List */}
        {showChapters && chapters.length > 0 && (
          <View style={styles.chapterPanel}>
            <View style={styles.chapterPanelHeader}>
              <Text style={styles.chapterPanelTitle}>CHAPTERS</Text>
              <Text style={styles.chapterPanelMeta}>{chapters.length} · {formatTime(effectiveDuration)}</Text>
            </View>
            <ScrollView style={styles.chapterListScroll} nestedScrollEnabled>
              {chapters.map((ch, idx) => {
                const isActive = idx === currentChapterIndex;
                const nextStart = idx < chapters.length - 1 ? chapters[idx + 1].start_seconds : effectiveDuration;
                const chProgress = currentTime >= ch.start_seconds 
                    ? Math.min(100, ((currentTime - ch.start_seconds) / (nextStart - ch.start_seconds || 1)) * 100)
                    : 0;

                return (
                  <TouchableOpacity 
                    key={idx} 
                    style={[styles.chapterRow, isActive && styles.chapterRowActive]}
                    onPress={() => jumpToChapter(idx)}
                  >
                    <View style={styles.chapterRowLeft}>
                      <Text style={[styles.chNum, isActive && styles.chNumActive]}>
                        {String(idx + 1).padStart(2, "0")}
                      </Text>
                      <View style={styles.chTextBlock}>
                        <Text style={[styles.chName, isActive && styles.chNameActive]} numberOfLines={1}>{ch.title}</Text>
                        <Text style={styles.chDur}>{formatTime(nextStart - ch.start_seconds)}</Text>
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
            </ScrollView>
          </View>
        )}
      </View>
    </View>
  );
}

const windowWidth = Dimensions.get('window').width;

const styles = StyleSheet.create({
  root: {
    width: '100%',
    alignItems: 'center',
    justifyContent: 'center',
    backgroundColor: '#090909',
    paddingVertical: 20,
    paddingHorizontal: 16,
    borderRadius: 16,
    overflow: 'hidden',
  },
  container: {
    width: '100%',
    maxWidth: 400,
  },
  header: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingBottom: 24,
  },
  headerBtn: {
    width: 36,
    height: 36,
    borderRadius: 18,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.06)',
    backgroundColor: 'rgba(255,255,255,0.02)',
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
    gap: 6,
  },
  dot: {
    width: 5,
    height: 5,
    borderRadius: 2.5,
  },
  nowPlayingText: {
    fontSize: 10,
    fontWeight: '500',
    letterSpacing: 2,
    color: 'rgba(255,255,255,0.3)',
    fontFamily: 'Courier', // Standard monospace
  },
  coverSection: {
    alignItems: 'center',
    paddingBottom: 28,
  },
  coverWrapper: {
    width: 160,
    height: 160,
    position: 'relative',
    alignItems: 'center',
    justifyContent: 'center',
  },
  pulseRing: {
    position: 'absolute',
    width: 160,
    height: 160,
    borderRadius: 80,
    backgroundColor: 'rgba(200,30,30,0.4)',
  },
  cover: {
    width: '100%',
    height: '100%',
    borderRadius: 4,
    overflow: 'hidden',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.06)',
    backgroundColor: '#0f0f0f',
  },
  coverImage: {
    width: '100%',
    height: '100%',
  },
  coverBg: {
    flex: 1,
    alignItems: 'center',
    justifyContent: 'center',
    padding: 16,
    backgroundColor: '#141010',
  },
  coverAuthorFallback: {
    fontSize: 7,
    fontWeight: '500',
    letterSpacing: 3,
    color: 'rgba(200,30,30,0.5)',
    fontFamily: 'Courier',
  },
  coverDivider: {
    width: 24,
    height: 1,
    backgroundColor: 'rgba(200,30,30,0.2)',
    marginVertical: 8,
  },
  coverTitleTopFallback: {
    fontSize: 24,
    fontWeight: '300',
    letterSpacing: 2,
    color: 'rgba(255,255,255,0.85)',
    textAlign: 'center',
  },
  coverTitleBotFallback: {
    fontSize: 24,
    fontWeight: '600',
    letterSpacing: 2,
    color: 'rgba(255,255,255,0.95)',
    textAlign: 'center',
    marginTop: 2,
  },
  coverSubFallback: {
    fontSize: 6,
    fontWeight: '400',
    letterSpacing: 5,
    color: 'rgba(255,255,255,0.2)',
    fontFamily: 'Courier',
  },
  infoBlock: {
    alignItems: 'center',
    paddingBottom: 24,
  },
  title: {
    fontSize: 22,
    fontWeight: '400',
    color: '#fff',
    letterSpacing: 1,
    marginBottom: 2,
    textAlign: 'center',
    fontFamily: 'Georgia', // Standard serif fallback
  },
  author: {
    fontSize: 13,
    fontWeight: '300',
    fontStyle: 'italic',
    color: 'rgba(255,255,255,0.3)',
    marginBottom: 12,
  },
  chapterIndicator: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 8,
  },
  chapterLabel: {
    fontSize: 10,
    fontWeight: '500',
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
    fontWeight: '300',
    color: 'rgba(255,255,255,0.4)',
    fontFamily: 'Courier',
    flexShrink: 1,
  },
  waveformSection: {
    paddingBottom: 20,
  },
  waveformContainer: {
    height: 40, // Shorter than web since it's a solid bar on mobile
    borderRadius: 4,
    backgroundColor: 'rgba(255,255,255,0.015)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.03)',
    justifyContent: 'center',
    paddingHorizontal: 4,
  },
  progressBg: {
    height: 4,
    backgroundColor: 'rgba(255,255,255,0.1)',
    borderRadius: 2,
  },
  progressFill: {
    height: '100%',
    backgroundColor: '#c81e1e',
    borderRadius: 2,
  },
  timeRow: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    paddingTop: 8,
    paddingHorizontal: 2,
  },
  time: {
    fontSize: 10,
    color: 'rgba(255,255,255,0.25)',
    fontFamily: 'Courier',
    fontWeight: '300',
  },
  transport: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'center',
    gap: 14,
    paddingTop: 4,
    paddingBottom: 16,
  },
  smallBtn: {
    width: 34,
    height: 34,
    borderRadius: 17,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.06)',
    alignItems: 'center',
    justifyContent: 'center',
  },
  speedText: {
    fontSize: 10,
    color: 'rgba(255,255,255,0.4)',
    fontFamily: 'Courier',
    fontWeight: '400',
  },
  transportBtn: {
    width: 40,
    height: 40,
    borderRadius: 20,
    alignItems: 'center',
    justifyContent: 'center',
  },
  skipNum: {
    position: 'absolute',
    fontSize: 7,
    fontWeight: '500',
    color: 'rgba(255,255,255,0.5)',
    fontFamily: 'Courier',
    top: 15, // Adjusted to sit inside the icon visually
  },
  playBtn: {
    width: 56,
    height: 56,
    borderRadius: 28,
    backgroundColor: '#c81e1e',
    alignItems: 'center',
    justifyContent: 'center',
    shadowColor: '#c81e1e',
    shadowOffset: { width: 0, height: 0 },
    shadowOpacity: 0.15,
    shadowRadius: 10,
    elevation: 4,
  },
  playBtnActive: {
    shadowOpacity: 0.3,
    shadowRadius: 20,
    elevation: 10,
  },
  chapterPanel: {
    backgroundColor: 'rgba(255,255,255,0.02)',
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.04)',
    borderRadius: 8,
    marginTop: 8,
    maxHeight: 250,
  },
  chapterPanelHeader: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    paddingTop: 14,
    paddingHorizontal: 16,
    paddingBottom: 10,
    borderBottomWidth: 1,
    borderBottomColor: 'rgba(255,255,255,0.04)',
  },
  chapterPanelTitle: {
    fontSize: 10,
    fontWeight: '500',
    letterSpacing: 2,
    color: 'rgba(255,255,255,0.35)',
    fontFamily: 'Courier',
  },
  chapterPanelMeta: {
    fontSize: 10,
    color: 'rgba(255,255,255,0.2)',
    fontFamily: 'Courier',
  },
  chapterListScroll: {
    paddingHorizontal: 6,
    paddingBottom: 8,
  },
  chapterRow: {
    flexDirection: 'row',
    alignItems: 'center',
    justifyContent: 'space-between',
    paddingVertical: 9,
    paddingHorizontal: 12,
    borderRadius: 6,
  },
  chapterRowActive: {
    backgroundColor: 'rgba(200,30,30,0.1)',
  },
  chapterRowLeft: {
    flexDirection: 'row',
    alignItems: 'center',
    gap: 14,
    flex: 1,
  },
  chNum: {
    fontSize: 11,
    fontWeight: '500',
    fontFamily: 'Courier',
    color: 'rgba(255,255,255,0.2)',
    width: 22,
    textAlign: 'center',
  },
  chNumActive: {
    color: '#c81e1e',
  },
  chTextBlock: {
    flex: 1,
  },
  chName: {
    fontSize: 14,
    fontWeight: '400',
    fontFamily: 'Georgia',
    color: 'rgba(255,255,255,0.55)',
  },
  chNameActive: {
    color: '#fff',
  },
  chDur: {
    fontSize: 9,
    color: 'rgba(255,255,255,0.18)',
    fontFamily: 'Courier',
    marginTop: 2,
  },
  chBar: {
    width: 36,
    height: 2,
    backgroundColor: 'rgba(255,255,255,0.06)',
    borderRadius: 1,
    marginLeft: 8,
  },
  chBarFill: {
    height: '100%',
    backgroundColor: '#c81e1e',
    borderRadius: 1,
  },

  // Compact styles adapted to new aesthetic
  compactContainer: {
    gap: 12,
    backgroundColor: '#090909',
    padding: 12,
    borderRadius: 12,
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
    borderRadius: 8,
    borderWidth: 1,
    borderColor: 'rgba(255,255,255,0.1)',
  },
  compactPlaceholder: {
    width: 48,
    height: 48,
    borderRadius: 8,
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
    fontFamily: 'Georgia',
  },
  compactAuthor: {
    color: 'rgba(255,255,255,0.4)',
    fontSize: 11,
    marginTop: 2,
  },
  compactPlayBtn: {
    width: 36,
    height: 36,
    borderRadius: 18,
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
