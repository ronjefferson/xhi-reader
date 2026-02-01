import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';

import '../../models/book_model.dart';
import '../../core/services/library_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/api_service.dart';
import '../reader/reader_view.dart';
import '../settings/settings_view.dart';
import '../auth/login_view.dart';
import '../widgets/progress_book_cover.dart';

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

  final Map<int, double> _downloadProgress = {};

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
  }

  @override
  void dispose() {
    _sessionSub?.cancel();
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadLocalBooks({bool force = false}) async {
    setState(() => isLoadingLocal = true);
    final loaded = await LibraryService().scanForEpubs(forceRefresh: force);
    if (mounted) {
      setState(() {
        localBooks = loaded;
        isLoadingLocal = false;
      });
    }
  }

  Future<void> _loadOnlineBooks() async {
    setState(() => isLoadingOnline = true);
    try {
      final loaded = await ApiService().fetchUserBooks();
      if (mounted) {
        setState(() {
          onlineBooks = loaded;
          isLoadingOnline = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => isLoadingOnline = false);
    }
  }

  // --- UPLOAD ---
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
      await _uploadFileProcess(file);
    }
  }

  Future<void> _uploadFileProcess(File file) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final msg = await ApiService().uploadBook(file);

      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.green),
        );
        _loadOnlineBooks();
        _tabController.animateTo(1);
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        if (e.toString().contains("Book already exists")) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("You already have this book in the cloud."),
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Upload Error: $e"),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // --- DOWNLOAD ---
  Future<void> _downloadOnlineBook(BookModel book) async {
    String savePath;
    final safeTitle = book.title.replaceAll(RegExp(r'[^\w\s\.]'), '');
    int bookId = int.parse(book.id.toString());

    if (Platform.isAndroid) {
      if (await Permission.manageExternalStorage.request().isGranted) {
        savePath = "/storage/emulated/0/Download/$safeTitle.epub";
      } else if (await Permission.storage.request().isGranted) {
        savePath = "/storage/emulated/0/Download/$safeTitle.epub";
      } else {
        if (mounted)
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text("Permission denied.")));
        return;
      }
    } else {
      final dir = await getApplicationDocumentsDirectory();
      savePath = "${dir.path}/$safeTitle.epub";
    }

    setState(() {
      _downloadProgress[bookId] = 0.0;
    });

    try {
      await ApiService().downloadBook(
        bookId: bookId,
        savePath: savePath,
        onProgress: (received, total) {
          if (total != -1) {
            setState(() {
              _downloadProgress[bookId] = received / total;
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _downloadProgress.remove(bookId);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Saved to Downloads: $safeTitle.epub"),
            backgroundColor: Colors.green,
          ),
        );

        await _loadLocalBooks(force: true);
        _tabController.animateTo(0);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _downloadProgress.remove(bookId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Download Failed: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _deleteLocalBook(BookModel book) async {
    try {
      if (book.filePath != null) {
        final file = File(book.filePath!);
        if (await file.exists()) await file.delete();
        setState(
          () => localBooks.removeWhere((b) => b.filePath == book.filePath),
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Book deleted from device")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Error deleting file: $e")));
    }
  }

  Future<void> _deleteOnlineBook(BookModel book) async {
    final int index = onlineBooks.indexOf(book);
    setState(() => onlineBooks.remove(book));

    try {
      int bookId = int.parse(book.id.toString());
      final success = await ApiService().deleteBook(bookId);
      if (!success) throw "Server failure";
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Book deleted from cloud")),
        );
    } catch (e) {
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
        content: const Text("Login to upload books to the cloud."),
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
        MaterialPageRoute(builder: (context) => const LoginView()),
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
            icon: const Icon(Icons.refresh),
            onPressed: () {
              if (_tabController.index == 0)
                _loadLocalBooks(force: true);
              else if (isLoggedIn)
                _loadOnlineBooks();
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: primaryColor,
          unselectedLabelColor: Colors.grey,
          indicatorColor: primaryColor,
          tabs: const [
            Tab(text: "On Device", icon: Icon(Icons.phone_android)),
            Tab(text: "Cloud", icon: Icon(Icons.cloud)),
          ],
        ),
      ),
      drawer: _buildDrawer(isLoggedIn),
      floatingActionButton: FloatingActionButton(
        onPressed: _pickAndUploadFile,
        child: const Icon(Icons.add),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          KeepAliveBookGrid(
            books: localBooks,
            isLoading: isLoadingLocal,
            isLocal: true,
            onUploadRequest: _uploadFileProcess,
            onDeleteRequest: _deleteLocalBook,
            onDownloadRequest: null,
          ),
          isLoggedIn
              ? KeepAliveBookGrid(
                  books: onlineBooks,
                  isLoading: isLoadingOnline,
                  isLocal: false,
                  onUploadRequest: null,
                  onDeleteRequest: _deleteOnlineBook,
                  onDownloadRequest: _downloadOnlineBook,
                  activeDownloads: _downloadProgress,
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

  Widget _buildLoginPrompt() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Text("Login to view Cloud Library"),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _handleProfileTap,
            child: const Text("Login"),
          ),
        ],
      ),
    );
  }
}

// --- KEEP ALIVE GRID ---
class KeepAliveBookGrid extends StatefulWidget {
  final List<BookModel> books;
  final bool isLoading;
  final bool isLocal;
  final Function(File)? onUploadRequest;
  final Function(BookModel)? onDeleteRequest;
  final Function(BookModel)? onDownloadRequest;
  final Map<int, double>? activeDownloads;

