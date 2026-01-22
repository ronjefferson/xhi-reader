import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/book_model.dart';
import '../../core/services/epub_service.dart';

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
      final directory = await getApplicationDocumentsDirectory();
      final appDocPath = directory.path;

      await EpubService().startServer(appDocPath);

      spine = await EpubService().getSpineUrls(
        File(book.filePath),
        book.id,
        appDocPath,
      );

      // Calculate Pages AND Extract Titles
      await _calculateADEPageCounts(book.id, appDocPath);

      if (spine.isNotEmpty) {
        currentChapterIndex = 0;

        // Use helper to set initial URL with correct flags
        _updateUrl(spine[0]);

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

    // Check Boundaries
    bool isFirst = currentChapterIndex == 0;
    bool isLast = currentChapterIndex == spine.length - 1;

    String finalUrl = "$baseUrl?v=$v";
    if (posEnd) finalUrl += "&pos=end";

    // Pass flags to JS so it can block invalid swipes
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
    }
  }

  void previousChapter() {
    if (hasPrevious) {
      currentChapterIndex--;
      _updateUrl(spine[currentChapterIndex], posEnd: true);
      requestScrollToProgress = 1.0;
      notifyListeners();
    }
  }

  void jumpToChapter(int index) {
    if (index >= 0 && index < spine.length) {
      currentChapterIndex = index;
      _updateUrl(spine[index]);
      requestScrollToProgress = 0.0;
      notifyListeners();
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

        requestScrollToProgress = percent.clamp(0.0, 1.0);

        if (currentChapterIndex != i) {
          currentChapterIndex = i;
          _updateUrl(spine[i]);
        } else {
          notifyListeners(); // Just update progress if same chapter
        }
        return;
      }
    }
  }

  // ... (Standard Helpers below) ...

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

      String title = "Chapter ${index + 1}";
      File file = File(localPath);
      if (await file.exists()) {
        try {
          String content = await file.readAsString();
          RegExp h1 = RegExp(
            r'<h1[^>]*>(.*?)</h1>',
            caseSensitive: false,
            dotAll: true,
          );
          var m = h1.firstMatch(content);
          if (m != null) title = _stripHtml(m.group(1)!);
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
    int start = _cumulativePageCounts[currentChapterIndex];
    int count = _chapterPageCounts[currentChapterIndex];
    int pagesIn = (_currentChapterProgress * count).round();
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
        return {'chapterIndex': i, 'percent': percent.clamp(0.0, 1.0)};
      }
    }
    return {'chapterIndex': 0, 'percent': 0.0};
  }

  void updateScrollProgress(double progress) {
    _currentChapterProgress = progress;
    notifyListeners();
  }

  bool get hasNext => currentChapterIndex < spine.length - 1;
  bool get hasPrevious => currentChapterIndex > 0;
}
