import 'dart:async';
import 'dart:convert';
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
    if (mounted) {
      if (_dragValue == null) setState(() {});

      if (!_viewModel.isPdf &&
          _viewModel.epubUrl != null &&
          _viewModel.epubUrl != _currentUrl) {
        _currentUrl = _viewModel.epubUrl;
        _loadEpubContent(_currentUrl!);
      }

      if (_viewModel.isPdf && _viewModel.requestJumpToPage != null) {
        int targetPage = _viewModel.requestJumpToPage!;
        if (_pageController != null && _pageController!.hasClients) {
          _pageController!.jumpToPage(targetPage - 1);
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
  }

  void _loadEpubContent(String url) {
    _startLoading();
    final uri = Uri.parse(url);
    if (widget.book.isLocal) {
      _webViewController?.loadRequest(uri);
    } else {
      _webViewController?.loadRequest(uri, headers: _getAuthHeaders());
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

          // Top bar
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

          // Bottom bar
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
                                : (val) => setState(() => _dragValue = val),
                            onChangeEnd: _isLoading
                                ? null
                                : (val) {
                                    _viewModel.jumpToGlobalPage(val.toInt());
                                    setState(() => _dragValue = null);
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
        physics: const ClampingScrollPhysics(),
        onPageChanged: (index) {
          _viewModel.onPdfPageChanged(index + 1);
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
            if (!_viewModel.isPdf) {
              if (widget.book.isLocal) {
                // Local Books: CSS/JS is on disk.
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
              } else {
                // Cloud Books: Inject JS/CSS
                _injectAssets();
              }
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
      _applyTheme();
      if (_viewModel.requestScrollToProgress != null) {
        _executeEpubScroll(_viewModel.requestScrollToProgress!);
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
        setState(() => _viewModel.updateEpubScrollProgress(val));
    }
  }

  void _injectAssets() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgHex = isDark ? '#18122B' : '#FCF8F8';
    final textHex = isDark ? '#E8E0F0' : '#1A1A1A';
    final token = AuthService().token ?? '';
    final apiBaseUrl = ApiService.baseUrl;

    // Mirrors reader.js exactly — same GPU hints, same passive touch, same snap logic.
    // Only difference: image fixer uses _base URL replacement instead of localhost swap.
    const String rawJs = r'''
      (function() {
        function post(msg) { if (window.PrintReader) window.PrintReader.postMessage(msg); }
        function W()  { return document.documentElement.clientWidth || window.innerWidth; }
        function SW() { return document.body.scrollWidth; }

        // Mirror reader.js: set GPU hints directly on body via JS
        var s = document.body.style;
        s.height              = (window.innerHeight - 80) + 'px';
        s.width               = '100vw';
        s.margin              = '40px 0';
        s.padding             = '0';
        s.columnWidth         = '100vw';
        s.columnGap           = '0';
        s.columnFill          = 'auto';
        s.willChange          = 'transform';
        s.webkitBackfaceVisibility = 'hidden';
        s.backfaceVisibility  = 'hidden';
        s.overflow            = 'visible';

        document.documentElement.style.overflow = 'hidden';
        document.documentElement.style.height   = '100vh';
        document.documentElement.style.width    = '100vw';

        var curX = 0;
        function setX(x) {
          curX = x;
          document.body.style.transform = 'translate3d(' + (-x) + 'px, 0, 0)';
          window.globalScrollX = x;
        }
        window.globalScrollX = 0;

        window.setTheme = function(isDark) {
          var fn = isDark ? 'add' : 'remove';
          document.documentElement.classList[fn]('dark-mode');
          document.body.classList[fn]('dark-mode');
        };

        window.scrollToPercent = function(percent) {
          var w      = W();
          var total  = SW() - w;
          var target = Math.round((total * percent) / w) * w;
          setX(target);
        };

        function fixImages() {
          var token   = window._tok  || '';
          var baseUrl = window._base || '';
          var imgs    = document.getElementsByTagName('img');
          for (var i = 0; i < imgs.length; i++) {
            var src = imgs[i].src, orig = src;
            if (baseUrl && (src.indexOf('localhost') > -1 || src.indexOf('127.0.0.1') > -1))
              src = src.replace(/http:\/\/(localhost|127\.0\.0\.1)(:\d+)?/gi, baseUrl);
            if (src.indexOf('/Images/') > -1)
              src = src.replace('/Images/', '/images/');
            if (token && src.indexOf('token=') === -1)
              src += (src.indexOf('?') > -1 ? '&' : '?') + 'token=' + token;
            if (src !== orig) imgs[i].src = src;
          }
        }
        window.fixImages = fixImages;

        var startX    = 0;
        var startY    = 0;
        var startPage = 0;
        var dragging  = false;

        window.addEventListener('touchstart', function(e) {
          startX    = e.touches[0].clientX;
          startY    = e.touches[0].clientY;
          startPage = Math.round(curX / W());
          dragging  = true;
          window._snapCancel = true;
        }, { passive: true });

        window.addEventListener('touchmove', function(e) {
          if (!dragging) return;
          var diff    = startX - e.touches[0].clientX;
          var targetX = startPage * W() + diff;
          setX(Math.max(-W(), Math.min(SW(), targetX)));
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
            var validP = Math.max(0, Math.min(Math.ceil((SW()-20)/w)-1, startPage));
            snapTo(validP * w);
            return;
          }

          var maxX = SW() - w;

          if (curX < -w * 0.15) {
            var params = new URLSearchParams(window.location.search);
            if (params.get('isFirst') !== 'true') {
              snapTo(-w);
              setTimeout(function() { post('prev_chapter'); }, 250);
              return;
            }
          }
          if (curX > maxX + w * 0.15) {
            snapTo(SW());
            setTimeout(function() { post('next_chapter'); }, 250);
            return;
          }

          var targetPage = startPage;
          if (diffX > 50)       targetPage = startPage + 1;
          else if (diffX < -50) targetPage = startPage - 1;

          var maxPage = Math.ceil((SW() - 20) / w) - 1;
          targetPage  = Math.max(0, Math.min(maxPage, targetPage));
          snapTo(targetPage * w);
        }

        window.addEventListener('touchend',   onTouchEnd, { passive: true });
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
          var total  = SW() - W();
          var validX = Math.max(0, Math.min(total, x));
          post('progress:' + (total > 0 ? validX / total : 0));
        }

        function init() {
          dragging = false;
          fixImages();
          setTimeout(fixImages, 500);
          var params = new URLSearchParams(window.location.search);
          if (params.get('pos') === 'end') setX(SW() - W());
          else setX(0);
          setTimeout(function() { post('ready'); }, 100);
        }

        init();
      })();
    ''';

    // Minimal CSS — layout and GPU hints are set via JS (matching reader.js approach)
    // Only handles: overflow clipping, image sizing, dark mode classes
    const String rawCss = r'''
      * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
      html {
        touch-action: none !important;
        -webkit-user-select: none; user-select: none;
      }
      p, h1, h2, h3, h4, h5, h6, li, blockquote {
        margin-left: 20px !important; margin-right: 20px !important;
      }
      img, svg {
        max-width: calc(100vw - 40px) !important; max-height: 100% !important;
        object-fit: contain !important; display: block !important; margin: 0 auto !important;
      }
      html.dark-mode { background-color: #18122B !important; }
      body.dark-mode  { color: #E8E0F0 !important; background-color: #18122B !important; }
      html.dark-mode img { opacity: 0.85 !important; }
    ''';

    final String jsB64 = base64Encode(utf8.encode(rawJs));
    final String cssB64 = base64Encode(utf8.encode(rawCss));

    _webViewController?.runJavaScript('''
      window._tok  = "$token";
      window._base = "$apiBaseUrl";
      var st = document.createElement('style');
      st.innerHTML = decodeURIComponent(escape(window.atob('$cssB64')));
      document.head.appendChild(st);
      document.body.style.backgroundColor = "$bgHex";
      document.body.style.color = "$textHex";
      var sc = document.createElement('script');
      sc.innerHTML = decodeURIComponent(escape(window.atob('$jsB64')));
      document.head.appendChild(sc);
    ''');
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
