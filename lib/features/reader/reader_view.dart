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

  // UI State
  bool _showControls = false; // Start hidden
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

        return Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: Colors.white,
          body: Stack(
            children: [
              // 1. THE WEBVIEW (Static Background)
              Positioned.fill(child: _buildEpubWebView()),

              // 2. THE TOP BAR (Floating Overlay)
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

  Widget _buildFloatingAppBar() {
    // We add padding for the status bar so the content doesn't overlap time/battery
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
            icon: const Icon(Icons.arrow_back, color: Colors.black87),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Text(
              widget.book.title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.list, color: Colors.black87),
            onPressed: _showChapterList,
          ),
        ],
      ),
    );
  }

  Widget _buildEpubWebView() {
    String finalUrl = _viewModel.epubUrl ?? "about:blank";

    // Add ?pos=end if going backwards
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
          onMessageReceived: (message) => _handleJsMessage(message.message),
        )
        ..loadRequest(Uri.parse(finalUrl));
    } else {
      _webViewController!.loadRequest(Uri.parse(finalUrl));
    }

    // No SafeArea here, let text flow full screen
    return WebViewWidget(controller: _webViewController!);
  }

  void _handleJsMessage(String message) {
    if (message == 'toggle_controls') {
      _toggleControls();
    } else if (message == 'next_chapter') {
      if (_viewModel.hasNext) {
        _isBackwardNav = false;
        _viewModel.nextChapter();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("End of book"),
            duration: Duration(milliseconds: 500),
          ),
        );
      }
    } else if (message == 'prev_chapter') {
      if (_viewModel.hasPrevious) {
        _isBackwardNav = true;
        _viewModel.previousChapter();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Start of book"),
            duration: Duration(milliseconds: 500),
          ),
        );
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
              child: Text(
                "Chapters",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: ListView.builder(
                itemCount: _viewModel.spine.length,
                itemBuilder: (context, index) {
                  final isSelected = index == _viewModel.currentChapterIndex;
                  return ListTile(
                    leading: isSelected
                        ? const Icon(Icons.play_arrow, color: Colors.blue)
                        : const SizedBox(width: 24),
                    title: Text("Chapter ${index + 1}"),
                    onTap: () {
                      Navigator.pop(context);
                      _isBackwardNav = false;
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
