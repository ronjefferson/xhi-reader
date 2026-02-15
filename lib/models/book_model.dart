class BookModel {
  final String id;
  final String title;
  final String author;
  final String? filePath; // Null for Online Books
  final String? coverPath; // Local path (for downloaded books)
  final String? coverUrl; // Online URL (for cloud books)
  final bool isLocal; // The flag to separate them
  final DateTime? lastRead;

  BookModel({
    required this.id,
    required this.title,
    this.author = "Unknown",
    this.filePath,
    this.coverPath,
    this.coverUrl,
    this.isLocal = true,
    this.lastRead,
  });

  // Factory to create a Book from your Backend JSON
  factory BookModel.fromJson(Map<String, dynamic> json, String baseUrl) {
    return BookModel(
      id: json['id'].toString(),
      title: json['title'] ?? "Untitled",
      author: json['author'] ?? "Unknown",
      isLocal: false,
      // Construct the cover URL using the ID (as per your backend spec)
      coverUrl: "$baseUrl/books/${json['id']}/cover",
    );
  }

  // 🟢 NEW: copyWith method
  // This fixes the error in LibraryService by allowing us to easily update timestamps
  BookModel copyWith({
    String? id,
    String? title,
    String? author,
    String? filePath,
    String? coverPath,
    String? coverUrl,
    bool? isLocal,
    DateTime? lastRead,
  }) {
    return BookModel(
      id: id ?? this.id,
      title: title ?? this.title,
      author: author ?? this.author,
      filePath: filePath ?? this.filePath,
      coverPath: coverPath ?? this.coverPath,
      coverUrl: coverUrl ?? this.coverUrl,
      isLocal: isLocal ?? this.isLocal,
      lastRead: lastRead ?? this.lastRead,
    );
  }
}

enum BookType { epub, pdf }
