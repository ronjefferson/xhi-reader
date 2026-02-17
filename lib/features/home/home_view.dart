import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/book_model.dart';
import '../../core/services/library_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/api_service.dart';
import '../../core/services/download_service.dart';
import '../../core/services/upload_service.dart';

import '../reader/reader_view.dart';
import '../settings/settings_view.dart';
import '../auth/login_view.dart';
import 'queue_view.dart';
import './widgets/progress_book_cover.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

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

    DownloadService().addListener(() {
      if (mounted) setState(() {});
    });
    UploadService().addListener(() {
      if (mounted) setState(() {});
    });

    DownloadService().onBookDownloaded = () {
      if (mounted) {
        _loadLocalBooks(force: true, isRefresh: true);
        setState(() {});
      }
    };

    UploadService().onUploadCompleted = () {
      if (mounted) {
        _loadOnlineBooks(silent: true);
        setState(() {});
      }
    };
  }

  Future<void> _loadLocalBooks({
    bool force = false,
    bool isRefresh = false,
  }) async {
    if (!isRefresh) setState(() => isLoadingLocal = true);
    final loaded = await LibraryService().scanForEpubs(forceRefresh: force);
    if (mounted) {
      setState(() {
        localBooks = loaded;
        isLoadingLocal = false;
      });
    }
  }

  Future<void> _loadOnlineBooks({
    bool silent = false,
    bool isRefresh = false,
  }) async {
    if (!silent && !isRefresh) setState(() => isLoadingOnline = true);
    try {
      final loaded = await ApiService().fetchUserBooks();

      // 🟢 Sort cloud books by recency (last read)
      final sortedBooks = await LibraryService().sortBooksByRecent(loaded);

      if (mounted) {
        setState(() {
          onlineBooks = sortedBooks;
          isLoadingOnline = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => isLoadingOnline = false);
    }
  }

  Future<void> _handleImport() async {
    await LibraryService().importPdf();
    _loadLocalBooks(isRefresh: true);
  }

  String _getOriginalFilename(BookModel book) {
    if (book.filePath != null && book.filePath!.isNotEmpty) {
      return book.id;
    } else {
      return book.title;
    }
  }

  String _normalizeTitle(String title) {
    var text = title.toLowerCase();
    text = text.replaceAll('.pdf', '').replaceAll('.epub', '');
    return text.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  void _openBook(BookModel book, bool isLocal) {
    if (isLocal) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ReaderView(book: book)),
      ).then((_) {
        // 🟢 Re-sort local books when returning from reader
        _loadLocalBooks(isRefresh: true);
      });
      LibraryService().updateLastRead(book.id);
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ReaderView(book: book)),
      ).then((_) {
        // 🟢 Re-sort cloud books when returning from reader
        _loadOnlineBooks(silent: true);
      });
      LibraryService().updateLastRead(book.id);
    }
  }

  bool _isBookSynced(BookModel book, bool isLocal) {
    final otherList = isLocal ? onlineBooks : localBooks;
    final normalizedFilename = _normalizeTitle(_getOriginalFilename(book));

    return otherList.any(
      (b) => _normalizeTitle(_getOriginalFilename(b)) == normalizedFilename,
    );
  }

  void _showBookActions(BookModel book, bool isLocal) {
    final isSynced = _isBookSynced(book, isLocal);

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 60,
                  height: 90,
                  decoration: BoxDecoration(
                    color: Colors.white, // 🟢 White background
                    borderRadius: BorderRadius.circular(4),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: _buildBookCover(book),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    book.title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                    maxLines: 2,
                  ),
                ),
              ],
            ),
            const Divider(height: 32),

            if (isLocal)
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text("Rename"),
                onTap: () {
                  Navigator.pop(context);
                  _showRenameDialog(book);
                },
              ),

            ListTile(
              leading: Icon(
                isLocal
                    ? (isSynced ? Icons.cloud_done : Icons.cloud_upload)
                    : (isSynced ? Icons.check_circle : Icons.download),
              ),
              title: Text(
                isLocal
                    ? (isSynced ? "Already in Cloud" : "Upload to Cloud")
                    : (isSynced ? "Already Downloaded" : "Download"),
              ),
              enabled: !isSynced,
              onTap: isSynced
                  ? null
                  : () {
                      Navigator.pop(context);
                      if (isLocal) {
                        UploadService().addToQueue(File(book.filePath!));
                      } else {
                        final ext = book.title.toLowerCase().endsWith('.epub')
                            ? '.epub'
                            : '.pdf';
                        final baseTitle = book.title
                            .replaceAll(
                              RegExp(r'\.(pdf|epub)$', caseSensitive: false),
                              '',
                            )
                            .replaceAll(RegExp(r'[/\\:*?"<>|]'), '_');
                        final savePath =
                            "/storage/emulated/0/Download/$baseTitle$ext";
                        DownloadService().addToQueue(
                          int.tryParse(book.id) ?? 0,
                          book.title,
                          book.coverUrl ?? "",
                          savePath,
                        );
                      }
                    },
            ),

            // Delete option
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: const Text("Delete"),
              onTap: () async {
                Navigator.pop(context);
                if (isLocal) {
                  // Delete local book
                  await LibraryService().deleteBook(book);
                  _loadLocalBooks(isRefresh: true);
                } else {
                  // Delete cloud book
                  final confirmed = await showDialog<bool>(
                    context: context,
                    builder: (context) => AlertDialog(
                      title: const Text("Delete from Cloud"),
                      content: Text(
                        "Are you sure you want to delete \"${book.title}\" from the cloud? This cannot be undone.",
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text("Cancel"),
                        ),
                        ElevatedButton(
                          onPressed: () => Navigator.pop(context, true),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                          child: const Text("Delete"),
                        ),
                      ],
                    ),
                  );

                  if (confirmed == true) {
                    try {
                      final success = await ApiService().deleteBook(
                        int.parse(book.id),
                      );

                      if (success) {
                        _loadOnlineBooks(silent: true);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Book deleted from cloud"),
                            ),
                          );
                        }
                      } else {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Failed to delete book"),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    } catch (e) {
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text("Error: $e"),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  }
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameDialog(BookModel book) {
    final controller = TextEditingController(text: book.title);
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Rename Book"),
        content: SizedBox(
          width: double.maxFinite,
          child: TextField(
            controller: controller,
            decoration: InputDecoration(
              hintText: "Enter a nickname for this book",
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () => controller.clear(),
                tooltip: "Clear",
              ),
            ),
            maxLines: null,
            minLines: 2,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              await prefs.remove('custom_title_${book.id}');
              Navigator.pop(context);
              _loadLocalBooks(isRefresh: true);
            },
            child: const Text("Revert to Original"),
          ),
          ElevatedButton(
            onPressed: () async {
              final newTitle = controller.text.trim();
              if (newTitle.isNotEmpty) {
                await LibraryService().renameBookVirtual(book.id, newTitle);
              }
              Navigator.pop(context);
              _loadLocalBooks(isRefresh: true);
            },
            child: const Text("Save"),
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
    setState(() {
      onlineBooks.clear();
    });
    _tabController.animateTo(0);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Logged out successfully")));
  }

  Widget _buildBookCover(BookModel book) {
    Widget coverWidget;

    if (book.coverPath != null && File(book.coverPath!).existsSync()) {
      coverWidget = Image.file(File(book.coverPath!), fit: BoxFit.cover);
    } else if (book.coverUrl != null) {
      coverWidget = CachedNetworkImage(
        imageUrl: book.coverUrl!,
        httpHeaders: {
          'Authorization': 'Bearer ${AuthService().token}',
          'ngrok-skip-browser-warning': 'true',
        },
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          color: Colors.white,
          child: const Center(
            child: Icon(Icons.book, size: 48, color: Colors.grey),
          ),
        ),
        errorWidget: (_, __, ___) => Container(
          color: Colors.white,
          child: const Center(
            child: Icon(Icons.book, size: 48, color: Colors.grey),
          ),
        ),
      );
    } else {
      coverWidget = Container(
        color: Colors.white,
        child: const Center(
          child: Icon(Icons.book, size: 48, color: Colors.grey),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: coverWidget,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = theme.brightness == Brightness.dark
        ? const Color.fromARGB(255, 175, 126, 209)
        : const Color(0xFFF5AFAF);

    return Scaffold(
      drawer: _buildDrawer(),
      appBar: AppBar(
        title: const Text("My Library"),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _handleImport),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: theme.dividerColor, width: 0.5),
              ),
            ),
            child: TabBar(
              controller: _tabController,
              labelColor: accentColor,
              indicatorColor: accentColor,
              dividerColor: Colors.transparent,
              tabs: const [
                Tab(text: "On Device"),
                Tab(text: "Cloud"),
              ],
            ),
          ),
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          RefreshIndicator(
            onRefresh: () async =>
                _loadLocalBooks(force: true, isRefresh: true),
            child: KeepAliveBookGrid(
              books: localBooks,
              others: onlineBooks,
              isLoading: isLoadingLocal,
              isLocal: true,
              onTap: (b) => _openBook(b, true),
              onBookLongPress: (b) => _showBookActions(b, true),
            ),
          ),
          AuthService().isLoggedIn
              ? RefreshIndicator(
                  onRefresh: () async => _loadOnlineBooks(isRefresh: true),
                  child: KeepAliveBookGrid(
                    books: onlineBooks,
                    others: localBooks,
                    isLoading: isLoadingOnline,
                    isLocal: false,
                    onTap: (b) => _openBook(b, false),
                    onBookLongPress: (b) => _showBookActions(b, false),
                  ),
                )
              : _buildLoginPrompt(),
        ],
      ),
    );
  }

  Widget _buildDrawer() {
    final isLoggedIn = AuthService().isLoggedIn;
    final theme = Theme.of(context);
    final headerBg = theme.brightness == Brightness.dark
        ? theme.drawerTheme.backgroundColor
        : theme.primaryColor;

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          DrawerHeader(
            decoration: BoxDecoration(color: headerBg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                const CircleAvatar(
                  backgroundColor: Colors.white,
                  child: Icon(Icons.person, color: Colors.grey),
                ),
                const SizedBox(height: 10),
                Text(
                  isLoggedIn ? (AuthService().username ?? "User") : "Guest",
                  style: const TextStyle(color: Colors.white, fontSize: 18),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.login),
            title: Text(isLoggedIn ? "Profile" : "Login"),
            onTap: () {
              Navigator.pop(context);
              _handleProfileTap();
            },
          ),
          if (isLoggedIn)
            ListTile(
              leading: const Icon(Icons.download),
              title: const Text("Queue"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const QueueView()),
                );
              },
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.settings),
            title: const Text("Settings"),
            onTap: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const SettingsView()),
              );
            },
          ),
          if (isLoggedIn)
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text("Logout", style: TextStyle(color: Colors.red)),
              onTap: _handleLogout,
            ),
        ],
      ),
    );
  }

  Widget _buildLoginPrompt() => Center(
    child: ElevatedButton(
      onPressed: _handleProfileTap,
      child: const Text("Login to view cloud"),
    ),
  );
}

