import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

import 'reader_viewmodel.dart';
import '../../models/book_model.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/api_service.dart';

class ReaderView extends StatefulWidget {
  final BookModel book;
  const ReaderView({super.key, required this.book});

  @override
  State<ReaderView> createState() => _ReaderViewState();
}

class _ReaderViewState extends State<ReaderView> {
  late ReaderViewModel _viewModel;
  WebViewController? _controller;
  Timer? _spinnerSafetyTimer;

  bool _showControls = false;
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
    _spinnerSafetyTimer?.cancel();
    _viewModel.removeListener(_onViewModelUpdate);
    super.dispose();
  }

  void _onViewModelUpdate() {
    if (mounted) {
      if (_dragValue == null) setState(() {});
      if (_viewModel.epubUrl != null && _viewModel.epubUrl != _currentUrl) {
        _currentUrl = _viewModel.epubUrl;
        _loadContent(_currentUrl!);
      }
    }
  }

  void _loadContent(String url) {
    _startLoading();
    final uri = Uri.parse(url);

    if (widget.book.isLocal) {
      _controller?.loadRequest(uri);
    } else {
      _controller?.loadRequest(uri, headers: _getAuthHeaders());
    }
  }

  void _startLoading() {
    setState(() => _isLoading = true);
    _spinnerSafetyTimer?.cancel();
    _spinnerSafetyTimer = Timer(const Duration(seconds: 3), () {
      if (mounted && _isLoading) setState(() => _isLoading = false);
    });
  }

  Map<String, String> _getAuthHeaders() {
    if (widget.book.isLocal) return {};
    final token = AuthService().token;
    return {
      if (token != null) 'Authorization': 'Bearer $token',
      'ngrok-skip-browser-warning': 'true',
    };
  }

  void _executeScroll(double percent) {
    _controller?.runJavaScript(
      'if(window.scrollToPercent) window.scrollToPercent($percent);',
    );
  }

  void _applyTheme() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    _controller?.runJavaScript('if(window.setTheme) window.setTheme($isDark);');
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
          SafeArea(child: WebViewWidget(controller: _controller!)),

          if (_isLoading)
            GestureDetector(
              onTap: () => setState(() => _showControls = !_showControls),
              behavior: HitTestBehavior.opaque,
              child: Container(
                color: bgColor,
                child: const Center(child: CircularProgressIndicator()),
              ),
            ),

          // Top Bar
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

          // Bottom Bar
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
                      const Text(
                        "1",
                        style: TextStyle(fontSize: 12, color: Colors.grey),
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
                          onChanged: _isLoading
                              ? null
                              : (val) => setState(() => _dragValue = val),
                          onChangeEnd: _isLoading
                              ? null
                              : (val) {
                                  _viewModel.jumpToGlobalPage(val.toInt());
                                  setState(() => _dragValue = null);
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
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(bgColor)
      ..setUserAgent("MyBookReader/1.0")
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            if (!widget.book.isLocal) _injectOnlineAssets();
          },
          onWebResourceError: (error) {
            if (mounted) setState(() => _isLoading = false);
          },
        ),
      )
      ..addJavaScriptChannel(
        'PrintReader',
        onMessageReceived: (m) => _handleJsMessage(m.message),
      );

    if (_viewModel.epubUrl != null) {
      _loadContent(_viewModel.epubUrl!);
    }
  }

  void _injectOnlineAssets() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgHex = isDark ? '#121212' : '#FFFFFF';
    final textHex = isDark ? '#E0E0E0' : '#000000';
    final token = AuthService().token ?? '';
    final apiBaseUrl = ApiService.baseUrl;

    const String rawCss = r'''
      * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
      html { height: 100vh !important; width: 100vw !important; overflow: hidden !important; margin: 0 !important; padding: 0 !important; background-color: #ffffff !important; touch-action: pan-y !important; -webkit-user-select: none; user-select: none; }
      body { height: calc(100vh - 80px) !important; width: 100vw !important; margin: 40px 0 !important; padding: 0 !important; border: none !important; overflow: visible !important; column-width: 100vw !important; column-gap: 0px !important; column-fill: auto !important; font-family: sans-serif !important; font-size: 18px !important; line-height: 1.6 !important; text-align: justify; transform: translate3d(0,0,0); backface-visibility: hidden; }
      p, h1, h2, h3 { margin-left: 20px !important; margin-right: 20px !important; }
      img { max-width: calc(100vw - 40px) !important; max-height: 100% !important; object-fit: contain !important; display: block !important; margin: 0 auto !important; }
      html.dark-mode { background-color: #121212 !important; }
      body.dark-mode { color: #e0e0e0 !important; background-color: #121212 !important; }
    ''';

    const String rawJs = r'''
      (function() {
          function post(msg) { if(window.PrintReader) window.PrintReader.postMessage(msg); }
          function getWidth() { return document.documentElement.clientWidth || window.innerWidth; }
          function getScrollWidth() { return document.body.scrollWidth; }

          window.setTheme = function(isDark) {
              if (isDark) { document.documentElement.classList.add('dark-mode'); document.body.classList.add('dark-mode'); }
              else { document.documentElement.classList.remove('dark-mode'); document.body.classList.remove('dark-mode'); }
          }

          function setScroll(x) {
              document.body.style.transform = 'translate3d(' + (-x) + 'px, 0, 0)';
              window.globalScrollX = x;
          }
          window.globalScrollX = 0;

          function fixImages() {
              let token = window.AUTH_TOKEN || ''; 
              let baseUrl = window.API_BASE_URL || '';
              let imgs = document.getElementsByTagName('img');

              for(let i=0; i<imgs.length; i++) {
                let src = imgs[i].src;
                let originalSrc = src;

                if (baseUrl && (src.includes('localhost') || src.includes('127.0.0.1'))) {
                    src = src.replace(/http:\/\/(localhost|127\.0\.0\.1)(:\d+)?/gi, baseUrl);
                }

                if (src.includes('/Images/')) src = src.replace('/Images/', '/images/');

                // Just append token. User-Agent handles the Ngrok bypass.
                if (token && !src.includes('token=')) {
                    let separator = src.includes('?') ? '&' : '?';
                    src = src + separator + 'token=' + token;
                }
                
                if (src !== originalSrc) imgs[i].src = src;
              }
          }

          function init() {
              fixImages();
              setTimeout(fixImages, 300); 
              const w = getWidth();
              const params = new URLSearchParams(window.location.search);
              if (params.get('pos') === 'end') setScroll(getScrollWidth() - w);
              else setScroll(0);
              setTimeout(function(){ post('ready'); }, 200);
          }

          let startX = 0; let isDragging = false; let startPage = 0; 
          window.addEventListener('touchstart', function(e) { startX = e.touches[0].clientX; isDragging = true; const w = getWidth(); const maxPage = Math.ceil((getScrollWidth() - 20) / w) - 1; let rawStart = Math.round((window.globalScrollX || 0) / w); if (rawStart > maxPage) rawStart = maxPage; if (rawStart < 0) rawStart = 0; startPage = rawStart; }, {passive: false});
          window.addEventListener('touchmove', function(e) { if (!isDragging) return; const diff = startX - e.touches[0].clientX; if (e.cancelable) e.preventDefault(); setScroll((startPage * getWidth()) + diff); }, {passive: false});
          window.addEventListener('touchend', function(e) { if (!isDragging) return; isDragging = false; const w = getWidth(); const diff = startX - e.changedTouches[0].clientX; if (Math.abs(diff) < 10) { post('toggle_controls'); return; } let targetPage = startPage; if (diff > 50) targetPage = startPage + 1; else if (diff < -50) targetPage = startPage - 1; const maxPage = Math.ceil((getScrollWidth() - 20) / w) - 1; if (targetPage < 0) { const params = new URLSearchParams(window.location.search); if (params.get('isFirst') !== 'true') { post('prev_chapter'); return; } targetPage = 0; } if (targetPage > maxPage) { post('next_chapter'); return; } const targetX = targetPage * w; smoothScrollTo(targetX); }, {passive: false});
          function smoothScrollTo(targetX) { const start = window.globalScrollX || 0; const dist = targetX - start; let startTime = null; function step(ts) { if (!startTime) startTime = ts; const p = Math.min((ts - startTime)/250, 1); const ease = 1 - Math.pow(1 - p, 3); setScroll(start + (dist * ease)); if (p < 1) requestAnimationFrame(step); else { setScroll(targetX); const total = getScrollWidth() - getWidth(); post('progress:' + (total > 0 ? targetX/total : 0)); } } requestAnimationFrame(step); }
          init();
      })();
    ''';

    String cssBase64 = base64Encode(utf8.encode(rawCss));
    String jsBase64 = base64Encode(utf8.encode(rawJs));

    _controller?.runJavaScript('''
      window.AUTH_TOKEN = "$token";
      window.API_BASE_URL = "$apiBaseUrl";
      var style = document.createElement('style');
      style.innerHTML = decodeURIComponent(escape(window.atob('$cssBase64')));
      document.head.appendChild(style);
      document.body.style.backgroundColor = "$bgHex";
      document.body.style.color = "$textHex";
      var script = document.createElement('script');
      script.innerHTML = decodeURIComponent(escape(window.atob('$jsBase64')));
      document.head.appendChild(script);
    ''');
  }

  void _handleJsMessage(String message) {
    if (message == 'ready') {
      _spinnerSafetyTimer?.cancel();
      _applyTheme();
      if (_viewModel.requestScrollToProgress != null) {
        _executeScroll(_viewModel.requestScrollToProgress!);
        _viewModel.requestScrollToProgress = null;
      }
      Future.delayed(const Duration(milliseconds: 100), () {
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
      if (_dragValue == null)
        setState(() => _viewModel.updateScrollProgress(val));
    }
  }

  void _showChapterList() {
    final bgColor = Theme.of(context).scaffoldBackgroundColor;
    showModalBottomSheet(
      context: context,
      backgroundColor: bgColor,
      // Optional: Nice rounded corners
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return ListView.separated(
          // 🟢 ADDED PADDING HERE
          padding: const EdgeInsets.symmetric(vertical: 20),
          itemCount: _viewModel.chapterTitles.length,
          separatorBuilder: (c, i) => const Divider(height: 1),
          itemBuilder: (context, index) {
            return ListTile(
              title: Text(_viewModel.chapterTitles[index]),
              onTap: () {
                Navigator.pop(context);
                _viewModel.jumpToChapter(index);
              },
            );
          },
        );
      },
    );
  }
}
