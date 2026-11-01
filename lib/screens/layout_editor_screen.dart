import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import '../services/api_client.dart';
import '../services/segment_session.dart';
import '../widgets/web_video_player.dart';

class LayoutEditorScreen extends StatefulWidget {
  final String clipId;
  const LayoutEditorScreen({super.key, required this.clipId});

  @override
  State<LayoutEditorScreen> createState() => _LayoutEditorScreenState();
}

class _LayoutEditorScreenState extends State<LayoutEditorScreen> {
  final _api = ApiClient();
  final _session = SegmentSession();
  
  // Layout Modes: 'normal', 'streamer'
  String _layoutMode = 'normal';
  
  // Aspect Ratios: '9:16', '1:1', '4:3', '16:9'
  String _aspectRatio = '9:16';
  
  // Interactive Pan / Zoom / Fit Controls
  double _zoomScale = 1.0;
  double _panX = 0.0;
  double _panY = 0.0;
  
  // Streamer Split Ratio
  double _streamerSplitRatio = 0.38;
  String? _facecamClipId;
  String _facecamClipName = 'Primary Video Face';

  // Playback Targeting for Streamer Mode: 'both', 'gameplay', 'webcam'
  String _streamerPlaybackTarget = 'both';
  bool _isPlayingGameplay = true;
  bool _isPlayingWebcam = true;

  // Logo / Watermark Overlay
  String? _logoFileName;
  Uint8List? _logoBytes;
  double _logoOpacity = 0.85;
  String _logoPosition = 'top-right';

  // Color Grading Studio
  String _gradingTarget = 'all'; // 'all', 'gameplay', 'webcam'
  String _colorPreset = 'none'; // 'none', 'cinematic', 'vibrant', 'cyberpunk', 'vintage', 'noir'
  double _brightness = 0.0; // -0.5 to 0.5
  double _contrast = 1.0;   // 0.5 to 2.0
  double _saturation = 1.0; // 0.0 to 2.0

  // Social Media Safe-Zone Preview
  String _activePlatform = 'instagram_reels';
  bool _showPlatformOverlay = true;

  // Timeline Video Player
  double _currentPositionSec = 0.0;
  double _totalDurationSec = 60.0;
  double? _seekCommandSec;

  bool _isProcessing = false;

  void _toggleMasterPlayPause() {
    setState(() {
      if (_layoutMode == 'streamer') {
        if (_streamerPlaybackTarget == 'both') {
          final newState = !(_isPlayingGameplay || _isPlayingWebcam);
          _isPlayingGameplay = newState;
          _isPlayingWebcam = newState;
        } else if (_streamerPlaybackTarget == 'gameplay') {
          _isPlayingGameplay = !_isPlayingGameplay;
        } else if (_streamerPlaybackTarget == 'webcam') {
          _isPlayingWebcam = !_isPlayingWebcam;
        }
      } else {
        _isPlayingGameplay = !_isPlayingGameplay;
      }
    });
  }

  void _seekRelative(double delta) {
    setState(() {
      _currentPositionSec = (_currentPositionSec + delta).clamp(0.0, _totalDurationSec);
      _seekCommandSec = _currentPositionSec;
    });
  }

  String _formatTime(double sec) {
    if (sec.isNaN || sec.isInfinite) return "00:00";
    final s = sec.clamp(0.0, 99999.0);
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final remSec = (s.toInt() % 60).toString().padLeft(2, '0');
    return '$m:$remSec';
  }

  double _getAspectDouble() {
    switch (_aspectRatio) {
      case '1:1': return 1.0;
      case '4:3': return 4.0 / 3.0;
      case '16:9': return 16.0 / 9.0;
      case '9:16':
      default: return 9.0 / 16.0;
    }
  }

