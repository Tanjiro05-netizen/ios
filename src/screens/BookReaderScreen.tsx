import React, { useState, useEffect } from 'react';
import {
    View,
    Text,
    StyleSheet,
    TouchableOpacity,
    ActivityIndicator,
    Dimensions,
} from 'react-native';
import { SafeAreaView } from 'react-native-safe-area-context';
import { Ionicons } from '@expo/vector-icons';
import { useNavigation, useRoute, RouteProp } from '@react-navigation/native';
import Pdf from 'react-native-pdf';
import * as FileSystem from 'expo-file-system/legacy';
import { COLORS } from '../constants';
import { api } from '../lib/api';
import { Book, RootStackParamList } from '../types';
import { downloadsStorage, downloadBookPdf } from '../lib/downloads';
import toast from '../lib/toast';

type BookReaderRouteProp = RouteProp<RootStackParamList, 'BookReader'>;

const { width, height } = Dimensions.get('window');

export default function BookReaderScreen() {
    const navigation = useNavigation();
    const route = useRoute<BookReaderRouteProp>();
    const { bookId } = route.params;

    const [book, setBook] = useState<Book | null>(null);
    const [loading, setLoading] = useState(true);
    const [downloadProgress, setDownloadProgress] = useState(0);
    const [localPdfPath, setLocalPdfPath] = useState<string | null>(null);
    const [error, setError] = useState<string | null>(null);
    const [currentPage, setCurrentPage] = useState(1);
    const [totalPages, setTotalPages] = useState(0);
    const [showHeader, setShowHeader] = useState(true);
    const [isOfflineSaved, setIsOfflineSaved] = useState(false);
    const [savingOffline, setSavingOffline] = useState(false);

    useEffect(() => {
        loadBook();
    }, [bookId]);

    const loadBook = async () => {
        try {
            setLoading(true);
            setError(null);
            setDownloadProgress(0);

            // Check persistent offline download FIRST (works without network)
            const offlineEntry = await downloadsStorage.get(bookId);
            if (offlineEntry) {
                const offlineInfo = await FileSystem.getInfoAsync(offlineEntry.localPath);
                if (offlineInfo.exists) {
                    // Use offline metadata so the reader works without network
                    setBook({
                        id: offlineEntry.bookId,
                        title: offlineEntry.title,
                        author: offlineEntry.author ?? null,
                        pdf_filename: offlineEntry.pdfFilename,
                    } as Book);
                    setLocalPdfPath(offlineEntry.localPath);
                    setIsOfflineSaved(true);
                    setLoading(false);
                    // Try to increment count but don't block on it
                    api.incrementDownloadCount(bookId).catch(() => {});
                    return;
                }
            }

            // No local download — fetch book data from network
            const bookData = await api.getBook(bookId);
            if (!bookData) {
                setError('Book not found');
                setLoading(false);
                return;
            }

            setBook(bookData);

            // Check if already in cache
            const localPath = `${FileSystem.cacheDirectory}${bookData.pdf_filename}`;
            const fileInfo = await FileSystem.getInfoAsync(localPath);
            if (fileInfo.exists) {
                setLocalPdfPath(localPath);
                setLoading(false);
                api.incrementDownloadCount(bookId);
                return;
            }

            // Download PDF to local cache
            const remoteUrl = api.getBookPdfUrl(bookData.pdf_filename);
            const downloadResumable = FileSystem.createDownloadResumable(
                remoteUrl,
                localPath,
                {},
                (downloadProgress) => {
                    const progress = downloadProgress.totalBytesWritten / downloadProgress.totalBytesExpectedToWrite;
                    setDownloadProgress(Math.round(progress * 100));
                }
            );

            const result = await downloadResumable.downloadAsync();

            if (result && result.uri) {
                setLocalPdfPath(result.uri);
                api.incrementDownloadCount(bookId);
            } else {
                throw new Error('Download failed - no file result');
            }
        } catch (err: any) {
            console.error('Error loading book:', err);
            setError(err?.message || 'Failed to load book');
        } finally {
            setLoading(false);
        }
    };

    const handleSaveOffline = async () => {
        if (!book || !book.pdf_filename || isOfflineSaved) return;
        try {
            setSavingOffline(true);
            const remoteUrl = api.getBookPdfUrl(book.pdf_filename);
            await downloadBookPdf(
                book.id,
                book.title,
                book.author ?? undefined,
                book.pdf_filename,
                remoteUrl,
            );
            setIsOfflineSaved(true);
            toast.success('Saved offline!', `"${book.title}" is now available without internet.`);
        } catch (err) {
            console.error('Error saving offline:', err);
            toast.error('Save failed', 'Could not save for offline reading.');
        } finally {
            setSavingOffline(false);
        }
    };

    const toggleHeader = () => {
        setShowHeader(!showHeader);
    };

    if (loading) {
        return (
            <SafeAreaView style={styles.container}>
                <View style={styles.loadingContainer}>
                    <ActivityIndicator size="large" color={COLORS.primary} />
                    <Text style={styles.loadingText}>
                        {downloadProgress > 0
                            ? `Downloading... ${downloadProgress}%`
                            : 'Loading book...'}
                    </Text>
                    {downloadProgress > 0 && (
                        <View style={styles.progressBarContainer}>
                            <View style={[styles.progressBar, { width: `${downloadProgress}%` }]} />
                        </View>
                    )}
                </View>
            </SafeAreaView>
        );
    }

    if (error || !book) {
        return (
            <SafeAreaView style={styles.container}>
                <View style={styles.header}>
                    <TouchableOpacity
                        style={styles.backButton}
                        onPress={() => navigation.goBack()}
                    >
                        <Ionicons name="arrow-back" size={24} color={COLORS.text} />
                    </TouchableOpacity>
                </View>
                <View style={styles.errorContainer}>
                    <Ionicons name="alert-circle" size={64} color={COLORS.textSecondary} />
                    <Text style={styles.errorTitle}>{error || 'Book not found'}</Text>
                    <TouchableOpacity style={styles.retryButton} onPress={loadBook}>
                        <Text style={styles.retryText}>Try Again</Text>
                    </TouchableOpacity>
                </View>
            </SafeAreaView>
        );
    }

    return (
        <View style={styles.container}>
            {/* Header (toggleable) */}
            {showHeader && (
                <SafeAreaView edges={['top']} style={styles.headerSafeArea}>
                    <View style={styles.header}>
                        <TouchableOpacity
                            style={styles.backButton}
                            onPress={() => navigation.goBack()}
                        >
                            <Ionicons name="arrow-back" size={24} color={COLORS.text} />
                        </TouchableOpacity>
                        <View style={styles.titleContainer}>
                            <Text style={styles.title} numberOfLines={1}>
                                {book.title}
                            </Text>
                            {book.author && (
                                <Text style={styles.author} numberOfLines={1}>
                                    {book.author}
                                </Text>
                            )}
                        </View>
                        <TouchableOpacity
                            style={styles.offlineBtn}
                            onPress={handleSaveOffline}
                            disabled={isOfflineSaved || savingOffline}
                        >
                            {savingOffline ? (
                                <ActivityIndicator size="small" color={COLORS.primary} />
                            ) : (
                                <Ionicons
                                    name={isOfflineSaved ? 'cloud-done' : 'cloud-download-outline'}
                                    size={20}
                                    color={isOfflineSaved ? '#00BA7C' : COLORS.text}
                                />
                            )}
                        </TouchableOpacity>
                        <View style={styles.pageIndicator}>
                            <Text style={styles.pageText}>
                                {currentPage}/{totalPages || '?'}
                            </Text>
                        </View>
                    </View>
                </SafeAreaView>
            )}

            {/* PDF Viewer */}
            {localPdfPath ? (
                <View style={styles.pdfContainer}>
                    <Pdf
                        source={{ uri: localPdfPath }}
                        style={styles.pdf}
                        onLoadComplete={(numberOfPages) => {
                            console.log('📚 PDF loaded successfully:', numberOfPages, 'pages');
                            setTotalPages(numberOfPages);
                        }}
                        onPageChanged={(page) => {
                            setCurrentPage(page);
                        }}
                        onError={(error: any) => {
                            console.error('PDF Render Error:', error);
                            setError(`Failed to render PDF: ${error?.message || 'Unknown error'}`);
                        }}
                        onPageSingleTap={() => {
                            toggleHeader();
                        }}
                        enablePaging={true}
                        horizontal={false}
                        fitPolicy={0}
                        spacing={0}
                    />
                </View>
            ) : (
                <View style={styles.errorContainer}>
                    <Ionicons name="document-text" size={64} color={COLORS.textSecondary} />
                    <Text style={styles.errorTitle}>PDF not available</Text>
                </View>
            )}

            {/* Floating Back Button (when header hidden) */}
            {!showHeader && (
                <SafeAreaView style={styles.floatingBackButtonSafeArea} pointerEvents="box-none">
                    <TouchableOpacity
                        style={styles.floatingBackButton}
                        onPress={() => navigation.goBack()}
                    >
                        <Ionicons name="arrow-back" size={24} color="#fff" />
                    </TouchableOpacity>
                </SafeAreaView>
            )}

            {/* Bottom Page Indicator (when header hidden) */}
            {!showHeader && (
                <SafeAreaView edges={['bottom']} style={styles.bottomIndicator} pointerEvents="box-none">
                    <View style={styles.bottomIndicatorContent}>
                        <Text style={styles.bottomPageText}>
                            Page {currentPage} of {totalPages}
                        </Text>
                    </View>
                </SafeAreaView>
            )}
        </View>
    );
}

