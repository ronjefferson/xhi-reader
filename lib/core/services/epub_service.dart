import 'dart:io';
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

  Future<void> startServer(String appDocPath) async {
    if (_server != null) return;
    var handler = createStaticHandler(
      appDocPath,
      defaultDocument: 'index.html',
    );
    final pipeline = Pipeline()
        .addMiddleware((innerHandler) {
          return (request) async {
            final response = await innerHandler(request);
            return response.change(
              headers: {
                'Access-Control-Allow-Origin': '*',
                'Access-Control-Allow-Methods': 'GET, POST',
              },
            );
          };
        })
        .addHandler(handler);
    _server = await shelf_io.serve(pipeline, '0.0.0.0', _port);
  }

  void stopServer() {
    _server?.close();
    _server = null;
  }

  // Returns list of URLs for chapters
  Future<List<String>> getSpineUrls(
    File epubFile,
    String bookId,
    String appDocPath,
  ) async {
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
      // Ensure we don't double slash
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
      final containerFile = File('${rawDir.path}/META-INF/container.xml');
      if (!containerFile.existsSync()) return null;

      final containerXml = XmlDocument.parse(
        await containerFile.readAsString(),
      );
      final rootfile = containerXml.findAllElements('rootfile').first;
      final opfPath = rootfile.getAttribute('full-path')!;
      final opfFile = File('${rawDir.path}/$opfPath');
      final opfXml = XmlDocument.parse(await opfFile.readAsString());

      final manifest = <String, String>{};
      for (var item in opfXml.findAllElements('item')) {
        manifest[item.getAttribute('id')!] = item.getAttribute('href')!;
      }

      final spinePaths = <String>[];
      for (var itemref in opfXml.findAllElements('itemref')) {
        final id = itemref.getAttribute('idref');
        if (manifest.containsKey(id)) {
          spinePaths.add(manifest[id]!);
        }
      }

      String rootFolder = "";
      if (opfPath.contains('/')) rootFolder = p.dirname(opfPath);

      return {'rootFolder': rootFolder, 'spinePaths': spinePaths};
    } catch (e) {
      return null;
    }
  }
}
