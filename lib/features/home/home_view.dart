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

    DownloadService().onBookDownloaded = () {
      if (mounted) {
        _loadLocalBooks(force: true, isRefresh: true);
        if (AuthService().isLoggedIn) _loadOnlineBooks(silent: true);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Download completed!"),
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
    super.dispose();
  }

  void _onQueueUpdate() {
    if (mounted) setState(() {});
  }

  void _openBook(BookModel book, bool isLocal) async {
    await LibraryService().updateLastRead(book.id);

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
      final sorted = await LibraryService().sortBooksByRecent(loaded);

      if (mounted) {
        setState(() {
          onlineBooks = sorted;
          isLoadingOnline = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => isLoadingOnline = false);
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // Direct color overrides to avoid TabBarTheme errors
    final accentColor = isDark
        ? const Color.fromARGB(255, 175, 126, 209)
        : const Color(0xFFF5AFAF);

    return Scaffold(
      appBar: AppBar(
        title: const Text("My Library"),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _pickAndUploadFile,
          ),
        ],
        // 🟢 MANUAL TABBAR WITH THEME-MATCHED BORDER
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: theme
                      .dividerColor, // Auto-matches F9DFDF (Light) or Subtle White (Dark)
                  width: 0.5,
                ),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: accentColor,
              unselectedLabelColor: isDark ? Colors.grey : Colors.black54,
              indicatorColor: accentColor,
              // This removes the default thick grey divider
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: "On Device"),
                Tab(text: "Cloud"),
              ],
            ),
          ),
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
                    onBookTap: (b) => _openBook(b, false),
                  ),
                )
              : _buildLoginPrompt(),
        ],
      ),
    );
  }

  Widget _buildDrawer(bool isLoggedIn) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final headerBg = isDark
        ? theme.drawerTheme.backgroundColor
        : theme.primaryColor;

    final headerContentColor = theme.colorScheme.onPrimary;

    return Drawer(
      child: Builder(
        builder: (context) => ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: headerBg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  CircleAvatar(
                    backgroundColor: headerContentColor,
                    child: Icon(
                      isLoggedIn ? Icons.person : Icons.person_outline,
                      color: headerBg,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    isLoggedIn
                        ? (AuthService().username ?? "Cloud User")
                        : "Guest",
                    style: TextStyle(color: headerContentColor, fontSize: 18),
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
  final Function(BookModel)? onBookTap;

  const KeepAliveBookGrid({
    super.key,
    required this.books,
    required this.isLoading,
    required this.isLocal,
    this.onlineBooksReference,
    this.onBookTap,
  });

  @override
  State<KeepAliveBookGrid> createState() => _KeepAliveBookGridState();
}

class _KeepAliveBookGridState extends State<KeepAliveBookGrid>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

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
            return AnimatedBookItem(
              book: book,
              isLocal: widget.isLocal,
              onTap: () {
                if (widget.onBookTap != null) widget.onBookTap!(book);
              },
            );
          },
        ),
      ],
    );
  }
}

class AnimatedBookItem extends StatelessWidget {
  final BookModel book;
  final bool isLocal;
  final VoidCallback onTap;

  const AnimatedBookItem({
    super.key,
    required this.book,
    required this.isLocal,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.grey[200],
                borderRadius: BorderRadius.circular(8),
              ),
              clipBehavior: Clip.antiAlias,
              child:
                  book.coverPath != null && File(book.coverPath!).existsSync()
                  ? Image.file(File(book.coverPath!), fit: BoxFit.cover)
                  : (book.coverUrl != null
                        ? CachedNetworkImage(
                            imageUrl: book.coverUrl!,
                            fit: BoxFit.cover,
                          )
                        : const Icon(Icons.book, size: 40)),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            book.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}
