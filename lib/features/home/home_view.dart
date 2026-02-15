import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/book_model.dart';
import '../../models/download_task.dart';
import '../../models/upload_task.dart';
import '../../core/services/library_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/api_service.dart';
import '../../core/services/download_service.dart';
import '../../core/services/upload_service.dart';

import '../reader/reader_view.dart';
import '../settings/settings_view.dart';
import '../auth/login_view.dart';
import 'widgets/progress_book_cover.dart';
import 'queue_view.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  StreamSubscription? _sessionSub;

  List<BookModel> localBooks = [];
  List<BookModel> onlineBooks = [];
  bool isLoadingLocal = true;
  bool isLoadingOnline = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);

    _loadLocalBooks();

    if (AuthService().isLoggedIn) {
      _loadOnlineBooks();
    }

    _sessionSub = AuthService().sessionExpiredStream.listen((expired) {
      if (expired && mounted) _showSessionExpiredDialog();
    });

    _tabController.addListener(() {
      if (_tabController.index == 1 &&
          AuthService().isLoggedIn &&
          onlineBooks.isEmpty) {
        _loadOnlineBooks();
      }
    });

    DownloadService().addListener(_onQueueUpdate);
    UploadService().addListener(_onQueueUpdate);

    // Refresh Library after successful download
    DownloadService().onBookDownloaded = () {
      if (mounted) {
        _loadLocalBooks(force: true, isRefresh: true);
        if (AuthService().isLoggedIn) _loadOnlineBooks(silent: true);

        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Download completed! Library refreshed."),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 1),
          ),
        );
      }
    };

    UploadService().onUploadCompleted = () async {
      if (mounted) {
        await Future.delayed(const Duration(seconds: 1));
        if (!mounted) return;

        await _loadOnlineBooks(silent: true);

        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Cloud sync complete."),
            backgroundColor: Colors.blue,
            duration: Duration(seconds: 2),
          ),
        );
      }
    };
  }

  @override
  void dispose() {
    _sessionSub?.cancel();
    _tabController.dispose();
    DownloadService().removeListener(_onQueueUpdate);
    UploadService().removeListener(_onQueueUpdate);
    DownloadService().onBookDownloaded = null;
    UploadService().onUploadCompleted = null;
    super.dispose();
  }

  void _onQueueUpdate() {
    if (mounted) setState(() {});
  }

  // 🟢 NEW: OPEN & SORT
  void _openBook(BookModel book, bool isLocal) async {
    // 1. Update Last Read Time (This moves it to top left)
    await LibraryService().updateLastRead(book.id);

    // 2. Open Reader
    BookModel toOpen = book;
    if (!isLocal) {
      try {
        toOpen = localBooks.firstWhere(
          (l) => l.id == book.id || l.title == book.title,
        );
      } catch (_) {}
    }

    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ReaderView(book: toOpen)),
    );

    // 3. Refresh lists to update sort order on return
    _loadLocalBooks(force: true, isRefresh: true);
    if (AuthService().isLoggedIn) _loadOnlineBooks(silent: true);
  }

  Future<void> _loadLocalBooks({
    bool force = false,
    bool isRefresh = false,
  }) async {
    if (!isRefresh) setState(() => isLoadingLocal = true);
    final loaded = await LibraryService().scanForEpubs(forceRefresh: force);
    if (mounted)
      setState(() {
        localBooks = loaded;
        isLoadingLocal = false;
      });
  }

  Future<void> _loadOnlineBooks({
    bool silent = false,
    bool isRefresh = false,
  }) async {
    if (!silent && !isRefresh) setState(() => isLoadingOnline = true);
    try {
      final loaded = await ApiService().fetchUserBooks();
      // 🟢 Sort Cloud books manually
      final sorted = await LibraryService().sortBooksByRecent(loaded);

      if (mounted) {
        setState(() {
          onlineBooks = sorted;
          isLoadingOnline = false;
        });
        UploadService().updateOnlineBooksCache(loaded);
      }
    } catch (_) {
      if (mounted && !silent && !isRefresh)
        setState(() => isLoadingOnline = false);
    }
  }

  Future<void> _pickAndUploadFile() async {
    if (!AuthService().isLoggedIn) {
      _showLoginNeededSnackBar();
      return;
    }
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub', 'pdf'],
    );
    if (result != null && result.files.single.path != null) {
      final file = File(result.files.single.path!);
      UploadService().addToQueue(file);
      _showUploadStartedSnackBar();
    }
  }

  Future<void> _uploadFromContextMenu(File file, String title) async {
    UploadService().addToQueue(file, knownTitle: title);
    _showUploadStartedSnackBar();
  }

  void _showUploadStartedSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text("Added to upload queue"),
        action: SnackBarAction(
          label: "View",
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const QueueView()),
          ),
        ),
      ),
    );
  }

  Future<void> _downloadOnlineBook(BookModel book) async {
    if (LibraryService().isBookDownloaded(book.title)) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Book is already downloaded.")),
        );
      return;
    }

    if (Platform.isAndroid) {
      if (!await Permission.manageExternalStorage.isGranted &&
          !await Permission.storage.isGranted) {
        await Permission.manageExternalStorage.request();
        await Permission.storage.request();
      }
    }

    String extension = ".epub";
    if (book.title.toLowerCase().endsWith(".pdf") ||
        (book.filePath != null &&
            book.filePath!.toLowerCase().endsWith(".pdf"))) {
      extension = ".pdf";
    }

    final safeTitle = book.title.replaceAll(RegExp(r'[^\w\s\.]'), '');
    String filename = safeTitle;
    if (!filename.toLowerCase().endsWith(extension)) {
      filename = "$filename$extension";
    }

    final savePath = "/storage/emulated/0/Download/$filename";
    int bookId = int.tryParse(book.id.toString()) ?? 0;

    DownloadService().addToQueue(
      bookId,
      book.title,
      book.coverUrl ?? "",
      savePath,
    );
    if (mounted)
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Downloading...")));
  }

  Future<void> _deleteLocalBook(BookModel book) async {
    try {
      if (book.filePath != null) {
        final file = File(book.filePath!);
        if (await file.exists()) await file.delete();
        setState(
          () => localBooks.removeWhere((b) => b.filePath == book.filePath),
        );
        if (mounted)
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Book deleted from device")),
          );
      }
    } catch (_) {}
  }

  Future<void> _deleteOnlineBook(BookModel book) async {
    final int index = onlineBooks.indexOf(book);
    setState(() => onlineBooks.remove(book));
    try {
      await ApiService().deleteBook(int.parse(book.id));
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Book deleted from cloud")),
        );
    } catch (_) {
      if (mounted) {
        setState(() => onlineBooks.insert(index, book));
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Failed to delete book."),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showLoginNeededSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text("Login to upload."),
        action: SnackBarAction(label: "Login", onPressed: _handleProfileTap),
      ),
    );
  }

  void _showSessionExpiredDialog() {
    setState(() => onlineBooks.clear());
    _tabController.animateTo(0);
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Session Expired"),
        content: const Text("Please log in again."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Later"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _handleProfileTap();
            },
            child: const Text("Log In"),
          ),
        ],
      ),
    );
  }

  void _handleProfileTap() async {
    if (AuthService().isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You are already logged in.")),
      );
    } else {
      final bool? result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const LoginView()),
      );
      if (result == true) {
        setState(() {});
        _loadOnlineBooks();
        _tabController.animateTo(1);
      }
    }
  }

  void _handleLogout() async {
    Navigator.pop(context);
    await AuthService().logout();
    setState(() => onlineBooks.clear());
    _tabController.animateTo(0);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Logged out successfully")));
  }

  @override
  Widget build(BuildContext context) {
    final isLoggedIn = AuthService().isLoggedIn;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Library"),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _pickAndUploadFile,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "On Device"),
            Tab(text: "Cloud"),
          ],
        ),
      ),
      drawer: _buildDrawer(isLoggedIn),
      body: TabBarView(
        controller: _tabController,
        children: [
          RefreshIndicator(
            onRefresh: () async =>
                _loadLocalBooks(force: true, isRefresh: true),
            child: KeepAliveBookGrid(
              books: localBooks,
              isLoading: isLoadingLocal,
              isLocal: true,
              onlineBooksReference: onlineBooks,
              onUploadRequest: _uploadFromContextMenu,
              onDeleteRequest: _deleteLocalBook,
              onDownloadRequest: null,
              // 🟢 PASS HANDLER
              onBookTap: (b) => _openBook(b, true),
            ),
          ),

          isLoggedIn
              ? RefreshIndicator(
                  onRefresh: () async => _loadOnlineBooks(isRefresh: true),
                  child: KeepAliveBookGrid(
                    books: onlineBooks,
                    isLoading: isLoadingOnline,
                    isLocal: false,
                    onlineBooksReference: null,
                    onUploadRequest: null,
                    onDeleteRequest: _deleteOnlineBook,
                    onDownloadRequest: _downloadOnlineBook,
                    // 🟢 PASS HANDLER
                    onBookTap: (b) => _openBook(b, false),
                  ),
                )
              : _buildLoginPrompt(),
        ],
      ),
    );
  }

  Widget _buildDrawer(bool isLoggedIn) {
    return Drawer(
      child: Builder(
        builder: (context) => ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Theme.of(context).primaryColor),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.white,
                    child: Icon(
                      isLoggedIn ? Icons.person : Icons.person_outline,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isLoggedIn
                        ? (AuthService().username ?? "Cloud User")
                        : "Guest",
                    style: const TextStyle(color: Colors.white, fontSize: 18),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            ListTile(
              leading: Icon(isLoggedIn ? Icons.person : Icons.login),
              title: Text(isLoggedIn ? "Profile" : "Login"),
              onTap: () {
                Navigator.pop(context);
                _handleProfileTap();
              },
            ),
            if (isLoggedIn)
              ListTile(
                leading: const Icon(Icons.download_rounded),
                title: const Text("Activity Queue"),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const QueueView()),
                  );
                },
              ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text("Settings"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const SettingsView()),
                );
              },
            ),
            if (isLoggedIn) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.logout, color: Colors.red),
                title: const Text(
                  "Logout",
                  style: TextStyle(color: Colors.red),
                ),
                onTap: _handleLogout,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildLoginPrompt() => Center(
    child: ElevatedButton(
      onPressed: _handleProfileTap,
      child: const Text("Login to view Cloud Library"),
    ),
  );
}

