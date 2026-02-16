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
  /// Fetches the latest library state from LibraryService
  Future<void> loadLibrary() async {
    _isLoading = true;
    notifyListeners();

    try {
      // Don't force refresh on initial load, just read what's there/new
      _books = await _libraryService.scanForEpubs(forceRefresh: false);
    } catch (e) {
      debugPrint("HomeViewModel Load Error: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Pull-to-Refresh Action (Force re-scan covers)
  /// We pass true to re-run cover extraction on existing books if needed
  Future<void> refreshLibrary() async {
    try {
      _books = await _libraryService.scanForEpubs(forceRefresh: true);
    } catch (e) {
      debugPrint("HomeViewModel Refresh Error: $e");
    } finally {
      notifyListeners();
    }
  }

  /// Explicitly import a PDF or EPUB using the LibraryService
  /// Then triggers a reload of the library to update the UI
  Future<void> importPdf() async {
    try {
      await _libraryService.importPdf();
      await loadLibrary(); // Refresh the list after successful import
    } catch (e) {
      debugPrint("HomeViewModel Import Error: $e");
    }
  }

  /// Notifies the UI to rebuild after a Rename or Delete action
  /// performed directly via the LibraryService
  Future<void> updateLibraryState() async {
    _books = await _libraryService.scanForEpubs(forceRefresh: false);
    notifyListeners();
  }
}
