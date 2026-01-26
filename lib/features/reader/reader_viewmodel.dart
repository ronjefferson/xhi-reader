import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/book_model.dart';
import '../../core/services/epub_service.dart';
import '../../core/services/library_service.dart';

class ReaderViewModel extends ChangeNotifier {
  final BookModel book;

  // Connection & State
  String? epubUrl;
  bool isReady = false;
  String? errorMessage;

  // Navigation
  List<String> spine = [];
  List<String> chapterTitles = [];
  int currentChapterIndex = 0;

  // Pagination Logic
  List<int> _chapterPageCounts = [];
  List<int> _cumulativePageCounts = [];
  int _totalBookPages = 1;
  double _currentChapterProgress = 0.0;

  // Slider Jump Request
  double? requestScrollToProgress;

  ReaderViewModel({required this.book});

  int get totalBookPages => _totalBookPages;

  Future<void> initializeReader() async {
    try {
      // 1. SAFETY CHECK: Ensure we can read this book
      if (book.isLocal && book.filePath == null) {
        errorMessage = "Error: Local book path is missing.";
        isReady = true;
        notifyListeners();
        return;
      }

      if (!book.isLocal) {
        // Placeholder for Online Reader
        errorMessage = "Online Reader not implemented yet.";
        isReady = true;
        notifyListeners();
        return;
      }

      // --- LOCAL FILE LOGIC ---
      final directory = await getApplicationDocumentsDirectory();
      final appDocPath = directory.path;

      await EpubService().startServer(appDocPath);

      spine = await EpubService().getSpineUrls(
        File(book.filePath!), // Safe because we checked isLocal
        book.id,
        appDocPath,
      );

      await _calculateADEPageCounts(book.id, appDocPath);

      if (spine.isNotEmpty) {
        // --- RESTORE SAVED PROGRESS ---
        final savedData = await LibraryService().getLastProgress(book.id);

        if (savedData != null) {
          int savedIndex = savedData['chapterIndex'];
          if (savedIndex >= 0 && savedIndex < spine.length) {
            currentChapterIndex = savedIndex;
            double savedPercent = (savedData['progress'] as double).clamp(
              0.0,
              1.0,
            );
            if (savedPercent > 0) {
              requestScrollToProgress = savedPercent;
            }
          } else {
            currentChapterIndex = 0;
          }
        } else {
          currentChapterIndex = 0;
        }

        _updateUrl(spine[currentChapterIndex]);
        isReady = true;
        notifyListeners();
      } else {
        errorMessage = "Error: Book has no chapters.";
        isReady = true;
        notifyListeners();
      }
    } catch (e) {
      errorMessage = "Failed to load book: $e";
      isReady = true;
      notifyListeners();
    }
  }

  // --- HELPER: Update URL with Boundary Flags ---
  void _updateUrl(String baseUrl, {bool posEnd = false}) {
    final String v = DateTime.now().millisecondsSinceEpoch.toString();

    bool isFirst = currentChapterIndex == 0;
    bool isLast = currentChapterIndex == spine.length - 1;

    String finalUrl = "$baseUrl?v=$v";
    if (posEnd) finalUrl += "&pos=end";

    if (isFirst) finalUrl += "&isFirst=true";
    if (isLast) finalUrl += "&isLast=true";

    epubUrl = finalUrl;
  }

  // --- NAVIGATION LOGIC ---

  void nextChapter() {
    if (hasNext) {
      currentChapterIndex++;
      _updateUrl(spine[currentChapterIndex]);
      requestScrollToProgress = 0.0;
      notifyListeners();
      LibraryService().saveProgress(book.id, currentChapterIndex, 0.0);
    }
  }

  void previousChapter() {
    if (hasPrevious) {
      currentChapterIndex--;
      _updateUrl(spine[currentChapterIndex], posEnd: true);
      requestScrollToProgress = 1.0;
      notifyListeners();
      LibraryService().saveProgress(book.id, currentChapterIndex, 1.0);
    }
  }

  void jumpToChapter(int index) {
    if (index >= 0 && index < spine.length) {
      currentChapterIndex = index;
      _updateUrl(spine[index]);
      requestScrollToProgress = 0.0;
      notifyListeners();
      LibraryService().saveProgress(book.id, currentChapterIndex, 0.0);
    }
  }

