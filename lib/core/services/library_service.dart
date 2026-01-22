import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
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
import 'package:shared_preferences/shared_preferences.dart'; // Import this

import '../../models/book_model.dart';

class LibraryService {
  static final LibraryService _instance = LibraryService._internal();
  factory LibraryService() => _instance;
  LibraryService._internal();

  static const String _appFolderName = "MyReaderData";

  // --- PERMISSIONS ---
  Future<bool> requestPermission() async {
    // Check if already granted
    if (await Permission.manageExternalStorage.isGranted) return true;
    if (await Permission.storage.isGranted) return true;
    
    // Request Manage Storage (Android 11+)
    if (await Permission.manageExternalStorage.request().isGranted) return true;
    
    // Request Standard Storage (Android 10 and below)
    if (await Permission.storage.request().isGranted) return true;
    
    return false;
  }

  Future<Directory> _getAppDataDirectory() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDocDir.path}/$_appFolderName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  // --- UPDATE TIMESTAMP ---
  Future<void> updateLastRead(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('last_read_$bookId', DateTime.now().millisecondsSinceEpoch);
  }

  // --- MAIN SCAN METHOD ---
  Future<List<BookModel>> scanForEpubs({bool forceRefresh = false}) async {
    // 1. Permission Check
    if (!await requestPermission()) {
      debugPrint("Permission denied");
      return []; 
    }

    final prefs = await SharedPreferences.getInstance(); // Load Prefs
    List<BookModel> books = [];

    // 2. Scan Downloads Folder
    try {
      final downloadsPath = await ExternalPath.getExternalStoragePublicDirectory("Download");
      final downloadsDir = Directory(downloadsPath);
      final appDataDir = await _getAppDataDirectory();

      if (downloadsDir.existsSync()) {
        List<FileSystemEntity> files = downloadsDir.listSync();
        
        for (var entity in files) {
          if (entity is File && p.extension(entity.path) == '.epub') {
            final fileName = p.basenameWithoutExtension(entity.path);
            final bookId = fileName.replaceAll(RegExp(r'\s+'), '_');
            
            // Set up Internal Paths for Cover/Data
            final bookDataDir = Directory('${appDataDir.path}/$bookId');
            final coverFile = File('${bookDataDir.path}/cover.png');

            // Processing Check
            bool needsProcessing = !await bookDataDir.exists() || !await coverFile.exists() || forceRefresh;

            if (needsProcessing) {
              await bookDataDir.create(recursive: true);
              // We create the cover, but we KEEP using the original file path for reading
              await _extractEpubCover(entity, coverFile);
            }

            // Get Last Read Time
            final lastReadMillis = prefs.getInt('last_read_$bookId');
            final lastRead = lastReadMillis != null 
                ? DateTime.fromMillisecondsSinceEpoch(lastReadMillis) 
                : null;

            // ADD TO LIST IMMEDIATELY (Original Logic)
            books.add(
              BookModel(
                id: bookId,
                title: fileName,
                filePath: entity.path, // Use the Download path
                coverPath: coverFile.path,
                type: BookType.epub,
                author: "Unknown",
                lastRead: lastRead, // <--- Add Timestamp
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint("Error scanning downloads: $e");
    }

    // 3. Add Imported PDFs (Merging lists)
    books.addAll(await _scanImportedPdfs(prefs)); // Pass prefs helper

    // 4. SORT (Recent First)
    books.sort((a, b) {
      if (b.lastRead == null) return -1;
      if (a.lastRead == null) return 1;
      return b.lastRead!.compareTo(a.lastRead!);
    });

    return books;
  }

  /// IMPORT PDF (Kept mostly same)
  Future<void> importPdf() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null && result.files.single.path != null) {
      File originalPdf = File(result.files.single.path!);
      final fileName = p.basenameWithoutExtension(originalPdf.path);
      final bookId = fileName.replaceAll(RegExp(r'\s+'), '_');
      final appDataDir = await _getAppDataDirectory();
      final bookDataDir = Directory('${appDataDir.path}/$bookId');

      if (!await bookDataDir.exists()) await bookDataDir.create(recursive: true);

      final savedPdf = await originalPdf.copy('${bookDataDir.path}/$fileName.pdf');
      final coverFile = File('${bookDataDir.path}/cover.png');
      await _generatePdfCover(savedPdf, coverFile);
    }
  }

  /// Helper: Load internal PDFs
  Future<List<BookModel>> _scanImportedPdfs(SharedPreferences prefs) async {
    final appDataDir = await _getAppDataDirectory();
    List<BookModel> pdfs = [];
    try {
      if (!appDataDir.existsSync()) return [];
      for (var folder in appDataDir.listSync()) {
        if (folder is Directory) {
          File? pdfFile;
          File? coverFile;
          for (var f in folder.listSync()) {
            if (f is File) {
              if (p.extension(f.path) == '.pdf') pdfFile = f;
              if (p.basename(f.path).contains('cover')) coverFile = f;
            }
          }
          if (pdfFile != null && coverFile != null) {
            final id = p.basename(folder.path);
            
            // Get Timestamp
            final lastReadMillis = prefs.getInt('last_read_$id');
            final lastRead = lastReadMillis != null 
                ? DateTime.fromMillisecondsSinceEpoch(lastReadMillis) 
                : null;

            pdfs.add(
              BookModel(
                id: id,
                title: p.basenameWithoutExtension(pdfFile.path),
                filePath: pdfFile.path,
                coverPath: coverFile.path,
                type: BookType.pdf,
                author: "Unknown",
                lastRead: lastRead,
              ),
            );
          }
        }
      }
    } catch (_) {}
    return pdfs;
  }

  // ---------------------------------------------------------
  // 🎨 PDF COVER LOGIC
  // ---------------------------------------------------------
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
        final Uint8List pngBytes = img.encodePng(image);
        await targetCoverFile.writeAsBytes(pngBytes);
      }
      await doc.dispose();
    } catch (e) {
      debugPrint("Error generating PDF cover: $e");
    }
  }

  // ---------------------------------------------------------
  // 🎨 EPUB COVER LOGIC
  // ---------------------------------------------------------
  Future<void> _extractEpubCover(File epubFile, File targetCoverFile) async {
    try {
      final bytes = await epubFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      ArchiveFile? containerFile = archive.files.firstWhere(
        (f) => f.name.contains('container.xml'),
        orElse: () => archive.files.first,
      );
      final containerXml = XmlDocument.parse(utf8.decode(containerFile.content as List<int>));
      final rootPath = containerXml.findAllElements('rootfile').first.getAttribute('full-path')!;

      ArchiveFile? opfFile = archive.files.firstWhere(
        (f) => f.name.contains(rootPath),
        orElse: () => archive.files.first,
      );
      final opfXml = XmlDocument.parse(utf8.decode(opfFile.content as List<int>));

      String? coverHref;

      // Layer 1
      String? coverId;
      for (var meta in opfXml.findAllElements('meta')) {
        if (meta.getAttribute('name') == 'cover') coverId = meta.getAttribute('content');
      }
      if (coverId != null) {
        for (var item in opfXml.findAllElements('item')) {
          if (item.getAttribute('id') == coverId) coverHref = item.getAttribute('href');
        }
      }

      // Layer 2
      if (coverHref == null) {
        try {
          final possible = archive.files.firstWhere(
            (f) => f.name.toLowerCase().contains('cover') && 
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
           orElse: () => archive.files.firstWhere((f) => f.name.endsWith('cover.jpg')),
        );
        await targetCoverFile.writeAsBytes(imageFile.content as List<int>);
      }
    } catch (e) {
      debugPrint("Error extracting EPUB cover: $e");
    }
  }
}