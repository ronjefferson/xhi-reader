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
        // 1. Loading State
        if (!_viewModel.isReady && _viewModel.errorMessage == null) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // 2. Error State
        if (_viewModel.errorMessage != null) {
          return Scaffold(
            appBar: AppBar(title: const Text("Error")),
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Text(
                  _viewModel.errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.red),
                ),
              ),
            ),
          );
        }

        // 3. Reader UI
        return Scaffold(
          appBar: AppBar(
            title: Text(
              widget.book.title,
              style: const TextStyle(fontSize: 16),
            ),
            centerTitle: true,
            elevation: 1,
            leading: IconButton(
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.pop(context),
            ),
          ),

          // Switch between PDF and EPUB
          body: widget.book.type == BookType.pdf
              ? _buildPdfViewer()
              : _buildEpubWebView(),
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

  Widget _buildEpubWebView() {
    // If we haven't created the controller yet, initialize it.
    if (_webViewController == null) {
      _webViewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFFFFFFFF)) // Prevents black flash
        // Listen for signals from assets/reader.js
        ..addJavaScriptChannel(
          'PrintReader',
          onMessageReceived: (JavaScriptMessage message) {
            _handleJsMessage(message.message);
          },
        )
        ..loadRequest(Uri.parse(_viewModel.epubUrl ?? "about:blank"));
    } else {
      // If controller exists, just update the URL when the chapter changes
      // This is more efficient than rebuilding the whole widget
      final currentUrl = _viewModel.epubUrl ?? "about:blank";
      _webViewController!.loadRequest(Uri.parse(currentUrl));
    }

    // Return the widget directly.
    // CRITICAL: No GestureDetector here. We let the WebView handle swipes natively.
    return WebViewWidget(controller: _webViewController!);
  }

  // --- Logic to handle JS Signals ---
  void _handleJsMessage(String message) {
    if (message == 'next_chapter') {
      if (_viewModel.hasNext) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Loading next chapter..."),
            duration: Duration(milliseconds: 700),
          ),
        );
        _viewModel.nextChapter();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("You have reached the end of the book."),
          ),
        );
      }
    } else if (message == 'prev_chapter') {
      if (_viewModel.hasPrevious) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Previous chapter..."),
            duration: Duration(milliseconds: 700),
          ),
        );
        _viewModel.previousChapter();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("This is the first chapter.")),
        );
      }
    }
  }
}
