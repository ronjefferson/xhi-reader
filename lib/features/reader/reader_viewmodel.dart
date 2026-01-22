import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/book_model.dart';
import '../../core/services/epub_service.dart';

class ReaderViewModel extends ChangeNotifier {
  final BookModel book;

  String? epubUrl;
  bool isReady = false;
  String? errorMessage;

  List<String> spine = [];
  List<String> chapterTitles = [];
  int currentChapterIndex = 0;

  List<int> _chapterPageCounts = [];
  List<int> _cumulativePageCounts = [];
  int _totalBookPages = 1;
  double _currentChapterProgress = 0.0;

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

      await _calculateADEPageCounts(book.id, appDocPath);

      if (spine.isNotEmpty) {
        // Add cache busting here
        final String v = DateTime.now().millisecondsSinceEpoch.toString();
        spine = spine.map((url) => "$url?v=$v").toList();

        epubUrl = spine[0];
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

  // --- NAVIGATION FIXES ---

  void nextChapter() {
    if (hasNext) {
      currentChapterIndex++;
      epubUrl = spine[currentChapterIndex]; // Normal load (starts at top)
      requestScrollToProgress = 0.0;
      notifyListeners();
    }
  }

  void previousChapter() {
    if (hasPrevious) {
      currentChapterIndex--;
      String baseUrl = spine[currentChapterIndex];
      // FIX: Correctly append &pos=end (spine urls already have ?v=...)
      epubUrl = "$baseUrl&pos=end";
      requestScrollToProgress = 1.0;
      notifyListeners();
    }
  }

  // ... (Keep existing _calculateADEPageCounts, getCurrentGlobalPage, etc.) ...
  // Copy-paste the exact same methods from the previous working step for:
  // _calculateADEPageCounts, _stripHtml, getCurrentGlobalPage, jumpToGlobalPage, getPreviewLocation

  // Re-pasting them here for completeness:
  Future<void> _calculateADEPageCounts(String bookId, String appDocPath) async {
    _chapterPageCounts.clear();
    _cumulativePageCounts.clear();
    chapterTitles.clear();
    int runningTotal = 0;
    int index = 0;
    for (String url in spine) {
      _cumulativePageCounts.add(runningTotal);
      // Remove query params for file lookup
      Uri uri = Uri.parse(url);
      String localPath = "$appDocPath${uri.path}";
      int pages = await EpubService().countPagesForChapter(localPath);

      // Title Extraction
      String title = "Chapter ${index + 1}";
      File file = File(localPath);
      if (await file.exists()) {
        try {
          String c = await file.readAsString();
          RegExp h1 = RegExp(
            r'<h1[^>]*>(.*?)</h1>',
            caseSensitive: false,
            dotAll: true,
          );
          var m = h1.firstMatch(c);
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

  void jumpToGlobalPage(int globalPage) {
    globalPage = globalPage.clamp(1, _totalBookPages);
    for (int i = 0; i < _cumulativePageCounts.length; i++) {
      if (globalPage <= _cumulativePageCounts[i] + _chapterPageCounts[i]) {
        int local = globalPage - _cumulativePageCounts[i];
        double p =
            (local - 1) /
            (_chapterPageCounts[i] > 1 ? _chapterPageCounts[i] - 1 : 1);
        requestScrollToProgress = p.clamp(0.0, 1.0);
        if (currentChapterIndex != i) {
          currentChapterIndex = i;
          epubUrl = spine[i];
        }
        notifyListeners();
        return;
      }
    }
  }

  Map<String, dynamic> getPreviewLocation(int globalPage) {
    globalPage = globalPage.clamp(1, _totalBookPages);
    for (int i = 0; i < _cumulativePageCounts.length; i++) {
      if (globalPage <= _cumulativePageCounts[i] + _chapterPageCounts[i]) {
        int local = globalPage - _cumulativePageCounts[i];
        double p =
            (local - 1) /
            (_chapterPageCounts[i] > 1 ? _chapterPageCounts[i] - 1 : 1);
        return {'chapterIndex': i, 'percent': p.clamp(0.0, 1.0)};
      }
    }
    return {'chapterIndex': 0, 'percent': 0.0};
  }

  void updateScrollProgress(double p) {
    _currentChapterProgress = p;
    notifyListeners();
  }

  bool get hasNext => currentChapterIndex < spine.length - 1;
  bool get hasPrevious => currentChapterIndex > 0;
  void jumpToChapter(int i) {
    if (i >= 0 && i < spine.length) {
      currentChapterIndex = i;
      epubUrl = spine[i];
      requestScrollToProgress = 0.0;
      notifyListeners();
    }
  }
}
