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

  // Slider / Interaction State
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

    // Block UI updates while dragging slider to prevent jitter
    if (!_isInteractingWithSlider && _dragValue == null) {
      setState(() {});
    }

    if (!_viewModel.isPdf &&
        _viewModel.epubUrl != null &&
        _viewModel.epubUrl != _currentUrl) {
      _currentUrl = _viewModel.epubUrl;
      _loadEpubContent(_currentUrl!);
    }

    // PDF Page Jumps
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
                                    // Delay releasing slider lock to prevent jumping
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
            if (!_viewModel.isPdf) {
              if (widget.book.isLocal) {
                // LOCAL LOGIC
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
                // ONLINE LOGIC (New Fixed Version)
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
      // Handle delayed scroll requests
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
      if (!_isInteractingWithSlider) {
        final val = double.tryParse(message.split(':')[1]) ?? 0.0;
        _viewModel.updateEpubScrollProgress(val);
        setState(() {}); // Immediate update
      }
    }
  }

  // ---------------------------------------------------------
  // THE FIXED ONLINE READER ASSETS
  // ---------------------------------------------------------
  void _injectAssets() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgHex = isDark ? '#18122B' : '#FCF8F8';
    final textHex = isDark ? '#E8E0F0' : '#1A1A1A';
    final token = AuthService().token ?? '';
    final apiBaseUrl = ApiService.baseUrl;
    final bool wantEnd = _viewModel.epubUrl?.contains('pos=end') ?? false;

    const String rawCss = r'''
      * { box-sizing: border-box; }
      html { height: 100vh; width: 100vw; overflow: hidden; margin: 0; padding: 0; touch-action: none; background-color: #ffffff; }
      body { 
        visibility: hidden; /* Default hidden until JS enables it */
        height: calc(100vh - 80px); width: 100vw; margin: 40px 0; padding: 0;
        column-width: 100vw; column-gap: 0px; column-fill: auto;
        font-family: sans-serif; font-size: 18px; line-height: 1.6; text-align: justify;
        will-change: transform; backface-visibility: hidden; overflow: visible;
      }
      p, h1, h2, h3, h4, h5, h6, li, blockquote, dd, dt { margin-left: 20px; margin-right: 20px; }
      img, svg { max-width: calc(100vw - 40px); max-height: 100%; object-fit: contain; display: block; margin: 0 auto; }
      #reading-anchor { display: inline-block; width: 1px; height: 1px; }
      html.dark-mode { background-color: #18122B !important; }
      body.dark-mode { color: #E8E0F0 !important; background-color: #18122B !important; }
    ''';

    const String rawJs = r'''
      (function() {
        if(window.didInit) return; window.didInit = true;
        function post(msg) { if (window.PrintReader) window.PrintReader.postMessage(msg); }
        function W()  { return document.documentElement.clientWidth; }
        
        var anchor = document.createElement('span');
        anchor.id = 'reading-anchor'; anchor.innerHTML = '&nbsp;'; 
        document.body.appendChild(anchor);

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

        function init() {
          var params = new URLSearchParams(window.location.search);
          var forceEnd = (params.get('pos') === 'end' || window._forceEnd === true);
          var lastAnchorX = -1, stability = 0;
          
          var check = setInterval(function() {
            var rect = anchor.getBoundingClientRect();
            var currentAnchorX = rect.left + curX; 
            
            if (currentAnchorX > 0 && Math.abs(currentAnchorX - lastAnchorX) < 1) stability++;
            else stability = 0;
            lastAnchorX = currentAnchorX;

            if (stability >= 5) { 
              clearInterval(check);
              var screen = W();
              var maxIdx = Math.max(0, Math.ceil((currentAnchorX + 10) / screen) - 1);
              
              var targetX = forceEnd ? maxIdx * screen : 0;
              setX(targetX);

              // 🟢 STICKY END LOGIC:
              // If we are supposed to be at the end, keep checking for content growth (images/fonts).
              // If the page grows, snap to the NEW end immediately.
              if (forceEnd) {
                 var retries = 0;
                 var reCheck = setInterval(function() {
                    var newRect = anchor.getBoundingClientRect();
                    var newTotal = newRect.left + curX;
                    var newMax = Math.max(0, Math.ceil((newTotal + 10) / screen) - 1);
                    // If content grew beyond current view, update view
                    if (newMax * screen > curX) {
                       setX(newMax * screen);
                    }
                    retries++;
                    if(retries > 20) clearInterval(reCheck); // Stop checking after 2 seconds
                 }, 100);
              }

              // 🟢 DOUBLE FRAME DELAY:
              // Ensure the translation renders physically before making body visible.
              // Prevents the "Random Page" flash.
              requestAnimationFrame(function() {
                 requestAnimationFrame(function() {
                    document.body.style.visibility = 'visible';
                    post('ready');
                    report(targetX);
                 });
              });
            }
          }, 80);
        }

        var startX=0, startCurX=0, dragging=false;
        
        window.addEventListener('touchstart', function(e) {
          startX = e.touches[0].clientX;
          startCurX = curX; 
          dragging = true;
          window._snapCancel = true;
        }, {passive:true});
        
        window.addEventListener('touchmove', function(e) {
          if(!dragging) return;
          var delta = startX - e.touches[0].clientX;
          setX(startCurX + delta); 
        }, {passive:true});
        
        window.addEventListener('touchend', function(e) {
          if(!dragging) return; dragging = false;
          var w = W();
          var diffX = startX - e.changedTouches[0].clientX;
          
          var rect = anchor.getBoundingClientRect();
          var totalWidth = rect.left + curX;
          var maxIdx = Math.max(0, Math.ceil((totalWidth + 10) / w) - 1);

          if(Math.abs(diffX) < 10) { 
             var currentIdx = Math.round(startCurX / w);
             snapTo(currentIdx * w); 
             post('toggle_controls'); 
             return; 
          }
          
          var direction = 0;
          if (diffX > 50) direction = 1;
          else if (diffX < -50) direction = -1;

          var targetIdx;
          if (direction === 0) {
             targetIdx = Math.round(startCurX / w);
          } else {
             targetIdx = Math.round(startCurX / w) + direction;
          }

          if (targetIdx > maxIdx) { post('next_chapter'); return; }
          if (targetIdx < 0) { post('prev_chapter'); return; }

          snapTo(targetIdx * w);
        });

        function snapTo(targetX) {
          window._snapCancel = false;
          var from = curX, dist = targetX - from;
          if (Math.abs(dist) < 1) { setX(targetX); report(targetX); return; }
          
          var startTime = null;
          function step(ts) {
            if (window._snapCancel) return;
            if (!startTime) startTime = ts;
            var p = Math.min((ts - startTime) / 250, 1);
            setX(from + dist * (1 - Math.pow(1 - p, 3)));
            if (p < 1) requestAnimationFrame(step);
            else { setX(targetX); report(targetX); }
          }
          requestAnimationFrame(step);
        }

        function report(x) {
          var rect = anchor.getBoundingClientRect();
          var total = rect.left + curX - W();
          if (total <= 1) { post('progress:1'); return; }
          post('progress:' + (x / total));
        }

        init();
      })();
    ''';

    const String compatJs = r'''
      window.scrollToPercent = function(pct) {
        var screen = document.documentElement.clientWidth;
        var anchor = document.getElementById('reading-anchor');
        if(anchor) {
           var rect = anchor.getBoundingClientRect();
           var style = window.getComputedStyle(document.body);
           var matrix = new WebKitCSSMatrix(style.transform);
           var curX = -matrix.m41; 
           var total = rect.left + curX - screen;
           if (total > 0) {
              var target = pct * total;
              target = Math.round(target / screen) * screen;
              document.body.style.transform = 'translate3d(' + (-target) + 'px, 0, 0)';
           }
        }
      };
    ''';

    final String jsB64 = base64Encode(utf8.encode(rawJs + compatJs));
    final String cssB64 = base64Encode(utf8.encode(rawCss));

    _webViewController?.runJavaScript('''
      window._tok = "$token";
      window._base = "$apiBaseUrl";
      window._forceEnd = $wantEnd;
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
