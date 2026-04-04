import AsyncStorage from '@react-native-async-storage/async-storage';
import * as FileSystem from 'expo-file-system/legacy';

const DOWNLOADS_KEY = '@marxist_library_downloads';

export interface DownloadedBook {
  bookId: string;
  title: string;
  author?: string;
  pdfFilename: string;
  localPath: string;
  downloadedAt: string;
  fileSize?: number;
}

const getDownloadsDir = () => `${FileSystem.documentDirectory}downloads/`;

async function ensureDownloadsDir() {
  const dir = getDownloadsDir();
  const info = await FileSystem.getInfoAsync(dir);
  if (!info.exists) {
    await FileSystem.makeDirectoryAsync(dir, { intermediates: true });
  }
  return dir;
}

export const downloadsStorage = {
  async getAll(): Promise<DownloadedBook[]> {
    try {
      const json = await AsyncStorage.getItem(DOWNLOADS_KEY);
      return json ? JSON.parse(json) : [];
    } catch {
      return [];
    }
  },

  async get(bookId: string): Promise<DownloadedBook | null> {
    const all = await this.getAll();
    return all.find((d) => d.bookId === bookId) ?? null;
  },

  async isDownloaded(bookId: string): Promise<boolean> {
    const entry = await this.get(bookId);
    if (!entry) return false;
    const info = await FileSystem.getInfoAsync(entry.localPath);
    if (!info.exists) {
      await this.remove(bookId);
      return false;
    }
    return true;
  },

  async save(book: DownloadedBook): Promise<void> {
    const all = await this.getAll();
    const filtered = all.filter((d) => d.bookId !== book.bookId);
    filtered.push(book);
    await AsyncStorage.setItem(DOWNLOADS_KEY, JSON.stringify(filtered));
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
    await AsyncStorage.setItem(DOWNLOADS_KEY, JSON.stringify(filtered));
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
    await AsyncStorage.removeItem(DOWNLOADS_KEY);
  },
};

export interface DownloadProgress {
  bookId: string;
  progress: number; // 0-100
}

export async function downloadBookPdf(
  bookId: string,
  title: string,
  author: string | undefined,
  pdfFilename: string,
  remoteUrl: string,
  onProgress?: (progress: number) => void,
): Promise<DownloadedBook> {
  const dir = await ensureDownloadsDir();
  const localPath = `${dir}${pdfFilename}`;

  // Check if already downloaded
  const existing = await downloadsStorage.get(bookId);
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

  const entry: DownloadedBook = {
    bookId,
    title,
    author,
    pdfFilename,
    localPath: result.uri,
    downloadedAt: new Date().toISOString(),
    fileSize: fileInfo.exists && !('isDirectory' in fileInfo && fileInfo.isDirectory) ? (fileInfo as any).size : undefined,
  };

  await downloadsStorage.save(entry);
  return entry;
}
