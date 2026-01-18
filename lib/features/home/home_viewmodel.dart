import 'package:flutter/material.dart';
import '../../core/services/library_service.dart';
import '../../models/book_model.dart';

class HomeViewModel extends ChangeNotifier {
  final LibraryService _libraryService = LibraryService();
  List<BookModel> _books = [];
  bool _isLoading = false;

  List<BookModel> get books => _books;
  bool get isLoading => _isLoading;

  /// Initial Load (Full screen spinner)
  Future<void> loadLibrary() async {
    _isLoading = true;
    notifyListeners();
    try {
      // Don't force refresh on initial load, just read what's there/new
      _books = await _libraryService.scanForEpubs(forceRefresh: false);
    } catch (e) {
      debugPrint("Error: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Pull-to-Refresh Action (Force re-scan covers)
  Future<void> refreshLibrary() async {
    // We pass true here to re-run cover extraction on existing books
    _books = await _libraryService.scanForEpubs(forceRefresh: true);
    notifyListeners();
  }

  Future<void> importPdf() async {
    await _libraryService.importPdf();
    await loadLibrary();
  }
}
