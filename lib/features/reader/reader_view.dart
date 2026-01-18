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
          appBar: AppBar(title: Text(widget.book.title)),
          body: widget.book.type == BookType.pdf
              ? PdfViewer.file(
                  widget.book.filePath,
                  params: const PdfViewerParams(panEnabled: true),
                )
              : _buildEpubWebView(),

          bottomNavigationBar: widget.book.type == BookType.epub
              ? BottomAppBar(
                  height: 60,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back_ios),
                        onPressed: _viewModel.hasPrevious
                            ? _viewModel.previousChapter
                            : null,
                      ),
                      Text(
                        "Ch ${_viewModel.currentChapterIndex + 1} / ${_viewModel.totalChapters}",
                      ),
                      IconButton(
                        icon: const Icon(Icons.arrow_forward_ios),
                        onPressed: _viewModel.hasNext
                            ? _viewModel.nextChapter
                            : null,
                      ),
                    ],
                  ),
                )
              : null,
        );
      },
    );
  }

  Widget _buildEpubWebView() {
    final controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0x00000000))
      ..loadRequest(Uri.parse(_viewModel.epubUrl ?? "about:blank"));

    return WebViewWidget(controller: controller);
  }
}
