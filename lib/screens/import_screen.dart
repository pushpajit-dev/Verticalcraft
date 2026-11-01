import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import '../services/api_client.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _urlController = TextEditingController();
  final _batchUrlsController = TextEditingController();
  final _api = ApiClient();
  
  bool _isLoading = false;
  String _status = '';
  Map<String, dynamic>? _lastClip;
  
  // Library clips
  List<Map<String, dynamic>> _libraryClips = [];
  bool _isLoadingLibrary = true;
  final Set<String> _selectedClipIds = {};

  @override
  void initState() {
    super.initState();
    _loadLibrary();
  }

  Future<void> _loadLibrary() async {
    setState(() => _isLoadingLibrary = true);
    try {
      final clips = await _api.getLibrary();
      setState(() {
        _libraryClips = clips;
        _selectedClipIds.clear();
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoadingLibrary = false);
    }
  }

  Future<void> _deleteClip(String clipId, String name) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E3A),
        title: const Text('Delete Clip?'),
        content: Text('Are you sure you want to delete "$name" from your project library?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _api.deleteClip(clipId);
        _showSnack('Clip deleted from library');
        _loadLibrary();
      } catch (e) {
        _showSnack('Failed to delete clip: $e', isError: true);
      }
    }
  }

  Future<void> _deleteSelected() async {
    if (_selectedClipIds.isEmpty) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E3A),
        title: Text('Delete ${_selectedClipIds.length} Selected Clip(s)?'),
        content: const Text('This will remove the selected files from disk.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Delete All Selected'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      for (final id in _selectedClipIds) {
        try { await _api.deleteClip(id); } catch (_) {}
      }
      _showSnack('Selected clips deleted');
      _loadLibrary();
    }
  }

  Future<void> _clearEntireLibrary() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E3A),
        title: const Text('Clear Entire Media Library?'),
        content: const Text('This will delete all imported and downloaded video files from this project.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            child: const Text('Clear All'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _api.clearLibrary();
        _showSnack('Media library cleared');
        _loadLibrary();
      } catch (e) {
        _showSnack('Failed to clear library: $e', isError: true);
      }
    }
  }

  Future<void> _importSingleUrl() async {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      _showSnack('Please paste a valid video URL', isError: true);
      return;
    }
    setState(() {
      _isLoading = true;
      _status = 'Downloading video stream with yt-dlp & FFmpeg...';
    });
    try {
      final res = await _api.importFromUrl(url: url);
      setState(() {
        _lastClip = res;
        _status = 'Download & Analysis complete!';
      });
      _loadLibrary();
      _showSnack('Online video imported successfully!');
    } catch (e) {
      setState(() => _status = 'Error during download: $e');
      _showSnack('Download issue: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _importBatchUrls() async {
    final text = _batchUrlsController.text.trim();
    final urls = text.split('\n').map((u) => u.trim()).where((u) => u.isNotEmpty).toList();
    if (urls.isEmpty) {
      _showSnack('Please enter at least one URL per line', isError: true);
      return;
    }
    setState(() {
      _isLoading = true;
      _status = 'Processing batch download queue of ${urls.length} link(s)...';
    });
    try {
      final results = await _api.importBatchUrls(urls: urls);
      final successful = results.where((r) => r['status'] == 'success').toList();
      if (successful.isNotEmpty) {
        setState(() => _lastClip = successful.first);
      }
      _loadLibrary();
      _showSnack('Batch queue completed: ${successful.length}/${urls.length} downloaded!');
    } catch (e) {
      _showSnack('Batch download error: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _importFiles() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: true,
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      setState(() {
        _isLoading = true;
        _status = 'Uploading and analyzing ${result.files.length} file(s)...';
      });

      for (final file in result.files) {
        final res = await _api.importFile(
          fileBytes: file.bytes,
          fileName: file.name,
        );
        setState(() => _lastClip = res);
      }

      _loadLibrary();
      _showSnack('${result.files.length} video(s) ingested & analyzed!');
    } catch (e) {
      setState(() => _status = 'Upload failed: $e');
      _showSnack('Upload failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: isError ? Colors.redAccent : const Color(0xFF6C63FF),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final meta = _lastClip?['metadata'] as Map<String, dynamic>?;
    final video = meta?['video'] as Map<String, dynamic>?;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Media Ingest & Project Library'),
        actions: [
          IconButton(
            tooltip: 'Refresh Library',
            icon: const Icon(Icons.refresh),
            onPressed: _loadLibrary,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Row with URL and Batch Queue
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left: Single URL + File Picker
                Expanded(
                  flex: 5,
                  child: Column(
                    children: [
                      // Single URL Ingest
                      Card(
                        color: const Color(0xFF1E1E3A),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.cloud_download_rounded, color: Color(0xFF6C63FF), size: 26),
                                  SizedBox(width: 10),
                                  Text('1. Import from Online URL', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              const Text('Paste any YouTube, Twitch, TikTok, or video link:', style: TextStyle(color: Colors.white60, fontSize: 12)),
                              const SizedBox(height: 14),
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _urlController,
                                      decoration: InputDecoration(
                                        hintText: 'https://www.youtube.com/watch?v=...',
                                        prefixIcon: const Icon(Icons.link),
                                        filled: true,
                                        fillColor: const Color(0xFF14142B),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                      ),
                                      onSubmitted: (_) => _isLoading ? null : _importSingleUrl(),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  ElevatedButton.icon(
                                    onPressed: _isLoading ? null : _importSingleUrl,
                                    icon: const Icon(Icons.download, size: 18),
                                    label: const Text('Download'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF6C63FF),
                                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // Local Files Picker
                      Card(
                        color: const Color(0xFF1E1E3A),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: Padding(
                          padding: const EdgeInsets.all(20.0),
                          child: Row(
                            children: [
                              const Icon(Icons.folder_open_rounded, color: Color(0xFF00BCD4), size: 30),
                              const SizedBox(width: 14),
                              const Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('2. Pick Local Video File(s)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                    SizedBox(height: 2),
                                    Text('Cross-platform: MP4, MOV, MKV, WebM', style: TextStyle(color: Colors.white60, fontSize: 12)),
                                  ],
                                ),
                              ),
                              OutlinedButton.icon(
                                onPressed: _isLoading ? null : _importFiles,
                                icon: const Icon(Icons.upload_file),
                                label: const Text('Browse Files'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: const Color(0xFF00BCD4),
                                  side: const BorderSide(color: Color(0xFF00BCD4)),
                                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 16),

                // Right: Batch URL Queue Ingest
                Expanded(
                  flex: 4,
                  child: Card(
                    color: const Color(0xFF1E1E3A),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(20.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.playlist_add_check, color: Color(0xFFFFD700), size: 26),
                              SizedBox(width: 10),
                              Text('3. Batch URL Queue', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text('Paste multiple links (one per line) for batch download:', style: TextStyle(color: Colors.white60, fontSize: 12)),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _batchUrlsController,
                            maxLines: 3,
                            decoration: InputDecoration(
                              hintText: 'https://youtube.com/watch?v=...\nhttps://youtube.com/shorts/...',
                              filled: true,
                              fillColor: const Color(0xFF14142B),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                            ),
                          ),
                          const SizedBox(height: 12),
                          ElevatedButton.icon(
                            onPressed: _isLoading ? null : _importBatchUrls,
                            icon: const Icon(Icons.all_inclusive, size: 18),
                            label: const Text('Download All in Batch'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFFD700),
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // Loading / Status Banner
            if (_isLoading) ...[
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF25254B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF6C63FF)),
                ),
                child: Row(
                  children: [
                    const CircularProgressIndicator(color: Color(0xFF6C63FF)),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(_status, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
            ],

            // Active Analyzed Clip Card (Next: Step 2 AI Highlights & Niche Selection)
            if (_lastClip != null && !_isLoading) ...[
              Card(
                color: const Color(0xFF1B2A4A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: Color(0xFF00BCD4), width: 1.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18.0),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 30),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(meta?['filename'] ?? 'Imported Video', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                            const SizedBox(height: 2),
                            Text('Resolution: ${video?['width'] ?? '?'}x${video?['height'] ?? '?'} · Duration: ${(meta?['duration'] as num?)?.toStringAsFixed(1) ?? '?'}s · FPS: ${video?['fps'] ?? '?'}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                          ],
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => context.push('/highlights?clipId=${_lastClip!["clip_id"]}'),
                        icon: const Icon(Icons.auto_awesome),
                        label: const Text('Next: AI Niche & Smart Trimmer'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6C63FF),
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Project Media Library (Downloaded Clips + Delete Controls)
            Card(
              color: const Color(0xFF1E1E3A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.video_library_rounded, color: Color(0xFF00BCD4), size: 26),
                            const SizedBox(width: 10),
                            const Text('4. Project Media Library', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                            const SizedBox(width: 12),
                            Text('(${_libraryClips.length} clips)', style: const TextStyle(color: Colors.white60, fontSize: 13)),
                          ],
                        ),
                        Row(
                          children: [
                            if (_selectedClipIds.isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: TextButton.icon(
                                  onPressed: _deleteSelected,
                                  icon: const Icon(Icons.delete, color: Colors.redAccent, size: 18),
                                  label: Text('Delete (${_selectedClipIds.length})', style: const TextStyle(color: Colors.redAccent)),
                                ),
                              ),
                            TextButton.icon(
                              onPressed: _libraryClips.isEmpty ? null : _clearEntireLibrary,
                              icon: const Icon(Icons.delete_sweep, color: Colors.redAccent, size: 18),
                              label: const Text('Clear All', style: TextStyle(color: Colors.redAccent)),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    if (_isLoadingLibrary)
                      const Center(child: Padding(padding: EdgeInsets.all(20.0), child: CircularProgressIndicator()))
                    else if (_libraryClips.isEmpty)
                      Container(
                        padding: const EdgeInsets.all(24),
                        alignment: Alignment.center,
                        child: const Text('No clips in library yet. Import a URL or pick a video file above to start!', style: TextStyle(color: Colors.white54)),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _libraryClips.length,
                        separatorBuilder: (_, __) => const Divider(color: Colors.white12, height: 16),
                        itemBuilder: (ctx, idx) {
                          final clip = _libraryClips[idx];
                          final cId = clip['clip_id'] as String;
                          final cMeta = clip['metadata'] as Map<String, dynamic>?;
                          final cVid = cMeta?['video'] as Map<String, dynamic>?;
                          final isSelected = _selectedClipIds.contains(cId);

                          return ListTile(
                            tileColor: const Color(0xFF14142B),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            leading: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Checkbox(
                                  value: isSelected,
                                  activeColor: const Color(0xFF6C63FF),
                                  onChanged: (v) {
                                    setState(() {
                                      if (v == true) _selectedClipIds.add(cId);
                                      else _selectedClipIds.remove(cId);
                                    });
                                  },
                                ),
                                Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF25254B),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(Icons.movie_creation_outlined, color: Color(0xFF6C63FF), size: 20),
                                ),
                              ],
                            ),
                            title: Text(clip['filename'] ?? 'Video Clip', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14), maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              '${cVid?['width'] ?? '?'}x${cVid?['height'] ?? '?'} (${cVid?['aspect_ratio'] ?? '16:9'}) · ${(cMeta?['duration'] as num?)?.toStringAsFixed(1) ?? '?'}s · ${clip['size_mb'] ?? '?'} MB',
                              style: const TextStyle(fontSize: 11, color: Colors.white60),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ElevatedButton.icon(
                                  onPressed: () => context.push('/highlights?clipId=$cId'),
                                  icon: const Icon(Icons.auto_awesome, size: 16),
                                  label: const Text('AI Niche & Trimmer'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF00BCD4),
                                    foregroundColor: Colors.black,
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                IconButton(
                                  tooltip: 'Delete Clip',
                                  icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 20),
                                  onPressed: () => _deleteClip(cId, clip['filename'] ?? 'Clip'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
