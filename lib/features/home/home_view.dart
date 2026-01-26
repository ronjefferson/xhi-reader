import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../models/book_model.dart';
import '../../core/services/library_service.dart';
import '../../core/services/auth_service.dart';
import '../../core/services/api_service.dart';
import '../reader/reader_view.dart';
import '../settings/settings_view.dart';
import '../auth/login_view.dart';

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

    // 1. Load Local Books
    _loadLocalBooks();

    // 2. Load Online Books if logged in
    if (AuthService().isLoggedIn) {
      _loadOnlineBooks();
    }

    // 3. Listen for Session Expiry
    _sessionSub = AuthService().sessionExpiredStream.listen((expired) {
      if (expired && mounted) {
        _showSessionExpiredDialog();
      }
    });

    // 4. Listen for Tab Changes
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
    final loaded = await ApiService().fetchUserBooks();
    if (mounted) {
      setState(() {
        onlineBooks = loaded;
        isLoadingOnline = false;
      });
    }
  }

  // --- DIALOGS & ACTIONS ---

  void _showSessionExpiredDialog() {
    setState(() {
      onlineBooks.clear();
    });
    _tabController.animateTo(0);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text("Session Expired"),
        content: const Text(
          "Your login session has ended. Please log in again to access your cloud library.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Do it later"),
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
    // FIX: Removed Scaffold.of(context) check here.
    // The drawer closing logic is handled by the caller (in _buildDrawer).

    if (AuthService().isLoggedIn) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("You are already logged in.")),
      );
    } else {
      final bool? result = await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => const LoginView()),
      );

      // If login was successful (result == true)
      if (result == true) {
        setState(() {}); // Refresh UI
        _loadOnlineBooks();
        _tabController.animateTo(1); // Go to Cloud tab
      }
    }
  }

  void _handleLogout() async {
    Navigator.pop(context); // Close drawer
    await AuthService().logout();

    setState(() {
      onlineBooks.clear();
    });
    _tabController.animateTo(0); // Go to local tab

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text("Logged out successfully")));
  }

  // --- BUILD UI ---

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
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildBookGrid(localBooks, isLoadingLocal, isLocal: true),
          isLoggedIn
              ? _buildBookGrid(onlineBooks, isLoadingOnline, isLocal: false)
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
                  if (!isLoggedIn)
                    const Text(
                      "Log in to sync your books",
                      style: TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                ],
              ),
            ),
            ListTile(
              leading: Icon(isLoggedIn ? Icons.person : Icons.login),
              title: Text(isLoggedIn ? "Profile" : "Login"),
              onTap: () {
                Navigator.pop(
                  context,
                ); // SAFE: Close drawer here using builder context
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
          const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            "Login to view your Cloud Library",
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _handleProfileTap(),
            child: const Text("Login Now"),
          ),
        ],
      ),
    );
  }

  Widget _buildBookGrid(
    List<BookModel> books,
    bool loading, {
    required bool isLocal,
  }) {
    if (loading) return const Center(child: CircularProgressIndicator());
    if (books.isEmpty) {
      return Center(
        child: Text(isLocal ? "No downloads found." : "No online books found."),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 0.65,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      itemCount: books.length,
      itemBuilder: (context, index) {
        final book = books[index];
        return GestureDetector(
          onTap: () {
            if (isLocal) {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => ReaderView(book: book)),
              );
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Online Reader coming next!")),
              );
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black12,
                        blurRadius: 4,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: isLocal
                      // Local Cover
                      ? (book.coverPath != null &&
                                File(book.coverPath!).existsSync()
                            ? Image.file(
                                File(book.coverPath!),
                                fit: BoxFit.cover,
                              )
                            : const Icon(
                                Icons.book,
                                size: 40,
                                color: Colors.grey,
                              ))
                      // Online Cover
                      : (book.coverUrl != null
                            ? CachedNetworkImage(
                                imageUrl: book.coverUrl!,
                                httpHeaders: ApiService().authHeaders,
                                fit: BoxFit.cover,
                                placeholder: (context, url) => const Center(
                                  child: SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  ),
                                ),
                                errorWidget: (context, url, error) =>
                                    const Icon(
                                      Icons.broken_image,
                                      color: Colors.grey,
                                    ),
                                fadeInDuration: const Duration(
                                  milliseconds: 200,
                                ),
                              )
                            : const Icon(
                                Icons.cloud,
                                size: 40,
                                color: Colors.blue,
                              )),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                book.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