  void jumpToGlobalPage(int globalPage) {
    globalPage = globalPage.clamp(1, _totalBookPages);
    for (int i = 0; i < _cumulativePageCounts.length; i++) {
      int start = _cumulativePageCounts[i];
      int count = _chapterPageCounts[i];

      if (globalPage <= start + count) {
        int localPage = globalPage - start;
        double percent = (localPage - 1) / (count > 1 ? count - 1 : 1);

        percent = percent.clamp(0.0, 1.0);
        if (percent.isNaN || percent.isInfinite) percent = 0.0;

        if (currentChapterIndex == i) {
          requestScrollToProgress = percent;
          notifyListeners();
          LibraryService().saveProgress(book.id, currentChapterIndex, percent);
        } else {
          currentChapterIndex = i;
          _updateUrl(spine[i]);
          requestScrollToProgress = percent;
          notifyListeners();
          LibraryService().saveProgress(book.id, currentChapterIndex, percent);
        }
        return;
      }
    }
  }

  // --- PAGINATION & TITLES ---

  Future<void> _calculateADEPageCounts(String bookId, String appDocPath) async {
    _chapterPageCounts.clear();
    _cumulativePageCounts.clear();
    chapterTitles.clear();
    int runningTotal = 0;
    int index = 0;

    for (String url in spine) {
      _cumulativePageCounts.add(runningTotal);
      Uri uri = Uri.parse(url);
      String localPath = "$appDocPath${uri.path}";
      int pages = await EpubService().countPagesForChapter(localPath);

      String title = "Section ${index + 1}";
      File file = File(localPath);
      if (await file.exists()) {
        try {
          String content = await file.readAsString();
          var h1 = RegExp(
            r'<h1[^>]*>(.*?)</h1>',
            caseSensitive: false,
            dotAll: true,
          ).firstMatch(content);
          if (h1 != null) {
            String clean = _stripHtml(h1.group(1)!);
            if (clean.trim().isNotEmpty && clean.length < 100) title = clean;
          } else {
            var h2 = RegExp(
              r'<h2[^>]*>(.*?)</h2>',
              caseSensitive: false,
              dotAll: true,
            ).firstMatch(content);
            if (h2 != null) {
              String clean = _stripHtml(h2.group(1)!);
              if (clean.trim().isNotEmpty && clean.length < 100) title = clean;
            }
          }

          if (title.startsWith("Section")) {
            bool hasImage =
                content.contains('<img') ||
                content.contains('<svg') ||
                content.contains('<image');
            if (content.length < 1500 && hasImage) title = "Illustration";
          }
        } catch (e) {}
      }

      chapterTitles.add(title);
      _chapterPageCounts.add(pages);
      runningTotal += pages;
      index++;
    }
    _totalBookPages = runningTotal > 0 ? runningTotal : 1;
    notifyListeners();
  }

  String _stripHtml(String html) => html
      .replaceAll(RegExp(r'<[^>]*>'), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ');

  int getCurrentGlobalPage() {
    if (_chapterPageCounts.isEmpty) return 1;
    if (currentChapterIndex < 0 ||
        currentChapterIndex >= _cumulativePageCounts.length)
      return 1;

    int start = _cumulativePageCounts[currentChapterIndex];
    int count = _chapterPageCounts[currentChapterIndex];

    double safeProgress = _currentChapterProgress;
    if (safeProgress.isNaN || safeProgress.isInfinite) safeProgress = 0.0;

    int pagesIn = (safeProgress * count).round();
    if (pagesIn >= count) pagesIn = count - 1;

    return start + pagesIn + 1;
  }

  Map<String, dynamic> getPreviewLocation(int globalPage) {
    globalPage = globalPage.clamp(1, _totalBookPages);
    for (int i = 0; i < _cumulativePageCounts.length; i++) {
      int start = _cumulativePageCounts[i];
      int count = _chapterPageCounts[i];
      if (globalPage <= start + count) {
        int localPage = globalPage - start;
        double percent = (localPage - 1) / (count > 1 ? count - 1 : 1);
        percent = percent.clamp(0.0, 1.0);
        if (percent.isNaN || percent.isInfinite) percent = 0.0;
        return {'chapterIndex': i, 'percent': percent};
      }
    }
    return {'chapterIndex': 0, 'percent': 0.0};
  }

  void updateScrollProgress(double progress) {
    if (progress.isNaN || progress.isInfinite) progress = 0.0;
    _currentChapterProgress = progress;
    notifyListeners();

    // SAVE PROGRESS
    LibraryService().saveProgress(book.id, currentChapterIndex, progress);
  }

  bool get hasNext => currentChapterIndex < spine.length - 1;
  bool get hasPrevious => currentChapterIndex > 0;
}
