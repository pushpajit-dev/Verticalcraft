import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_client.dart';
import '../services/segment_session.dart';

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

class ExportScreen extends StatefulWidget {
  final String clipId;
  const ExportScreen({super.key, required this.clipId});

  @override
  State<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends State<ExportScreen> {
  final _api = ApiClient();
  final _session = SegmentSession();

  // Export Quality Settings
  int _fps = 60;
  int _crf = 20;

  // Custom Output Directory
  final _outputDirController = TextEditingController(text: r"C:\Users\pushp\Desktop\VerticalCraft_Exports");

  // Render & Export State
  bool _isRenderingSingle = false;
  bool _isBatchRendering = false;
  Map<String, dynamic>? _exportedResult;
  Map<String, dynamic>? _batchResult;
  String _hardwareLabel = '⚡ Detecting Hardware Acceleration...';

  // Selected Segment Index for Single Export
  int _activeSegmentIndex = 0;

  @override
  void initState() {
    super.initState();
    _activeSegmentIndex = _session.activeSegmentIndex;
    _fetchHardwareInfo();
  }

  Future<void> _fetchHardwareInfo() async {
    try {
      final hw = await _api.getHardwareInfo();
      if (mounted) {
        setState(() {
          if (hw['nvenc_available'] == true) {
            _hardwareLabel = '⚡ NVIDIA NVENC GPU Hardware Acceleration Active (60 FPS Fast Render)';
          } else {
            _hardwareLabel = '💻 CPU Encoder (libx264 high-quality fallback active)';
          }
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _hardwareLabel = '⚡ Hardware Rendering Ready (1080x1920 60 FPS)');
      }
    }
  }

  void _triggerDownloadUrl(String url, String filename) {
    if (kIsWeb) {
      try {
        final anchor = html.AnchorElement(href: url)
          ..setAttribute('download', filename)
          ..target = '_blank'
          ..style.display = 'none';
        html.document.body?.children.add(anchor);
        anchor.click();
        anchor.remove();
      } catch (_) {
        html.window.open(url, '_blank');
      }
    }
  }

  Future<void> _startSingleExport() async {
    setState(() => _isRenderingSingle = true);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        backgroundColor: Color(0xFF14142B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20)), side: BorderSide(color: Color(0xFF00F0FF), width: 1.5)),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 10),
              SizedBox(
                width: 56,
                height: 56,
                child: CircularProgressIndicator(strokeWidth: 4, valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00F0FF))),
              ),
              SizedBox(height: 20),
              Text(
                '⚡ Rendering 1080x1920 Vertical Short...',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: 8),
              Text(
                'Compositing 9:16 layout, burning kinetic ASS subtitles & rendering with GPU hardware acceleration.',
                style: TextStyle(fontSize: 12, color: Colors.white70),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );

    try {
      final allSegments = _session.allSegments;
      final activeSeg = (_activeSegmentIndex >= 0 && _activeSegmentIndex < allSegments.length)
          ? allSegments[_activeSegmentIndex]
          : (allSegments.isNotEmpty ? allSegments[0] : null);

      final startSec = (activeSeg?['start_time_sec'] ?? activeSeg?['timestamp_sec'] as num?)?.toDouble() ?? 0.0;
      final durSec = (activeSeg?['duration_sec'] as num?)?.toDouble() ?? 30.0;
      final partNum = (activeSeg?['segment_number'] as num?)?.toInt() ?? (_activeSegmentIndex + 1);

      final activeCaptions = _session.segmentCaptions[_activeSegmentIndex] ?? _session.activeSegmentCaptions;

      final res = await _api.renderVideo(
        clipId: widget.clipId,
        outputDirectory: _outputDirController.text.trim(),
        layoutMode: _session.layoutMode,
        faceClipId: _session.faceClipId,
        faceRatio: _session.faceRatio,
        startTimeSec: (allSegments.isNotEmpty && durSec > 0) ? startSec : null,
        durationSec: (allSegments.isNotEmpty && durSec > 0) ? durSec : null,
        segmentNumber: allSegments.isNotEmpty ? partNum : null,
        styleConfig: {
          'stem_model': _session.stemModel,
          'language': _session.language,
          'animation': _session.animation,
          'font_family': _session.font,
          'font_size': _session.fontSize,
          'text_color': _session.textColorHex,
          'highlight_color': _session.highlightColorHex,
          'badge_color': _session.badgeColorHex,
          'pos_y': _session.posY,
          'layout_mode': _session.layoutMode,
          'face_ratio': _session.faceRatio,
          'face_clip_id': _session.faceClipId,
        },
        captionLines: activeCaptions.isNotEmpty ? activeCaptions : null,
        crf: _crf,
        fps: _fps,
      );

      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      setState(() {
        _exportedResult = res;
      });

      final dlUrl = res['download_url'];
      final filename = res['filename'] ?? 'VerticalCraft_Short.mp4';

      if (dlUrl != null) {
        _triggerDownloadUrl(dlUrl, filename);
      }

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF14142B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.greenAccent, width: 1.5)),
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.greenAccent, size: 28),
                SizedBox(width: 10),
                Text('Render Completed!'),
              ],
            ),
            content: SizedBox(
              width: 480,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('🎬 Short saved to: $filename', style: const TextStyle(fontSize: 13, color: Colors.white70)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (dlUrl != null) _triggerDownloadUrl(dlUrl, filename);
                          },
                          icon: const Icon(Icons.download, size: 18),
                          label: const Text('Download MP4 Video'),
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00F0FF), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 12)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: () => _api.openExportFolder(),
                        icon: const Icon(Icons.folder_open, size: 18),
                        label: const Text('Open Folder'),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1F2232), foregroundColor: const Color(0xFF00F0FF), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done', style: TextStyle(color: Colors.white70))),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Render notice: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isRenderingSingle = false);
    }
  }

  Future<void> _startBatchMultiSegmentExport() async {
    List<Map<String, dynamic>> selected = _session.selectedSegments;
    if (selected.isEmpty) {
      if (_session.allSegments.isNotEmpty) {
        selected = List.from(_session.allSegments);
      } else {
        selected = [
          {
            "segment_number": 1,
            "start_time_sec": 0.0,
            "duration_sec": 30.0,
            "title": "Highlight Part 1",
          }
        ];
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF14142B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Color(0xFFFFD700), width: 1.5)),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              const SizedBox(
                width: 56,
                height: 56,
                child: CircularProgressIndicator(strokeWidth: 4, valueColor: AlwaysStoppedAnimation<Color>(Color(0xFFFFD700))),
              ),
              const SizedBox(height: 20),
              Text(
                '⚡ Rendering ${selected.length} Viral Shorts...',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Burning kinetic ASS subtitles, audio mastering & GPU NVENC rendering into a 1-Click ZIP package.',
                style: TextStyle(fontSize: 12, color: Colors.white70),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(color: const Color(0xFF0B0C10), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.flash_on, color: Color(0xFFFFD700), size: 16),
                    const SizedBox(width: 6),
                    Text('Processing ${selected.length} parts in parallel', style: const TextStyle(fontSize: 11, color: Color(0xFFFFD700))),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );

    setState(() => _isBatchRendering = true);

    try {
      final res = await _api.batchProcessSegments(
        clipId: widget.clipId,
        segments: selected,
        styleConfig: {
          'stem_model': _session.stemModel,
          'language': _session.language,
          'animation': _session.animation,
          'font_family': _session.font,
          'font_size': _session.fontSize,
          'text_color': _session.textColorHex,
          'highlight_color': _session.highlightColorHex,
          'badge_color': _session.badgeColorHex,
          'pos_y': _session.posY,
          'layout_mode': _session.layoutMode,
          'face_ratio': _session.faceRatio,
          'face_clip_id': _session.faceClipId,
          'segment_captions': _session.jsonSerializableSegmentCaptions,
        },
      );

      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }

      setState(() {
        _batchResult = res;
      });

      final zipUrl = res['zip_download_url'];
      final zipName = res['zip_filename'] ?? 'VerticalCraft_AllParts.zip';
      final files = (res['files'] as List?)?.cast<String>() ?? [];

      if (zipUrl != null) {
        _triggerDownloadUrl(zipUrl, zipName);
      }

      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            backgroundColor: const Color(0xFF14142B),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: Colors.greenAccent, width: 1.5)),
            title: const Row(
              children: [
                Icon(Icons.check_circle, color: Colors.greenAccent, size: 28),
                SizedBox(width: 10),
                Text('Batch Render Complete!'),
              ],
            ),
            content: SizedBox(
              width: 520,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('🎉 Successfully created ${res["total_segments_processed"] ?? selected.length} 1080x1920 Shorts & master ZIP archive.', style: const TextStyle(fontSize: 13, color: Colors.white70)),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            if (zipUrl != null) _triggerDownloadUrl(zipUrl, zipName);
                          },
                          icon: const Icon(Icons.download, size: 18),
                          label: const Text('Download ZIP Archive'),
                          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(vertical: 12)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      ElevatedButton.icon(
                        onPressed: () => _api.openExportFolder(),
                        icon: const Icon(Icons.folder_open, size: 18),
                        label: const Text('Open Folder'),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1F2232), foregroundColor: const Color(0xFF00F0FF), padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                      ),
                    ],
                  ),
                  if (files.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text('Rendered Video Files:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
                    const SizedBox(height: 6),
                    Container(
                      constraints: const BoxConstraints(maxHeight: 180),
                      decoration: BoxDecoration(color: const Color(0xFF0B0C10), borderRadius: BorderRadius.circular(10)),
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: files.length,
                        separatorBuilder: (_, __) => const Divider(height: 1, color: Colors.white12),
                        itemBuilder: (ctx, idx) => ListTile(
                          dense: true,
                          leading: const Icon(Icons.video_file, color: Color(0xFF00F0FF), size: 20),
                          title: Text(files[idx], style: const TextStyle(fontSize: 11, color: Colors.white)),
                          trailing: IconButton(
                            icon: const Icon(Icons.download, size: 16, color: Color(0xFFFFD700)),
                            tooltip: 'Download Part ${idx + 1}',
                            onPressed: () => _triggerDownloadUrl('http://127.0.0.1:8765/export/download/${files[idx]}', files[idx]),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done', style: TextStyle(color: Colors.white70))),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export notice: $e'), backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) setState(() => _isBatchRendering = false);
    }
  }

  Future<void> _showSaveProjectDialog() async {
    final ctrl = TextEditingController(text: _session.projectName.isNotEmpty ? _session.projectName : 'My Vertical Project');
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141724),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Color(0xFF00F0FF))),
        title: const Row(
          children: [
            Icon(Icons.save_rounded, color: Color(0xFF00F0FF)),
            SizedBox(width: 8),
            Text('Save Project'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Enter a project title to save your segments, layout, captions, and audio settings:', style: TextStyle(fontSize: 12, color: Colors.white70)),
            const SizedBox(height: 14),
            TextField(
              controller: ctrl,
              autofocus: true,
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                filled: true,
                fillColor: const Color(0xFF0F111A),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFF00F0FF))),
                labelText: 'Project Name',
                labelStyle: const TextStyle(color: Color(0xFF00F0FF)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.white60))),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check, size: 16),
            label: const Text('Save Project'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00F0FF), foregroundColor: Colors.black),
          ),
        ],
      ),
    );

    if (saved == true && ctrl.text.trim().isNotEmpty) {
      _session.projectName = ctrl.text.trim();
      try {
        await _api.saveProject(_session.toMap());
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('🎉 Project "${_session.projectName}" saved successfully!'), backgroundColor: Colors.green),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to save project: $e'), backgroundColor: Colors.redAccent),
          );
        }
      }
    }
  }

  String _formatTime(num sec) {
    final s = sec.toDouble();
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final remSec = (s % 60).toStringAsFixed(1).padLeft(4, '0');
    return '$m:$remSec';
  }

  @override
  Widget build(BuildContext context) {
    final allSegments = _session.allSegments.isNotEmpty ? _session.allSegments : [
      {
        'segment_number': 1,
        'title': 'Highlight Part 1',
        'start_time_sec': 0.0,
        'duration_sec': 30.0,
      }
    ];

    final activeSegment = (_activeSegmentIndex >= 0 && _activeSegmentIndex < allSegments.length)
        ? allSegments[_activeSegmentIndex]
        : allSegments[0];

    final startSec = (activeSegment['start_time_sec'] as num?)?.toDouble() ?? 0.0;
    final durSec = (activeSegment['duration_sec'] as num?)?.toDouble() ?? 30.0;
    final activeCaptionsCount = (_session.segmentCaptions[_activeSegmentIndex] ?? _session.activeSegmentCaptions).length;

    return Scaffold(
      backgroundColor: const Color(0xFF0B0C10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F111A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
        title: Row(
          children: [
            const Icon(Icons.download_for_offline, color: Color(0xFF00F0FF), size: 22),
            const SizedBox(width: 10),
            Text('Export Studio: ${_session.projectName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Save Project',
            icon: const Icon(Icons.save_outlined, color: Color(0xFF00F0FF)),
            onPressed: _showSaveProjectDialog,
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () => _api.openExportFolder(),
            icon: const Icon(Icons.folder_open, size: 16),
            label: const Text('Open Export Folder'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF141724),
              foregroundColor: const Color(0xFF00F0FF),
              side: const BorderSide(color: Color(0xFF00F0FF)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 0. Hardware Acceleration & Project Summary Banner
            Container(
              margin: const EdgeInsets.only(bottom: 20),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF0F1B2B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF00F0FF).withOpacity(0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.memory, color: Color(0xFF00F0FF), size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_hardwareLabel, style: const TextStyle(color: Color(0xFF00F0FF), fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(height: 4),
                        Text(
                          'Project: ${_session.projectName}  •  ${allSegments.length} Trimmed Clips  •  Layout: ${_session.layoutMode.toUpperCase()}  •  Kinetic Subtitles: ${_session.animation.toUpperCase()}',
                          style: const TextStyle(color: Colors.white70, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Top Multi-Segment Batch Banner
            Container(
              margin: const EdgeInsets.only(bottom: 24),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF141724),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFFD700).withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.all_inclusive, color: Color(0xFFFFD700), size: 36),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('⚡ Batch Multi-Segment Export Queue (${allSegments.length} Trimmed Clips)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 4),
                        const Text(
                          'Renders every trimmed segment with your customized subtitles, 9:16 layout, audio isolation, and packages everything into a 1-Click ZIP Archive.',
                          style: TextStyle(fontSize: 12, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),
                  ElevatedButton.icon(
                    onPressed: _isBatchRendering ? null : _startBatchMultiSegmentExport,
                    icon: const Icon(Icons.archive, size: 20),
                    label: Text(_isBatchRendering ? 'Rendering Batch...' : '⚡ Render & Export All (${allSegments.length} Clips ZIP)'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFFD700),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),

            // Batch Result Download Box
            if (_batchResult != null) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF102A24),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.greenAccent),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.check_circle, color: Colors.greenAccent, size: 26),
                        const SizedBox(width: 10),
                        Text('Batch ZIP Package Ready (${_batchResult!["total_segments_processed"]} Shorts Generated!)', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('📁 Saved to: ${_batchResult!["export_folder"]}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 12,
                      runSpacing: 10,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () => _triggerDownloadUrl(_batchResult!["zip_download_url"], _batchResult!["zip_filename"]),
                          icon: const Icon(Icons.download, size: 18),
                          label: Text('⬇️ Download Master ZIP Package (${_batchResult!["zip_filename"]})'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.greenAccent,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: () => _api.openExportFolder(),
                          icon: const Icon(Icons.folder_open, size: 18),
                          label: const Text('📂 Open Folder in Explorer'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF0F111A),
                            foregroundColor: const Color(0xFF00F0FF),
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],

            // 2-Column Split: Single Clip Export & All Trimmed Segments List
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Left Column: Single Clip Direct Export
                Expanded(
                  flex: 5,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141724),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.movie_creation_outlined, color: Color(0xFF00F0FF), size: 22),
                            SizedBox(width: 8),
                            Text('1. Single Clip Render (Active Segment)', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        const SizedBox(height: 14),

                        // Segment Selector Chips
                        const Text('Select Clip to Export:', style: TextStyle(fontSize: 12, color: Colors.white70)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: List.generate(allSegments.length, (i) {
                            final isSel = i == _activeSegmentIndex;
                            return ChoiceChip(
                              label: Text('Part ${i + 1} (${_formatTime(allSegments[i]['start_time_sec'] ?? 0)})', style: TextStyle(fontSize: 11, fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
                              selected: isSel,
                              selectedColor: const Color(0xFF00F0FF),
                              backgroundColor: const Color(0xFF0F111A),
                              labelStyle: TextStyle(color: isSel ? Colors.black : Colors.white70),
                              onSelected: (_) => setState(() => _activeSegmentIndex = i),
                            );
                          }),
                        ),
                        const SizedBox(height: 16),

                        // Active Segment Details Card
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: const Color(0xFF0B0C10),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text('Part ${_activeSegmentIndex + 1} Details', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Color(0xFF00F0FF))),
                                  Text('${durSec.toStringAsFixed(1)} Seconds', style: const TextStyle(fontSize: 12, color: Color(0xFFFFD700), fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text('⏱️ Range: ${_formatTime(startSec)} ➔ ${_formatTime(startSec + durSec)}', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                              const SizedBox(height: 4),
                              Text('📝 Subtitles: $activeCaptionsCount Lines (${_session.animation.toUpperCase()} style)', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Framerate & Quality Controls
                        Row(
                          children: [
                            const Text('Framerate: ', style: TextStyle(fontSize: 13)),
                            const SizedBox(width: 8),
                            ChoiceChip(label: const Text('60 FPS (Pro)'), selected: _fps == 60, onSelected: (_) => setState(() => _fps = 60)),
                            const SizedBox(width: 8),
                            ChoiceChip(label: const Text('30 FPS'), selected: _fps == 30, onSelected: (_) => setState(() => _fps = 30)),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Text('Quality (CRF): ', style: TextStyle(fontSize: 13)),
                            const SizedBox(width: 8),
                            ChoiceChip(label: const Text('18 (High Quality)'), selected: _crf == 18, onSelected: (_) => setState(() => _crf = 18)),
                            const SizedBox(width: 8),
                            ChoiceChip(label: const Text('20 (Standard)'), selected: _crf == 20, onSelected: (_) => setState(() => _crf = 20)),
                          ],
                        ),
                        const SizedBox(height: 16),

                        // Output Folder Path
                        const Text('Output Directory:', style: TextStyle(fontSize: 12, color: Colors.white70)),
                        const SizedBox(height: 6),
                        TextField(
                          controller: _outputDirController,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: const Color(0xFF0F111A),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          ),
                        ),
                        const SizedBox(height: 18),

                        ElevatedButton.icon(
                          onPressed: _isRenderingSingle ? null : _startSingleExport,
                          icon: const Icon(Icons.movie_creation, size: 18),
                          label: Text(_isRenderingSingle ? 'Rendering Short...' : '🚀 Render Part ${_activeSegmentIndex + 1} (1080x1920 MP4)'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF00F0FF),
                            foregroundColor: Colors.black,
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),

                        if (_exportedResult != null) ...[
                          const SizedBox(height: 14),
                          ElevatedButton.icon(
                            onPressed: () => _triggerDownloadUrl(_exportedResult!["download_url"], _exportedResult!["filename"]),
                            icon: const Icon(Icons.download),
                            label: Text('⬇️ Download ${_exportedResult!["filename"]}'),
                            style: ElevatedButton.styleFrom(backgroundColor: Colors.greenAccent, foregroundColor: Colors.black, minimumSize: const Size.fromHeight(44)),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),

                const SizedBox(width: 20),

                // Right Column: All Trimmed Clips Queue & Preview
                Expanded(
                  flex: 5,
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141724),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.format_list_numbered, color: Color(0xFFFFD700), size: 22),
                                SizedBox(width: 8),
                                Text('2. Project Trimmed Clips Queue', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                              ],
                            ),
                            Text(
                              '${_session.allSegments.length} Clips Available',
                              style: const TextStyle(color: Color(0xFF00F0FF), fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text('Batch render all selected parts into individual 1080x1920 MP4s and a single packaged master ZIP:', style: TextStyle(fontSize: 11, color: Colors.white60)),
                        const SizedBox(height: 14),

                        // List of clips
                        Container(
                          height: 240,
                          decoration: BoxDecoration(
                            color: const Color(0xFF0F111A),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white.withOpacity(0.05)),
                          ),
                          child: _session.allSegments.isEmpty
                              ? const Center(child: Text('No clips detected or trimmed in session.', style: TextStyle(color: Colors.white54, fontSize: 12)))
                              : ListView.separated(
                                  padding: const EdgeInsets.all(10),
                                  itemCount: _session.allSegments.length,
                                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                                  itemBuilder: (ctx, idx) {
                                    final seg = _session.allSegments[idx];
                                    final isSelected = _session.selectedIndices.contains(idx);
                                    final start = (seg['start_time_sec'] ?? seg['timestamp_sec'] as num?)?.toDouble() ?? 0.0;
                                    final dur = (seg['duration_sec'] as num?)?.toDouble() ?? 30.0;

                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: isSelected ? const Color(0xFF1F2438) : const Color(0xFF141724),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: isSelected ? const Color(0xFF00F0FF) : Colors.transparent),
                                      ),
                                      child: Row(
                                        children: [
                                          Checkbox(
                                            value: isSelected,
                                            activeColor: const Color(0xFF00F0FF),
                                            checkColor: Colors.black,
                                            onChanged: (_) {
                                              setState(() {
                                                _session.toggleIndex(idx);
                                              });
                                            },
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(seg['title']?.toString() ?? 'Part ${idx + 1}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                                                const SizedBox(height: 2),
                                                Text('${_formatTime(start)} ➔ ${_formatTime(start + dur)} (${dur.toInt()}s)', style: const TextStyle(fontSize: 10, color: Colors.white70, fontFamily: 'monospace')),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                        ),
                        const SizedBox(height: 18),

                        ElevatedButton.icon(
                          onPressed: _isBatchRendering ? null : _startBatchMultiSegmentExport,
                          icon: const Icon(Icons.archive, size: 18),
                          label: Text(_isBatchRendering ? 'Rendering Master Archive...' : '📦 Batch Export Selected to Master ZIP (${_session.selectedIndices.length} Parts)'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFFD700),
                            foregroundColor: Colors.black,
                            minimumSize: const Size.fromHeight(48),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),

                        if (_batchResult != null) ...[
                          const SizedBox(height: 14),
                          ElevatedButton.icon(
                            onPressed: () => _triggerDownloadUrl(_batchResult!["download_url"], _batchResult!["zip_filename"]),
                            icon: const Icon(Icons.cloud_download),
                            label: Text('⬇️ Download ZIP Archive: ${_batchResult!["zip_filename"]}'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.greenAccent,
                              foregroundColor: Colors.black,
                              minimumSize: const Size.fromHeight(44),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
