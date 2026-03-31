import Toast, { ToastShowParams } from 'react-native-toast-message';
import { haptics } from './haptics';

type ToastType = 'success' | 'error' | 'info';

interface ShowToastOptions {
  type?: ToastType;
  text1: string;
  text2?: string;
  duration?: number;
  haptic?: boolean;
}

/**
 * Show a toast notification
 */
export const showToast = ({
  type = 'success',
  text1,
  text2,
  duration = 3000,
  haptic = true,
}: ShowToastOptions) => {
  // Trigger haptic feedback based on type
  if (haptic) {
    switch (type) {
      case 'success':
        haptics.success();
        break;
      case 'error':
        haptics.error();
        break;
      case 'info':
        haptics.light();
        break;
    }
  }

  Toast.show({
    type,
    text1,
    text2,
    visibilityTime: duration,
    position: 'top',
    topOffset: 60,
  });
};

// Convenience methods
export const toast = {
  success: (message: string, description?: string) =>
    showToast({ type: 'success', text1: message, text2: description }),

  error: (message: string, description?: string) =>
    showToast({ type: 'error', text1: message, text2: description }),

  info: (message: string, description?: string) =>
    showToast({ type: 'info', text1: message, text2: description }),

  // Specific action toasts
  posted: () => showToast({ type: 'success', text1: 'Thread posted!', text2: 'Your thread is now live.' }),

  commented: () => showToast({ type: 'success', text1: 'Comment added!' }),

  liked: () => showToast({ type: 'success', text1: 'Liked!', duration: 1500 }),

  unliked: () => showToast({ type: 'info', text1: 'Removed like', duration: 1500 }),

  bookmarked: () => showToast({ type: 'success', text1: 'Bookmarked!', text2: 'Saved to your bookmarks.' }),

  unbookmarked: () => showToast({ type: 'info', text1: 'Removed from bookmarks', duration: 1500 }),

  copied: () => showToast({ type: 'success', text1: 'Copied to clipboard!', duration: 1500 }),

  deleted: () => showToast({ type: 'success', text1: 'Deleted successfully' }),

  saved: () => showToast({ type: 'success', text1: 'Changes saved!' }),

  networkError: () => showToast({
    type: 'error',
    text1: 'Network error',
    text2: 'Please check your connection and try again.'
  }),

  genericError: () => showToast({
    type: 'error',
    text1: 'Something went wrong',
    text2: 'Please try again later.'
  }),

  followed: (username: string) => showToast({
    type: 'success',
    text1: `Following @${username}`
  }),

  unfollowed: (username: string) => showToast({
    type: 'info',
    text1: `Unfollowed @${username}`
  }),
};

export default toast;