const styles = StyleSheet.create({
    container: {
        flex: 1,
        backgroundColor: '#000',
    },
    headerSafeArea: {
        backgroundColor: COLORS.background,
    },
    header: {
        flexDirection: 'row',
        alignItems: 'center',
        paddingHorizontal: 16,
        paddingVertical: 12,
        backgroundColor: COLORS.background,
        borderBottomWidth: 1,
        borderBottomColor: COLORS.border,
    },
    backButton: {
        padding: 4,
        marginRight: 12,
    },
    titleContainer: {
        flex: 1,
    },
    title: {
        fontSize: 16,
        fontWeight: '600',
        color: COLORS.text,
    },
    author: {
        fontSize: 13,
        color: COLORS.textSecondary,
        marginTop: 2,
    },
    offlineBtn: {
        padding: 8,
        marginRight: 8,
    },
    pageIndicator: {
        backgroundColor: COLORS.backgroundSecondary,
        paddingHorizontal: 10,
        paddingVertical: 6,
        borderRadius: 12,
    },
    pageText: {
        fontSize: 13,
        fontWeight: '600',
        color: COLORS.text,
    },
    pdfContainer: {
        flex: 1,
    },
    pdf: {
        flex: 1,
        width,
        height,
        backgroundColor: '#fff',
    },
    loadingContainer: {
        flex: 1,
        alignItems: 'center',
        justifyContent: 'center',
        backgroundColor: COLORS.background,
    },
    loadingText: {
        marginTop: 12,
        fontSize: 16,
        color: COLORS.textSecondary,
    },
    progressBarContainer: {
        width: 200,
        height: 6,
        backgroundColor: COLORS.border,
        borderRadius: 3,
        marginTop: 16,
        overflow: 'hidden',
    },
    progressBar: {
        height: '100%',
        backgroundColor: COLORS.primary,
        borderRadius: 3,
    },
    errorContainer: {
        flex: 1,
        alignItems: 'center',
        justifyContent: 'center',
        backgroundColor: COLORS.background,
        paddingHorizontal: 32,
    },
    errorTitle: {
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
        backgroundColor: COLORS.primary,
        borderRadius: 8,
    },
    retryText: {
        fontSize: 16,
        fontWeight: '600',
        color: '#fff',
    },
    bottomIndicator: {
        position: 'absolute',
        bottom: 0,
        left: 0,
        right: 0,
        backgroundColor: 'rgba(0, 0, 0, 0.7)',
    },
    bottomIndicatorContent: {
        paddingVertical: 8,
        alignItems: 'center',
    },
    bottomPageText: {
        fontSize: 14,
        color: '#fff',
    },
    floatingBackButtonSafeArea: {
        position: 'absolute',
        top: 0,
        left: 0,
        right: 0,
    },
    floatingBackButton: {
        width: 40,
        height: 40,
        borderRadius: 20,
        backgroundColor: 'rgba(0, 0, 0, 0.5)',
        alignItems: 'center',
        justifyContent: 'center',
        marginLeft: 16,
        marginTop: 10,
    },
});
