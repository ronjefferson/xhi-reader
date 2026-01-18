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

import '../../models/book_model.dart';

class LibraryService {
  static final LibraryService _instance = LibraryService._internal();
  factory LibraryService() => _instance;
  LibraryService._internal();

  static const String _appFolderName = "MyReaderData";

  Future<bool> requestPermission() async {
    if (await Permission.manageExternalStorage.isGranted) return true;
    PermissionStatus status = await Permission.manageExternalStorage.request();
    if (!status.isGranted) status = await Permission.storage.request();
    return status.isGranted;
  }

  Future<Directory> _getAppDataDirectory() async {
    final appDocDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDocDir.path}/$_appFolderName');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  /// SCAN EPUBs
  /// [forceRefresh]: If true, regenerates covers even if they exist.
  Future<List<BookModel>> scanForEpubs({bool forceRefresh = false}) async {
    if (!await requestPermission()) return [];

    // Use string literal to avoid constant errors
    final downloadsPath = await ExternalPath.getExternalStoragePublicDirectory(
      "Download",
    );
    final appDataDir = await _getAppDataDirectory();
    final downloadsDir = Directory(downloadsPath);
    List<BookModel> books = [];

    if (downloadsDir.existsSync()) {
      try {
        List<FileSystemEntity> files = downloadsDir.listSync();
        for (var entity in files) {
          if (entity is File && p.extension(entity.path) == '.epub') {
            final fileName = p.basenameWithoutExtension(entity.path);
            final bookId = fileName.replaceAll(RegExp(r'\s+'), '_');
            final bookDataDir = Directory('${appDataDir.path}/$bookId');
            final coverFile = File('${bookDataDir.path}/cover.png');

            // LOGIC: Process if new OR if we are forcing a refresh
            bool needsProcessing =
                !await bookDataDir.exists() ||
                !await coverFile.exists() ||
                forceRefresh;

            if (needsProcessing) {
              await bookDataDir.create(recursive: true);
              await _extractEpubCover(entity, coverFile);
            }

            books.add(
              BookModel(
                id: bookId,
                title: fileName,
                filePath: entity.path,
                coverPath: coverFile.path,
                type: BookType.epub,
              ),
            );
          }
        }
      } catch (e) {
        debugPrint("Error scanning downloads: $e");
      }
    }

    books.addAll(await _scanImportedPdfs(appDataDir));
    return books;
  }

  /// IMPORT PDF
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

      if (!await bookDataDir.exists())
        await bookDataDir.create(recursive: true);

