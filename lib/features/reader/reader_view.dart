import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:pdfrx/pdfrx.dart';

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

  WebViewController? _webViewController;
  PageController? _pageController;

  Timer? _spinnerSafetyTimer;
  bool _showControls = false;
  bool _isLoading = true;
  String? _currentUrl;

  double? _dragValue;
  bool _isInteractingWithSlider = false;

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
    _viewModel.dispose();
    _pageController?.dispose();
    super.dispose();
  }

  void _onViewModelUpdate() {
    if (!mounted) return;

    if (!_isInteractingWithSlider && _dragValue == null) {
      setState(() {});
    }

    if (!_viewModel.isPdf &&
        _viewModel.epubUrl != null &&
        _viewModel.epubUrl != _currentUrl) {
      _currentUrl = _viewModel.epubUrl;
      _loadEpubContent(_currentUrl!);
    }

    if (_viewModel.isPdf && _viewModel.requestJumpToPage != null) {
      int targetPage = _viewModel.requestJumpToPage!;
      if (_pageController != null && _pageController!.hasClients) {
        if (_pageController!.page?.round() != targetPage - 1) {
          _pageController!.jumpToPage(targetPage - 1);
        }
      }
      _viewModel.requestJumpToPage = null;
    }

    if (_viewModel.isPdf && _viewModel.isReady && _pageController == null) {
      int initialPage = (_viewModel.getCurrentGlobalPage() - 1).clamp(
        0,
        _viewModel.totalBookPages - 1,
      );
      _pageController = PageController(initialPage: initialPage);
      setState(() => _isLoading = false);
    }
  }

  void _loadEpubContent(String url) {
    _startLoading();
    final uri = Uri.parse(url);
    if (widget.book.isLocal) {
      _webViewController?.loadRequest(uri);
    } else {
      _loadOnlineEpubAsString(uri);
    }
  }

  Future<void> _loadOnlineEpubAsString(Uri uri) async {
    try {
      final client = HttpClient();
      final request = await client.getUrl(uri);
      _getAuthHeaders().forEach((k, v) => request.headers.set(k, v));
      final response = await request.close();
      final bytes = await response.fold<List<int>>(
        [],
        (acc, chunk) => acc..addAll(chunk),
      );
      client.close();

      final rawHtml = utf8.decode(bytes, allowMalformed: true);
      final injected = _injectIntoHtml(rawHtml, uri.toString());

      if (mounted) {
        _webViewController?.loadHtmlString(injected, baseUrl: uri.toString());
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _injectIntoHtml(String html, String baseUrl) {
    final bool wantEnd = baseUrl.contains('pos=end');
    final css = _buildCss();
    final js = _buildJs(wantEnd);

    const metaTag =
        '<meta name="viewport" content="width=device-width, '
        'height=device-height, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">';
    final cssTag = '<style>$css</style>';
    final jsTag = '<script>$js</script>';

    String modified = html;

    if (modified.contains('<head>')) {
      modified = modified.replaceFirst('<head>', '<head>$metaTag$cssTag');
    } else {
      modified = '<head>$metaTag$cssTag</head>$modified';
    }

    if (modified.contains('<body')) {
      modified = modified.replaceFirstMapped(
        RegExp(r'<body[^>]*>', caseSensitive: false),
        (m) => '${m.group(0)}<div id="viewer">',
      );
      modified = modified.replaceFirst('</body>', '</div>$jsTag</body>');
    } else {
      modified = '<body><div id="viewer">$modified</div>$jsTag</body>';
    }

    return modified;
  }

  void _startLoading() {
    setState(() => _isLoading = true);
    _spinnerSafetyTimer?.cancel();
    _spinnerSafetyTimer = Timer(const Duration(seconds: 10), () {
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

  void _executeEpubScroll(double percent) {
    _webViewController?.runJavaScript(
      'if(window.scrollToPercent) window.scrollToPercent($percent);',
    );
  }

  void _applyTheme() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    _webViewController?.runJavaScript(
      'if(window.setTheme) window.setTheme($isDark);',
    );
  }

  String _buildCss() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgHex = isDark ? '#121212' : '#ffffff';
    final textHex = isDark ? '#e0e0e0' : '#000000';

    return '''
      * { box-sizing: border-box; }
      html {
        height: 100vh !important;
        width: 100vw !important;
        overflow: hidden !important;
        margin: 0 !important;
        padding: 0 !important;
        background-color: $bgHex !important;
        touch-action: none !important;
      }
      body {
        height: calc(100vh - 80px) !important;
        width: 100vw !important;
        margin-top: 40px !important;
        margin-bottom: 40px !important;
        margin-left: 0 !important;
        margin-right: 0 !important;
        overflow: visible !important;
        padding: 0 !important;
        border: none !important;
        column-width: 100vw !important;
        column-gap: 0px !important;
        column-fill: auto !important;
        color: $textHex !important;
        font-family: sans-serif !important;
        font-size: 18px !important;
        line-height: 1.6 !important;
        text-align: justify;
        will-change: transform;
        backface-visibility: hidden;
        visibility: hidden;
      }
      p, h1, h2, h3, h4, h5, h6, li, blockquote, dd, dt {
        margin-left: 20px !important;
        margin-right: 20px !important;
      }
      img, svg, image {
        max-width: calc(100vw - 40px) !important;
        max-height: 100% !important;
        object-fit: contain !important;
        display: block !important;
        margin: 0 auto !important;
      }
      #viewer { display: contents; }
      html.dark-mode { background-color: #121212 !important; }
      body.dark-mode { color: #e0e0e0 !important; background-color: #121212 !important; }
      html.dark-mode img { opacity: 0.85 !important; }
    ''';
  }

  String _buildJs(bool wantEnd) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final token = AuthService().token ?? '';

    return '''
      (function() {
        if (window.didInit) return; window.didInit = true;

        function post(msg) { if (window.PrintReader) window.PrintReader.postMessage(msg); }
        function W() { return document.documentElement.clientWidth || window.innerWidth; }

        var _totalSW = 0;

        var s = document.body.style;
        s.height               = (window.innerHeight - 80) + 'px';
        s.width                = '100vw';
        s.margin               = '40px 0';
        s.padding              = '0';
        s.columnWidth          = '100vw';
        s.columnGap            = '0';
        s.columnFill           = 'auto';
        s.willChange           = 'transform';
        s.webkitBackfaceVisibility = 'hidden';
        s.backfaceVisibility   = 'hidden';
        s.overflow             = 'visible';

        document.documentElement.style.overflow = 'hidden';
        document.documentElement.style.height   = '100vh';
        document.documentElement.style.width    = '100vw';

        var curX = 0;
        function setX(x) {
          curX = x;
          document.body.style.transform = 'translate3d(' + (-x) + 'px, 0, 0)';
        }

        window.setTheme = function(isDark) {
          var fn = isDark ? 'add' : 'remove';
          document.documentElement.classList[fn]('dark-mode');
          document.body.classList[fn]('dark-mode');
        };
        window.setTheme($isDark);

        function fixImages() {
          var token = '$token';
          var imgs = document.getElementsByTagName('img');
          for (var i = 0; i < imgs.length; i++) {
            var src = imgs[i].src;
            if (src.indexOf('localhost') > -1 || src.indexOf('127.0.0.1') > -1)
              src = src.replace('localhost', '10.0.2.2').replace('127.0.0.1', '10.0.2.2');
            if (src.indexOf('/Images/') > -1)
              src = src.replace('/Images/', '/images/');
            if (token && src.indexOf('token=') === -1 && src.startsWith('http'))
              src += (src.indexOf('?') > -1 ? '&' : '?') + 'token=' + token;
            imgs[i].src = src;
          }
        }

        function init() {
          fixImages();
          setTimeout(fixImages, 500);

          _totalSW = document.body.scrollWidth;

          var w = W();
          var targetX = ${wantEnd ? 'true' : 'false'} ? (_totalSW - w) : 0;
          targetX = Math.round(targetX / w) * w;
          targetX = Math.max(0, Math.min(_totalSW - w, targetX));
          setX(targetX);

          document.body.style.visibility = 'visible';

          var pageCount = Math.max(1, Math.round(_totalSW / w));
          post('page_count:' + pageCount);

          setTimeout(function() { post('ready'); }, 100);
        }

        window.scrollToPercent = function(percent) {
          var w = W();
          var total  = _totalSW - w;
          var target = Math.round((total * percent) / w) * w;
          target = Math.max(0, Math.min(total, target));
          setX(target);
        };

        var startX    = 0;
        var startY    = 0;
        var startPage = 0;
        var dragging  = false;

        window.addEventListener('touchstart', function(e) {
          startX = e.touches[0].clientX;
          startY = e.touches[0].clientY;
          var w = W();
          var maxPage = Math.max(0, Math.round(_totalSW / w) - 1);
          startPage = Math.max(0, Math.min(maxPage, Math.round(curX / w)));
          dragging = true;
          window._snapCancel = true;
        }, { passive: true });

        window.addEventListener('touchmove', function(e) {
          if (!dragging) return;
          var diff    = startX - e.touches[0].clientX;
          var w       = W();
          var targetX = startPage * w + diff;
          setX(Math.max(-w, Math.min(_totalSW, targetX)));
        }, { passive: true });

        function onTouchEnd(e) {
          if (!dragging) return;
          dragging = false;

          var w       = W();
          var touch   = e.changedTouches ? e.changedTouches[0] : e.touches[0];
          var clientX = touch ? touch.clientX : startX;
          var clientY = touch ? touch.clientY : startY;
          var diffX   = startX - clientX;
          var diffY   = startY - clientY;

          if (Math.abs(diffX) < 10 && Math.abs(diffY) < 10) {
            post('toggle_controls');
            var maxP   = Math.max(0, Math.round(_totalSW / w) - 1);
            var validP = Math.max(0, Math.min(maxP, startPage));
            snapTo(validP * w);
            return;
          }

          var maxX = _totalSW - w;

          if (curX < -w * 0.15) {
            snapTo(-w);
            setTimeout(function() { post('prev_chapter'); }, 250);
            return;
          }
          if (curX > maxX + w * 0.15) {
            snapTo(_totalSW);
            setTimeout(function() { post('next_chapter'); }, 250);
            return;
          }

          var targetPage = startPage;
          if (diffX > 50)       targetPage = startPage + 1;
          else if (diffX < -50) targetPage = startPage - 1;

          var maxPage = Math.max(0, Math.round(_totalSW / w) - 1);
          targetPage  = Math.max(0, Math.min(maxPage, targetPage));
          snapTo(targetPage * w);
        }

        window.addEventListener('touchend',    onTouchEnd, { passive: true });
        window.addEventListener('touchcancel', onTouchEnd, { passive: true });

        function snapTo(targetX) {
          window._snapCancel = false;
          var from = curX;
          var dist = targetX - from;
          if (Math.abs(dist) < 1) { setX(targetX); reportProgress(targetX); return; }

          var startTime = null;
          function step(ts) {
            if (window._snapCancel) return;
            if (!startTime) startTime = ts;
            var p    = Math.min((ts - startTime) / 250, 1);
            var ease = 1 - Math.pow(1 - p, 3);
            setX(from + dist * ease);
            if (p < 1) requestAnimationFrame(step);
            else { setX(targetX); reportProgress(targetX); }
          }
          requestAnimationFrame(step);
        }

        function reportProgress(x) {
          var w         = W();
          var pageCount = Math.max(1, Math.round(_totalSW / w));
          var maxX      = (pageCount - 1) * w;
          var valid     = Math.max(0, Math.min(maxX, x));
          post('progress:' + (maxX > 0 ? valid / maxX : 1));
        }

        window.addEventListener('load', function() { init(); });

      })();
    ''';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bgColor = theme.scaffoldBackgroundColor;
    final txtColor = theme.colorScheme.onSurface;
    final barColor = isDark ? const Color(0xFF18122B) : const Color(0xFFFCF8F8);
    final accentColor = isDark
        ? const Color(0xFF635985)
        : const Color(0xFFF5AFAF);

    if (!_viewModel.isReady) {
      return Scaffold(
        backgroundColor: bgColor,
        body: Center(child: CircularProgressIndicator(color: accentColor)),
      );
    }

    if (!_viewModel.isPdf && _webViewController == null) _initWebView(bgColor);

    return Scaffold(
      backgroundColor: bgColor,
      body: Stack(
        children: [
          SafeArea(
            child: _viewModel.isPdf
                ? _buildPdfPageView(bgColor)
                : WebViewWidget(controller: _webViewController!),
          ),

          if (_isLoading)
            GestureDetector(
              onTap: () => setState(() => _showControls = !_showControls),
              behavior: HitTestBehavior.opaque,
              child: Container(
                color: bgColor,
                child: Center(
                  child: CircularProgressIndicator(color: accentColor),
                ),
              ),
            ),

          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            top: _showControls ? 0 : -100,
            left: 0,
            right: 0,
            child: Container(
              height: kToolbarHeight + MediaQuery.of(context).padding.top,
              padding: EdgeInsets.only(top: MediaQuery.of(context).padding.top),
              decoration: BoxDecoration(
                color: barColor.withOpacity(0.97),
                border: Border(
                  bottom: BorderSide(color: theme.dividerColor, width: 0.5),
                ),
              ),
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

          AnimatedPositioned(
            duration: const Duration(milliseconds: 200),
            bottom: _showControls ? 0 : -160,
            left: 0,
            right: 0,
            child: Container(
              decoration: BoxDecoration(
                color: barColor.withOpacity(0.97),
                border: Border(
                  top: BorderSide(color: theme.dividerColor, width: 0.5),
                ),
              ),
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
                          color: txtColor.withOpacity(0.5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Text(
                        "1",
                        style: TextStyle(
                          fontSize: 12,
                          color: txtColor.withOpacity(0.5),
                        ),
                      ),
                      Expanded(
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            activeTrackColor: accentColor,
                            inactiveTrackColor: accentColor.withOpacity(0.2),
                            thumbColor: accentColor,
                            overlayColor: accentColor.withOpacity(0.15),
                            trackHeight: 3,
                          ),
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
                            onChanged: _isLoading
                                ? null
                                : (val) {
                                    setState(() {
                                      _dragValue = val;
                                      _isInteractingWithSlider = true;
                                    });
                                  },
                            onChangeEnd: _isLoading
                                ? null
                                : (val) {
                                    _viewModel.jumpToGlobalPage(val.toInt());
                                    Future.delayed(
                                      const Duration(milliseconds: 800),
                                      () {
                                        if (mounted) {
                                          setState(() {
                                            _dragValue = null;
                                            _isInteractingWithSlider = false;
                                          });
                                        }
                                      },
                                    );
                                  },
                          ),
                        ),
                      ),
                      Text(
                        "${_viewModel.totalBookPages}",
                        style: TextStyle(
                          fontSize: 12,
                          color: txtColor.withOpacity(0.5),
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

  Widget _buildPdfPageView(Color bgColor) {
    if (_pageController == null || _viewModel.pdfDoc == null) {
      return Container(color: bgColor);
    }

    return GestureDetector(
      onTap: () => setState(() => _showControls = !_showControls),
      child: PageView.builder(
        controller: _pageController,
        itemCount: _viewModel.totalBookPages,
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        onPageChanged: (index) {
          if (!_isInteractingWithSlider) {
            _viewModel.onPdfPageChanged(index + 1);
          }
        },
        itemBuilder: (context, index) {
          return InteractiveViewer(
            maxScale: 3.0,
            minScale: 1.0,
            child: PdfPageView(
              document: _viewModel.pdfDoc!,
              pageNumber: index + 1,
              alignment: Alignment.center,
              decoration: BoxDecoration(color: bgColor),
            ),
          );
        },
      ),
    );
  }

  void _initWebView(Color bgColor) {
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(bgColor)
      ..setUserAgent("MyBookReader/1.0")
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            if (!_viewModel.isPdf && widget.book.isLocal) {
              _applyTheme();
              _webViewController?.runJavaScript(
                'if(window.fixImages) window.fixImages();',
              );
              if (_viewModel.requestScrollToProgress != null) {
                _executeEpubScroll(_viewModel.requestScrollToProgress!);
                _viewModel.requestScrollToProgress = null;
              }
              Future.delayed(const Duration(milliseconds: 150), () {
                if (mounted) setState(() => _isLoading = false);
              });
            }
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
      _loadEpubContent(_viewModel.epubUrl!);
    }
  }

  void _handleJsMessage(String message) {
    if (message == 'ready') {
      _spinnerSafetyTimer?.cancel();
      _viewModel.requestScrollToProgress = null;
      Future.delayed(const Duration(milliseconds: 150), () {
        if (mounted) setState(() => _isLoading = false);
      });
    } else if (message == 'toggle_controls') {
      setState(() => _showControls = !_showControls);
    } else if (message == 'next_chapter') {
      _viewModel.nextChapter();
    } else if (message == 'prev_chapter') {
      _viewModel.previousChapter();
    } else if (message.startsWith('page_count:')) {
      final count = int.tryParse(message.split(':')[1]);
      if (count != null) {
        _viewModel.updateChapterPageCount(
          _viewModel.currentChapterIndex,
          count,
        );
      }
    } else if (message.startsWith('progress:')) {
      if (!_isInteractingWithSlider) {
        final val = double.tryParse(message.split(':')[1]) ?? 0.0;
        _viewModel.updateEpubScrollProgress(val);
        setState(() {});
      }
    }
  }

  void _showChapterList() {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accent = isDark ? const Color(0xFF635985) : const Color(0xFFF5AFAF);
    final chapters = _viewModel.chapterTitles;

    if (chapters.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _viewModel.isPdf
                ? "No table of contents available."
                : "No chapters found.",
          ),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => ListView.separated(
        padding: const EdgeInsets.symmetric(vertical: 20),
        itemCount: chapters.length,
        separatorBuilder: (_, __) =>
            Divider(height: 1, color: theme.dividerColor),
        itemBuilder: (_, i) {
          final bool current = i == _viewModel.currentChapterIndex;
          return ListTile(
            title: Text(
              chapters[i],
              style: TextStyle(
                color: current ? accent : theme.colorScheme.onSurface,
                fontWeight: current ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            trailing: current
                ? Icon(Icons.circle, size: 8, color: accent)
                : null,
            onTap: () {
              Navigator.pop(context);
              _viewModel.jumpToChapter(i);
            },
          );
        },
      ),
    );
  }
}