class KeepAliveBookGrid extends StatefulWidget {
  final List<BookModel> books;
  final List<BookModel> others;
  final bool isLoading;
  final bool isLocal;
  final Function(BookModel) onTap;
  final Function(BookModel) onBookLongPress;

  const KeepAliveBookGrid({
    super.key,
    required this.books,
    required this.others,
    required this.isLoading,
    required this.isLocal,
    required this.onTap,
    required this.onBookLongPress,
  });

  @override
  State<KeepAliveBookGrid> createState() => _KeepAliveBookGridState();
}

class _KeepAliveBookGridState extends State<KeepAliveBookGrid>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // Track books whose progress overlay should be hidden
  final Set<String> _hiddenOverlays = {};

  // 🟢 FIX: Cache progress values to prevent flickering
  final Map<String, double> _progressCache = {};
  final Map<String, bool> _completionScheduled = {};

  String _getOriginalFilename(BookModel book) {
    if (book.filePath != null && book.filePath!.isNotEmpty) {
      return book.id;
    } else {
      return book.title;
    }
  }

  String _normalizeTitle(String title) {
    var text = title.toLowerCase();
    text = text.replaceAll('.pdf', '').replaceAll('.epub', '');
    return text.replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  // 🟢 FIXED: Check upload progress without flickering
  double _getUploadProgress(BookModel book) {
    final bookKey = book.id;

    if (_hiddenOverlays.contains(bookKey)) {
      return -1.0;
    }

    final tasks = UploadService().tasks;
    try {
      final task = tasks.firstWhere((t) => t.filePath == book.filePath);
      final currentProgress = task.progress;

      // 🟢 Update cache with actual progress
      _progressCache[bookKey] = currentProgress;

      // Schedule hiding after completion (only once)
      if (currentProgress >= 1.0 &&
          !_hiddenOverlays.contains(bookKey) &&
          !_completionScheduled.containsKey(bookKey)) {
        _completionScheduled[bookKey] = true;
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            setState(() {
              _hiddenOverlays.add(bookKey);
              _progressCache.remove(bookKey);
              _completionScheduled.remove(bookKey);
            });
          }
        });
      }

      return currentProgress;
    } catch (e) {
      // 🟢 FIX: Return cached progress if task not found (prevents flicker)
      if (_progressCache.containsKey(bookKey)) {
        final cachedProgress = _progressCache[bookKey]!;
        // Only return cache if it's in progress (not at 0 or 1)
        if (cachedProgress > 0.0 && cachedProgress < 1.0) {
          return cachedProgress;
        }
      }
      _progressCache.remove(bookKey);
      return -1.0; // Not uploading
    }
  }

  // 🟢 FIXED: Check download progress without flickering
  double _getDownloadProgress(BookModel book) {
    final bookKey = book.id;

    if (_hiddenOverlays.contains(bookKey)) {
      return -1.0;
    }

    final tasks = DownloadService().tasks;
    try {
      final normalizedTitle = _normalizeTitle(_getOriginalFilename(book));
      final task = tasks.firstWhere((t) {
        final taskTitle = _normalizeTitle(t.title);
        return taskTitle == normalizedTitle;
      });

      final currentProgress = task.progress;

      // 🟢 Update cache with actual progress
      _progressCache[bookKey] = currentProgress;

      // Schedule hiding after completion (only once)
      if (currentProgress >= 1.0 &&
          !_hiddenOverlays.contains(bookKey) &&
          !_completionScheduled.containsKey(bookKey)) {
        _completionScheduled[bookKey] = true;
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) {
            setState(() {
              _hiddenOverlays.add(bookKey);
              _progressCache.remove(bookKey);
              _completionScheduled.remove(bookKey);
            });
          }
        });
      }

      return currentProgress;
    } catch (e) {
      // 🟢 FIX: Return cached progress if task not found (prevents flicker)
      if (_progressCache.containsKey(bookKey)) {
        final cachedProgress = _progressCache[bookKey]!;
        // Only return cache if it's in progress (not at 0 or 1)
        if (cachedProgress > 0.0 && cachedProgress < 1.0) {
          return cachedProgress;
        }
      }
      _progressCache.remove(bookKey);
      return -1.0; // Not downloading
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    if (widget.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (widget.books.isEmpty) {
      return const Center(child: Text("No books found."));
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: widget.books.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.55,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemBuilder: (context, index) {
        final book = widget.books[index];

        final normalizedFilename = _normalizeTitle(_getOriginalFilename(book));
        final isSynced = widget.others.any(
          (b) => _normalizeTitle(_getOriginalFilename(b)) == normalizedFilename,
        );

        // Get progress
        final uploadProgress = widget.isLocal ? _getUploadProgress(book) : -1.0;
        final downloadProgress = !widget.isLocal
            ? _getDownloadProgress(book)
            : -1.0;

        final isUploading = uploadProgress >= 0.0;
        final isDownloading = downloadProgress >= 0.0;
        final progress = isUploading ? uploadProgress : downloadProgress;

        return GestureDetector(
          onTap: () => widget.onTap(book),
          onLongPress: () => widget.onBookLongPress(book),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white, // 🟢 White background
                        borderRadius: BorderRadius.circular(8),
                      ),
                      clipBehavior: Clip.antiAlias,
                      width: double.infinity,
                      child: (isUploading || isDownloading)
                          ? ProgressBookCover(
                              progress: progress,
                              isUploading: isUploading,
                              imageBuilder: () => _buildBookCover(book),
                            )
                          : _buildBookCover(book),
                    ),

                    if (isSynced && !isUploading && !isDownloading)
                      Positioned(
                        top: 4,
                        right: 4,
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: widget.isLocal
                                ? Colors.blue.withOpacity(0.9)
                                : Colors.green.withOpacity(0.9),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(6),
                          child: Icon(
                            widget.isLocal ? Icons.cloud_done : Icons.check,
                            size: 14,
                            color: Colors.white,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                book.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBookCover(BookModel book) {
    Widget coverWidget;

    if (book.coverPath != null && File(book.coverPath!).existsSync()) {
      coverWidget = Image.file(File(book.coverPath!), fit: BoxFit.cover);
    } else if (book.coverUrl != null) {
      coverWidget = CachedNetworkImage(
        imageUrl: book.coverUrl!,
        httpHeaders: {
          'Authorization': 'Bearer ${AuthService().token}',
          'ngrok-skip-browser-warning': 'true',
        },
        fit: BoxFit.cover,
        placeholder: (context, url) => Container(
          color: Colors.white,
          child: const Center(
            child: Icon(Icons.book, size: 48, color: Colors.grey),
          ),
        ),
        errorWidget: (_, __, ___) => Container(
          color: Colors.white,
          child: const Center(
            child: Icon(Icons.book, size: 48, color: Colors.grey),
          ),
        ),
      );
    } else {
      coverWidget = Container(
        color: Colors.white,
        child: const Center(
          child: Icon(Icons.book, size: 48, color: Colors.grey),
        ),
      );
    }

    return SizedBox(
      width: double.infinity,
      height: double.infinity,
      child: coverWidget,
    );
  }
}
