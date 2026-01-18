import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'reader_viewmodel.dart';
import '../../models/book_model.dart';

class ReaderView extends StatefulWidget {
  final BookModel book;
  const ReaderView({super.key, required this.book});

  @override
  State<ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends State<ReaderView> {
  late ReaderViewModel _viewModel;
  WebViewController? _webViewController;

  @override
  void initState() {
    super.initState();
    _viewModel = ReaderViewModel(book: widget.book);
    _viewModel.initializeReader();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, child) {
        if (!_viewModel.isReady && _viewModel.errorMessage == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        if (_viewModel.errorMessage != null) {
          return Scaffold(
            appBar: AppBar(title: const Text("Error")),
            body: Center(child: Text(_viewModel.errorMessage!)),
          );
        }

        return Scaffold(
          appBar: AppBar(
            title: Text(
              widget.book.title,
              style: const TextStyle(fontSize: 16),
            ),
            elevation: 1,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          body: widget.book.type == BookType.pdf
              ? _buildPdfViewer()
              : _buildEpubViewer(),
        );
      },
    );
  }

  Widget _buildPdfViewer() {
    return PdfViewer.file(
      widget.book.filePath,
      params: const PdfViewerParams(panEnabled: true),
    );
  }

  Widget _buildEpubViewer() {
    // 1. PREPARE CONTROLLER
    if (_webViewController == null) {
      _webViewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFFFFFFFF))
        ..loadRequest(Uri.parse(_viewModel.epubUrl ?? "about:blank"));
    } else {
      // If controller exists, just load the new URL (Chapter change)
      _webViewController!.loadRequest(
        Uri.parse(_viewModel.epubUrl ?? "about:blank"),
      );
    }

    // 2. THE FLUTTER GESTURE LAYER
    return GestureDetector(
      // We claim the gestures so the WebView doesn't fight us
      behavior: HitTestBehavior.opaque,

      onHorizontalDragEnd: (details) {
        // SENSITIVITY CHECK
        // If primary velocity is high, it's a swipe
        if (details.primaryVelocity! < -300) {
          // SWIPE LEFT -> NEXT PAGE
          _handlePageTurn(1);
        } else if (details.primaryVelocity! > 300) {
          // SWIPE RIGHT -> PREVIOUS PAGE
          _handlePageTurn(-1);
        }
      },

      onTapUp: (details) {
        // Optional: Tap edges to turn
        final width = MediaQuery.of(context).size.width;
        if (details.globalPosition.dx > width * 0.75) {
          _handlePageTurn(1);
        } else if (details.globalPosition.dx < width * 0.25) {
          _handlePageTurn(-1);
        }
      },

      child: WebViewWidget(controller: _webViewController!),
    );
  }

  // --- THE BRIDGE LOGIC ---
  Future<void> _handlePageTurn(int direction) async {
    if (_webViewController == null) return;

    try {
      // 1. COMMAND JS TO TURN PAGE
      // We call the function and get the result back immediately
      final result = await _webViewController!.runJavaScriptReturningResult(
        "tryTurnPage($direction)",
      );

      // 2. PROCESS RESULT
      // result is typically a String like '"edge_next"' (with quotes)
      final status = result.toString().replaceAll('"', '');

      if (status == 'edge_next') {
        // JS says: I'm at the end. Flutter, please load next chapter.
        _goToNextChapter();
      } else if (status == 'edge_prev') {
        // JS says: I'm at the start. Flutter, please load prev chapter.
        _goToPrevChapter();
      } else {
        // Status is 'success', the slide happened in JS. Do nothing.
      }
    } catch (e) {
      debugPrint("Error turning page: $e");
    }
  }

  void _goToNextChapter() {
    if (_viewModel.hasNext) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Loading next chapter..."),
          duration: Duration(milliseconds: 500),
        ),
      );
      _viewModel.nextChapter();
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("End of book")));
    }
  }

  void _goToPrevChapter() {
    if (_viewModel.hasPrevious) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Previous chapter..."),
          duration: Duration(milliseconds: 500),
        ),
      );
      _viewModel.previousChapter();
    }
  }
}
