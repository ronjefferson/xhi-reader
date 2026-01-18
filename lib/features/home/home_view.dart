import 'dart:io';
import 'package:flutter/material.dart';
import 'home_viewmodel.dart';
import '../reader/reader_view.dart';
import '../../models/book_model.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  final HomeViewModel _viewModel = HomeViewModel();

  @override
  void initState() {
    super.initState();
    _viewModel.loadLibrary();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _viewModel,
      builder: (context, child) {
        return Scaffold(
          appBar: AppBar(
            title: const Text("My Library"),
            actions: [
              IconButton(
                icon: const Icon(Icons.picture_as_pdf),
                onPressed: _viewModel.importPdf,
              ),
            ],
          ),
          body: _viewModel.isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  // 1. Triggers when you pull down
                  onRefresh: _viewModel.refreshLibrary,
                  child: GridView.builder(
                    padding: const EdgeInsets.all(16),
                    // 2. Physics is required for RefreshIndicator to work on short lists
                    physics: const AlwaysScrollableScrollPhysics(),
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          childAspectRatio: 0.65, // Standard book cover ratio
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                    itemCount: _viewModel.books.length,
                    itemBuilder: (context, index) {
                      final book = _viewModel.books[index];
                      return _buildBookCard(context, book);
                    },
                  ),
                ),
        );
      },
    );
  }

  Widget _buildBookCard(BuildContext context, BookModel book) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => ReaderView(book: book)),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(book.coverPath),
                fit: BoxFit.cover,
                // 3. IMPORTANT: This key forces Flutter to redraw the image
                // if the file path or timestamp changes (which happens on refresh)
                key: ValueKey(
                  "${book.coverPath}_${DateTime.now().millisecondsSinceEpoch}",
                ),
                errorBuilder: (c, o, s) => Container(
                  color: Colors.grey[300],
                  child: const Icon(Icons.book, size: 40, color: Colors.grey),
                ),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            book.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }
}
