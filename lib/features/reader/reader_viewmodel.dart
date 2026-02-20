import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../models/book_model.dart';
import '../../core/services/epub_service.dart';
import '../../core/services/library_service.dart';
import '../../core/services/api_service.dart';
import '../../core/services/auth_service.dart';

class ReaderViewModel extends ChangeNotifier {
  final BookModel book;

  String? epubUrl;
  String? pdfPath;
  bool isReady = false;
  String? errorMessage;
  bool isPdf = false;

  List<String> spine = [];
  List<String> chapterTitles = [];
  int currentChapterIndex = 0;
  List<int> _chapterPageCounts = [];
  List<int> _cumulativePageCounts = [];
  double _currentChapterProgress = 0.0;

  PdfDocument? pdfDoc;
  int _pdfCurrentPage = 1;
  int _pdfTotalPages = 1;

  int _totalBookPages = 1;
  double? requestScrollToProgress;
  int? requestJumpToPage;

  ReaderViewModel({required this.book});

  int get totalBookPages => isPdf ? _pdfTotalPages : _totalBookPages;

  Future<void> initializeReader() async {
    try {
      if (book.filePath != null) {
        isPdf = book.filePath!.toLowerCase().endsWith('.pdf');
      } else {
        isPdf = !book.title.toLowerCase().endsWith('.epub');
      }

      if (isPdf) {
        await _initPdfMode();
      } else {
        if (book.isLocal) {
          await _initLocalEpub();
        } else {
          await _initOnlineEpub();
        }
      }
    } catch (e) {
      errorMessage = "Error loading book: $e";
      isReady = true;
      notifyListeners();
    }
  }

  Future<void> _initPdfMode() async {
    if (book.isLocal && book.filePath != null) {
      try {
        pdfPath = book.filePath;
        pdfDoc = await PdfDocument.openFile(pdfPath!);
      } catch (e) {
        throw "Could not open local file: $e";
      }
    } else {
      await _openCloudPdfWithRetry();
    }

    if (pdfDoc != null) {
      _pdfTotalPages = pdfDoc!.pages.length;
      chapterTitles = [];

      var savedData = await LibraryService().getLastProgress(
        book.id.toString(),
      );

      if (savedData == null && !book.isLocal) {
        try {
          int intId = int.tryParse(book.id.toString()) ?? 0;
          final cloudData = await ApiService().getReadingProgress(intId);
          if (cloudData != null) {
            savedData = {'chapterIndex': cloudData['chapter_index']};
          }
        } catch (e) {}
      }

      if (savedData != null) {
        _pdfCurrentPage = savedData['chapterIndex'] ?? 1;
        if (_pdfCurrentPage < 1) _pdfCurrentPage = 1;
        if (_pdfCurrentPage > _pdfTotalPages) _pdfCurrentPage = _pdfTotalPages;

        requestJumpToPage = _pdfCurrentPage;
      }
    }

    isReady = true;
    notifyListeners();
  }

  Future<void> _openCloudPdfWithRetry() async {
    final url = '${ApiService.baseUrl}/books/${book.id}/download';

    try {
      await _attemptOpenPdf(url);
    } catch (e) {
      if (e.toString().contains('401') ||
          e.toString().contains('Unauthorized')) {
        final success = await AuthService().tryRefreshToken();
        if (success) {
          await _attemptOpenPdf(url);
        } else {
          throw "Session expired. Please log in.";
        }
      } else {
        throw e;
      }
    }
  }

