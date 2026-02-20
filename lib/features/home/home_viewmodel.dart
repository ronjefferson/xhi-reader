import 'package:flutter/material.dart';
import '../../core/services/library_service.dart';
import '../../models/book_model.dart';

class HomeViewModel extends ChangeNotifier {
  final LibraryService _libraryService = LibraryService();
  List<BookModel> _books = [];
  bool _isLoading = false;

  List<BookModel> get books => _books;
  bool get isLoading => _isLoading;

  Future<void> loadLibrary() async {
    _isLoading = true;
    notifyListeners();

    try {
      _books = await _libraryService.scanForEpubs(forceRefresh: false);
    } catch (e) {
      debugPrint("HomeViewModel Load Error: $e");
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshLibrary() async {
    try {
      _books = await _libraryService.scanForEpubs(forceRefresh: true);
    } catch (e) {
      debugPrint("HomeViewModel Refresh Error: $e");
    } finally {
      notifyListeners();
    }
  }

  Future<void> importPdf() async {
    try {
      await _libraryService.importPdf();
      await loadLibrary();
    } catch (e) {
      debugPrint("HomeViewModel Import Error: $e");
    }
  }

  Future<void> updateLibraryState() async {
    _books = await _libraryService.scanForEpubs(forceRefresh: false);
    notifyListeners();
  }
}
