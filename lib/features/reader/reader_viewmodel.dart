import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/book_model.dart';
import '../../core/services/epub_service.dart';

class ReaderViewModel extends ChangeNotifier {
  final BookModel book;

  // State
  bool _isReady = false;
  String? _errorMessage;

  // Epub Specifics
  List<String> _spine = [];
  int _currentChapterIndex = 0;

  ReaderViewModel({required this.book});

  // --- GETTERS ---
  bool get isReady => _isReady;
  String? get errorMessage => _errorMessage;
  List<String> get spine => _spine;
  int get currentChapterIndex => _currentChapterIndex;

  // Returns the localhost URL for the current chapter
  String? get epubUrl {
    if (_spine.isEmpty || _currentChapterIndex >= _spine.length) return null;
    return _spine[_currentChapterIndex];
  }

  bool get hasNext => _currentChapterIndex < _spine.length - 1;
  bool get hasPrevious => _currentChapterIndex > 0;

  // --- INITIALIZATION ---
  Future<void> initializeReader() async {
    try {
      _isReady = false;
      notifyListeners();

      if (book.type == BookType.pdf) {
        // PDF doesn't need a local server, it reads directly from file
        _isReady = true;
        notifyListeners();
        return;
      }

      // EPUB SETUP
      final dir = await getApplicationDocumentsDirectory();
      final appDocPath = dir.path;

      // 1. Start the Local Server (if not running)
      // This injects the CSS/JS and serves files
      await EpubService().startServer(appDocPath);

      // 2. Parse the EPUB Spine
      // This gives us a list of URLs like: http://localhost:8080/books/123/chapter1.html
      _spine = await EpubService().getSpineUrls(
        File(book.filePath),
        book.id,
        appDocPath,
      );

      if (_spine.isEmpty) {
        _errorMessage =
            "Could not load chapters. The book format might be invalid.";
      } else {
        _isReady = true;
      }
    } catch (e) {
      _errorMessage = "Error loading book: $e";
      print("ReaderViewModel Error: $e");
    } finally {
      notifyListeners();
    }
  }

  // --- NAVIGATION LOGIC ---

  void nextChapter() {
    if (hasNext) {
      _currentChapterIndex++;
      notifyListeners();
    }
  }

  void previousChapter() {
    if (hasPrevious) {
      _currentChapterIndex--;
      notifyListeners();
    }
  }

  // Used by the Chapter List UI to jump directly
  void jumpToChapter(int index) {
    if (index >= 0 && index < _spine.length) {
      _currentChapterIndex = index;
      notifyListeners();
    }
  }
}
