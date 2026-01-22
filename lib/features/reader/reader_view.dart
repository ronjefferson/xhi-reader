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
  WebViewController? _controller;

  bool _showControls = false;

  // --- LOADING STATE ---
  // Start true so we see spinner immediately
  bool _isLoading = true;

  String? _currentUrl;
  double? _dragValue;

  @override
  void initState() {
    super.initState();
    _viewModel = ReaderViewModel(book: widget.book);
    _viewModel.addListener(_onViewModelUpdate);
    _viewModel.initializeReader();
  }

  @override
  void dispose() {
    _viewModel.removeListener(_onViewModelUpdate);
    super.dispose();
  }

  void _onViewModelUpdate() {
    if (mounted) {
      if (_dragValue == null) setState(() {});

      if (_viewModel.epubUrl != null && _viewModel.epubUrl != _currentUrl) {
        // NEW URL LOADING:
        // 1. Show Spinner
        setState(() => _isLoading = true);

        _currentUrl = _viewModel.epubUrl;

        // Reset progress locally
        if (!_viewModel.epubUrl!.contains('pos=end')) {
          _viewModel.updateScrollProgress(0.0);
        }

        _controller?.loadRequest(Uri.parse(_currentUrl!));
      } else if (_viewModel.requestScrollToProgress != null) {
        _executeScroll(_viewModel.requestScrollToProgress!);
        _viewModel.requestScrollToProgress = null;
      }
    }
  }

  void _executeScroll(double percent) {
    _controller?.runJavaScript('scrollToPercent($percent)');
  }

  @override
  Widget build(BuildContext context) {
    // 1. Initial ViewModel Loading
    if (!_viewModel.isReady) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_controller == null) _initWebView();

    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // A. THE READER
          SafeArea(child: WebViewWidget(controller: _controller!)),

          // B. LOADING SPINNER OVERLAY
          // Covers the WebView while it loads/scrolls to position
          if (_isLoading)
            Container(
              color: Colors.white, // Opaque cover
              child: const Center(child: CircularProgressIndicator()),
            ),

          // C. CONTROLS (Top Bar)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            top: _showControls && !_isLoading
                ? 0
                : -100, // Hide controls while loading
            left: 0,
            right: 0,
            child: _buildTopBar(),
          ),

          // D. CONTROLS (Bottom Bar)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            bottom: _showControls && !_isLoading ? 0 : -160,
            left: 0,
            right: 0,
            child: _buildBottomBar(),
          ),
        ],
      ),
    );
  }

  void _initWebView() {
    _currentUrl = _viewModel.epubUrl;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            // Apply pending scroll (e.g. from slider)
            if (_viewModel.requestScrollToProgress != null) {
              _executeScroll(_viewModel.requestScrollToProgress!);
              _viewModel.requestScrollToProgress = null;
            }
            // Note: We do NOT set _isLoading = false here.
            // We wait for the 'ready' message from JS.
          },
        ),
      )
      ..addJavaScriptChannel(
        'PrintReader',
        onMessageReceived: (m) => _handleJsMessage(m.message),
      )
      ..loadRequest(Uri.parse(_currentUrl!));
  }

  void _handleJsMessage(String message) {
    // 1. HANDLE READY SIGNAL
    if (message == 'ready') {
      setState(() {
        _isLoading = false; // Hide spinner, show content
      });
    }
    // 2. CONTROLS
    else if (message == 'toggle_controls') {
      setState(() => _showControls = !_showControls);
    }
    // 3. NAVIGATION
    else if (message == 'next_chapter') {
      _viewModel.nextChapter();
    } else if (message == 'prev_chapter') {
      _viewModel.previousChapter();
    }
    // 4. PROGRESS
    else if (message.startsWith('progress:')) {
      final val = double.tryParse(message.split(':')[1]) ?? 0.0;
      if (_dragValue == null) _viewModel.updateScrollProgress(val);
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
                "Table of Contents",
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: _viewModel.chapterTitles.length,
                separatorBuilder: (c, i) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  bool isCurrent = index == _viewModel.currentChapterIndex;
                  return ListTile(
                    title: Text(
                      _viewModel.chapterTitles[index],
                      style: TextStyle(
                        fontWeight: isCurrent
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isCurrent ? Colors.blue : Colors.black87,
                      ),
                    ),
                    trailing: isCurrent
                        ? const Icon(Icons.check, color: Colors.blue, size: 20)
                        : null,
                    onTap: () {
                      Navigator.pop(context);
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

  Widget _buildTopBar() {
    return Container(
      height: kToolbarHeight + MediaQuery.of(context).padding.top,
      padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
      color: Colors.white.withOpacity(0.95),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
          Expanded(
            child: Text(
              widget.book.title,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
          ),
          IconButton(icon: const Icon(Icons.list), onPressed: _showChapterList),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final double displayValue =
        _dragValue ?? _viewModel.getCurrentGlobalPage().toDouble();
    final int totalGlobal = _viewModel.totalBookPages;
    final String percentStr =
        "${((displayValue / totalGlobal) * 100).toStringAsFixed(1)}%";

    return Container(
      color: Colors.white.withOpacity(0.95),
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Page ${displayValue.toInt()} of $totalGlobal",
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
              Text(
                percentStr,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                  color: Colors.grey,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Text(
                "1",
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
              Expanded(
                child: Slider(
                  value: displayValue.clamp(1.0, totalGlobal.toDouble()),
                  min: 1.0,
                  max: totalGlobal.toDouble(),
                  activeColor: Colors.black87,
                  inactiveColor: Colors.grey[300],
                  onChanged: (val) {
                    setState(() {
                      _dragValue = val;
                    });
                    final location = _viewModel.getPreviewLocation(val.toInt());
                    if (location['chapterIndex'] ==
                        _viewModel.currentChapterIndex) {
                      _executeScroll(location['percent']);
                    }
                  },
                  onChangeEnd: (val) {
                    _viewModel.jumpToGlobalPage(val.toInt());
                    setState(() {
                      _dragValue = null;
                    });
                  },
                ),
              ),
              Text(
                "$totalGlobal",
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
