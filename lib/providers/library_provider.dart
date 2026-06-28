import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/book.dart';

class LibraryProvider extends ChangeNotifier {
  final ApiService _apiService;

  List<Map<String, dynamic>> _libraries = [];
  Map<String, dynamic>? _selectedLibrary;
  List<Book> _books = [];
  List<Book> _filteredBooks = [];
  bool _isLoading = false;
  String _searchQuery = '';

  LibraryProvider(this._apiService);

  List<Map<String, dynamic>> get libraries => _libraries;
  Map<String, dynamic>? get selectedLibrary => _selectedLibrary;
  List<Book> get books => _filteredBooks;
  bool get isLoading => _isLoading;
  String get searchQuery => _searchQuery;

  // 加载书库列表
  Future<void> fetchLibraries() async {
    _isLoading = true;
    notifyListeners();

    try {
      _libraries = await _apiService.getLibraries();
      if (_libraries.isNotEmpty && _selectedLibrary == null) {
        // 默认选中第一个
        await selectLibrary(_libraries.first);
      }
    } catch (_) {
      // 容错
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 选中某一个书库，并加载其内容
  Future<void> selectLibrary(Map<String, dynamic> library) async {
    _selectedLibrary = library;
    _books = [];
    _filteredBooks = [];
    _isLoading = true;
    notifyListeners();

    try {
      final libraryId = library['id'] as String;
      _books = await _apiService.getLibraryItems(libraryId);
      _applyFilter();
    } catch (_) {
      // 容错
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  // 搜索过滤
  void search(String query) {
    _searchQuery = query;
    _applyFilter();
  }

  void _applyFilter() {
    if (_searchQuery.trim().isEmpty) {
      _filteredBooks = List.from(_books);
    } else {
      final query = _searchQuery.toLowerCase();
      _filteredBooks = _books.where((book) {
        return book.title.toLowerCase().contains(query) ||
               book.author.toLowerCase().contains(query) ||
               book.narrator.toLowerCase().contains(query);
      }).toList();
    }
    notifyListeners();
  }

  // 加载单本书的最新详情
  Future<Book?> fetchBookDetails(String bookId) async {
    return await _apiService.getBookDetails(bookId);
  }
}
