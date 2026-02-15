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

  // --- MAIN SCAN METHOD (Restored Logic) ---
  Future<List<BookModel>> scanForEpubs({bool forceRefresh = false}) async {
    if (!await requestPermission()) return [];

    final prefs = await SharedPreferences.getInstance();
    final Set<String> seenPaths = {};
    List<BookModel> books = [];

    // 1. Scan Public Downloads
    // We pass forceRefresh here to decide if we regenerate covers
    final publicBooks = await _scanPublicDownloads(
      prefs,
      seenPaths,
      forceRefresh,
    );
    books.addAll(publicBooks);

    // 2. Scan App Documents
    final privateBooks = await _scanAppDocuments(prefs, seenPaths);
    books.addAll(privateBooks);

    books.sort((a, b) {
      if (b.lastRead == null) return -1;
      if (a.lastRead == null) return 1;
      return b.lastRead!.compareTo(a.lastRead!);
    });

    // Update Cache (Crucial for Cloud Tab)
    _loadedBooks = books;
    return books;
  }

  bool isBookDownloaded(String onlineTitle) {
    if (_loadedBooks.isEmpty) return false;
    final cleanOnline = _normalize(onlineTitle);

    return _loadedBooks.any((localBook) {
      final cleanLocal = _normalize(localBook.title);

      if (cleanLocal == cleanOnline) return true;

      final filename = p
          .basenameWithoutExtension(localBook.filePath ?? "")
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (filename.isNotEmpty && filename == cleanOnline) return true;

      if (cleanLocal.length > 4 && cleanOnline.length > 4) {
        if (cleanLocal.contains(cleanOnline) ||
            cleanOnline.contains(cleanLocal)) {
          return true;
        }
      }
      return false;
    });
  }

  String _normalize(String input) {
    return input.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  // --- SCANNERS (Restored listSync logic) ---
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
        // 🟢 RESTORED: listSync with recursive: true
        // This ensures we find files in subfolders and prevents "missed" files
        List<FileSystemEntity> files = downloadsDir.listSync(recursive: true);

        for (var entity in files) {
          if (entity is File) {
            final ext = p.extension(entity.path).toLowerCase();
            if (ext != '.epub' && ext != '.pdf') continue;

            if (seenPaths.contains(entity.path)) continue;
            seenPaths.add(entity.path);

            final fileName = p.basenameWithoutExtension(entity.path);
            final bookId = fileName.replaceAll(RegExp(r'\s+'), '_');

            final bookDataDir = Directory('${appDataDir.path}/$bookId');
            final coverFile = File('${bookDataDir.path}/cover.png');

            // 🟢 SAFE OPTIMIZATION: Check timestamps
            // Only generate if:
            // 1. Folder missing
            // 2. Cover missing
            // 3. Book file is NEWER than cover file (User updated the file)
            bool needsProcessing = false;

            if (!await bookDataDir.exists()) {
              await bookDataDir.create(recursive: true);
              needsProcessing = true;
            } else if (!await coverFile.exists()) {
              needsProcessing = true;
            } else {
              // Only check timestamp if forceRefresh was requested or regular check
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

            if (needsProcessing) {
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

      // 🟢 RESTORED: listSync for stability
      final folders = appDataDir.listSync();

      for (var folder in folders) {
        if (folder is Directory) {
          File? bookFile;
          File? coverFile;

          final folderFiles = folder.listSync();
          for (var f in folderFiles) {
            if (f is File) {
              final ext = p.extension(f.path).toLowerCase();
              if (ext == '.pdf' || ext == '.epub') bookFile = f;
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

  Future<void> importPdf() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf', 'epub'],
    );

    if (result != null && result.files.single.path != null) {
      File originalFile = File(result.files.single.path!);
      final fileName = p.basenameWithoutExtension(originalFile.path);
      final bookId = fileName.replaceAll(RegExp(r'\s+'), '_');
      final appDataDir = await _getAppDataDirectory();
      final bookDataDir = Directory('${appDataDir.path}/$bookId');

      if (!await bookDataDir.exists())
        await bookDataDir.create(recursive: true);

      final ext = p.extension(originalFile.path).toLowerCase();
      final savedFile = await originalFile.copy(
        '${bookDataDir.path}/$fileName$ext',
      );
      final coverFile = File('${bookDataDir.path}/cover.png');

      if (ext == '.pdf') {
        await _generatePdfCover(savedFile, coverFile);
      } else {
        await _extractEpubCover(savedFile, coverFile);
      }
    }
  }

  Future<void> _generatePdfCover(File pdfFile, File targetCoverFile) async {
    try {
      final pdfBytes = await pdfFile.readAsBytes();
      // 🟢 SAFE OPTIMIZATION: 72 DPI is enough for thumbnails and prevents crashes
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
        if (meta.getAttribute('name') == 'cover')
          coverId = meta.getAttribute('content');
      }

      if (coverId != null) {
        for (var item in opfXml.findAllElements('item')) {
          if (item.getAttribute('id') == coverId)
            coverHref = item.getAttribute('href');
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
}
