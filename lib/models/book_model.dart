// 1. The Enum to distinguish file types
enum BookType { epub, pdf }

// 2. The Data Class
class BookModel {
  final String id; // Unique ID (e.g. "harry_potter") used for folder names
  final String title; // Display title (e.g. "Harry Potter")
  final String
  filePath; // The absolute path to the original file (e.g. /Downloads/hp.epub)
  final String coverPath; // The absolute path to the generated cover image
  final BookType type; // Is it PDF or EPUB?

  BookModel({
    required this.id,
    required this.title,
    required this.filePath,
    required this.coverPath,
    required this.type,
  });
}
