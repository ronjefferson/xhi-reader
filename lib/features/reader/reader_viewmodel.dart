import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/book_model.dart';
import '../../core/services/epub_service.dart';
import '../../core/services/library_service.dart';
import '../../core/services/api_service.dart'; // REQUIRED for BaseUrl
import '../../core/services/auth_service.dart';

class ReaderViewModel extends ChangeNotifier {
  final BookModel book;

  // --- State ---
  String? epubUrl;
  bool isReady = false;
  String? errorMessage;

  // --- Navigation ---
  List<String> spine = [];
  List<String> chapterTitles = [];
  int currentChapterIndex = 0;

  // --- Pagination ---
  List<int> _chapterPageCounts = [];
  List<int> _cumulativePageCounts = [];
  int _totalBookPages = 1;
  double _currentChapterProgress = 0.0;

  // --- Events ---
  double? requestScrollToProgress;

  ReaderViewModel({required this.book});

  int get totalBookPages => _totalBookPages;

  // --- INITIALIZATION ---
  Future<void> initializeReader() async {
    try {
      if (book.isLocal) {
        await _initLocalMode();
      } else {
        await _initOnlineMode();
      }
    } catch (e) {
      errorMessage = "Error loading book: $e";
      isReady = true;
      notifyListeners();
    }
  }

  // --- MODE 1: LOCAL ---
  Future<void> _initLocalMode() async {
    if (book.filePath == null) throw "Local file path missing.";
    final appDocPath = (await getApplicationDocumentsDirectory()).path;
    await EpubService().startServer(appDocPath);

    spine = await EpubService().getSpineUrls(
      File(book.filePath!),
      book.id,
      appDocPath,
    );
    await _calculateLocalPageCounts(book.id, appDocPath);

    final savedData = await LibraryService().getLastProgress(book.id);
    _restoreState(savedData);
  }

  // --- MODE 2: ONLINE ---
  Future<void> _initOnlineMode() async {
    // 1. Fetch Manifest
    final manifest = await ApiService().fetchManifest(book.id);
    if (manifest == null) throw "Could not fetch book manifest.";

    spine = [];
    chapterTitles = [];
    _chapterPageCounts = [];
    _cumulativePageCounts = [];
    int runningTotal = 0;

    final List<dynamic> chapters = manifest['chapters'];

    // 🟢 SINGLE SOURCE OF TRUTH: Get the current active Base URL
    final String currentBaseUrl = ApiService.baseUrl;

    for (var chap in chapters) {
      String rawUrl = chap['url'];

      // 🟢 DYNAMIC SWAP:
      // If the URL from DB is localhost/127.0.0.1, replace it with currentBaseUrl
      // (This handles switching between Emulator Loopback and Ngrok automatically)
      if (rawUrl.contains('localhost') || rawUrl.contains('127.0.0.1')) {
        rawUrl = rawUrl.replaceFirst(
          RegExp(r'http://(localhost|127\.0\.0\.1)(:\d+)?'),
          currentBaseUrl,
        );
      }

      spine.add(rawUrl);

      // 🟢 TITLE LOGIC: Rename "Chapter X" to "Illustration" if needed
      String t = chap['title'] ?? "";
      final genericNameRegex = RegExp(r'^Chapter\s*\d*$', caseSensitive: false);
      if (t.trim().isEmpty || genericNameRegex.hasMatch(t.trim())) {
        t = "Illustration";
      }
      chapterTitles.add(t);

      // Estimate Pages
      int size = chap['sizeBytes'] ?? 2000;
      int pages = (size / 2000).ceil();
      if (pages < 1) pages = 1;

      _cumulativePageCounts.add(runningTotal);
      _chapterPageCounts.add(pages);
      runningTotal += pages;
    }
    _totalBookPages = runningTotal > 0 ? runningTotal : 1;

    // 2. Fetch Progress
    final cloudData = await ApiService().getProgress(book.id);
    Map<String, dynamic>? progressData;
    if (cloudData != null) {
      progressData = {
        'chapterIndex': cloudData['chapter_index'],
        'progress': cloudData['progress_percent'],
      };
    }
    _restoreState(progressData);
  }

