import 'package:flutter/material.dart';

class ProgressBookCover extends StatelessWidget {
  final double progress;
  final bool isUploading; // 🟢 Kept this new parameter
  final Widget Function() imageBuilder;

  const ProgressBookCover({
    super.key,
    required this.progress,
    required this.imageBuilder,
    this.isUploading = false,
  });

  @override
  Widget build(BuildContext context) {
    // Queued if 0.0, Finished if 1.0
    final bool isQueued = progress <= 0.0;
    final bool isDone = progress >= 1.0;

    return Stack(
      fit: StackFit.expand,
      children: [
        // LAYER 1: Background (Grayscale)
        ColorFiltered(
          colorFilter: const ColorFilter.mode(
            Colors.grey,
            BlendMode.saturation,
          ),
          child: imageBuilder(),
        ),

        // LAYER 2: Foreground (Color) - Clipped (The Animation)
        ClipRect(
          clipper: _ProgressBarClipper(isQueued ? 0.0 : progress),
          child: imageBuilder(),
        ),

        // LAYER 3: Dark Overlay (Make text pop)
        Container(color: Colors.black26),

        // LAYER 4: Status Text & Icon
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 🟢 DYNAMIC ICON LOGIC
              Icon(
                isDone
                    ? Icons.check_circle
                    : (isQueued
                          ? Icons.hourglass_empty
                          : (isUploading
                                ? Icons.cloud_upload
                                : Icons.download)), // 🟢 Swap here
                color: isDone ? Colors.greenAccent : Colors.white,
                size: 28, // Bumped size slightly for visibility
              ),
              const SizedBox(height: 4),

              // Status Pill
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  isDone
                      ? "Done"
                      : (isQueued ? "Queued" : "${(progress * 100).toInt()}%"),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// 🟢 RESTORED CLIPPER CLASS
class _ProgressBarClipper extends CustomClipper<Rect> {
  final double progress;

  _ProgressBarClipper(this.progress);

  @override
  Rect getClip(Size size) {
    return Rect.fromLTRB(
      0,
      0,
      size.width * progress.clamp(0.0, 1.0),
      size.height,
    );
  }

  @override
  bool shouldReclip(covariant _ProgressBarClipper oldClipper) {
    return oldClipper.progress != progress;
  }
}
