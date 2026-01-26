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
}

enum BookType { epub, pdf }
