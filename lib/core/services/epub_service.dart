import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';

class EpubService {
  static final EpubService _instance = EpubService._internal();
  factory EpubService() => _instance;
  EpubService._internal();

  HttpServer? _server;
  static const int _port = 8080;

  /// Starts the local server and copies necessary assets
  Future<void> startServer(String appDocPath) async {
    if (_server != null) return;

    // 1. COPY TEMPLATES: Assets -> Device Storage
    // This allows the server to serve physical files 'reader.css' and 'reader.js'
    await _copyAssetsToStorage(appDocPath);

    // 2. STATIC HANDLER: Serve the AppDocPath (where books AND templates are)
    // defaultDocument is index.html, though we usually request specific chapters
    var staticHandler = createStaticHandler(
      appDocPath,
      defaultDocument: 'index.html',
    );

    // 3. MIDDLEWARE: Intercept HTML files and inject links to templates
    final pipeline = Pipeline()
        .addMiddleware((innerHandler) {
          return (request) async {
            final response = await innerHandler(request);
            final path = request.url.path.toLowerCase();

            // Only modify HTML files (chapters)
            if (response.statusCode == 200 &&
                (path.endsWith('.html') ||
                    path.endsWith('.xhtml') ||
                    path.endsWith('.htm'))) {
              final bodyBytes = await response.read().toList();
              final originalBody = String.fromCharCodes(
                bodyBytes.expand((x) => x),
              );

              // --- INJECTION PAYLOAD ---
              // 1. Viewport: Critical for 100vw to match screen width on mobile
              // 2. CSS: Handles the layout (Sliding columns)
              // 3. JS: Handles the logic (Touch gestures & Slide animation)
              const String tagsToInject = '''
            <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
            <link rel="stylesheet" href="/reader.css">
            <script src="/reader.js"></script>
          ''';

              String modifiedBody;
              // Inject into <head> if it exists, otherwise prepend it
              if (originalBody.contains('</head>')) {
                modifiedBody = originalBody.replaceFirst(
                  '</head>',
                  '$tagsToInject</head>',
                );
              } else {
                modifiedBody = '<head>$tagsToInject</head>$originalBody';
              }

              return Response.ok(
                modifiedBody,
                headers: {
                  ...response.headers,
                  'content-type': 'text/html; charset=utf-8',
                },
              );
            }

            // For non-HTML files (images, css), allow CORS just in case
            return response.change(
              headers: {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET, POST',
              },
            );
          };
        })
        .addHandler(staticHandler);

    // Bind to all interfaces (0.0.0.0) so the WebView can reach it via localhost
    _server = await shelf_io.serve(pipeline, '0.0.0.0', _port);
  }

  void stopServer() {
    _server?.close();
    _server = null;
  }

  // --- HELPER: Copy Assets to Real Files ---
  Future<void> _copyAssetsToStorage(String appDocPath) async {
    try {
      // Copy CSS
      final cssData = await rootBundle.loadString('assets/reader.css');
      final cssFile = File('$appDocPath/reader.css');
      await cssFile.writeAsString(cssData);

      // Copy JS
      final jsData = await rootBundle.loadString('assets/reader.js');
      final jsFile = File('$appDocPath/reader.js');
      await jsFile.writeAsString(jsData);
    } catch (e) {
      // Log error if assets are missing (ensure they are in pubspec.yaml)
      print("Error copying reader templates: $e");
    }
  }

  // --- STANDARD EPUB PARSING LOGIC ---
  Future<List<String>> getSpineUrls(
    File epubFile,
    String bookId,
    String appDocPath,
  ) async {
    final bookDir = Directory('$appDocPath/books/$bookId');
    final rawDir = Directory('${bookDir.path}/raw');

    // Extract if not already extracted
    if (!await rawDir.exists()) {
      await _unzipBook(epubFile, rawDir);
    }

    final opfData = await _parseOpf(rawDir);
    if (opfData == null) return [];

    final rootFolder = opfData['rootFolder'] as String;
    final spinePaths = opfData['spinePaths'] as List<String>;

    // Generate localhost URLs for the WebView
    return spinePaths.map((path) {
      final cleanPath = rootFolder.isNotEmpty ? '$rootFolder/$path' : path;
      return 'http://localhost:$_port/books/$bookId/raw/$cleanPath';
    }).toList();
  }

  Future<void> _unzipBook(File epubFile, Directory targetDir) async {
    await targetDir.create(recursive: true);
    final bytes = await epubFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final file in archive) {
      final filename = file.name;
      if (file.isFile) {
        final data = file.content as List<int>;
        File('${targetDir.path}/$filename')
          ..createSync(recursive: true)
          ..writeAsBytesSync(data);
      }
    }
  }

  Future<Map<String, dynamic>?> _parseOpf(Directory rawDir) async {
    try {
      // 1. Find the .opf file via container.xml
      final containerFile = File('${rawDir.path}/META-INF/container.xml');
      if (!containerFile.existsSync()) return null;

      final containerXml = XmlDocument.parse(
        await containerFile.readAsString(),
      );
      final rootfile = containerXml.findAllElements('rootfile').first;
      final opfPath = rootfile.getAttribute('full-path')!;
      final opfFile = File('${rawDir.path}/$opfPath');
      final opfXml = XmlDocument.parse(await opfFile.readAsString());

      // 2. Map IDs to Hrefs (Manifest)
      final manifest = <String, String>{};
      for (var item in opfXml.findAllElements('item')) {
        manifest[item.getAttribute('id')!] = item.getAttribute('href')!;
      }

      // 3. Get Reading Order (Spine)
      final spinePaths = <String>[];
      for (var itemref in opfXml.findAllElements('itemref')) {
        final id = itemref.getAttribute('idref');
        if (manifest.containsKey(id)) {
          spinePaths.add(manifest[id]!);
        }
      }

      // 4. Handle subfolders (if OPF is in OEBPS/)
      String rootFolder = "";
      if (opfPath.contains('/')) rootFolder = p.dirname(opfPath);

      return {'rootFolder': rootFolder, 'spinePaths': spinePaths};
    } catch (e) {
      return null;
    }
  }
}
