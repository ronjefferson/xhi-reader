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

  // Start with loading true. This will cover the initial rendering.
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

      // If URL changed (New Chapter OR Force Refresh from Slider)
      if (_viewModel.epubUrl != null && _viewModel.epubUrl != _currentUrl) {
        setState(() => _isLoading = true); // SHOW SPINNER
        _currentUrl = _viewModel.epubUrl;
        _controller?.loadRequest(Uri.parse(_currentUrl!));
      }

      // Note: We don't need to handle scroll request here anymore because
      // the URL change handles the flow (Load -> Ready -> Scroll)
    }
  }

  void _executeScroll(double percent) {
    _controller?.runJavaScript('scrollToPercent($percent)');
  }

  void _applyTheme() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    _controller?.runJavaScript('setTheme($isDark)');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bgColor = theme.scaffoldBackgroundColor;
    final txtColor = theme.textTheme.bodyMedium?.color ?? Colors.black;
    final isDark = theme.brightness == Brightness.dark;

    if (!_viewModel.isReady) {
      return Scaffold(
        backgroundColor: bgColor,
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_controller == null) _initWebView(bgColor);

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          // A. THE READER
          SafeArea(child: WebViewWidget(controller: _controller!)),

          // B. LOADING OVERLAY (Hides the "Nudge")
          if (_isLoading)
            Container(
              color: bgColor,
              child: const Center(child: CircularProgressIndicator()),
            ),

          // C. CONTROLS (Top Bar)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            top: _showControls ? 0 : -100,
            left: 0,
            right: 0,
            child: Container(
              height: kToolbarHeight + MediaQuery.of(context).padding.top,
              padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
              color: (isDark ? const Color(0xFF1E1E1E) : Colors.white)
                  .withOpacity(0.95),
              child: Row(
                children: [
                  IconButton(
                    icon: Icon(Icons.arrow_back, color: txtColor),
                    onPressed: () => Navigator.pop(context),
                  ),
                  Expanded(
                    child: Text(
                      widget.book.title,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: txtColor,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.list, color: txtColor),
                    onPressed: _showChapterList,
                  ),
                ],
              ),
            ),
          ),

          // D. CONTROLS (Bottom Bar)
          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            bottom: _showControls ? 0 : -160,
            left: 0,
            right: 0,
            child: Container(
              color: (isDark ? const Color(0xFF1E1E1E) : Colors.white)
                  .withOpacity(0.95),
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "Page ${(_dragValue ?? _viewModel.getCurrentGlobalPage()).toInt()} of ${_viewModel.totalBookPages}",
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                          color: txtColor,
                        ),
                      ),
                      Text(
                        "${(((_dragValue ?? _viewModel.getCurrentGlobalPage().toDouble()) / _viewModel.totalBookPages) * 100).toStringAsFixed(1)}%",
                        style: TextStyle(
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
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value:
                              (_dragValue ??
                                      _viewModel
                                          .getCurrentGlobalPage()
                                          .toDouble())
                                  .clamp(
                                    1.0,
                                    _viewModel.totalBookPages.toDouble(),
                                  ),
                          min: 1.0,
                          max: _viewModel.totalBookPages.toDouble(),
                          activeColor: isDark ? Colors.white : Colors.black87,
                          inactiveColor: Colors.grey[300],
                          onChanged: (val) {
                            setState(() {
                              _dragValue = val;
                            });
                            final location = _viewModel.getPreviewLocation(
                              val.toInt(),
                            );
                            if (location['chapterIndex'] ==
                                _viewModel.currentChapterIndex) {
                              // Optional: live preview scroll if desired, but risky if you want full refresh
                            }
                          },
                          onChangeEnd: (val) {
                            // Trigger the refresh/jump
                            _viewModel.jumpToGlobalPage(val.toInt());
                            setState(() {
                              _dragValue = null;
                            });
                          },
                        ),
                      ),
                      Text(
                        "${_viewModel.totalBookPages}",
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _initWebView(Color bgColor) {
    _currentUrl = _viewModel.epubUrl;
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(bgColor)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            // Wait for 'ready' message
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
    if (message == 'ready') {
      _applyTheme();

      // 1. PERFORM SCROLL (While hidden)
      if (_viewModel.requestScrollToProgress != null) {
        _executeScroll(_viewModel.requestScrollToProgress!);
        _viewModel.requestScrollToProgress = null;
      }

      // 2. DELAYED REVEAL (The Fix for the "Nudge")
      // Wait 500ms for the scroll to render properly behind the spinner
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) setState(() => _isLoading = false);
      });
    } else if (message == 'toggle_controls') {
      setState(() => _showControls = !_showControls);
    } else if (message == 'next_chapter') {
      _viewModel.nextChapter();
    } else if (message == 'prev_chapter') {
      _viewModel.previousChapter();
    } else if (message.startsWith('progress:')) {
      final val = double.tryParse(message.split(':')[1]) ?? 0.0;
      if (_dragValue == null) _viewModel.updateScrollProgress(val);
    }
  }

  void _showChapterList() {
    // ... (Same Chapter List Code as Checkpoint 4) ...
    // Just ensure it uses the context theme correctly
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    final txtColor =
        Theme.of(context).textTheme.bodyMedium?.color ?? Colors.black;

    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                "Table of Contents",
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: txtColor,
                ),
              ),
            ),
            Expanded(
              child: ListView.separated(
                itemCount: _viewModel.chapterTitles.length,
                separatorBuilder: (c, i) =>
                    Divider(height: 1, color: Colors.grey.withOpacity(0.3)),
                itemBuilder: (context, index) {
                  bool isCurrent = index == _viewModel.currentChapterIndex;
                  return ListTile(
                    title: Text(
                      _viewModel.chapterTitles[index],
                      style: TextStyle(
                        fontWeight: isCurrent
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isCurrent ? Colors.blue : txtColor,
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
}
