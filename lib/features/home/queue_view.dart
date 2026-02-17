import 'package:flutter/material.dart';
import '../../core/services/download_service.dart';
import '../../core/services/upload_service.dart';
import '../../models/download_task.dart';
import '../../models/upload_task.dart';

class QueueView extends StatefulWidget {
  const QueueView({super.key});

  @override
  State<QueueView> createState() => _QueueViewState();
}

class _QueueViewState extends State<QueueView>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = theme.brightness == Brightness.dark
        ? const Color(0xFF635985)
        : const Color(0xFFF5AFAF);

    return Scaffold(
      appBar: AppBar(
        title: const Text("Activity Queue"),
        bottom: TabBar(
          controller: _tabController,
          labelColor: accentColor,
          indicatorColor: accentColor,
          tabs: const [
            Tab(text: "Downloads", icon: Icon(Icons.download)),
            Tab(text: "Uploads", icon: Icon(Icons.cloud_upload)),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [DownloadList(), UploadList()],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 📥 DOWNLOAD LIST
// -----------------------------------------------------------------------------
class DownloadList extends StatelessWidget {
  const DownloadList({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: DownloadService(),
      builder: (context, _) {
        final tasks = DownloadService().tasks;

        if (tasks.isEmpty) {
          return const Center(child: Text("No downloads yet."));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: tasks.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final task = tasks[tasks.length - 1 - index]; // Newest first

            final isDone = task.status == DownloadStatus.completed;
            final isFailed = task.status == DownloadStatus.failed;
            final isRunning = !isDone && !isFailed;

            if (isRunning) {
              return ProgressEntryCard(
                title: task.title,
                status: task.status == DownloadStatus.paused
                    ? "Paused"
                    : "Downloading...",
                progress: task.progress,
                isPaused: task.status == DownloadStatus.paused,
                onPause: () {
                  if (task.status == DownloadStatus.paused) {
                    DownloadService().resumeTask(task);
                  } else {
                    DownloadService().pauseTask(task);
                  }
                },
                onCancel: () => DownloadService().cancelTask(task),
              );
            } else {
              return NotificationEntryCard(
                key: ValueKey(
                  'download_${task.bookId}_${task.status}',
                ), // 🟢 Unique key
                title: task.title,
                message: isDone ? "Download Completed" : "Download Failed",
                icon: isDone ? Icons.check_circle : Icons.error,
                color: isDone ? Colors.green : Colors.red,
                onDelete: () => DownloadService().removeTask(task.bookId),
              );
            }
          },
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// 📤 UPLOAD LIST
// -----------------------------------------------------------------------------
class UploadList extends StatelessWidget {
  const UploadList({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: UploadService(),
      builder: (context, _) {
        final tasks = UploadService().tasks;

        if (tasks.isEmpty) {
          return const Center(child: Text("No uploads yet."));
        }

        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: tasks.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final task = tasks[tasks.length - 1 - index]; // Newest first

            final isDone = task.status == UploadStatus.completed;
            final isFailed = task.status == UploadStatus.failed;
            final isRunning = !isDone && !isFailed;

            if (isRunning) {
              return ProgressEntryCard(
                title: task.title,
                status: "Uploading...",
                progress: task.progress,
                isPaused: false,
                onPause: null,
                onCancel: () {}, // Add cancel logic if needed
              );
            } else {
              return NotificationEntryCard(
                key: ValueKey(
                  'upload_${task.id}_${task.status}',
                ), // 🟢 Unique key
                title: task.title,
                message: isDone
                    ? "Upload Completed"
                    : (task.errorMessage ?? "Upload Failed"),
                icon: isDone ? Icons.cloud_done : Icons.cloud_off,
                color: isDone ? Colors.blue : Colors.red,
                onDelete: () => UploadService().removeTask(task.id),
              );
            }
          },
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// 🟢 PROGRESS ENTRY (Active Tasks)
// -----------------------------------------------------------------------------
class ProgressEntryCard extends StatelessWidget {
  final String title;
  final String status;
  final double progress;
  final bool isPaused;
  final VoidCallback? onPause;
  final VoidCallback onCancel;

  const ProgressEntryCard({
    super.key,
    required this.title,
    required this.status,
    required this.progress,
    required this.isPaused,
    this.onPause,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // 🟢 THEME-AWARE COLORS
    final cardColor = isDark ? const Color(0xFF393053) : Colors.white;
    final iconBgColor = isDark ? const Color(0xFF443C68) : Colors.grey[100];
    final iconColor = isDark ? Colors.white70 : Colors.grey;
    final textColor = isDark ? Colors.white70 : Colors.grey[600];
    final progressBg = isDark ? const Color(0xFF443C68) : Colors.grey[200];
    final accentColor = isDark
        ? const Color(0xFF635985)
        : const Color(0xFFF5AFAF);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconBgColor,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.insert_drive_file, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      status,
                      style: TextStyle(color: textColor, fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (onPause != null)
                IconButton(
                  icon: Icon(
                    isPaused ? Icons.play_arrow : Icons.pause,
                    color: accentColor,
                  ),
                  onPressed: onPause,
                  tooltip: isPaused ? "Resume" : "Pause",
                ),
              IconButton(
                icon: Icon(Icons.close, color: iconColor),
                onPressed: onCancel,
                tooltip: "Cancel",
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: progressBg,
            valueColor: AlwaysStoppedAnimation<Color>(accentColor),
            borderRadius: BorderRadius.circular(4),
            minHeight: 6,
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// 🔵 NOTIFICATION ENTRY (Finished Tasks)
// -----------------------------------------------------------------------------
class NotificationEntryCard extends StatefulWidget {
  final String title;
  final String message;
  final IconData icon;
  final Color color;
  final VoidCallback onDelete;
  final bool autoDismiss;
  final VoidCallback? onAutoDismiss;

  const NotificationEntryCard({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
    required this.color,
    required this.onDelete,
    this.autoDismiss = false,
    this.onAutoDismiss,
  });

  @override
  State<NotificationEntryCard> createState() => _NotificationEntryCardState();
}

class _NotificationEntryCardState extends State<NotificationEntryCard> {
  bool _isMenuOpen = false;

  static const double _actionAreaWidth = 120.0;

  @override
  void initState() {
    super.initState();
    // Queue entries stay until manually deleted
  }

  void _toggleMenu() {
    setState(() => _isMenuOpen = !_isMenuOpen);
  }

  void _closeMenu() {
    if (_isMenuOpen) setState(() => _isMenuOpen = false);
  }

  // 🟢 FIX: Close menu before deleting
  void _handleDelete() {
    _closeMenu();
    // Small delay to let animation complete
    Future.delayed(const Duration(milliseconds: 100), () {
      widget.onDelete();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final screenWidth = MediaQuery.of(context).size.width;
    final availableWidth = screenWidth - 32;
    final double cardWidth = _isMenuOpen
        ? availableWidth - _actionAreaWidth
        : availableWidth;

    // 🟢 THEME-AWARE COLORS
    final bgColor = isDark ? const Color(0xFF443C68) : Colors.grey[100];
    final cardColor = isDark ? const Color(0xFF393053) : Colors.white;
    final borderColor = isDark ? const Color(0xFF635985) : Colors.grey.shade300;

    return TapRegion(
      onTapOutside: (event) => _closeMenu(),
      child: GestureDetector(
        onLongPress: () {
          if (!_isMenuOpen) _toggleMenu();
        },
        onTap: _closeMenu,
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            // 1. BACKGROUND ACTIONS LAYER
            Container(
              height: 72,
              width: availableWidth,
              decoration: BoxDecoration(
                color: bgColor,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  IconButton(
                    onPressed: _handleDelete,
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: "Delete",
                  ),
                  IconButton(
                    onPressed: _closeMenu,
                    icon: Icon(
                      Icons.close,
                      color: isDark ? Colors.white70 : Colors.grey,
                    ),
                    tooltip: "Close",
                  ),
                ],
              ),
            ),

            // 2. FOREGROUND CONTENT LAYER
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              width: cardWidth,
              height: 72,
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(12),
                border: _isMenuOpen ? Border.all(color: borderColor) : null,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(isDark ? 0.3 : 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Row(
                children: [
                  Icon(widget.icon, color: widget.color, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          widget.message,
                          style: TextStyle(
                            color: widget.color,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_isMenuOpen)
                    Icon(
                      Icons.chevron_left,
                      color: (isDark ? Colors.white : Colors.grey).withOpacity(
                        0.3,
                      ),
                      size: 16,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
