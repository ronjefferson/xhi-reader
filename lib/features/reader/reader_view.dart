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

  // State to track if we should load the end of the next chapter
  bool _isBackwardNav = false;

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
    // 1. CONSTRUCT URL
    // We check our flag to decide if we add '?pos=end'
    String finalUrl = _viewModel.epubUrl ?? "about:blank";

    if (_isBackwardNav) {
      if (finalUrl.contains('?')) {
        finalUrl += "&pos=end";
      } else {
        finalUrl += "?pos=end";
      }
    }

    if (_webViewController == null) {
      _webViewController = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0xFFFFFFFF))
        ..addJavaScriptChannel(
          'PrintReader',
          onMessageReceived: (JavaScriptMessage message) {
            _handleJsMessage(message.message);
          },
        )
        ..loadRequest(Uri.parse(finalUrl));
    } else {
      // Load the new URL (with or without the ?pos=end param)
      _webViewController!.loadRequest(Uri.parse(finalUrl));
    }

    return WebViewWidget(controller: _webViewController!);
  }

  void _handleJsMessage(String message) {
    if (message == 'next_chapter') {
      if (_viewModel.hasNext) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Next chapter..."),
            duration: Duration(milliseconds: 500),
          ),
        );

        // Going forward -> Start at Top
        _isBackwardNav = false;
        _viewModel.nextChapter();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("End of book")));
      }
    } else if (message == 'prev_chapter') {
      if (_viewModel.hasPrevious) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Previous chapter..."),
            duration: Duration(milliseconds: 500),
          ),
        );

        // Going backward -> Start at End
        _isBackwardNav = true;
        _viewModel.previousChapter();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Start of book")));
      }
    }
  }
}
