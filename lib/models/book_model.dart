class BookModel {
  final String id;
  final String title;
  final String author;
  final String? filePath;
  final String? coverPath;
  final String? coverUrl;
  final bool isLocal;
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

  factory BookModel.fromJson(Map<String, dynamic> json, String baseUrl) {
    return BookModel(
      id: json['id'].toString(),
      title: json['title'] ?? "Untitled",
      author: json['author'] ?? "Unknown",
      isLocal: false,
      coverUrl: "$baseUrl/books/${json['id']}/cover",
    );
  }

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
