import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/auth_service.dart';
import 'video_thumbnail.dart';

class VideoSearchDialog extends StatefulWidget {
  const VideoSearchDialog({
    super.key,
    required this.token,
    required this.recentSearches,
    required this.onSearchSubmitted,
    required this.onRemoveSearch,
    required this.onClearSearches,
  });

  final String? token;
  final List<String> recentSearches;
  final ValueChanged<String> onSearchSubmitted;
  final ValueChanged<String> onRemoveSearch;
  final VoidCallback onClearSearches;

  @override
  State<VideoSearchDialog> createState() => _VideoSearchDialogState();
}

class _VideoSearchDialogState extends State<VideoSearchDialog> {
  final TextEditingController _searchController = TextEditingController();
  Future<List<dynamic>>? _searchResults;
  String _query = '';
  late final List<String> _recentSearches = List<String>.from(widget.recentSearches);

  Future<List<dynamic>> _searchEveryPage(String term) async {
    final results = <dynamic>[];
    var page = 1;
    var lastPage = 1;
    do {
      final uri = Uri.parse('${AuthService.baseUrl}/videos').replace(
        queryParameters: {'search': term, 'page': '$page'},
      );
      final response = await http.get(
        uri,
        headers: {
          'Accept': 'application/json',
          if (widget.token != null) 'Authorization': 'Bearer ${widget.token}',
        },
      );
      if (response.statusCode != 200) {
        throw Exception('La recherche est momentanément indisponible.');
      }
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        results.addAll((decoded['data'] as List<dynamic>?) ?? []);
        lastPage = int.tryParse('${decoded['last_page']}') ?? page;
      } else if (decoded is List<dynamic>) {
        results.addAll(decoded);
        lastPage = page;
      }
      page++;
    } while (page <= lastPage);
    return results;
  }

  void _submitSearch([String? value]) {
    final term = (value ?? _searchController.text).trim();
    if (term.isEmpty) return;
    _searchController.text = term;
    setState(() {
      _query = term;
      _searchResults = _searchEveryPage(term);
    });
    widget.onSearchSubmitted(term);
  }

  String _absoluteUrl(Object? rawValue) {
    final raw = rawValue?.toString() ?? '';
    if (raw.isEmpty || raw.startsWith('http')) return raw;
    final base = AuthService.baseUrl.replaceFirst(RegExp(r'/api$'), '');
    return '$base${raw.startsWith('/') ? '' : '/'}$raw';
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final width = math.min(560.0, size.width - 24);
    final height = math.min(590.0, size.height - 32);

    return Dialog(
      backgroundColor: const Color(0xFF171819),
      insetPadding: const EdgeInsets.all(12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: SizedBox(
        width: width,
        height: height,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchController,
                      autofocus: true,
                      textInputAction: TextInputAction.search,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: 'Rechercher des vidéos',
                        hintStyle: const TextStyle(color: Colors.white54),
                        prefixIcon: const Icon(Icons.search, color: Colors.white70),
                        filled: true,
                        fillColor: Colors.white10,
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                      ),
                      onSubmitted: _submitSearch,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fermer la recherche',
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white70),
                  ),
                ],
              ),
            ),
            if (_query.isEmpty) ...[
              if (_recentSearches.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        Expanded(child: Text('Recherches récentes', style: TextStyle(color: Colors.white.withValues(alpha: 0.72), fontSize: 13, fontWeight: FontWeight.w600))),
                        TextButton(
                          onPressed: () {
                            setState(_recentSearches.clear);
                            widget.onClearSearches();
                          },
                          child: const Text('Tout effacer'),
                        ),
                      ],
                    ),
                  ),
                ),
              Expanded(
                child: _recentSearches.isEmpty
                    ? const Center(child: Text('Tes recherches récentes apparaîtront ici.', style: TextStyle(color: Colors.white54)))
                    : ListView.builder(
                        itemCount: _recentSearches.length,
                        itemBuilder: (context, index) {
                          final query = _recentSearches[index];
                          return ListTile(
                            leading: const Icon(Icons.history, color: Colors.white54),
                            title: Text(query, style: const TextStyle(color: Colors.white)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  tooltip: 'Rechercher',
                                  onPressed: () => _submitSearch(query),
                                  icon: const Icon(Icons.north_west, color: Colors.white54, size: 18),
                                ),
                                IconButton(
                                  tooltip: 'Supprimer cette recherche',
                                  onPressed: () {
                                    setState(() => _recentSearches.removeAt(index));
                                    widget.onRemoveSearch(query);
                                  },
                                  icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                                ),
                              ],
                            ),
                            onTap: () => _submitSearch(query),
                          );
                        },
                      ),
              ),
            ] else
              Expanded(
                child: _searchResults == null
                    ? const SizedBox.shrink()
                    : FutureBuilder<List<dynamic>>(
                        future: _searchResults,
                        builder: (context, snapshot) {
                          if (snapshot.connectionState != ConnectionState.done) {
                            return const Center(child: CircularProgressIndicator());
                          }
                          if (snapshot.hasError) {
                            return Center(child: Padding(padding: const EdgeInsets.all(20), child: Text('${snapshot.error}', style: const TextStyle(color: Colors.white70))));
                          }
                          final videos = snapshot.data ?? [];
                          if (videos.isEmpty) {
                            return const Center(child: Text('Aucune vidéo trouvée', style: TextStyle(color: Colors.white70)));
                          }
                          final columns = size.width >= 760 ? 4 : size.width >= 500 ? 3 : 2;
                          return GridView.builder(
                            padding: const EdgeInsets.all(12),
                            itemCount: videos.length,
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: columns,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 10,
                              childAspectRatio: 0.66,
                            ),
                            itemBuilder: (context, index) {
                              final video = Map<String, dynamic>.from(videos[index] as Map);
                              final videoUrl = _absoluteUrl(video['video_path'] ?? video['video_url']);
                              final thumbnailUrl = _absoluteUrl(video['thumbnail_path']);
                              final user = video['user'] is Map ? video['user']['name'] : 'Anonyme';
                              return InkWell(
                                onTap: () => Navigator.pop(context, video),
                                borderRadius: BorderRadius.circular(8),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      VideoThumbnail(thumbnailUrl: thumbnailUrl, videoUrl: videoUrl),
                                      const Align(
                                        alignment: Alignment.center,
                                        child: Icon(Icons.play_circle_fill, color: Colors.white70, size: 38),
                                      ),
                                      Align(
                                        alignment: Alignment.bottomCenter,
                                        child: Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.fromLTRB(8, 24, 8, 8),
                                          decoration: const BoxDecoration(
                                            gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87]),
                                          ),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text((video['title'] ?? 'Sans titre').toString(), maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 12)),
                                              Text('@$user', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white70, fontSize: 10)),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
              ),
          ],
        ),
      ),
    );
  }
}