  // --- URL BUILDER ---
  void _updateUrl(String baseUrl, {bool posEnd = false}) {
    final String v = DateTime.now().millisecondsSinceEpoch.toString();
    String separator = baseUrl.contains('?') ? '&' : '?';
    String finalUrl = "$baseUrl${separator}v=$v";

    if (!book.isLocal) {
      final token = AuthService().token;
      if (token != null) finalUrl += "&token=$token";
    }

    if (posEnd) finalUrl += "&pos=end";
    if (currentChapterIndex == 0) finalUrl += "&isFirst=true";
    if (currentChapterIndex == spine.length - 1) finalUrl += "&isLast=true";

    epubUrl = finalUrl;
  }

  // --- STATE RESTORATION ---
  void _restoreState(Map<String, dynamic>? data) {
    if (data != null) {
      currentChapterIndex = data['chapterIndex'] ?? 0;
      double pct = (data['progress'] is int)
          ? (data['progress'] as int).toDouble()
          : (data['progress'] as double? ?? 0.0);

      if (currentChapterIndex >= spine.length) currentChapterIndex = 0;
      requestScrollToProgress = pct.clamp(0.0, 1.0);
    }
    if (spine.isNotEmpty) {
      _updateUrl(spine[currentChapterIndex]);
      isReady = true;
      notifyListeners();
    }
  }

  void _saveCurrentProgress() {
    if (book.isLocal) {
      LibraryService().saveProgress(
        book.id,
        currentChapterIndex,
        _currentChapterProgress,
      );
    } else {
      ApiService().saveProgress(
        book.id,
        currentChapterIndex,
        _currentChapterProgress,
      );
    }
  }

  // --- NAVIGATION ---
  void nextChapter() {
    if (hasNext) {
      currentChapterIndex++;
      _updateUrl(spine[currentChapterIndex]);
      requestScrollToProgress = 0.0;
      _currentChapterProgress = 0.0;
      notifyListeners();
      _saveCurrentProgress();
    }
  }

  void previousChapter() {
    if (hasPrevious) {
      currentChapterIndex--;
      _updateUrl(spine[currentChapterIndex], posEnd: true);
      requestScrollToProgress = 1.0;
      _currentChapterProgress = 1.0;
      notifyListeners();
      _saveCurrentProgress();
    }
  }

  void jumpToChapter(int index) {
    if (index >= 0 && index < spine.length) {
      currentChapterIndex = index;
      _updateUrl(spine[index]);
      requestScrollToProgress = 0.0;
      notifyListeners();
      _saveCurrentProgress();
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

        if (currentChapterIndex != i) {
          currentChapterIndex = i;
          _updateUrl(spine[i]);
        }
        requestScrollToProgress = percent;
        notifyListeners();
        _saveCurrentProgress();
        return;
      }
    }
  }

  void updateScrollProgress(double progress) {
    _currentChapterProgress = progress;
    _saveCurrentProgress();
  }

  int getCurrentGlobalPage() {
    if (_chapterPageCounts.isEmpty) return 1;
    if (currentChapterIndex >= _cumulativePageCounts.length) return 1;
    int start = _cumulativePageCounts[currentChapterIndex];
    int count = _chapterPageCounts[currentChapterIndex];
    int pagesIn = (_currentChapterProgress * count).round();
    return start + pagesIn + 1;
  }

  // --- LOCAL CALCULATION ---
  Future<void> _calculateLocalPageCounts(
    String bookId,
    String appDocPath,
  ) async {
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

      String title = "Chapter ${index + 1}";
      try {
        String content = await File(localPath).readAsString();
        var match = RegExp(
          r'<h[1-2][^>]*>(.*?)</h[1-2]>',
          caseSensitive: false,
          dotAll: true,
        ).firstMatch(content);
        if (match != null) {
          String clean = match
              .group(1)!
              .replaceAll(RegExp(r'<[^>]*>'), '')
              .trim();
          if (clean.length < 50) title = clean;
        } else {
          if (content.contains('<img') ||
              content.contains('<image') ||
              content.contains('<svg')) {
            title = "Illustration";
          }
        }
      } catch (_) {}

      chapterTitles.add(title);
      _chapterPageCounts.add(pages);
      runningTotal += pages;
      index++;
    }
    _totalBookPages = runningTotal > 0 ? runningTotal : 1;
    notifyListeners();
  }

  bool get hasNext => currentChapterIndex < spine.length - 1;
  bool get hasPrevious => currentChapterIndex > 0;
}
