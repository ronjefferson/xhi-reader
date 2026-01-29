import 'dart:io';
import 'dart:convert'; // REQUIRED for utf8.decode
import 'package:flutter/services.dart' show rootBundle;
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';

class EpubService {
  static final EpubService _instance = EpubService._internal();
  factory EpubService() => _instance;
  EpubService._internal();

  HttpServer? _server;
  static const int _port = 4545;

  String? _cachedJs;
  String? _cachedCss;

  Future<void> startServer(String appDocPath) async {
    if (_server != null) return;

    // 1. Pre-load assets
    _cachedJs = await rootBundle.loadString('assets/reader.js');
    _cachedCss = await rootBundle.loadString('assets/reader.css');

    var staticHandler = createStaticHandler(
      appDocPath,
      defaultDocument: 'index.html',
    );

    final pipeline = Pipeline()
        .addMiddleware((innerHandler) {
          return (request) async {
            final response = await innerHandler(request);
            final path = request.url.path.toLowerCase();

            // 2. INTERCEPT HTML FILES
            if (response.statusCode == 200 &&
                (path.endsWith('.html') || path.endsWith('.xhtml'))) {
              final bodyBytes = await response.read().toList();
              final allBytes = bodyBytes.expand((x) => x).toList();

              // --- THE FIX ---
              // We force UTF-8 decoding here.
              // This fixes the "â€œ" garbage characters before they leave the server.
              final originalBody = utf8.decode(allBytes, allowMalformed: true);
              // ----------------

              final String cssTag = '<style>$_cachedCss</style>';
              final String jsTag = '<script>$_cachedJs</script>';
              // Viewport meta is critical for mobile scaling
              final String metaTag =
                  '<meta name="viewport" content="width=device-width, height=device-height, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">';

              String modified = originalBody;

              // A. Inject Head Items (Meta + CSS)
              if (modified.contains('<head>')) {
                modified = modified.replaceFirst(
                  '<head>',
                  '<head>$metaTag$cssTag',
                );
              } else {
                modified = '<head>$metaTag$cssTag</head>$modified';
              }

              // B. Wrap Body with div id="viewer" (For your scrolling logic)
              if (modified.contains('<body')) {
                modified = modified.replaceFirstMapped(
                  RegExp(r'<body[^>]*>', caseSensitive: false),
                  (match) => '${match.group(0)}<div id="viewer">',
                );

                modified = modified.replaceFirst(
                  '</body>',
                  '</div>$jsTag</body>',
                );
              } else {
                modified =
                    '<body><div id="viewer">$modified</div>$jsTag</body>';
              }

              return Response.ok(
                modified,
                headers: {
                  ...response.headers,
                  // C. Tell WebView this is definitely UTF-8
                  'content-type': 'text/html; charset=utf-8',
                },
              );
            }
            return response;
          };
        })
        .addHandler(staticHandler);

    try {
      _server = await shelf_io.serve(pipeline, InternetAddress.anyIPv4, _port);
      print('EpubServer running on http://127.0.0.1:$_port');
    } catch (e) {
      print("Error starting server: $e");
    }
  }

  // --- STANDARD EPUB PARSING (Unchanged) ---

  Future<List<String>> getSpineUrls(
    File epubFile,
    String bookId,
    String appDocPath,
  ) async {
    try {
      final bookDir = Directory('$appDocPath/books/$bookId');
      final rawDir = Directory('${bookDir.path}/raw');

      if (!await rawDir.exists()) {
        await _unzipBook(epubFile, rawDir);
      }

      final opfData = await _parseOpf(rawDir);
      if (opfData == null) return [];

      final rootFolder = opfData['rootFolder'] as String;
      final spinePaths = opfData['spinePaths'] as List<String>;

      return spinePaths.map((path) {
        final cleanPath = rootFolder.isNotEmpty ? '$rootFolder/$path' : path;
        return 'http://127.0.0.1:$_port/books/$bookId/raw/$cleanPath';
      }).toList();
    } catch (e) {
      print("Error getting spine: $e");
      return [];
    }
  }

  Future<int> countPagesForChapter(String localPath) async {
    try {
      final file = File(localPath);
      if (!await file.exists()) return 1;
      // Also ensure page counting reads UTF-8
      String content = await file.readAsString(encoding: utf8);

      bool hasImages =
          content.contains('<img') ||
          content.contains('<svg') ||
          content.contains('<image');
      String plainText = content
          .replaceAll(RegExp(r'<[^>]*>'), ' ')
          .replaceAll(RegExp(r'\s+'), ' ');

      int textPages = (plainText.length / 1200).ceil();
      if (textPages <= 0) return hasImages ? 1 : 1;
      return textPages;
    } catch (e) {
      return 1;
    }
  }

  Future<void> _unzipBook(File epubFile, Directory outputDir) async {
    final bytes = await epubFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);
    for (final file in archive) {
      final filename = file.name;
      if (file.isFile) {
        final data = file.content as List<int>;
        File('${outputDir.path}/$filename')
          ..createSync(recursive: true)
          ..writeAsBytesSync(data);
      }
    }
  }

  Future<Map<String, dynamic>?> _parseOpf(Directory rawDir) async {
    try {
      final containerFile = File('${rawDir.path}/META-INF/container.xml');
      if (!await containerFile.exists()) return null;

      final containerXml = XmlDocument.parse(
        await containerFile.readAsString(),
      );
      final rootfile = containerXml.findAllElements('rootfile').first;
      String opfPath = rootfile.getAttribute('full-path')!;

      final opfFile = File('${rawDir.path}/$opfPath');
      if (!await opfFile.exists()) return null;

      final opfXml = XmlDocument.parse(await opfFile.readAsString());
      final manifest = <String, String>{};

      for (var item in opfXml.findAllElements('item')) {
        final id = item.getAttribute('id');
        final href = item.getAttribute('href');
        if (id != null && href != null) manifest[id] = href;
      }

      final spinePaths = <String>[];
      for (var itemref in opfXml.findAllElements('itemref')) {
        final idref = itemref.getAttribute('idref');
        if (idref != null && manifest.containsKey(idref))
          spinePaths.add(manifest[idref]!);
      }

      String rootFolder = "";
      if (opfPath.contains('/'))
        rootFolder = opfPath.substring(0, opfPath.lastIndexOf('/'));

      return {'rootFolder': rootFolder, 'spinePaths': spinePaths};
    } catch (e) {
      return null;
    }
  }
}