  const KeepAliveBookGrid({
    super.key,
    required this.books,
    required this.isLoading,
    required this.isLocal,
    this.onUploadRequest,
    this.onDeleteRequest,
    this.onDownloadRequest,
    this.activeDownloads,
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

    if (widget.isLoading)
      return const Center(child: CircularProgressIndicator());
    if (widget.books.isEmpty) {
      return Center(
        child: Text(widget.isLocal ? "No downloads." : "No online books."),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        // 🟢 FIX 1: Adjusted Ratio to 0.55 (Taller to prevent squishing)
        childAspectRatio: 0.55,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: widget.books.length,
      itemBuilder: (context, index) {
        final book = widget.books[index];

        double? progress;
        int bId = int.tryParse(book.id.toString()) ?? -1;
        if (widget.activeDownloads != null &&
            widget.activeDownloads!.containsKey(bId)) {
          progress = widget.activeDownloads![bId];
        }

        return AnimatedBookItem(
          book: book,
          isLocal: widget.isLocal,
          progress: progress,
          onTap: () {
            if (progress != null) return;
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => ReaderView(book: book)),
            );
          },
          onShowMenu: (position) => _showContextMenu(context, position, book),
        );
      },
    );
  }

  Future<void> _showContextMenu(
    BuildContext context,
    Offset tapPosition,
    BookModel book,
  ) async {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;

    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        tapPosition & const Size(40, 40),
        Offset.zero & overlay.size,
      ),
      items: [
        if (widget.isLocal && widget.onUploadRequest != null)
          const PopupMenuItem(
            value: 'upload',
            child: Row(
              children: [
                Icon(Icons.cloud_upload, color: Colors.grey),
                SizedBox(width: 8),
                Text("Upload"),
              ],
            ),
          ),

        if (!widget.isLocal && widget.onDownloadRequest != null)
          const PopupMenuItem(
            value: 'download',
            child: Row(
              children: [
                Icon(Icons.download, color: Colors.blue),
                SizedBox(width: 8),
                Text("Download"),
              ],
            ),
          ),

        const PopupMenuItem(
          value: 'delete',
          child: Row(
            children: [
              Icon(Icons.delete, color: Colors.red),
              SizedBox(width: 8),
              Text("Delete", style: TextStyle(color: Colors.red)),
            ],
          ),
        ),
      ],
    );

    if (value == 'upload' && widget.onUploadRequest != null) {
      if (book.filePath != null) widget.onUploadRequest!(File(book.filePath!));
    } else if (value == 'download' && widget.onDownloadRequest != null) {
      widget.onDownloadRequest!(book);
    } else if (value == 'delete') {
      _confirmDelete(context, book);
    }
  }

  void _confirmDelete(BuildContext context, BookModel book) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("Delete Book"),
        content: Text("Are you sure you want to delete '${book.title}'?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text("Cancel"),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              if (widget.onDeleteRequest != null) {
                widget.onDeleteRequest!(book);
              }
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}

// --- ANIMATED BOOK ITEM (Standardized Sizing) ---
class AnimatedBookItem extends StatefulWidget {
  final BookModel book;
  final bool isLocal;
  final VoidCallback onTap;
  final Future<void> Function(Offset globalPosition) onShowMenu;
  final double? progress;

  const AnimatedBookItem({
    super.key,
    required this.book,
    required this.isLocal,
    required this.onTap,
    required this.onShowMenu,
    this.progress,
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
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // 🟢 HELPER: Creates the image widget with STRETCH fit (No clipping)
  Widget _buildCoverImage() {
    // 🟢 CHANGED: BoxFit.fill to stretch instead of clip (User preference)
    // If you prefer cropping, change this back to BoxFit.cover
    const BoxFit myFit = BoxFit.fill;

    if (widget.isLocal) {
      if (widget.book.coverPath != null &&
          File(widget.book.coverPath!).existsSync()) {
        return SizedBox.expand(
          // 🟢 Force fill parent
          child: Image.file(
            File(widget.book.coverPath!),
            fit: myFit,
            gaplessPlayback: true,
          ),
        );
      } else {
        return SizedBox.expand(
          // 🟢 Placeholder fills same space
          child: Container(
            color: Colors.grey[300],
            child: const Icon(Icons.book, size: 40, color: Colors.grey),
          ),
        );
      }
    } else {
      if (widget.book.coverUrl != null) {
        return SizedBox.expand(
          // 🟢 Force fill parent
          child: CachedNetworkImage(
            imageUrl: widget.book.coverUrl!,
            httpHeaders: ApiService().authHeaders,
            fit: myFit,
            placeholder: (c, u) => Container(color: Colors.grey[200]),
            errorWidget: (c, u, e) =>
                const Icon(Icons.broken_image, color: Colors.grey),
          ),
        );
      } else {
        return SizedBox.expand(
          // 🟢 Placeholder fills same space
          child: Container(
            color: Colors.grey[300],
            child: const Icon(Icons.cloud, size: 40, color: Colors.blue),
          ),
        );
      }
    }
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
                // 🟢 BUILDER PATTERN
                child: widget.progress != null
                    ? ProgressBookCover(
                        progress: widget.progress!,
                        isUploading: widget.isLocal,
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
}