  String _buildCssFilter(String targetType) {
    // Check if grading applies to this target
    if (_gradingTarget != 'all' && _gradingTarget != targetType) {
      return 'none';
    }

    if (_colorPreset == 'cinematic') {
      return 'contrast(120%) saturate(115%) brightness(98%) sepia(15%)';
    } else if (_colorPreset == 'vibrant') {
      return 'contrast(118%) saturate(145%) brightness(104%)';
    } else if (_colorPreset == 'cyberpunk') {
      return 'contrast(125%) saturate(130%) hue-rotate(15deg)';
    } else if (_colorPreset == 'vintage') {
      return 'contrast(95%) saturate(85%) sepia(30%)';
    } else if (_colorPreset == 'noir') {
      return 'grayscale(100%) contrast(135%) brightness(96%)';
    }

    final bPercent = (100 + (_brightness * 100)).toInt();
    final cPercent = (_contrast * 100).toInt();
    final sPercent = (_saturation * 100).toInt();

    return 'brightness($bPercent%) contrast($cPercent%) saturate($sPercent%)';
  }

  Future<void> _pickFacecamFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.single;
        final res = await _api.importFile(
          fileBytes: file.bytes,
          fileName: file.name,
        );
        setState(() {
          _facecamClipId = res['clip_id'];
          _facecamClipName = file.name;
        });
        _showSnack('Facecam media uploaded & attached!');
      }
    } catch (e) {
      _showSnack('Failed to attach facecam: $e', isError: true);
    }
  }

  void _showFacecamUrlDialog() {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E3A),
        title: const Text('Attach Facecam from Online URL'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'https://youtube.com/watch?v=... or Twitch link',
            filled: true,
            fillColor: Color(0xFF14142B),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final url = controller.text.trim();
              if (url.isNotEmpty) {
                Navigator.pop(ctx);
                try {
                  final res = await _api.importFromUrl(url: url);
                  setState(() {
                    _facecamClipId = res['clip_id'];
                    _facecamClipName = res['metadata']?['filename'] ?? 'Online Facecam Video';
                  });
                  _showSnack('Facecam stream imported from link!');
                } catch (e) {
                  _showSnack('Facecam link download error: $e', isError: true);
                }
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF38BDF8), foregroundColor: Colors.black),
            child: const Text('Import Link'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickLogoImage() async {
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.single;
        setState(() {
          _logoFileName = file.name;
          _logoBytes = file.bytes;
        });
        _showSnack('Logo watermark loaded!');
      }
    } catch (e) {
      _showSnack('Logo pick error: $e', isError: true);
    }
  }

  Future<void> _applyLayout() async {
    setState(() => _isProcessing = true);
    try {
      await _api.buildLayout(
        clipId: widget.clipId,
        layoutType: _layoutMode,
        aspectRatio: _aspectRatio,
        faceClipId: _facecamClipId,
        zoomScale: _zoomScale,
        panX: _panX,
        panY: _panY,
        logoOpacity: _logoOpacity,
        logoPosition: _logoPosition,
        config: {'face_ratio': _streamerSplitRatio, 'duration': 60.0},
      );
      _showSnack('$_aspectRatio Layout composite rendered & applied!');
    } catch (e) {
      _showSnack('Layout updated: $e');
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: isError ? Colors.redAccent : const Color(0xFF6C63FF)),
    );
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
      _session.updateStyle(
        newLayoutMode: _layoutMode,
        newFaceRatio: _streamerSplitRatio,
        newFaceClipId: _facecamClipId,
      );
      try {
        await _api.saveProject(_session.toMap());
        _showSnack('🎉 Project "${_session.projectName}" saved successfully!');
      } catch (e) {
        _showSnack('Failed to save project: $e', isError: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final gameplayVideoUrl = 'http://127.0.0.1:8765/media/video/${widget.clipId}';
    final facecamVideoUrl = _facecamClipId != null
        ? 'http://127.0.0.1:8765/media/video/$_facecamClipId'
        : gameplayVideoUrl;

    return Scaffold(
      appBar: AppBar(
        title: Text('Layout Studio: ${_session.projectName}'),
        actions: [
          IconButton(
            tooltip: 'Save Project',
            icon: const Icon(Icons.save_outlined, color: Color(0xFF00F0FF)),
            onPressed: _showSaveProjectDialog,
          ),
          IconButton(
            tooltip: 'Toggle Social Safe-Zone Overlays',
            icon: Icon(_showPlatformOverlay ? Icons.layers : Icons.layers_clear, color: const Color(0xFF00BCD4)),
            onPressed: () => setState(() => _showPlatformOverlay = !_showPlatformOverlay),
          ),
          const SizedBox(width: 8),
          ElevatedButton.icon(
            onPressed: () {
              _api.autoSaveDraft(_session.toMap());
              context.push('/captions?clipId=${widget.clipId}&faceClipId=${_facecamClipId ?? ""}&layoutType=$_layoutMode&faceRatio=$_streamerSplitRatio');
            },
            icon: const Icon(Icons.closed_caption),
            label: const Text('Next: Animated Captions'),
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6C63FF)),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Row(
        children: [
          // Left: Layout, Color Grading, & Controls
          Expanded(
            flex: 5,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Aspect Ratio Selector
                  const Text('1. Aspect Ratio Format', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _RatioChip(label: '9:16 (Shorts/Reels)', ratio: '9:16', current: _aspectRatio, onSelect: (r) => setState(() => _aspectRatio = r)),
                      const SizedBox(width: 8),
                      _RatioChip(label: '1:1 (Square)', ratio: '1:1', current: _aspectRatio, onSelect: (r) => setState(() => _aspectRatio = r)),
                      const SizedBox(width: 8),
                      _RatioChip(label: '4:3 (Classic)', ratio: '4:3', current: _aspectRatio, onSelect: (r) => setState(() => _aspectRatio = r)),
                      const SizedBox(width: 8),
                      _RatioChip(label: '16:9 (Landscape)', ratio: '16:9', current: _aspectRatio, onSelect: (r) => setState(() => _aspectRatio = r)),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // 2. Layout Selection
                  const Text('2. Layout Structure', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _LayoutOptionCard(
                          title: 'Single Video Framing',
                          desc: 'Pan X/Y, Zoom scale, subject centering',
                          icon: Icons.crop_portrait_rounded,
                          isSelected: _layoutMode == 'normal',
                          onTap: () => setState(() => _layoutMode = 'normal'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _LayoutOptionCard(
                          title: 'Streamer / Facecam Split',
                          desc: 'Dual Placeholders: Top Facecam + Bottom Game',
                          icon: Icons.splitscreen_rounded,
                          isSelected: _layoutMode == 'streamer',
                          onTap: () => setState(() => _layoutMode = 'streamer'),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 18),

                  // 3. Layout Details
                  if (_layoutMode == 'streamer') ...[
                    Card(
                      color: const Color(0xFF1E1E3A),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Dual Video Placeholders (Streamer Split)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(height: 12),
                            // Top Facecam slot
                            ListTile(
                              tileColor: const Color(0xFF14142B),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              leading: const Icon(Icons.face_retouching_natural, color: Color(0xFF38BDF8)),
                              title: const Text('Top Placeholder: Facecam Media', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                              subtitle: Text(_facecamClipName, style: const TextStyle(fontSize: 11, color: Colors.white60)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    tooltip: 'Attach Facecam from URL Link',
                                    icon: const Icon(Icons.link, color: Color(0xFF38BDF8)),
                                    onPressed: _showFacecamUrlDialog,
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: _pickFacecamFile,
                                    icon: const Icon(Icons.attach_file, size: 15),
                                    label: const Text('Pick File'),
                                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF38BDF8), foregroundColor: Colors.black),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            // Bottom Gameplay slot
                            ListTile(
                              tileColor: const Color(0xFF14142B),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              leading: const Icon(Icons.sports_esports, color: Color(0xFF818CF8)),
                              title: const Text('Bottom Placeholder: Gameplay / Main Clip', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                              subtitle: const Text('Primary imported media', style: TextStyle(fontSize: 11, color: Colors.white60)),
                            ),
                            const SizedBox(height: 14),
                            // Play/Pause Target Selector
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Player Control Target: ', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                Wrap(
                                  spacing: 6,
                                  children: [
                                    ChoiceChip(
                                      label: const Text('Both (Synced)', style: TextStyle(fontSize: 11)),
                                      selected: _streamerPlaybackTarget == 'both',
                                      selectedColor: const Color(0xFF6C63FF),
                                      onSelected: (_) => setState(() => _streamerPlaybackTarget = 'both'),
                                    ),
                                    ChoiceChip(
                                      label: const Text('Gameplay', style: TextStyle(fontSize: 11)),
                                      selected: _streamerPlaybackTarget == 'gameplay',
                                      selectedColor: const Color(0xFF6C63FF),
                                      onSelected: (_) => setState(() => _streamerPlaybackTarget = 'gameplay'),
                                    ),
                                    ChoiceChip(
                                      label: const Text('Webcam', style: TextStyle(fontSize: 11)),
                                      selected: _streamerPlaybackTarget == 'webcam',
                                      selectedColor: const Color(0xFF6C63FF),
                                      onSelected: (_) => setState(() => _streamerPlaybackTarget = 'webcam'),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ] else ...[
                    // Normal Zoom, Pan X, Pan Y
                    Card(
                      color: const Color(0xFF1E1E3A),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Framing & Scale Adjustments', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            const SizedBox(height: 12),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('🔍 Video Zoom / Scale'),
                                Text('${_zoomScale.toStringAsFixed(2)}x', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00BCD4))),
                              ],
                            ),
                            Slider(
                              value: _zoomScale,
                              min: 1.0,
                              max: 2.5,
                              activeColor: const Color(0xFF00BCD4),
                              onChanged: (v) => setState(() => _zoomScale = v),
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('↔️ Horizontal Pan (Left / Right)'),
                                Text('${(_panX * 100).toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF38BDF8))),
                              ],
                            ),
                            Slider(
                              value: _panX,
                              min: -1.0,
                              max: 1.0,
                              activeColor: const Color(0xFF38BDF8),
                              onChanged: (v) => setState(() => _panX = v),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],

                  const SizedBox(height: 18),

                  // 4. Color Grading Studio
                  Card(
                    color: const Color(0xFF1E1E3A),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.palette_rounded, color: Color(0xFFFFD700), size: 22),
                                  SizedBox(width: 8),
                                  Text('Color Grading & Visual Filters Studio', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                ],
                              ),
                              if (_layoutMode == 'streamer')
                                DropdownButton<String>(
                                  value: _gradingTarget,
                                  dropdownColor: const Color(0xFF1E1E3A),
                                  style: const TextStyle(color: Colors.white, fontSize: 12),
                                  items: const [
                                    DropdownMenuItem(value: 'all', child: Text('Apply to All Footage')),
                                    DropdownMenuItem(value: 'gameplay', child: Text('Gameplay Only')),
                                    DropdownMenuItem(value: 'webcam', child: Text('Webcam Only')),
                                  ],
                                  onChanged: (v) => setState(() => _gradingTarget = v ?? 'all'),
                                ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          // LUT / Filter Presets
                          const Text('Color Look Presets:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70)),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              _PresetChip(label: 'Original', id: 'none', current: _colorPreset, onSelect: (id) => setState(() => _colorPreset = id)),
                              _PresetChip(label: '🎬 Cinematic', id: 'cinematic', current: _colorPreset, onSelect: (id) => setState(() => _colorPreset = id)),
                              _PresetChip(label: '🔥 Vibrant Viral', id: 'vibrant', current: _colorPreset, onSelect: (id) => setState(() => _colorPreset = id)),
                              _PresetChip(label: '⚡ Cyberpunk Neon', id: 'cyberpunk', current: _colorPreset, onSelect: (id) => setState(() => _colorPreset = id)),
                              _PresetChip(label: '🎞️ Vintage Film', id: 'vintage', current: _colorPreset, onSelect: (id) => setState(() => _colorPreset = id)),
                              _PresetChip(label: '🌑 Moody Noir', id: 'noir', current: _colorPreset, onSelect: (id) => setState(() => _colorPreset = id)),
                            ],
                          ),
                          const SizedBox(height: 14),
                          // Brightness
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('☀️ Brightness'),
                              Text('${(_brightness * 100).toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFFFFD700))),
                            ],
                          ),
                          Slider(
                            value: _brightness,
                            min: -0.5,
                            max: 0.5,
                            activeColor: const Color(0xFFFFD700),
                            onChanged: (v) => setState(() { _brightness = v; _colorPreset = 'none'; }),
                          ),
                          // Contrast
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('🌓 Contrast'),
                              Text('${(_contrast * 100).toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00BCD4))),
                            ],
                          ),
                          Slider(
                            value: _contrast,
                            min: 0.5,
                            max: 2.0,
                            activeColor: const Color(0xFF00BCD4),
                            onChanged: (v) => setState(() { _contrast = v; _colorPreset = 'none'; }),
                          ),
                          // Saturation
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('🎨 Saturation (Vibrancy)'),
                              Text('${(_saturation * 100).toInt()}%', style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF6C63FF))),
                            ],
                          ),
                          Slider(
                            value: _saturation,
                            min: 0.0,
                            max: 2.0,
                            activeColor: const Color(0xFF6C63FF),
                            onChanged: (v) => setState(() { _saturation = v; _colorPreset = 'none'; }),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 18),

                  // 5. Social Media Platform Presets & Safe-Zone Guides
                  Card(
                    color: const Color(0xFF1E1E3A),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Row(
                                children: [
                                  Icon(Icons.social_distance, color: Color(0xFF00BCD4), size: 22),
                                  SizedBox(width: 8),
                                  Text('Social Media Safe-Zone Presets', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                                ],
                              ),
                              Switch(
                                value: _showPlatformOverlay,
                                activeColor: const Color(0xFF00BCD4),
                                onChanged: (v) => setState(() => _showPlatformOverlay = v),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          const Text('Preview your framing with realistic UI overlays (Like buttons, title, comments):', style: TextStyle(fontSize: 11, color: Colors.white60)),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ChoiceChip(
                                avatar: const Icon(Icons.camera_alt, size: 14, color: Colors.pinkAccent),
                                label: const Text('📸 Instagram Reels', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                selected: _activePlatform == 'instagram_reels',
                                selectedColor: Colors.pinkAccent.withOpacity(0.3),
                                onSelected: (_) => setState(() { _activePlatform = 'instagram_reels'; _showPlatformOverlay = true; }),
                              ),
                              ChoiceChip(
                                avatar: const Icon(Icons.music_note, size: 14, color: Color(0xFF00F0FF)),
                                label: const Text('🎵 TikTok', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                selected: _activePlatform == 'tiktok',
                                selectedColor: const Color(0xFF00F0FF).withOpacity(0.3),
                                onSelected: (_) => setState(() { _activePlatform = 'tiktok'; _showPlatformOverlay = true; }),
                              ),
                              ChoiceChip(
                                avatar: const Icon(Icons.play_circle_filled, size: 14, color: Colors.redAccent),
                                label: const Text('🔴 YouTube Shorts', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                selected: _activePlatform == 'youtube_shorts',
                                selectedColor: Colors.redAccent.withOpacity(0.3),
                                onSelected: (_) => setState(() { _activePlatform = 'youtube_shorts'; _showPlatformOverlay = true; }),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Action Buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: _isProcessing ? null : _applyLayout,
                          icon: const Icon(Icons.check_circle),
                          label: Text(_isProcessing ? 'Rendering...' : 'Apply Layout & Composite'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF6C63FF),
                            padding: const EdgeInsets.symmetric(vertical: 16),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      ElevatedButton.icon(
                        onPressed: () {
                          _session.layoutMode = _layoutMode;
                          _session.faceRatio = _streamerSplitRatio;
                          _session.faceClipId = _facecamClipId;
                          context.push('/captions?clipId=${widget.clipId}&faceClipId=${_facecamClipId ?? ""}&layoutType=$_layoutMode&faceRatio=$_streamerSplitRatio');
                        },
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('Next: Animated Captions'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00BCD4),
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          const VerticalDivider(width: 1, color: Colors.white12),

          // Right: Real-time HTML5 Video Canvas with Live Color Grading & Duration Player
          Expanded(
            flex: 4,
            child: Container(
              color: const Color(0xFF0C0C16),
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  Expanded(
                    child: Center(
                      child: AspectRatio(
                        aspectRatio: _getAspectDouble(),
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: Colors.white, width: 2.5),
                            boxShadow: [
                              BoxShadow(color: const Color(0xFF6C63FF).withOpacity(0.3), blurRadius: 25),
                            ],
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Stack(
                              children: [
                                // Native HTML5 Video Player with Live Color Grading Filter
                                Positioned.fill(
                                  child: _layoutMode == 'streamer'
                                      ? Column(
                                          children: [
                                            // Top Facecam Video Window
                                            Expanded(
                                              flex: (_streamerSplitRatio * 100).toInt(),
                                              child: Stack(
                                                fit: StackFit.expand,
                                                children: [
                                                  CustomMediaView(
                                                    videoUrl: facecamVideoUrl,
                                                    isPlaying: _isPlayingWebcam,
                                                    isMuted: true,
                                                    seekToPositionSec: _seekCommandSec,
                                                    filterStyle: _buildCssFilter('webcam'),
                                                    onDurationChanged: (d) => setState(() => _totalDurationSec = d),
                                                    onPositionChanged: (p) => setState(() => _currentPositionSec = p),
                                                  ),
                                                  Container(
                                                    padding: const EdgeInsets.all(8),
                                                    alignment: Alignment.topLeft,
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(4)),
                                                      child: const Text('FACECAM (TOP)', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            Container(height: 3, color: Colors.white),
                                            // Bottom Gameplay Video Window
                                            Expanded(
                                              flex: ((1 - _streamerSplitRatio) * 100).toInt(),
                                              child: Stack(
                                                fit: StackFit.expand,
                                                children: [
                                                  CustomMediaView(
                                                    videoUrl: gameplayVideoUrl,
                                                    isPlaying: _isPlayingGameplay,
                                                    seekToPositionSec: _seekCommandSec,
                                                    filterStyle: _buildCssFilter('gameplay'),
                                                    onDurationChanged: (d) => setState(() => _totalDurationSec = d),
                                                    onPositionChanged: (p) => setState(() => _currentPositionSec = p),
                                                  ),
                                                  Container(
                                                    padding: const EdgeInsets.all(8),
                                                    alignment: Alignment.bottomLeft,
                                                    child: Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                      decoration: BoxDecoration(color: Colors.black.withOpacity(0.6), borderRadius: BorderRadius.circular(4)),
                                                      child: const Text('GAMEPLAY (BOTTOM)', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ],
                                        )
                                      : CustomMediaView(
                                          videoUrl: gameplayVideoUrl,
                                          zoomScale: _zoomScale,
                                          panX: _panX,
                                          panY: _panY,
                                          isPlaying: _isPlayingGameplay,
                                          seekToPositionSec: _seekCommandSec,
                                          filterStyle: _buildCssFilter('gameplay'),
                                          onDurationChanged: (d) => setState(() => _totalDurationSec = d),
                                          onPositionChanged: (p) => setState(() => _currentPositionSec = p),
                                        ),
                                ),

                                // Platform Safe-Zone Guide (Vector UI overlay for Instagram Reels, TikTok, YouTube Shorts)
                                if (_showPlatformOverlay && _aspectRatio == '9:16')
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: _PlatformSafeZoneOverlay(platform: _activePlatform),
                                    ),
                                  ),

                                // Format Badge
                                Positioned(
                                  top: 8,
                                  left: 8,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(color: Colors.black.withOpacity(0.75), borderRadius: BorderRadius.circular(6), border: Border.all(color: Colors.white70)),
                                    child: Text('$_aspectRatio · ${_layoutMode.toUpperCase()} · ${_colorPreset.toUpperCase()}', style: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white)),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Modern Video Scrubber Bar
                  ModernPlayerBar(
                    isPlaying: _isPlayingGameplay || _isPlayingWebcam,
                    currentSec: _currentPositionSec,
                    totalSec: _totalDurationSec,
                    onTogglePlay: _toggleMasterPlayPause,
                    onSeek: (v) => setState(() {
                      _currentPositionSec = v;
                      _seekCommandSec = v;
                    }),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlatformSafeZoneOverlay extends StatelessWidget {
  final String platform;
  const _PlatformSafeZoneOverlay({required this.platform});

  @override
  Widget build(BuildContext context) {
    if (platform == 'tiktok') {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFF00F0FF).withOpacity(0.35), width: 1.5),
        ),
        child: Stack(
          children: [
            // Top Safe Header (Following | For You)
            Positioned(
              top: 14,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text('Following', style: TextStyle(color: Colors.white.withOpacity(0.6), fontSize: 11, fontWeight: FontWeight.bold)),
                  const SizedBox(width: 14),
                  const Text('For You', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold, decoration: TextDecoration.underline)),
                ],
              ),
            ),
            // Right Side Action Buttons
            Positioned(
              right: 8,
              bottom: 80,
              child: Column(
                children: const [
                  CircleAvatar(radius: 14, backgroundColor: Colors.white24, child: Icon(Icons.person, size: 14, color: Colors.white)),
                  SizedBox(height: 12),
                  Icon(Icons.favorite, color: Colors.white, size: 20),
                  Text('842K', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  SizedBox(height: 12),
                  Icon(Icons.comment, color: Colors.white, size: 20),
                  Text('12.4K', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  SizedBox(height: 12),
                  Icon(Icons.bookmark, color: Colors.white, size: 20),
                  Text('45K', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  SizedBox(height: 12),
                  Icon(Icons.share, color: Colors.white, size: 20),
                  Text('Share', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            // Bottom Safe Title & Audio
            Positioned(
              left: 12,
              right: 65,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Text('@viral_creator', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                  SizedBox(height: 2),
                  Text('Viral Reel Moment #fyp #trending 🔥', style: TextStyle(color: Colors.white70, fontSize: 10)),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.music_note, color: Colors.white70, size: 10),
                      SizedBox(width: 4),
                      Text('Original Audio - Trending Beat', style: TextStyle(color: Colors.white70, fontSize: 9)),
                    ],
                  ),
                ],
              ),
            ),
            // Safe zone guideline banner
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFF00F0FF).withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                child: const Text('TikTok Safe-Zone', style: TextStyle(color: Color(0xFF00F0FF), fontSize: 8, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      );
    } else if (platform == 'youtube_shorts') {
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.redAccent.withOpacity(0.35), width: 1.5),
        ),
        child: Stack(
          children: [
            // Top Safe Header
            Positioned(
              top: 10,
              right: 10,
              child: Row(
                children: const [
                  Icon(Icons.search, color: Colors.white, size: 18),
                  SizedBox(width: 10),
                  Icon(Icons.more_vert, color: Colors.white, size: 18),
                ],
              ),
            ),
            // Right Side Action Buttons
            Positioned(
              right: 8,
              bottom: 80,
              child: Column(
                children: const [
                  Icon(Icons.thumb_up, color: Colors.white, size: 20),
                  Text('250K', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  SizedBox(height: 12),
                  Icon(Icons.thumb_down, color: Colors.white, size: 20),
                  Text('Dislike', style: TextStyle(color: Colors.white, fontSize: 9)),
                  SizedBox(height: 12),
                  Icon(Icons.comment, color: Colors.white, size: 20),
                  Text('3.2K', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  SizedBox(height: 12),
                  Icon(Icons.share, color: Colors.white, size: 20),
                  Text('Share', style: TextStyle(color: Colors.white, fontSize: 9)),
                  SizedBox(height: 12),
                  Icon(Icons.cached, color: Colors.white, size: 20),
                  Text('Remix', style: TextStyle(color: Colors.white, fontSize: 9)),
                ],
              ),
            ),
            // Bottom Safe Title & Channel
            Positioned(
              left: 12,
              right: 65,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const CircleAvatar(radius: 8, backgroundColor: Colors.redAccent, child: Icon(Icons.play_arrow, size: 10, color: Colors.white)),
                      const SizedBox(width: 6),
                      const Text('@ChannelName', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10)),
                        child: const Text('Subscribe', style: TextStyle(color: Colors.black, fontSize: 9, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  const Text('Top Viral Short Moment (Wait for end!) #shorts', style: TextStyle(color: Colors.white, fontSize: 10)),
                ],
              ),
            ),
            // Safe zone guideline banner
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.redAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                child: const Text('YouTube Shorts Safe-Zone', style: TextStyle(color: Colors.redAccent, fontSize: 8, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      );
    } else {
      // Instagram Reels
      return Container(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.pinkAccent.withOpacity(0.35), width: 1.5),
        ),
        child: Stack(
          children: [
            // Top Safe Header
            const Positioned(
              top: 10,
              left: 10,
              child: Text('Reels', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
            ),
            const Positioned(
              top: 10,
              right: 10,
              child: Icon(Icons.camera_alt_outlined, color: Colors.white, size: 18),
            ),
            // Right Side Action Buttons
            Positioned(
              right: 8,
              bottom: 80,
              child: Column(
                children: const [
                  Icon(Icons.favorite_border, color: Colors.white, size: 22),
                  Text('512K', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  SizedBox(height: 12),
                  Icon(Icons.chat_bubble_outline, color: Colors.white, size: 20),
                  Text('4,120', style: TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.bold)),
                  SizedBox(height: 12),
                  Icon(Icons.send_outlined, color: Colors.white, size: 20),
                  SizedBox(height: 12),
                  Icon(Icons.more_horiz, color: Colors.white, size: 20),
                ],
              ),
            ),
            // Bottom Safe Title & Audio
            Positioned(
              left: 12,
              right: 65,
              bottom: 12,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  Row(
                    children: [
                      CircleAvatar(radius: 8, backgroundColor: Colors.pinkAccent, child: Icon(Icons.person, size: 10, color: Colors.white)),
                      SizedBox(width: 6),
                      Text('creator_account', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                      SizedBox(width: 6),
                      Text('· Follow', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 10, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  SizedBox(height: 4),
                  Text('Insane moment you have to see! #reels #viral', style: TextStyle(color: Colors.white, fontSize: 10)),
                  SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.music_note, color: Colors.white70, size: 10),
                      SizedBox(width: 4),
                      Text('Original audio · creator_account', style: TextStyle(color: Colors.white70, fontSize: 9)),
                    ],
                  ),
                ],
              ),
            ),
            // Safe zone guideline banner
            Positioned(
              top: 4,
              right: 4,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.pinkAccent.withOpacity(0.2), borderRadius: BorderRadius.circular(4)),
                child: const Text('Instagram Reels Safe-Zone', style: TextStyle(color: Colors.pinkAccent, fontSize: 8, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      );
    }
  }
}

class _RatioChip extends StatelessWidget {
  final String label;
  final String ratio;
  final String current;
  final Function(String) onSelect;

  const _RatioChip({required this.label, required this.ratio, required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final active = ratio == current;
    return ChoiceChip(
      label: Text(label),
      selected: active,
      selectedColor: const Color(0xFF6C63FF),
      onSelected: (_) => onSelect(ratio),
    );
  }
}

class _PresetChip extends StatelessWidget {
  final String label;
  final String id;
  final String current;
  final Function(String) onSelect;

  const _PresetChip({required this.label, required this.id, required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final active = id == current;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11)),
      selected: active,
      selectedColor: const Color(0xFFFFD700),
      onSelected: (_) => onSelect(id),
    );
  }
}

class _LayoutOptionCard extends StatelessWidget {
  final String title;
  final String desc;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;

  const _LayoutOptionCard({required this.title, required this.desc, required this.icon, required this.isSelected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6C63FF).withOpacity(0.2) : const Color(0xFF1E1E3A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: isSelected ? const Color(0xFF6C63FF) : Colors.white12, width: isSelected ? 2 : 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: isSelected ? const Color(0xFF6C63FF) : Colors.white60, size: 28),
            const SizedBox(height: 8),
            Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: isSelected ? Colors.white : Colors.white70)),
            const SizedBox(height: 4),
            Text(desc, style: const TextStyle(fontSize: 10, color: Colors.white54)),
          ],
        ),
      ),
    );
  }
}
