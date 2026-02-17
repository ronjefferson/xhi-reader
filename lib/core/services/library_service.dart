import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';
import 'package:external_path/external_path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:printing/printing.dart';

import '../../models/book_model.dart';

class LibraryService {
  static final LibraryService _instance = LibraryService._internal();
  factory LibraryService() => _instance;
  LibraryService._internal();

  static const String _appFolderName = "MyReaderData";

  // Cache
  List<BookModel> _loadedBooks = [];
  List<BookModel> get loadedBooks => _loadedBooks;

  // --- PERMISSIONS ---
  Future<bool> requestPermission() async {
    if (await Permission.manageExternalStorage.isGranted) return true;
    if (await Permission.storage.isGranted) return true;
    if (await Permission.manageExternalStorage.request().isGranted) return true;
    if (await Permission.storage.request().isGranted) return true;
    return false;
  }

  Future<Directory> _getAppDataDirectory() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDocDir.path}/$_appFolderName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // --- PROGRESS TRACKING ---
  Future<void> saveProgress(
    String bookId,
    int chapterIndex,
    double progress,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_chapter_$bookId', chapterIndex);
    await prefs.setDouble('last_progress_$bookId', progress);
    await updateLastRead(bookId);
  }

  Future<Map<String, dynamic>?> getLastProgress(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey('last_chapter_$bookId')) return null;

    return {
      'chapterIndex': prefs.getInt('last_chapter_$bookId') ?? 0,
      'progress': prefs.getDouble('last_progress_$bookId') ?? 0.0,
    };
  }

  Future<void> updateLastRead(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      'last_read_$bookId',
      DateTime.now().millisecondsSinceEpoch,
    );
  }

  Future<List<BookModel>> sortBooksByRecent(List<BookModel> books) async {
    final prefs = await SharedPreferences.getInstance();
    List<BookModel> updatedBooks = [];

    for (var book in books) {
      final lastReadMillis = prefs.getInt('last_read_${book.id}');
      final lastRead = lastReadMillis != null
          ? DateTime.fromMillisecondsSinceEpoch(lastReadMillis)
          : null;

      // Check for virtual rename alias
      final customTitle = prefs.getString('custom_title_${book.id}');

      updatedBooks.add(
        book.copyWith(lastRead: lastRead, title: customTitle ?? book.title),
      );
    }

    updatedBooks.sort((a, b) {
      final aTime = a.lastRead ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bTime = b.lastRead ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bTime.compareTo(aTime);
    });

    return updatedBooks;
  }

  // --- MAIN SCAN METHOD ---
  Future<List<BookModel>> scanForEpubs({bool forceRefresh = false}) async {
    if (!await requestPermission()) return [];

    final prefs = await SharedPreferences.getInstance();
    final Set<String> seenPaths = {};
    List<BookModel> books = [];

    // 1. Scan Public Downloads
    final publicBooks = await _scanPublicDownloads(
      prefs,
      seenPaths,
      forceRefresh,
    );
    books.addAll(publicBooks);

    // 2. Scan App Documents
    final privateBooks = await _scanAppDocuments(prefs, seenPaths);
    books.addAll(privateBooks);

    // Apply Virtual Names and Final Sort
    List<BookModel> processedBooks = [];
    for (var b in books) {
      final customTitle = prefs.getString('custom_title_${b.id}');
      processedBooks.add(b.copyWith(title: customTitle ?? b.title));
    }

    processedBooks.sort((a, b) {
      // 🟢 FIX: Books without lastRead go to the END
      if (a.lastRead == null && b.lastRead == null) return 0;
      if (a.lastRead == null) return 1; // a goes to end
      if (b.lastRead == null) return -1; // b goes to end
      // Most recent first (descending)
      return b.lastRead!.compareTo(a.lastRead!);
    });

    _loadedBooks = processedBooks;
    return processedBooks;
  }

  // --- SCANNERS ---
  Future<List<BookModel>> _scanPublicDownloads(
    SharedPreferences prefs,
    Set<String> seenPaths,
    bool forceRefresh,
  ) async {
    List<BookModel> found = [];
    try {
      final downloadsPath =
          await ExternalPath.getExternalStoragePublicDirectory("Download");
      final downloadsDir = Directory(downloadsPath);
      final appDataDir = await _getAppDataDirectory();

      if (downloadsDir.existsSync()) {
        List<FileSystemEntity> files = downloadsDir.listSync(recursive: true);

        for (var entity in files) {
          if (entity is File) {
            final ext = p.extension(entity.path).toLowerCase();

            // 🟢 ONLY SCAN EPUB FILES
            if (ext != '.epub') continue;

            if (seenPaths.contains(entity.path)) continue;
            seenPaths.add(entity.path);

            final fileName = p.basenameWithoutExtension(entity.path);
            final bookId = fileName.replaceAll(RegExp(r'\s+'), '_');

            final bookDataDir = Directory('${appDataDir.path}/$bookId');
            final coverFile = File('${bookDataDir.path}/cover.png');

            bool needsProcessing = false;

            if (!await bookDataDir.exists()) {
              await bookDataDir.create(recursive: true);
              needsProcessing = true;
            } else if (!await coverFile.exists()) {
              needsProcessing = true;
            } else {
              try {
                final bookStat = await entity.stat();
                final coverStat = await coverFile.stat();
                if (bookStat.modified.isAfter(coverStat.modified)) {
                  needsProcessing = true;
                }
              } catch (_) {
                needsProcessing = true;
              }
            }

            if (needsProcessing || forceRefresh) {
              if (ext == '.epub') {
                await _extractEpubCover(entity, coverFile);
              } else {
                await _generatePdfCover(entity, coverFile);
              }
            }

            final lastReadMillis = prefs.getInt('last_read_$bookId');
            final lastRead = lastReadMillis != null
                ? DateTime.fromMillisecondsSinceEpoch(lastReadMillis)
                : null;

            found.add(
              BookModel(
                id: bookId,
                title: fileName,
                filePath: entity.path,
                coverPath: coverFile.path,
                isLocal: true,
                author: "Unknown",
                lastRead: lastRead,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint("Error scanning public downloads: $e");
    }
    return found;
  }

  Future<List<BookModel>> _scanAppDocuments(
    SharedPreferences prefs,
    Set<String> seenPaths,
  ) async {
    final appDataDir = await _getAppDataDirectory();
    List<BookModel> found = [];
    try {
      if (!appDataDir.existsSync()) return [];

      final folders = appDataDir.listSync();

      for (var folder in folders) {
        if (folder is Directory) {
          File? bookFile;
          File? coverFile;

          final folderFiles = folder.listSync();
          for (var f in folderFiles) {
            if (f is File) {
              final ext = p.extension(f.path).toLowerCase();
              // 🟢 ONLY SCAN EPUB FILES
              if (ext == '.epub') bookFile = f;
              if (p.basename(f.path).contains('cover')) coverFile = f;
            }
          }

          if (bookFile != null && coverFile != null) {
            if (seenPaths.contains(bookFile.path)) continue;
            seenPaths.add(bookFile.path);

            final id = p.basename(folder.path);
            final lastReadMillis = prefs.getInt('last_read_$id');
            final lastRead = lastReadMillis != null
                ? DateTime.fromMillisecondsSinceEpoch(lastReadMillis)
                : null;

            found.add(
              BookModel(
                id: id,
                title: p.basenameWithoutExtension(bookFile.path),
                filePath: bookFile.path,
                coverPath: coverFile.path,
                isLocal: true,
                author: "Unknown",
                lastRead: lastRead,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint("Error scanning private docs: $e");
    }
    return found;
  }

  // --- EXPLICIT IMPORT ---
  Future<void> importPdf() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub'], // 🟢 ONLY EPUB
    );

    if (result != null && result.files.single.path != null) {
      File originalFile = File(result.files.single.path!);
      final fileName = p.basenameWithoutExtension(originalFile.path);
      final bookId = fileName.replaceAll(RegExp(r'\s+'), '_');
      final appDataDir = await _getAppDataDirectory();
      final bookDataDir = Directory('${appDataDir.path}/$bookId');

      if (!await bookDataDir.exists()) {
        await bookDataDir.create(recursive: true);
      }

      final ext = p.extension(originalFile.path).toLowerCase();
      final savedFile = await originalFile.copy(
        '${bookDataDir.path}/$fileName$ext',
      );
      final coverFile = File('${bookDataDir.path}/cover.png');

      // 🟢 ONLY EPUB
      await _extractEpubCover(savedFile, coverFile);
    }
  }

  Future<void> _generatePdfCover(File pdfFile, File targetCoverFile) async {
    try {
      final pdfBytes = await pdfFile.readAsBytes();
      await for (final page in Printing.raster(pdfBytes, dpi: 72, pages: [0])) {
        final pngBytes = await page.toPng();
        await targetCoverFile.writeAsBytes(pngBytes);
        break;
      }
    } catch (e) {
      debugPrint("Error generating PDF cover: $e");
    }
  }

  Future<void> _extractEpubCover(File epubFile, File targetCoverFile) async {
    try {
      final bytes = await epubFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      ArchiveFile? containerFile = archive.files.firstWhere(
        (f) => f.name.contains('container.xml'),
        orElse: () => archive.files.first,
      );

      final containerXml = XmlDocument.parse(
        utf8.decode(containerFile.content as List<int>),
      );
      final rootPath = containerXml
          .findAllElements('rootfile')
          .first
          .getAttribute('full-path')!;

      ArchiveFile? opfFile = archive.files.firstWhere(
        (f) => f.name.contains(rootPath),
        orElse: () => archive.files.first,
      );

      final opfXml = XmlDocument.parse(
        utf8.decode(opfFile.content as List<int>),
      );
      String? coverHref;
      String? coverId;

      for (var meta in opfXml.findAllElements('meta')) {
        if (meta.getAttribute('name') == 'cover') {
          coverId = meta.getAttribute('content');
        }
      }

      if (coverId != null) {
        for (var item in opfXml.findAllElements('item')) {
          if (item.getAttribute('id') == coverId) {
            coverHref = item.getAttribute('href');
          }
        }
      }

      if (coverHref == null) {
        try {
          final possible = archive.files.firstWhere(
            (f) =>
                f.name.toLowerCase().contains('cover') &&
                (f.name.endsWith('.jpg') || f.name.endsWith('.png')),
          );
          coverHref = possible.name;
        } catch (_) {}
      }

      if (coverHref != null) {
        coverHref = Uri.decodeFull(coverHref);
        final coverFilename = p.basename(coverHref);
        final imageFile = archive.files.firstWhere(
          (f) => f.name.endsWith(coverFilename),
          orElse: () =>
              archive.files.firstWhere((f) => f.name.endsWith('cover.jpg')),
        );
        await targetCoverFile.writeAsBytes(imageFile.content as List<int>);
      }
    } catch (e) {
      debugPrint("Error extracting EPUB cover: $e");
    }
  }

  // 🟢 FIXED DELETE FUNCTION
  Future<bool> deleteBook(BookModel book) async {
    try {
      if (book.filePath != null) {
        final file = File(book.filePath!);

        // Delete the actual book file
        if (await file.exists()) {
          await file.delete();
          debugPrint("Deleted book file: ${file.path}");
        }

        // Clean up the cover/metadata folder in app directory
        final fileName = p.basenameWithoutExtension(file.path);
        final bookId = fileName.replaceAll(RegExp(r'\s+'), '_');
        final appDataDir = await _getAppDataDirectory();
        final coverDir = Directory('${appDataDir.path}/$bookId');

        if (await coverDir.exists()) {
          await coverDir.delete(recursive: true);
          debugPrint("Deleted cover directory: ${coverDir.path}");
        }

        // Clean up SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('last_chapter_${book.id}');
        await prefs.remove('last_progress_${book.id}');
        await prefs.remove('last_read_${book.id}');
        await prefs.remove('custom_title_${book.id}');
        debugPrint("Cleaned up SharedPreferences for book: ${book.id}");

        return true;
      }
    } catch (e) {
      debugPrint("Delete Error: $e");
    }
    return false;
  }

  // Rename book (virtual only)
  Future<void> renameBookVirtual(String bookId, String newTitle) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('custom_title_$bookId', newTitle);
  }

  // Helper for Sync Indicators
  bool isBookDownloaded(String onlineTitle) {
    if (_loadedBooks.isEmpty) return false;
    final cleanOnline = _normalize(onlineTitle);
    return _loadedBooks.any(
      (localBook) => _normalize(localBook.title) == cleanOnline,
    );
  }

  String _normalize(String input) {
    // Aggressive normalization to match "Book Name.pdf" with "Book Name"
    var text = input.toLowerCase();
    text = text.replaceAll('.pdf', '').replaceAll('.epub', '');
    return text.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }
}
