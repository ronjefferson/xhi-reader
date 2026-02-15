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
    return Scaffold(
      appBar: AppBar(
        title: const Text("Activity Queue"),
        bottom: TabBar(
          controller: _tabController,
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
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
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
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.insert_drive_file, color: Colors.grey),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      status,
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
              ),
              if (onPause != null)
                IconButton(
                  icon: Icon(
                    isPaused ? Icons.play_arrow : Icons.pause,
                    color: Colors.blue,
                  ),
                  onPressed: onPause,
                  tooltip: isPaused ? "Resume" : "Pause",
                ),
              IconButton(
                icon: const Icon(Icons.close, color: Colors.grey),
                onPressed: onCancel,
                tooltip: "Cancel",
              ),
            ],
          ),
          const SizedBox(height: 12),
          LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.grey[200],
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

  const NotificationEntryCard({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
    required this.color,
    required this.onDelete,
  });

  @override
  State<NotificationEntryCard> createState() => _NotificationEntryCardState();
}

class _NotificationEntryCardState extends State<NotificationEntryCard> {
  bool _isMenuOpen = false;

  // 🟢 Fixed Width for Action Area: Enough for Delete + Close buttons
  static const double _actionAreaWidth = 120.0;

  void _toggleMenu() {
    setState(() => _isMenuOpen = !_isMenuOpen);
  }

  void _closeMenu() {
    if (_isMenuOpen) setState(() => _isMenuOpen = false);
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    // Adjust for list padding (16 left + 16 right = 32)
    final availableWidth = screenWidth - 32;

    // Calculate shrunk width
    final double cardWidth = _isMenuOpen
        ? availableWidth - _actionAreaWidth
        : availableWidth;

    // 🟢 TAP REGION: This detects taps ANYWHERE else on the screen
    return TapRegion(
      onTapOutside: (event) => _closeMenu(),
      child: GestureDetector(
        onLongPress: () {
          if (!_isMenuOpen) _toggleMenu();
        },
        onTap: _closeMenu, // Also close if tapping the card itself while open
        child: Stack(
          alignment: Alignment.centerLeft, // Keep content pinned left
          children: [
            // 1. BACKGROUND ACTIONS LAYER (Revealed on Right)
            Container(
              height: 72,
              width: availableWidth, // Fill full width behind
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              // Padding ensures buttons aren't glued to the edge
              padding: const EdgeInsets.only(right: 8),
              child: Row(
                mainAxisAlignment:
                    MainAxisAlignment.end, // Push buttons to right
                children: [
                  // 🟢 DELETE ICON (Left)
                  IconButton(
                    onPressed: widget.onDelete,
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    tooltip: "Delete",
                  ),

                  // 🟢 CLOSE ICON (Right of Delete)
                  IconButton(
                    onPressed: _closeMenu,
                    icon: const Icon(Icons.close, color: Colors.grey),
                    tooltip: "Close",
                  ),
                ],
              ),
            ),

            // 2. FOREGROUND CONTENT LAYER (Shrinks Width)
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              width: cardWidth,
              height: 72,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: _isMenuOpen
                    ? Border.all(color: Colors.grey.shade300)
                    : null,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
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
                          style: const TextStyle(fontWeight: FontWeight.bold),
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
                  // Small visual hint arrow when closed
                  if (!_isMenuOpen)
                    Icon(
                      Icons.chevron_left,
                      color: Colors.grey.withOpacity(0.3),
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
