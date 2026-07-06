import AsyncStorage from '@react-native-async-storage/async-storage';
import * as FileSystem from 'expo-file-system/legacy';
import * as Sharing from 'expo-sharing';

// ============================================
// EPUB OFFLINE CACHE (for in-app reading)
// ============================================

const EPUB_CACHE_KEY = '@marxist_library_epub_cache';

export interface CachedEpub {
  bookId: string;
  title: string;
  author?: string;
  epubFilename: string;
  localPath: string;
  cachedAt: string;
  fileSize?: number;
}

const getEpubCacheDir = () => `${FileSystem.documentDirectory}epub_cache/`;

async function ensureEpubCacheDir() {
  const dir = getEpubCacheDir();
  const info = await FileSystem.getInfoAsync(dir);
  if (!info.exists) {
    await FileSystem.makeDirectoryAsync(dir, { intermediates: true });
  }
  return dir;
}

export const epubCacheStorage = {
  async getAll(): Promise<CachedEpub[]> {
    try {
      const json = await AsyncStorage.getItem(EPUB_CACHE_KEY);
      return json ? JSON.parse(json) : [];
    } catch {
      return [];
    }
  },

  async get(bookId: string): Promise<CachedEpub | null> {
    const all = await this.getAll();
    return all.find((d) => d.bookId === bookId) ?? null;
  },

  async isCached(bookId: string): Promise<boolean> {
    const entry = await this.get(bookId);
    if (!entry) return false;
    const info = await FileSystem.getInfoAsync(entry.localPath);
    if (!info.exists) {
      await this.remove(bookId);
      return false;
    }
    return true;
  },

  async save(entry: CachedEpub): Promise<void> {
    const all = await this.getAll();
    const filtered = all.filter((d) => d.bookId !== entry.bookId);
    filtered.push(entry);
    await AsyncStorage.setItem(EPUB_CACHE_KEY, JSON.stringify(filtered));
  },

  async remove(bookId: string): Promise<void> {
    const all = await this.getAll();
    const entry = all.find((d) => d.bookId === bookId);
    if (entry) {
      try {
        await FileSystem.deleteAsync(entry.localPath, { idempotent: true });
      } catch {
        // file already gone
      }
    }
    const filtered = all.filter((d) => d.bookId !== bookId);
    await AsyncStorage.setItem(EPUB_CACHE_KEY, JSON.stringify(filtered));
  },

  async clearAll(): Promise<void> {
    const all = await this.getAll();
    for (const entry of all) {
      try {
        await FileSystem.deleteAsync(entry.localPath, { idempotent: true });
      } catch {
        // ignore
      }
    }
    await AsyncStorage.removeItem(EPUB_CACHE_KEY);
  },
};

export interface DownloadProgress {
  bookId: string;
  progress: number; // 0-100
}

/**
 * Download and cache an EPUB file for offline reading.
 */
export async function cacheBookEpub(
  bookId: string,
  title: string,
  author: string | undefined,
  epubFilename: string,
  remoteUrl: string,
  onProgress?: (progress: number) => void,
): Promise<CachedEpub> {
  const dir = await ensureEpubCacheDir();
  const localPath = `${dir}${epubFilename}`;

  // Check if already cached
  const existing = await epubCacheStorage.get(bookId);
  if (existing) {
    const info = await FileSystem.getInfoAsync(existing.localPath);
    if (info.exists) {
      return existing;
    }
  }

  const downloadResumable = FileSystem.createDownloadResumable(
    remoteUrl,
    localPath,
    {},
    (downloadProgress) => {
      if (downloadProgress.totalBytesExpectedToWrite > 0) {
        const pct = Math.round(
          (downloadProgress.totalBytesWritten / downloadProgress.totalBytesExpectedToWrite) * 100,
        );
        onProgress?.(pct);
      }
    },
  );

  const result = await downloadResumable.downloadAsync();
  if (!result?.uri) {
    throw new Error('Download failed — no file result');
  }

  const fileInfo = await FileSystem.getInfoAsync(result.uri);

  const entry: CachedEpub = {
    bookId,
    title,
    author,
    epubFilename,
    localPath: result.uri,
    cachedAt: new Date().toISOString(),
    fileSize: fileInfo.exists && !('isDirectory' in fileInfo && fileInfo.isDirectory) ? (fileInfo as any).size : undefined,
  };

  await epubCacheStorage.save(entry);
  return entry;
}

// ============================================
// PDF FILE DOWNLOAD (save to device / share)
// ============================================

const getPdfDownloadsDir = () => `${FileSystem.cacheDirectory}pdf_downloads/`;

async function ensurePdfDownloadsDir() {
  const dir = getPdfDownloadsDir();
  const info = await FileSystem.getInfoAsync(dir);
  if (!info.exists) {
    await FileSystem.makeDirectoryAsync(dir, { intermediates: true });
  }
  return dir;
}

/**
 * Download a PDF file and present the system share sheet so the user
 * can save it to Files, Google Drive, etc.
 */
export async function downloadAndSharePdf(
  pdfFilename: string,
  remoteUrl: string,
  onProgress?: (progress: number) => void,
): Promise<void> {
  const dir = await ensurePdfDownloadsDir();
  const localPath = `${dir}${pdfFilename}`;

  const downloadResumable = FileSystem.createDownloadResumable(
    remoteUrl,
    localPath,
    {},
    (downloadProgress) => {
      if (downloadProgress.totalBytesExpectedToWrite > 0) {
        const pct = Math.round(
          (downloadProgress.totalBytesWritten / downloadProgress.totalBytesExpectedToWrite) * 100,
        );
        onProgress?.(pct);
      }
    },
  );

  const result = await downloadResumable.downloadAsync();
  if (!result?.uri) {
    throw new Error('PDF download failed — no file result');
  }

  // Open the system share sheet so the user can save / send the file
  if (await Sharing.isAvailableAsync()) {
    await Sharing.shareAsync(result.uri, {
      mimeType: 'application/pdf',
      dialogTitle: pdfFilename,
    });
  }
}