class KeepAliveBookGrid extends StatefulWidget {
  final List<BookModel> books;
  final bool isLoading;
  final bool isLocal;
  final List<BookModel>? onlineBooksReference;
  final Function(File, String)? onUploadRequest;
  final Function(BookModel)? onDeleteRequest;
  final Function(BookModel)? onDownloadRequest;
  // 🟢 ADD CALLBACK
  final Function(BookModel)? onBookTap;

  const KeepAliveBookGrid({
    super.key,
    required this.books,
    required this.isLoading,
    required this.isLocal,
    this.onlineBooksReference,
    this.onUploadRequest,
    this.onDeleteRequest,
    this.onDownloadRequest,
    this.onBookTap,
  });

  @override
  State<KeepAliveBookGrid> createState() => _KeepAliveBookGridState();
}

class _KeepAliveBookGridState extends State<KeepAliveBookGrid>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  String _normalize(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  bool _isFuzzyMatch(String titleA, String titleB) {
    final a = _normalize(titleA);
    final b = _normalize(titleB);
    if (a == b) return true;
    if (a.length > 4 && b.length > 4) {
      return a.contains(b) || b.contains(a);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Stack(
      children: [
        if (widget.isLoading) const Center(child: CircularProgressIndicator()),
        if (!widget.isLoading && widget.books.isEmpty)
          Center(
            child: Text(
              widget.isLocal ? "No books found." : "No online books.",
            ),
          ),

        GridView.builder(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            childAspectRatio: 0.55,
            crossAxisSpacing: 16,
            mainAxisSpacing: 16,
          ),
          itemCount: widget.books.length,
          itemBuilder: (context, index) {
            final book = widget.books[index];
            double? progress;
            bool isUpload = false;

            bool isInCloud = false;
            if (widget.isLocal && widget.onlineBooksReference != null) {
              isInCloud = widget.onlineBooksReference!.any(
                (b) => _isFuzzyMatch(b.title, book.title),
              );
            }

            if (!widget.isLocal) {
              int bId = int.tryParse(book.id.toString()) ?? -1;
              try {
                final task = DownloadService().tasks.firstWhere(
                  (t) =>
                      t.bookId == bId &&
                      (t.status == DownloadStatus.downloading ||
                          t.status == DownloadStatus.pending),
                );
                progress = task.progress;
              } catch (_) {}
            }
            if (widget.isLocal) {
              try {
                final task = UploadService().tasks.firstWhere(
                  (t) =>
                      t.filePath == book.filePath &&
                      (t.status == UploadStatus.uploading ||
                          t.status == UploadStatus.pending),
                );
                progress = task.progress;
                isUpload = true;
              } catch (_) {}
            }

            return AnimatedBookItem(
              book: book,
              isLocal: widget.isLocal,
              progress: progress,
              isUploading: isUpload,
              isInCloud: isInCloud,

              onTap: () {
                if (progress != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Please wait...")),
                  );
                  return;
                }

                // 🟢 USE CALLBACK
                if (widget.onBookTap != null) widget.onBookTap!(book);
              },

              onShowMenu: (position) =>
                  _showContextMenu(context, position, book),
            );
          },
        ),
      ],
    );
  }

  Future<void> _showContextMenu(
    BuildContext context,
    Offset tapPosition,
    BookModel book,
  ) async {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    bool alreadyDownloaded = LibraryService().isBookDownloaded(book.title);

    bool isDownloading = DownloadService().tasks.any(
      (t) =>
          t.bookId == int.tryParse(book.id.toString()) &&
          (t.status == DownloadStatus.downloading ||
              t.status == DownloadStatus.pending),
    );
    bool isUploading = UploadService().tasks.any(
      (t) =>
          t.filePath == book.filePath &&
          (t.status == UploadStatus.uploading ||
              t.status == UploadStatus.pending),
    );

    bool alreadyInCloud = false;
    if (widget.isLocal && widget.onlineBooksReference != null) {
      alreadyInCloud = widget.onlineBooksReference!.any(
        (b) => _isFuzzyMatch(b.title, book.title),
      );
    }

    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        tapPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        if (widget.isLocal) ...[
          if (isUploading)
            const PopupMenuItem(enabled: false, child: Text("Uploading...")),
          if (alreadyInCloud)
            const PopupMenuItem(enabled: false, child: Text("In Cloud")),
          if (!isUploading && !alreadyInCloud && widget.onUploadRequest != null)
            const PopupMenuItem(value: 'upload', child: Text("Upload")),
        ],
        if (!widget.isLocal) ...[
          if (alreadyDownloaded)
            const PopupMenuItem(enabled: false, child: Text("Downloaded")),
          if (isDownloading)
            const PopupMenuItem(enabled: false, child: Text("Downloading...")),
          if (!alreadyDownloaded &&
              !isDownloading &&
              widget.onDownloadRequest != null)
            const PopupMenuItem(value: 'download', child: Text("Download")),
        ],
        const PopupMenuItem(
          value: 'delete',
          child: Text("Delete", style: TextStyle(color: Colors.red)),
        ),
      ],
    );

    if (!mounted) return;
    if (value == 'upload')
      widget.onUploadRequest!(File(book.filePath!), book.title);
    if (value == 'download') widget.onDownloadRequest!(book);
    if (value == 'delete') {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Delete Book"),
          content: const Text("Are you sure?"),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text("Cancel"),
            ),
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                widget.onDeleteRequest!(book);
              },
              child: const Text("Delete", style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
    }
  }
}

