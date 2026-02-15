import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart'; // 🟢 REQUIRED for PDF support

import '../../models/book_model.dart';
import '../../core/services/epub_service.dart';
import '../../core/services/library_service.dart';
import '../../core/services/api_service.dart';
import '../../core/services/auth_service.dart';

class ReaderViewModel extends ChangeNotifier {
  final BookModel book;

  // --- State ---
  String? epubUrl;
  String? pdfPath; // 🟢 PDF Path
  bool isReady = false;
  String? errorMessage;
  bool isPdf = false; // 🟢 PDF Flag

  // --- Navigation (EPUB) ---
  List<String> spine = [];
  List<String> chapterTitles = [];
  int currentChapterIndex = 0;
  List<int> _chapterPageCounts = [];
  List<int> _cumulativePageCounts = [];
  double _currentChapterProgress = 0.0;

  // --- Navigation (PDF) ---
  PdfDocument? pdfDoc;
  int _pdfCurrentPage = 1;
  int _pdfTotalPages = 1;
  List<PdfOutlineNode> pdfOutline = [];

  // --- Shared ---
  int _totalBookPages = 1;
  double? requestScrollToProgress; // For EPUB
  int? requestJumpToPage; // 🟢 For PDF

  ReaderViewModel({required this.book});

  int get totalBookPages => isPdf ? _pdfTotalPages : _totalBookPages;

  // --- INITIALIZATION ---
  Future<void> initializeReader() async {
    try {
      // Check file extension to detect PDF
      isPdf = book.filePath?.toLowerCase().endsWith('.pdf') ?? false;

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

  // --- MODE 1: PDF ---
  Future<void> _initPdfMode() async {
    if (book.filePath == null) throw "PDF file path missing.";
    pdfPath = book.filePath;

    try {
      // Open PDF to get stats
      pdfDoc = await PdfDocument.openFile(pdfPath!);
      _pdfTotalPages = pdfDoc!.pages.length;
      try {
        pdfOutline = await pdfDoc!.loadOutline();
      } catch (_) {}

      // Create simple chapter titles from Outline or generic pages
      chapterTitles = _flattenPdfOutline(pdfOutline);
      if (chapterTitles.isEmpty) {
        // If no outline, create generic "Page 10, 20..." markers so the list isn't empty
        chapterTitles = [];
      }
    } catch (e) {
      debugPrint("Error opening PDF: $e");
    }

    // Restore Progress
    final savedData = await LibraryService().getLastProgress(book.id);
    if (savedData != null) {
      _pdfCurrentPage = savedData['chapterIndex'] ?? 1;
      if (_pdfCurrentPage < 1) _pdfCurrentPage = 1;
      if (_pdfCurrentPage > _pdfTotalPages) _pdfCurrentPage = _pdfTotalPages;

      requestJumpToPage = _pdfCurrentPage;
    }

    isReady = true;
    notifyListeners();
  }

  List<String> _flattenPdfOutline(List<PdfOutlineNode> nodes) {
    List<String> titles = [];
    for (var node in nodes) {
      titles.add(node.title);
      if (node.children.isNotEmpty) {
        titles.addAll(_flattenPdfOutline(node.children));
      }
    }
    return titles;
  }

  // --- MODE 2: LOCAL EPUB ---
  Future<void> _initLocalEpub() async {
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
    _restoreEpubState(savedData);
  }

  // --- MODE 3: ONLINE EPUB ---
  Future<void> _initOnlineEpub() async {
    final manifest = await ApiService().fetchManifest(book.id);
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
      final genericNameRegex = RegExp(r'^Chapter\s*\d*$', caseSensitive: false);
      if (t.trim().isEmpty || genericNameRegex.hasMatch(t.trim())) {
        t = "Illustration";
      }
      chapterTitles.add(t);

      int size = chap['sizeBytes'] ?? 2000;
      int pages = (size / 2000).ceil();
      if (pages < 1) pages = 1;

      _cumulativePageCounts.add(runningTotal);
      _chapterPageCounts.add(pages);
      runningTotal += pages;
    }
    _totalBookPages = runningTotal > 0 ? runningTotal : 1;

    final cloudData = await ApiService().getProgress(book.id);
    Map<String, dynamic>? progressData;
    if (cloudData != null) {
      progressData = {
        'chapterIndex': cloudData['chapter_index'],
        'progress': cloudData['progress_percent'],
      };
    }
    _restoreEpubState(progressData);
  }

  // --- EPUB HELPERS ---
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

  // --- SAVE PROGRESS ---
  void saveCurrentProgress() {
    if (isPdf) {
      // PDF: Save Page Number as 'chapterIndex'
      LibraryService().saveProgress(book.id, _pdfCurrentPage, 0.0);
    } else {
      // EPUB: Save Chapter Index + Scroll %
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
  }

  // --- NAVIGATION (UNIFIED) ---

  // 🟢 NEW: Called by PDF Viewer when page changes
  void onPdfPageChanged(int page) {
    _pdfCurrentPage = page;
    saveCurrentProgress();
    notifyListeners();
  }

  // 🟢 NEW: Unified Jump (Slider)
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
          percent = percent.clamp(0.0, 1.0);

          if (currentChapterIndex != i) {
            currentChapterIndex = i;
            _updateUrl(spine[i]);
          }
          requestScrollToProgress = percent;
          notifyListeners();
          saveCurrentProgress();
          return;
        }
      }
    }
  }

  // 🟢 NEW: Renamed for clarity (was updateScrollProgress)
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
    if (isPdf) {
      if (index >= 0 && index < pdfOutline.length) {
        final node = pdfOutline[index];
        // PDF Outline destinations can be tricky, simplified to pageNumber
        requestJumpToPage = node.dest?.pageNumber ?? 1;
        notifyListeners();
      }
    } else {
      if (index >= 0 && index < spine.length) {
        currentChapterIndex = index;
        _updateUrl(spine[index]);
        requestScrollToProgress = 0.0;
        notifyListeners();
        saveCurrentProgress();
      }
    }
  }

  // --- GETTERS (UNIFIED) ---
  int getCurrentGlobalPage() {
    if (isPdf) return _pdfCurrentPage;

    if (_chapterPageCounts.isEmpty) return 1;
    if (currentChapterIndex >= _cumulativePageCounts.length) return 1;
    int start = _cumulativePageCounts[currentChapterIndex];
    int count = _chapterPageCounts[currentChapterIndex];
    int pagesIn = (_currentChapterProgress * count).round();
    return start + pagesIn + 1;
  }

  // --- LOCAL CALC ---
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
}
