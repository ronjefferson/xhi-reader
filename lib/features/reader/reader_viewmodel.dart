import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../../models/book_model.dart';
import '../../core/services/epub_service.dart';

class ReaderViewModel extends ChangeNotifier {
  final BookModel book;
  final EpubService _epubService = EpubService();

  bool _isReady = false;
  String? _errorMessage;
  String? _epubUrl;

  List<String> _chapters = [];
  int _currentChapterIndex = 0;

  ReaderViewModel({required this.book});

  bool get isReady => _isReady;
  String? get errorMessage => _errorMessage;
  String? get epubUrl => _epubUrl;

  int get currentChapterIndex => _currentChapterIndex;
  int get totalChapters => _chapters.length;
  bool get hasNext => _currentChapterIndex < _chapters.length - 1;
  bool get hasPrevious => _currentChapterIndex > 0;

  Future<void> initializeReader() async {
    _isReady = false;
    notifyListeners();

    try {
      if (book.type == BookType.epub) {
        final dir = await getApplicationDocumentsDirectory();
        await _epubService.startServer(dir.path);

        // Load Chapter List
        _chapters = await _epubService.getSpineUrls(
          File(book.filePath),
          book.id,
          dir.path,
        );

        if (_chapters.isNotEmpty) {
          _epubUrl = _chapters[0];
        } else {
          throw Exception("No chapters found in EPUB.");
        }
      }
      _isReady = true;
    } catch (e) {
      _errorMessage = "Error opening book: $e";
    } finally {
      notifyListeners();
    }
  }

  void nextChapter() {
    if (hasNext) {
      _currentChapterIndex++;
      _epubUrl = _chapters[_currentChapterIndex];
      notifyListeners();
    }
  }

  void previousChapter() {
    if (hasPrevious) {
      _currentChapterIndex--;
      _epubUrl = _chapters[_currentChapterIndex];
      notifyListeners();
    }
  }
}
