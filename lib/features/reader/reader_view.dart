import 'package:flutter/material.dart';
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

  // 1. THE CACHE
  // We store the widget instance here so it never gets rebuilt.
  WebViewWidget? _cachedWebView;

  bool _showControls = false;
  bool _isBackwardNav = false;

  @override
  void initState() {
    super.initState();
    _viewModel = ReaderViewModel(book: widget.book);
    _viewModel.initializeReader();
  }

  void _toggleControls() {
    setState(() {
      _showControls = !_showControls;
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, child) {
        if (!_viewModel.isReady) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        // 2. INITIALIZE ONCE
        // We create the WebView only if it doesn't exist yet.
        if (_cachedWebView == null) {
          _initWebView();
        }

        return Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: Colors.white,
          // Static background for immersion
          extendBodyBehindAppBar: true,

          body: Stack(
            children: [
              // 3. USE CACHED INSTANCE
              // Flutter sees this is the same instance and skips all work.
              Positioned.fill(child: _cachedWebView!),

              // 4. FLOATING CONTROLS
              AnimatedPositioned(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeInOut,
                top: _showControls ? 0 : -100,
                left: 0,
                right: 0,
                child: _buildFloatingAppBar(),
              ),
            ],
          ),
        );
      },
    );
  }

  void _initWebView() {
    String finalUrl = _viewModel.epubUrl ?? "about:blank";

    // JS Logic for back navigation
    if (_isBackwardNav) {
      finalUrl += (finalUrl.contains('?') ? "&pos=end" : "?pos=end");
    }

    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF))
      ..addJavaScriptChannel(
        'PrintReader',
        onMessageReceived: (message) => _handleJsMessage(message.message),
      )
      ..loadRequest(Uri.parse(finalUrl));

    // Store it forever
    _cachedWebView = WebViewWidget(controller: _webViewController!);
  }

  Widget _buildFloatingAppBar() {
    final topPadding = MediaQuery.of(context).padding.top;
    return Container(
      height: kToolbarHeight + topPadding,
      padding: EdgeInsets.only(top: topPadding),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.95),
        boxShadow: [
          if (_showControls)
            BoxShadow(
              color: Colors.black12,
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(child: Text(widget.book.title, textAlign: TextAlign.center)),
          IconButton(icon: const Icon(Icons.list), onPressed: _showChapterList),
        ],
      ),
    );
  }

  void _handleJsMessage(String message) {
    if (message == 'toggle_controls') {
      _toggleControls();
    } else if (message == 'next_chapter') {
      if (_viewModel.hasNext) {
        _isBackwardNav = false;
        // We must clear cache because we need a new URL for the new chapter
        _cachedWebView = null;
        _viewModel.nextChapter();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("End of book")));
      }
    } else if (message == 'prev_chapter') {
      if (_viewModel.hasPrevious) {
        _isBackwardNav = true;
        _cachedWebView = null; // Clear cache for new chapter
        _viewModel.previousChapter();
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text("Start of book")));
      }
    }
  }

  void _showChapterList() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Column(
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text("Chapters"),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: _viewModel.spine.length,
                itemBuilder: (context, index) {
                  return ListTile(
                    title: Text("Chapter ${index + 1}"),
                    onTap: () {
                      Navigator.pop(context);
                      _isBackwardNav = false;
                      _cachedWebView = null; // Clear cache
                      _viewModel.jumpToChapter(index);
                    },
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }
}
