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
      if (_apiService.isRssMode) {
        _libraries = [
          {'id': 'rss_library', 'name': 'RSS 播客订阅'}
        ];
        _selectedLibrary = _libraries.first;
        await selectLibrary(_selectedLibrary!);
      } else if (_apiService.isSubsonicMode) {
        _libraries = [
          {'id': 'subsonic_library', 'name': 'Navidrome 音乐库'}
        ];
        _selectedLibrary = _libraries.first;
        await selectLibrary(_selectedLibrary!);
        // 后台静默预加载歌手和歌单数据以获得其总数并预热缓存
        fetchArtists();
        fetchPlaylists();
      } else {
        _libraries = await _apiService.getLibraries();
        if (_libraries.isNotEmpty && _selectedLibrary == null) {
          // 默认选中第一个
          await selectLibrary(_libraries.first);
        }
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
      if (_apiService.isRssMode) {
        final feedUrl = _apiService.currentUrl ?? '';
        final book = await _apiService.parseRssFeed(feedUrl);
        if (book != null) {
          _books = [book];
        }
      } else {
        final libraryId = library['id'] as String;
        _books = await _apiService.getLibraryItems(libraryId);
      }
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

  // --- Subsonic 分类数据流转与状态管理 ---
  List<Map<String, dynamic>> _artists = [];
  List<Map<String, dynamic>> _playlists = [];
  bool _isLoadingArtists = false;
  bool _isLoadingPlaylists = false;

  List<Map<String, dynamic>> get artists => _artists;
  List<Map<String, dynamic>> get playlists => _playlists;
  bool get isLoadingArtists => _isLoadingArtists;
  bool get isLoadingPlaylists => _isLoadingPlaylists;

  // 加载歌手列表
  Future<void> fetchArtists() async {
    _isLoadingArtists = true;
    notifyListeners();
    try {
      _artists = await _apiService.getSubsonicArtists();
    } catch (_) {
      _artists = [];
    } finally {
      _isLoadingArtists = false;
      notifyListeners();
    }
  }

  // 加载歌手的专辑
  Future<List<Book>> fetchArtistAlbums(String artistId) async {
    return await _apiService.getSubsonicArtistAlbums(artistId);
  }

  // 加载歌单列表
  Future<void> fetchPlaylists() async {
    _isLoadingPlaylists = true;
    notifyListeners();
    try {
      _playlists = await _apiService.getSubsonicPlaylists();
    } catch (_) {
      _playlists = [];
    } finally {
      _isLoadingPlaylists = false;
      notifyListeners();
    }
  }

  // 加载歌单并转成虚拟书
  Future<Book?> fetchPlaylistTracksAsBook(String playlistId, String playlistName) async {
    return await _apiService.getSubsonicPlaylistTracks(playlistId, playlistName);
  }

  // 清空全部缓存（切换服务器时调用）
  void clearCache() {
    _libraries = [];
    _selectedLibrary = null;
    _books = [];
    _filteredBooks = [];
    _artists = [];
    _playlists = [];
    _searchQuery = '';
    _isLoading = false;
    _isLoadingArtists = false;
    _isLoadingPlaylists = false;
    notifyListeners();
  }
}
