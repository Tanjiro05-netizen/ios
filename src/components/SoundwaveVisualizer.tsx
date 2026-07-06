import React, { useEffect, useRef } from 'react';
import { View, StyleSheet, Animated, Easing } from 'react-native';

const BAR_COUNT = 32;
const BAR_GAP = 3;
const BAR_WIDTH = 4;
const BAR_RADIUS = 2;
const MIN_HEIGHT_FRACTION = 0.12;
const MAX_HEIGHT_FRACTION = 0.92;

// Amplitude envelope — bars near center are taller
const AMPLITUDE_ENVELOPE = Array.from({ length: BAR_COUNT }, (_, i) => {
  const norm = i / (BAR_COUNT - 1);
  const bell = Math.exp(-Math.pow((norm - 0.5) * 3.2, 2));
  return 0.35 + 0.65 * bell;
});

interface SoundwaveVisualizerProps {
  progress: number; // 0–1
  isPlaying: boolean;
  onSeek?: (percent: number) => void;
  height?: number;
  accentColor?: string;
  dimColor?: string;
}

export default function SoundwaveVisualizer({
  progress,
  isPlaying,
  onSeek,
  height = 56,
  accentColor = '#c81e1e',
  dimColor = 'rgba(255,255,255,0.08)',
}: SoundwaveVisualizerProps) {
  const barAnims = useRef(
    Array.from({ length: BAR_COUNT }, () => new Animated.Value(0.3))
  ).current;
  const widthRef = useRef(0);
  const progressIndex = Math.floor(progress * BAR_COUNT);

  useEffect(() => {
    barAnims.forEach((anim, i) => {
      anim.stopAnimation();

      if (isPlaying) {
        const amp = AMPLITUDE_ENVELOPE[i];
        const lo = MIN_HEIGHT_FRACTION + (1 - amp) * 0.15;
        const hi = MIN_HEIGHT_FRACTION + (MAX_HEIGHT_FRACTION - MIN_HEIGHT_FRACTION) * amp;
        const dur = 600 + (i % 5) * 80;

        anim.setValue(lo + (hi - lo) * 0.5);
        Animated.loop(
          Animated.sequence([
            Animated.timing(anim, { toValue: hi, duration: dur, easing: Easing.inOut(Easing.ease), useNativeDriver: false }),
            Animated.timing(anim, { toValue: lo, duration: dur + 100, easing: Easing.inOut(Easing.ease), useNativeDriver: false }),
          ]),
        ).start();
      } else {
        const restHeight = MIN_HEIGHT_FRACTION + AMPLITUDE_ENVELOPE[i] * 0.08;
        Animated.timing(anim, { toValue: restHeight, duration: 500, easing: Easing.out(Easing.ease), useNativeDriver: false }).start();
      }
    });
  }, [isPlaying]);

  return (
    <View
      style={[styles.container, { height }]}
      onLayout={(e) => { widthRef.current = e.nativeEvent.layout.width; }}
      onStartShouldSetResponder={() => !!onSeek}
      onResponderRelease={(e) => {
        if (!onSeek || widthRef.current <= 0) return;
        const pct = Math.max(0, Math.min(1, e.nativeEvent.locationX / widthRef.current));
        onSeek(pct);
      }}
    >
      <View style={styles.barsRow}>
        {barAnims.map((anim, i) => {
          const barHeight = anim.interpolate({
            inputRange: [0, 1],
            outputRange: [0, height],
          });
          const barTop = Animated.subtract(
            height / 2,
            Animated.multiply(anim, height / 2),
          );
          return (
            <Animated.View
              key={i}
              style={[
                styles.bar,
                {
                  height: barHeight,
                  top: barTop,
                  marginRight: i < BAR_COUNT - 1 ? BAR_GAP : 0,
                  backgroundColor: i <= progressIndex ? accentColor : dimColor,
                },
              ]}
            />
          );
        })}
      </View>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    width: '100%',
    borderRadius: 8,
    overflow: 'hidden',
  },
  barsRow: {
    flex: 1,
    flexDirection: 'row',
    alignItems: 'center',
  },
  bar: {
    width: BAR_WIDTH,
    borderRadius: BAR_RADIUS,
    position: 'absolute',
  },
});