  Future<void> _attemptOpenPdf(String url) async {
    final token = AuthService().token;

    pdfDoc = await PdfDocument.openUri(
      Uri.parse(url),
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
        'ngrok-skip-browser-warning': 'true',
      },
    );
  }

  Future<void> _initLocalEpub() async {
    if (book.filePath == null) throw "Local file path missing.";
    final appDocPath = (await getApplicationDocumentsDirectory()).path;
    await EpubService().startServer(appDocPath);

    spine = await EpubService().getSpineUrls(
      File(book.filePath!),
      book.id.toString(),
      appDocPath,
    );
    await _calculateLocalPageCounts(book.id.toString(), appDocPath);

    final savedData = await LibraryService().getLastProgress(
      book.id.toString(),
    );
    _restoreEpubState(savedData);
  }

  Future<void> _initOnlineEpub() async {
    int id = int.tryParse(book.id.toString()) ?? 0;

    final manifest = await ApiService().fetchManifest(id);
    if (manifest == null) throw "Could not fetch book manifest.";

    spine = [];
    chapterTitles = [];
    _chapterPageCounts = [];
    _cumulativePageCounts = [];
    int runningTotal = 0;

    final List<dynamic> chapters = manifest['chapters'];
    final String currentBaseUrl = ApiService.baseUrl;

    for (var chap in chapters) {
      String rawUrl = chap['url'];
      if (rawUrl.contains('localhost') || rawUrl.contains('127.0.0.1')) {
        rawUrl = rawUrl.replaceFirst(
          RegExp(r'http://(localhost|127\.0\.0\.1)(:\d+)?'),
          currentBaseUrl,
        );
      }
      spine.add(rawUrl);

      String t = chap['title'] ?? "";
      if (t.trim().isEmpty) t = "Illustration";
      chapterTitles.add(t);

      // Start with a placeholder of 1 page per chapter.
      // The real count will be reported by the WebView after render
      // via updateChapterPageCount().
      const int placeholderPages = 1;
      _cumulativePageCounts.add(runningTotal);
      _chapterPageCounts.add(placeholderPages);
      runningTotal += placeholderPages;
    }
    _totalBookPages = runningTotal > 0 ? runningTotal : 1;

    Map<String, dynamic>? progressData;
    try {
      final cloudData = await ApiService().getReadingProgress(id);
      if (cloudData != null) {
        progressData = {
          'chapterIndex': cloudData['chapter_index'],
          'progress': cloudData['progress_percent'],
        };
      }
    } catch (e) {}

    _restoreEpubState(progressData);
  }

  /// Called by the View when the WebView reports its actual rendered page count
  /// for the current chapter. This replaces the estimated/placeholder value and
  /// recalculates all cumulative totals from that chapter onward.
  void updateChapterPageCount(int chapterIndex, int actualPageCount) {
    if (chapterIndex < 0 || chapterIndex >= _chapterPageCounts.length) return;
    if (_chapterPageCounts[chapterIndex] == actualPageCount) return;

    _chapterPageCounts[chapterIndex] = actualPageCount;

    // Recalculate cumulative counts from this chapter onward
    int runningTotal = chapterIndex > 0
        ? _cumulativePageCounts[chapterIndex]
        : 0;
    for (int i = chapterIndex; i < _chapterPageCounts.length; i++) {
      _cumulativePageCounts[i] = runningTotal;
      runningTotal += _chapterPageCounts[i];
    }
    _totalBookPages = runningTotal > 0 ? runningTotal : 1;

    notifyListeners();
  }

  void _updateUrl(String baseUrl, {bool posEnd = false}) {
    final String v = DateTime.now().millisecondsSinceEpoch.toString();
    String separator = baseUrl.contains('?') ? '&' : '?';
    String finalUrl = "$baseUrl${separator}v=$v";

    if (!book.isLocal) {
      final token = AuthService().token;
      if (token != null) finalUrl += "&token=$token";
    }

    if (posEnd) finalUrl += "&pos=end";
    epubUrl = finalUrl;
  }

  void _restoreEpubState(Map<String, dynamic>? data) {
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

  void saveCurrentProgress() {
    String strId = book.id.toString();
    int intId = int.tryParse(strId) ?? 0;

    if (isPdf) {
      LibraryService().saveProgress(strId, _pdfCurrentPage, 0.0);
      ApiService().updateReadingProgress(intId, _pdfCurrentPage, 0.0);
    } else {
      if (book.isLocal) {
        LibraryService().saveProgress(
          strId,
          currentChapterIndex,
          _currentChapterProgress,
        );
      } else {
        ApiService().updateReadingProgress(
          intId,
          currentChapterIndex,
          _currentChapterProgress,
        );
      }
    }
  }

  void onPdfPageChanged(int page) {
    _pdfCurrentPage = page;
    saveCurrentProgress();
    notifyListeners();
  }

  void jumpToGlobalPage(int globalPage) {
    if (isPdf) {
      _pdfCurrentPage = globalPage.clamp(1, _pdfTotalPages);
      requestJumpToPage = _pdfCurrentPage;
      notifyListeners();
      saveCurrentProgress();
    } else {
      globalPage = globalPage.clamp(1, _totalBookPages);
      for (int i = 0; i < _cumulativePageCounts.length; i++) {
        int start = _cumulativePageCounts[i];
        int count = _chapterPageCounts[i];
        if (globalPage <= start + count) {
          int localPage = globalPage - start;
          double percent = (localPage - 1) / (count > 1 ? count - 1 : 1);
          currentChapterIndex = i;
          _updateUrl(spine[i]);
          requestScrollToProgress = percent;
          notifyListeners();
          saveCurrentProgress();
          return;
        }
      }
    }
  }

  void updateEpubScrollProgress(double progress) {
    _currentChapterProgress = progress;
    saveCurrentProgress();
  }

  void nextChapter() {
    if (!isPdf && currentChapterIndex < spine.length - 1) {
      currentChapterIndex++;
      _updateUrl(spine[currentChapterIndex]);
      requestScrollToProgress = 0.0;
      _currentChapterProgress = 0.0;
      notifyListeners();
      saveCurrentProgress();
    }
  }

  void previousChapter() {
    if (!isPdf && currentChapterIndex > 0) {
      currentChapterIndex--;
      _updateUrl(spine[currentChapterIndex], posEnd: true);
      requestScrollToProgress = 1.0;
      _currentChapterProgress = 1.0;
      notifyListeners();
      saveCurrentProgress();
    }
  }

  void jumpToChapter(int index) {
    if (!isPdf && index >= 0 && index < spine.length) {
      currentChapterIndex = index;
      _updateUrl(spine[index]);
      requestScrollToProgress = 0.0;
      notifyListeners();
      saveCurrentProgress();
    }
  }

  int getCurrentGlobalPage() {
    if (isPdf) return _pdfCurrentPage;
    if (_chapterPageCounts.isEmpty) return 1;
    if (currentChapterIndex >= _cumulativePageCounts.length) return 1;
    int start = _cumulativePageCounts[currentChapterIndex];
    int count = _chapterPageCounts[currentChapterIndex];
    int pagesIn = (_currentChapterProgress * count).round();
    return start + pagesIn + 1;
  }

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

      String title = await _extractChapterTitle(localPath, index);
      chapterTitles.add(title);

      _chapterPageCounts.add(pages);
      runningTotal += pages;
      index++;
    }
    _totalBookPages = runningTotal > 0 ? runningTotal : 1;
    notifyListeners();
  }

  Future<String> _extractChapterTitle(String path, int index) async {
    try {
      final file = File(path);
      if (!await file.exists()) return "Chapter ${index + 1}";

      final content = await file.readAsString();

      final h1Match = RegExp(
        r'<h1[^>]*>(.*?)</h1>',
        caseSensitive: false,
        dotAll: true,
      ).firstMatch(content);
      if (h1Match != null) {
        String text = h1Match
            .group(1)!
            .replaceAll(RegExp(r'<[^>]*>'), '')
            .trim();
        if (text.isNotEmpty) return _cleanHtmlEntities(text);
      }

      final h2Match = RegExp(
        r'<h2[^>]*>(.*?)</h2>',
        caseSensitive: false,
        dotAll: true,
      ).firstMatch(content);
      if (h2Match != null) {
        String text = h2Match
            .group(1)!
            .replaceAll(RegExp(r'<[^>]*>'), '')
            .trim();
        if (text.isNotEmpty) return _cleanHtmlEntities(text);
      }

      final titleMatch = RegExp(
        r'<title[^>]*>(.*?)</title>',
        caseSensitive: false,
        dotAll: true,
      ).firstMatch(content);
      if (titleMatch != null) {
        String text = titleMatch
            .group(1)!
            .replaceAll(RegExp(r'<[^>]*>'), '')
            .trim();
        if (text.isNotEmpty && text.length < 50)
          return _cleanHtmlEntities(text);
      }

      if (content.contains('<img') ||
          content.contains('<image') ||
          content.contains('<svg')) {
        final textOnly = content
            .replaceAll(RegExp(r'<[^>]*>'), '')
            .replaceAll(RegExp(r'\s+'), '')
            .trim();
        if (textOnly.length < 100) return "Illustration";
      }

      final fileName = path.split('/').last.toLowerCase();
      if (fileName.contains('cover')) return "Cover";
      if (fileName.contains('title')) return "Title Page";
    } catch (e) {}

    return "Chapter ${index + 1}";
  }

  String _cleanHtmlEntities(String text) {
    return text
        .replaceAll('&nbsp;', ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }
}
