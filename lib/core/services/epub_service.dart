import 'dart:io';
import 'package:flutter/services.dart' show rootBundle;
import 'package:archive/archive.dart';
import 'package:xml/xml.dart';
import 'package:path/path.dart' as p;
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_static/shelf_static.dart';

class EpubService {
  // Singleton Pattern
  static final EpubService _instance = EpubService._internal();
  factory EpubService() => _instance;
  EpubService._internal();

  HttpServer? _server;
  static const int _port = 8080;

  /// Starts the local server and copies necessary assets (CSS/JS) to storage.
  Future<void> startServer(String appDocPath) async {
    if (_server != null) return;

    // 1. COPY READER ASSETS
    // We copy reader.css and reader.js from the app bundle to the documents directory
    // so they can be served as static files at "http://localhost:8080/reader.css"
    await _copyAssetsToStorage(appDocPath);

    // 2. STATIC FILE HANDLER
    // Serves files from the app documents directory (where books and assets live)
    var staticHandler = createStaticHandler(
      appDocPath,
      defaultDocument: 'index.html',
    );

    // 3. INJECTION MIDDLEWARE
    // This is the most critical part. It intercepts every HTML chapter request
    // and injects the viewport settings, CSS, and JS required for the reader to work.
    final pipeline = Pipeline()
        .addMiddleware((innerHandler) {
          return (request) async {
            final response = await innerHandler(request);
            final path = request.url.path.toLowerCase();

            // Check if the requested file is an HTML chapter
            if (response.statusCode == 200 &&
                (path.endsWith('.html') ||
                    path.endsWith('.xhtml') ||
                    path.endsWith('.htm'))) {
              final bodyBytes = await response.read().toList();
              final originalBody = String.fromCharCodes(
                bodyBytes.expand((x) => x),
              );

              // --- CRITICAL INJECTION ---
              // 1. Viewport: 'width=device-width' is MANDATORY for 100vw to work correctly.
              // 2. CSS/JS: Links to the files we copied in Step 1.
              const String tagsToInject = '''
            <meta name="viewport" content="width=device-width, height=device-height, initial-scale=1.0, maximum-scale=1.0, user-scalable=no, viewport-fit=cover">
            <link rel="stylesheet" href="/reader.css">
            <script src="/reader.js"></script>
          ''';

              String modifiedBody;
              // Inject into <head> if it exists, otherwise prepend it to the body
              if (originalBody.contains('</head>')) {
                modifiedBody = originalBody.replaceFirst(
                  '</head>',
                  '$tagsToInject</head>',
                );
              } else {
                modifiedBody = '<head>$tagsToInject</head>$originalBody';
              }

              // Return modified HTML
              return Response.ok(
                modifiedBody,
                headers: {
                  ...response.headers,
                  'content-type': 'text/html; charset=utf-8',
                },
              );
            }

            // Add CORS headers for other files (images, fonts)
            return response.change(
              headers: {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET, POST',
              },
            );
          };
        })
        .addHandler(staticHandler);

    // 4. BIND SERVER
    // We bind to 0.0.0.0 to ensure the Android WebView can reach it via localhost
    _server = await shelf_io.serve(pipeline, '0.0.0.0', _port);
    print('EpubServer running on port $_port');
  }

  /// Stops the server to free up the port
  void stopServer() {
    _server?.close();
    _server = null;
  }

  // --- HELPER: Copy Assets ---
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
      print("Error copying reader templates: $e");
      print(
        "Make sure 'assets/reader.css' and 'assets/reader.js' are in your pubspec.yaml!",
      );
    }
  }

  // --- EPUB PARSING LOGIC ---

  /// Extracts the EPUB and returns a list of fully qualified localhost URLs for the spine (chapters).
  Future<List<String>> getSpineUrls(
    File epubFile,
    String bookId,
    String appDocPath,
  ) async {
    final bookDir = Directory('$appDocPath/books/$bookId');
    final rawDir = Directory('${bookDir.path}/raw');

    // 1. Unzip if not already extracted
    if (!await rawDir.exists()) {
      await _unzipBook(epubFile, rawDir);
    }

    // 2. Parse the OPF file to get the spine (chapter order)
    final opfData = await _parseOpf(rawDir);
    if (opfData == null) return [];

    final rootFolder = opfData['rootFolder'] as String;
    final spinePaths = opfData['spinePaths'] as List<String>;

    // 3. Convert relative paths to localhost URLs
    return spinePaths.map((path) {
      // Handle paths that might be inside a subfolder (e.g. OEBPS/chapter1.html)
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
      // 1. Locate the .opf file using META-INF/container.xml
      final containerFile = File('${rawDir.path}/META-INF/container.xml');
      if (!containerFile.existsSync()) return null;

      final containerXml = XmlDocument.parse(
        await containerFile.readAsString(),
      );
      final rootfile = containerXml.findAllElements('rootfile').first;
      final opfPath = rootfile.getAttribute('full-path')!;

      final opfFile = File('${rawDir.path}/$opfPath');
      final opfXml = XmlDocument.parse(await opfFile.readAsString());

      // 2. Map Manifest IDs to File Paths
      final manifest = <String, String>{};
      for (var item in opfXml.findAllElements('item')) {
        manifest[item.getAttribute('id')!] = item.getAttribute('href')!;
      }

      // 3. Build Spine (Ordered List of Paths)
      final spinePaths = <String>[];
      for (var itemref in opfXml.findAllElements('itemref')) {
        final id = itemref.getAttribute('idref');
        if (manifest.containsKey(id)) {
          spinePaths.add(manifest[id]!);
        }
      }

      // 4. Determine Root Folder (e.g., if OPF is in OEBPS folder)
      String rootFolder = "";
      if (opfPath.contains('/')) {
        rootFolder = p.dirname(opfPath);
      }

      return {'rootFolder': rootFolder, 'spinePaths': spinePaths};
    } catch (e) {
      print("Error parsing OPF: $e");
      return null;
    }
  }
}
