import { Board } from '../types';

// Theme colors - Brutalist Archival / Dialectic Library aesthetic
export const COLORS = {
  // Backgrounds
  background: '#131313',       // Main deep dark background
  backgroundSecondary: '#1c1b1b', // surfaceContainerLow
  card: '#1c1b1b',             // surfaceContainerLow
  cardHover: '#2a2a2a',        // surfaceContainerHigh

  // Brand
  primary: '#c81e1e',          // Dialectic red / primary-container
  primaryLight: '#ffb4ab',     // primary text tint
  primaryDark: '#872720',      // secondary-container

  // Text
  text: '#e5e2e1',             // on-surface
  textSecondary: '#ac8884',    // outline or muted text
  textTertiary: '#5c403c',     // outline-variant

  // Accents
  blue: '#a0caff',             // tertiary
  green: '#2d8a4e',            // Success
  orange: '#c8860a',           // Warning
  yellow: '#ffb4ab',           // Highlight

  // Interactions
  like: '#c81e1e',             // Red hearts
  repost: '#ac8884',           // Muted red/brown
  error: '#ffb4ab',            // Error red/pink

  // Borders (subtle)
  border: 'rgba(255, 255, 255, 0.05)',
  borderLight: 'rgba(255, 255, 255, 0.1)',

  // Overlays
  overlay: 'rgba(14, 14, 14, 0.8)',
};

// Spacing scale
export const SPACING = {
  xs: 4,
  sm: 8,
  md: 12,
  lg: 16,
  xl: 24,
  xxl: 32,
  xxxl: 48,
};

// Typography (Brutalist Luxury)
export const FONTS = {
  family: {
    display: 'Georgia, serif',
    body: '-apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif',
    mono: 'Courier, "Courier New", monospace',
  },
  sizes: {
    xs: 11,
    sm: 13,
    md: 15,
    lg: 18,
    xl: 24,
    xxl: 32,
    xxxl: 48,
  },
};

// Board definitions (cleaner icons)
export const BOARDS: Board[] = [
  { slug: 't', name: 'theory', fullName: 'Theory', description: 'Marxist theory and philosophy', icon: '📚' },
  { slug: 'r', name: 'reading', fullName: 'Reading', description: 'Study groups and discussions', icon: '📖' },
  { slug: 'o', name: 'organizing', fullName: 'Organizing', description: 'Praxis and action', icon: '✊' },
  { slug: 'h', name: 'history', fullName: 'History', description: 'Historical analysis', icon: '🏛' },
  { slug: 'c', name: 'current', fullName: 'Current Events', description: 'News and analysis', icon: '🌍' },
  { slug: 'm', name: 'meta', fullName: 'Meta', description: 'Site feedback', icon: '💬' },
  { slug: 'x', name: 'random', fullName: 'Random', description: 'Off-topic', icon: '🎲' },
];

// Ideology options with colors
export const IDEOLOGIES = [
  { value: 'Marxist-Leninist', label: 'Marxist-Leninist', abbrev: 'ML', color: '#D42727' },
  { value: 'Marxism-Leninism-Maoism', label: 'MLM', abbrev: 'MLM', color: '#E85D04' },
  { value: 'Left Communist', label: 'Left Communist', abbrev: 'LeftCom', color: '#FFBA08' },
  { value: 'Trotskyist', label: 'Trotskyist', abbrev: 'Trot', color: '#F48C06' },
  { value: 'Anarcho-Communist', label: 'Anarcho-Communist', abbrev: 'AnCom', color: '#9D0208' },
  { value: 'Orthodox Marxist', label: 'Orthodox Marxist', abbrev: 'Orthodox', color: '#DC2F02' },
  { value: 'Council Communist', label: 'Council Communist', abbrev: 'Council', color: '#E63946' },
  { value: 'Democratic Socialist', label: 'Democratic Socialist', abbrev: 'DemSoc', color: '#EF476F' },
  { value: 'Unaffiliated', label: 'Unaffiliated', abbrev: '', color: '#71767B' },
];

export const getIdeologyColor = (ideology: string | null): string => {
  const found = IDEOLOGIES.find(i => i.value === ideology || i.abbrev === ideology);
  return found?.color || '#71767B';
};

export const getIdeologyAbbrev = (ideology: string | null): string => {
  const found = IDEOLOGIES.find(i => i.value === ideology);
  return found?.abbrev || '';
};

// Format numbers X-style (1.2K, 3.4M)
export const formatCount = (num: number | null | undefined): string => {
  if (!num) return '0';
  if (num >= 1000000) return `${(num / 1000000).toFixed(1)}M`;
  if (num >= 1000) return `${(num / 1000).toFixed(1)}K`;
  return num.toString();
};

// Format time X-style
export const formatTimeAgo = (dateString: string): string => {
  const date = new Date(dateString);
  const now = new Date();
  const seconds = Math.floor((now.getTime() - date.getTime()) / 1000);

  if (seconds < 60) return `${seconds}s`;
  if (seconds < 3600) return `${Math.floor(seconds / 60)}m`;
  if (seconds < 86400) return `${Math.floor(seconds / 3600)}h`;
  if (seconds < 604800) return `${Math.floor(seconds / 86400)}d`;
  return date.toLocaleDateString('en-US', { month: 'short', day: 'numeric' });
};

// Content limits
export const LIMITS = {
  TITLE_MIN: 1, // Lowered for testing
  TITLE_MAX: 200,
  CONTENT_MIN: 1, // Lowered for testing
  CONTENT_MAX: 50000,
  BIO_MAX: 160,
  USERNAME_MIN: 3,
  USERNAME_MAX: 30,
  COMMENT_MIN: 1,
  COMMENT_MAX: 10000,
};