class AnimatedBookItem extends StatefulWidget {
  final BookModel book;
  final bool isLocal;
  final VoidCallback onTap;
  final Future<void> Function(Offset globalPosition) onShowMenu;
  final double? progress;
  final bool isUploading;
  final bool isInCloud;

  const AnimatedBookItem({
    super.key,
    required this.book,
    required this.isLocal,
    required this.onTap,
    required this.onShowMenu,
    this.progress,
    this.isUploading = false,
    this.isInCloud = false,
  });

  @override
  State<AnimatedBookItem> createState() => _AnimatedBookItemState();
}

class _AnimatedBookItemState extends State<AnimatedBookItem>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 0.95,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => _controller.forward(),
      onTapUp: (_) => _controller.reverse(),
      onTapCancel: () => _controller.reverse(),
      onTap: widget.onTap,
      onLongPressStart: (details) async {
        HapticFeedback.mediumImpact();
        await widget.onShowMenu(details.globalPosition);
        _controller.reverse();
      },
      child: ScaleTransition(
        scale: _scaleAnimation,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.grey[200],
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black12,
                      blurRadius: 4,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: widget.progress != null
                    ? ProgressBookCover(
                        progress: widget.progress!,
                        isUploading: widget.isUploading,
                        imageBuilder: _buildCoverImage,
                      )
                    : _buildCoverImage(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              widget.book.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverImage() {
    const BoxFit myFit = BoxFit.fill;
    Widget? indicator;

    if (!widget.isLocal &&
        LibraryService().isBookDownloaded(widget.book.title)) {
      indicator = Positioned(
        top: 6,
        right: 6,
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
          child: const Icon(Icons.check_circle, color: Colors.green, size: 18),
        ),
      );
    } else if (widget.isLocal && widget.isInCloud) {
      indicator = Positioned(
        top: 6,
        right: 6,
        child: Container(
          padding: const EdgeInsets.all(2),
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
          ),
          child: const Icon(Icons.cloud_done, color: Colors.blue, size: 18),
        ),
      );
    }

    Widget image;
    if (widget.isLocal) {
      if (widget.book.coverPath != null &&
          File(widget.book.coverPath!).existsSync()) {
        image = Image.file(
          File(widget.book.coverPath!),
          fit: myFit,
          gaplessPlayback: true,
        );
      } else {
        image = Container(
          color: Colors.grey[300],
          child: const Icon(Icons.book, size: 40, color: Colors.grey),
        );
      }
    } else {
      if (widget.book.coverUrl != null) {
        image = CachedNetworkImage(
          imageUrl: widget.book.coverUrl!,
          httpHeaders: ApiService().authHeaders,
          fit: myFit,
          placeholder: (c, u) => Container(color: Colors.grey[200]),
          errorWidget: (c, u, e) =>
              const Icon(Icons.broken_image, color: Colors.grey),
        );
      } else {
        image = Container(
          color: Colors.grey[300],
          child: const Icon(Icons.cloud, size: 40, color: Colors.blue),
        );
      }
    }

    return Stack(
      children: [
        SizedBox.expand(child: image),
        if (indicator != null) indicator,
      ],
    );
  }
}
