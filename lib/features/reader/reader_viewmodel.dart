import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/book_model.dart';
import '../../core/services/epub_service.dart';
import '../../core/services/library_service.dart';
import '../../core/services/api_service.dart';
import '../../core/services/auth_service.dart';

class ReaderViewModel extends ChangeNotifier {
  final BookModel book;

  // --- State Variables (Watched by View) ---
  String? epubUrl;
  bool isReady = false;
  String? errorMessage;

  // --- Navigation Data ---
  List<String> spine = [];
  List<String> chapterTitles = [];
  int currentChapterIndex = 0;

  // --- Pagination Math ---
  List<int> _chapterPageCounts = [];
  List<int> _cumulativePageCounts = [];
  int _totalBookPages = 1;
  double _currentChapterProgress = 0.0;

  // --- Events ---
  // The View reads this, scrolls the WebView, then sets it to null
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

    // Restore Progress
    final savedData = await LibraryService().getLastProgress(book.id);
    _restoreState(savedData);
  }

  // --- MODE 2: ONLINE (New Logic) ---
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

    for (var chap in chapters) {
      String rawUrl = chap['url'];

      // FIX: Rewrite 'localhost' to '10.0.2.2' for Android Emulator
      if (Platform.isAndroid) {
        if (rawUrl.contains('127.0.0.1')) {
          rawUrl = rawUrl.replaceAll('127.0.0.1', '10.0.2.2');
        } else if (rawUrl.contains('localhost')) {
          rawUrl = rawUrl.replaceAll('localhost', '10.0.2.2');
        }
      }

      spine.add(rawUrl);
      chapterTitles.add(chap['title'] ?? "Chapter");

      // Estimate Pages (approx 2KB per page)
      int size = chap['sizeBytes'] ?? 2000;
      int pages = (size / 2000).ceil();
      if (pages < 1) pages = 1;

      _cumulativePageCounts.add(runningTotal);
      _chapterPageCounts.add(pages);
      runningTotal += pages;
    }
    _totalBookPages = runningTotal > 0 ? runningTotal : 1;

    // 2. Fetch Progress from Cloud
    final cloudData = await ApiService().getProgress(book.id);

    // Map cloud data to our internal format
    Map<String, dynamic>? progressData;
    if (cloudData != null) {
      progressData = {
        'chapterIndex': cloudData['chapter_index'],
        'progress': cloudData['progress_percent'],
      };
    }
    _restoreState(progressData);
  }

  // --- URL BUILDER (Critical for Online Images) ---
  void _updateUrl(String baseUrl, {bool posEnd = false}) {
    final String v = DateTime.now().millisecondsSinceEpoch.toString();
    String separator = baseUrl.contains('?') ? '&' : '?';
    String finalUrl = "$baseUrl${separator}v=$v";

    // FIX: Inject Token so images inside the chapter load without 401
    if (!book.isLocal) {
      final token = AuthService().token;
      if (token != null) finalUrl += "&token=$token";
    }

    if (posEnd) finalUrl += "&pos=end";
    if (currentChapterIndex == 0) finalUrl += "&isFirst=true";
    if (currentChapterIndex == spine.length - 1) finalUrl += "&isLast=true";

    epubUrl = finalUrl;
    // View detects this change and reloads the WebView
  }

  // --- STATE RESTORATION ---
  void _restoreState(Map<String, dynamic>? data) {
    if (data != null) {
      currentChapterIndex = data['chapterIndex'] ?? 0;
      double pct = (data['progress'] is int)
          ? (data['progress'] as int).toDouble()
          : (data['progress'] as double? ?? 0.0);

      // Validate index
      if (currentChapterIndex >= spine.length) currentChapterIndex = 0;

      // Store the scroll request so the View executes it after loading
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

  // --- NAVIGATION METHODS (Called by View) ---

  void nextChapter() {
    if (hasNext) {
      currentChapterIndex++;
      _updateUrl(spine[currentChapterIndex]);
      requestScrollToProgress = 0.0; // Start at top
      _currentChapterProgress = 0.0;
      notifyListeners();
      _saveCurrentProgress();
    }
  }

  void previousChapter() {
    if (hasPrevious) {
      currentChapterIndex--;
      _updateUrl(spine[currentChapterIndex], posEnd: true);
      requestScrollToProgress = 1.0; // Start at bottom
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

  // Called when user releases the slider
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
          _updateUrl(spine[i]); // Change Chapter
        }

        requestScrollToProgress = percent; // Scroll to position
        notifyListeners();
        _saveCurrentProgress();
        return;
      }
    }
  }

  void updateScrollProgress(double progress) {
    _currentChapterProgress = progress;
    // We don't notifyListeners here to avoid rebuilding the whole UI on every pixel scroll
    _saveCurrentProgress();
  }

  // Helper for the slider label
  int getCurrentGlobalPage() {
    if (_chapterPageCounts.isEmpty) return 1;
    if (currentChapterIndex >= _cumulativePageCounts.length) return 1;

    int start = _cumulativePageCounts[currentChapterIndex];
    int count = _chapterPageCounts[currentChapterIndex];

    int pagesIn = (_currentChapterProgress * count).round();
    return start + pagesIn + 1;
  }

  // Helper for live preview while dragging slider
  Map<String, int> getPreviewLocation(int globalPage) {
    for (int i = 0; i < _cumulativePageCounts.length; i++) {
      int start = _cumulativePageCounts[i];
      int count = _chapterPageCounts[i];
      if (globalPage <= start + count) {
        return {'chapterIndex': i};
      }
    }
    return {'chapterIndex': 0};
  }

  // --- LOCAL CALCULATION HELPERS ---
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

      // Simple title extraction
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
