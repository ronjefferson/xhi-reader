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
import 'package:pdfrx/pdfrx.dart';
import 'package:image/image.dart' as img;
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/book_model.dart';

class LibraryService {
  static final LibraryService _instance = LibraryService._internal();
  factory LibraryService() => _instance;
  LibraryService._internal();

  static const String _appFolderName = "MyReaderData";

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

  // --- MAIN SCAN METHOD ---
  Future<List<BookModel>> scanForEpubs({bool forceRefresh = false}) async {
    if (!await requestPermission()) return [];

    final prefs = await SharedPreferences.getInstance();
    final Set<String> seenPaths = {};
    List<BookModel> books = [];

    // 1. Scan Public Downloads (Where "Download" button saves)
    final publicBooks = await _scanPublicDownloads(
      prefs,
      seenPaths,
      forceRefresh,
    );
    books.addAll(publicBooks);

    // 2. Scan App Documents (Legacy/Imported manually)
    final privateBooks = await _scanAppDocuments(prefs, seenPaths);
    books.addAll(privateBooks);

    books.sort((a, b) {
      if (b.lastRead == null) return -1;
      if (a.lastRead == null) return 1;
      return b.lastRead!.compareTo(a.lastRead!);
    });

    return books;
  }

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
        List<FileSystemEntity> files = downloadsDir.listSync();

        for (var entity in files) {
          if (entity is File &&
              (p.extension(entity.path) == '.epub' ||
                  p.extension(entity.path) == '.pdf')) {
            if (seenPaths.contains(entity.path)) continue;
            seenPaths.add(entity.path);

            final fileName = p.basenameWithoutExtension(entity.path);
            final bookId = fileName.replaceAll(RegExp(r'\s+'), '_');

            final bookDataDir = Directory('${appDataDir.path}/$bookId');
            final coverFile = File('${bookDataDir.path}/cover.png');

            bool needsProcessing =
                !await bookDataDir.exists() ||
                !await coverFile.exists() ||
                forceRefresh;

            if (needsProcessing) {
              await bookDataDir.create(recursive: true);
              if (p.extension(entity.path) == '.epub') {
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
      for (var folder in appDataDir.listSync()) {
        if (folder is Directory) {
          File? bookFile;
          File? coverFile;
          for (var f in folder.listSync()) {
            if (f is File) {
              if (p.extension(f.path) == '.pdf' ||
                  p.extension(f.path) == '.epub')
                bookFile = f;
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

  // --- HELPERS (Unchanged) ---
  Future<void> importPdf() async {
    // Keep this manual import logic if you want users to pick files from random folders
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

      final ext = p.extension(originalFile.path);
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
      final doc = await PdfDocument.openFile(pdfFile.path);
      final page = doc.pages[0];
      final PdfImage? rawPdfImage = await page.render(
        width: 300,
        height: (300 * page.height / page.width).toInt(),
      );
      if (rawPdfImage != null) {
        final img.Image image = img.Image.fromBytes(
          width: rawPdfImage.width,
          height: rawPdfImage.height,
          bytes: rawPdfImage.pixels.buffer,
          order: img.ChannelOrder.rgba,
          numChannels: 4,
        );
        await targetCoverFile.writeAsBytes(img.encodePng(image));
      }
      await doc.dispose();
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