      final savedPdf = await originalPdf.copy(
        '${bookDataDir.path}/$fileName.pdf',
      );
      final coverFile = File('${bookDataDir.path}/cover.png');
      await _generatePdfCover(savedPdf, coverFile);
    }
  }

  /// Helper: Load internal PDFs
  Future<List<BookModel>> _scanImportedPdfs(Directory appDataDir) async {
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
            pdfs.add(
              BookModel(
                id: p.basename(folder.path),
                title: p.basenameWithoutExtension(pdfFile.path),
                filePath: pdfFile.path,
                coverPath: coverFile.path,
                type: BookType.pdf,
              ),
            );
          }
        }
      }
    } catch (_) {}
    return pdfs;
  }

  // ---------------------------------------------------------
  // 🎨 PDF COVER LOGIC (pdfrx + image package)
  // ---------------------------------------------------------
  Future<void> _generatePdfCover(File pdfFile, File targetCoverFile) async {
    try {
      final doc = await PdfDocument.openFile(pdfFile.path);
      final page = doc.pages[0];

      // Render raw pixels (returns PdfImage)
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
  // 🎨 EPUB COVER LOGIC (The Waterfall Method)
  // ---------------------------------------------------------
  Future<void> _extractEpubCover(File epubFile, File targetCoverFile) async {
    try {
      final bytes = await epubFile.readAsBytes();
      final archive = ZipDecoder().decodeBytes(bytes);

      // --- SETUP: Parse Container & OPF ---
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

      // =========================================================
      // LAYER 1: Standard Metadata
      // =========================================================
      String? coverId;
      for (var meta in opfXml.findAllElements('meta')) {
        if (meta.getAttribute('name') == 'cover')
          coverId = meta.getAttribute('content');
      }
      if (coverId == null) {
        for (var item in opfXml.findAllElements('item')) {
          if (item.getAttribute('properties') == 'cover-image') {
            coverId = item.getAttribute('id');
            break;
          }
        }
      }
      if (coverId != null) {
        for (var item in opfXml.findAllElements('item')) {
          if (item.getAttribute('id') == coverId)
            coverHref = item.getAttribute('href');
        }
      }

      // =========================================================
      // LAYER 2: First Page SVG/Image Hunter (Precaution)
      // =========================================================
      if (coverHref == null) {
        try {
          final spine = opfXml.findAllElements('itemref').toList();
          if (spine.isNotEmpty) {
            final firstId = spine.first.getAttribute('idref');
            String? firstChapterPath;
            for (var item in opfXml.findAllElements('item')) {
              if (item.getAttribute('id') == firstId)
                firstChapterPath = item.getAttribute('href');
            }

            if (firstChapterPath != null) {
              final chapterFile = archive.files.firstWhere(
                (f) => f.name.endsWith(firstChapterPath!),
                orElse: () => archive.files.first,
              );

              final chapterXml = XmlDocument.parse(
                utf8.decode(chapterFile.content as List<int>),
              );

              // A. Look for <image> inside <svg>
              String? foundSrc;
              final images = chapterXml.findAllElements('image');
              if (images.isNotEmpty) {
                final imgTag = images.first;
                foundSrc =
                    imgTag.getAttribute('href') ??
                    imgTag.getAttribute('xlink:href') ??
                    imgTag.attributes
                        .firstWhere(
                          (a) => a.name.local == 'href',
                          orElse: () => imgTag.attributes.first,
                        )
                        .value;
              }

              // B. Look for standard <img>
              if (foundSrc == null) {
                final standardImgs = chapterXml.findAllElements('img');
                if (standardImgs.isNotEmpty) {
                  foundSrc = standardImgs.first.getAttribute('src');
                }
              }

              // VERIFY: Does this file actually exist in the zip?
              if (foundSrc != null) {
                foundSrc = Uri.decodeFull(foundSrc); // Fix %20 spaces
                foundSrc = foundSrc.replaceAll('../', '');
                final filename = p.basename(foundSrc);

                // CRITICAL CHECK: If this file isn't real, don't use it.
                bool exists = archive.files.any(
                  (f) => f.name.endsWith(filename),
                );
                if (exists) {
                  coverHref = foundSrc;
                }
              }
            }
          }
        } catch (e) {
          debugPrint("First page extraction strategy failed: $e");
        }
      }

      // =========================================================
      // LAYER 3: Brute Force Filename (Last Resort)
      // =========================================================
      if (coverHref == null) {
        try {
          final possible = archive.files.firstWhere(
            (f) =>
                f.name.toLowerCase().contains('cover') &&
                (f.name.endsWith('.jpg') ||
                    f.name.endsWith('.png') ||
                    f.name.endsWith('.jpeg')),
          );
          coverHref = possible.name;
        } catch (_) {}
      }

      // =========================================================
      // FINAL EXTRACTION
      // =========================================================
      if (coverHref != null) {
        // Fix URL encoding (e.g. "Cover%20Image.jpg" -> "Cover Image.jpg")
        coverHref = Uri.decodeFull(coverHref!);
        final coverFilename = p.basename(coverHref!);

        try {
          final imageFile = archive.files.firstWhere(
            (f) => f.name.endsWith(coverFilename),
          );
          await targetCoverFile.writeAsBytes(imageFile.content as List<int>);
        } catch (e) {
          debugPrint("Final extraction failed for: $coverFilename");
        }
      }
    } catch (e) {
      debugPrint("Error extracting EPUB cover: $e");
    }
  }
}
