enum BookType { epub, pdf }

class BookModel {
  final String id;
  final String title;
  final String author;
  final String coverPath;
  final String filePath;
  final BookType type;
  final DateTime? lastRead; // <--- NEW FIELD

  BookModel({
    required this.id,
    required this.title,
    required this.author,
    required this.coverPath,
    required this.filePath,
    this.type = BookType.epub,
    this.lastRead, // <--- NEW PARAMETER
  });
}
