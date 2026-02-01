import 'package:flutter/material.dart';

class ProgressBookCover extends StatelessWidget {
  final double progress;
  final bool isUploading;

  // 🟢 KEY FIX: We accept a builder instead of a URL/Path.
  // This ensures the image widget is identical to the one in your grid,
  // preventing zoom mismatches.
  final Widget Function() imageBuilder;

  const ProgressBookCover({
    super.key,
    required this.progress,
    required this.imageBuilder,
    this.isUploading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand, // Forces layers to fill the parent exactly
      children: [
        // LAYER 1: Grayscale Background
        ColorFiltered(
          colorFilter: const ColorFilter.mode(
            Colors.grey,
            BlendMode.saturation,
          ),
          child: imageBuilder(), // Create Image 1
        ),

        // LAYER 2: Full Color Foreground (Clipped Left-to-Right)
        ClipRect(
          clipper: _ProgressBarClipper(progress),
          child: imageBuilder(), // Create Image 2 (Identical settings)
        ),

        // LAYER 3: Percentage Text
        if (progress > 0 && progress < 1.0)
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                "${(progress * 100).toInt()}%",
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),

        // LAYER 4: Icon
        Positioned(
          top: 4,
          right: 4,
          child: Icon(
            isUploading ? Icons.cloud_upload : Icons.download,
            color: Colors.white.withOpacity(0.8),
            size: 16,
          ),
        ),
      ],
    );
  }
}

// Custom Clipper (Left to Right)
class _ProgressBarClipper extends CustomClipper<Rect> {
  final double progress;

  _ProgressBarClipper(this.progress);

  @override
  Rect getClip(Size size) {
    // Clip from Left (0) to (Width * Progress)
    // Using clamp ensures we don't crash if progress is weird
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
