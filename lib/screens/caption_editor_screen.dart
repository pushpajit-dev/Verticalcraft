import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api_client.dart';
import '../services/segment_session.dart';
import '../widgets/web_video_player.dart';

class CaptionEditorScreen extends StatefulWidget {
  final String clipId;
  final String? faceClipId;
  final String layoutType;
  final double faceRatio;

  const CaptionEditorScreen({
    super.key,
    required this.clipId,
    this.faceClipId,
    this.layoutType = 'normal',
    this.faceRatio = 0.38,
  });

  @override
  State<CaptionEditorScreen> createState() => _CaptionEditorScreenState();
}

class _CaptionEditorScreenState extends State<CaptionEditorScreen> with SingleTickerProviderStateMixin {
  final _api = ApiClient();
  final _session = SegmentSession();

  // Transcription & Language Settings
  String _mode = 'short';
  String _language = 'auto';
  late String _audioSource;

  // Kinetic Animation & Typography
  String _animation = 'popup-blur';
  Color _textColor = Colors.white;
  Color _highlightColor = const Color(0xFFFFD700);
  Color _badgeColor = const Color(0xFFE50914);
  String _fontFamily = 'Montserrat';
  double _fontSize = 24.0;
  bool _isUppercase = true;
  String _activePreset = 'mrbeast';

  // Advanced Styling Effects
  bool _styleGlow = true;
  bool _styleShadow = true;
  bool _styleStroke = false;
  bool _styleBadge = true;
  double _strokeWidth = 2.0;

  // Drag & Position Over Reel
  double _captionPosY = 0.72;
  double _captionPosX = 0.0;

  // Alignment Grid & Text Selector
  bool _showAlignmentGrid = true;
  int _selectedWordIndex = -1;

  // Subtitle Segments Map by Segment Number
  final Map<int, List<Map<String, dynamic>>> _segmentCaptions = {};
  int _activeLineIndex = 0;
  final _manualTextController = TextEditingController();

  // Video playback
  bool _isPlaying = true;
  double _currentPositionSec = 0.0;
  double _totalDurationSec = 60.0;
  double? _seekCommandSec;
  double _playbackRate = 1.0;

  late AnimationController _animController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fadeAnimation;

  bool _isGenerating = false;
  bool _isBatchTranscribing = false;
  int _batchTranscribeProgress = 0;

  final List<Color> _colorSwatches = [
    Colors.white,
    const Color(0xFFFFD700), // Gold
    const Color(0xFF00F0FF), // Cyan
    const Color(0xFF00FF66), // Green
    const Color(0xFFFF0055), // Pink
    const Color(0xFFFF5722), // Orange
    const Color(0xFF8B5CF6), // Purple
    const Color(0xFF38BDF8), // Blue
    Colors.black,
  ];

  @override
  void initState() {
    super.initState();
    _audioSource = (widget.faceClipId != null && widget.faceClipId!.isNotEmpty) ? 'webcam' : 'reel';

    _animController = AnimationController(vsync: this, duration: const Duration(milliseconds: 600))..repeat(reverse: true);
    _scaleAnimation = Tween<double>(begin: 0.88, end: 1.12).animate(CurvedAnimation(parent: _animController, curve: Curves.easeInOutBack));
    _fadeAnimation = Tween<double>(begin: 0.35, end: 1.0).animate(CurvedAnimation(parent: _animController, curve: Curves.easeInOut));

    final activeSeg = _session.activeSegment;
    if (activeSeg != null) {
      _currentPositionSec = (activeSeg['start_time_sec'] as num?)?.toDouble() ?? 0.0;
      _seekCommandSec = _currentPositionSec;
      _totalDurationSec = (activeSeg['duration_sec'] as num?)?.toDouble() ?? 30.0;
    }

    _generateCaptionsForActiveSegment();
  }

  @override
  void dispose() {
    _isPlaying = false;
    CustomMediaView.stopAllBackgroundPlayback();
    _animController.dispose();
    super.dispose();
  }

  void _navigateToRoute(String route) {
    setState(() => _isPlaying = false);
    CustomMediaView.stopAllBackgroundPlayback();
    _syncSessionStyle();
    context.push(route);
  }

  void _syncSessionStyle() {
    _session.segmentCaptions = Map.from(_segmentCaptions);
    _session.updateStyle(
      newFont: _fontFamily,
      newFontSize: _fontSize,
      newAnimation: _animation,
      newPreset: _activePreset,
      newLanguage: _language,
      newTextColor: '#${_textColor.value.toRadixString(16).substring(2)}',
      newHighlightColor: '#${_highlightColor.value.toRadixString(16).substring(2)}',
      newBadgeColor: '#${_badgeColor.value.toRadixString(16).substring(2)}',
      newPosY: _captionPosY,
      newPosX: _captionPosX,
    );
  }

  Future<void> _generateCaptionsForActiveSegment() async {
    setState(() => _isGenerating = true);
    try {
      final audioTargetClipId = (_audioSource == 'webcam' && widget.faceClipId != null && widget.faceClipId!.isNotEmpty)
          ? widget.faceClipId!
          : widget.clipId;

      final activeSeg = _session.activeSegment;
      final start = (activeSeg?['start_time_sec'] ?? activeSeg?['timestamp_sec'] as num?)?.toDouble() ?? 0.0;
      final dur = (activeSeg?['duration_sec'] as num?)?.toDouble() ?? 30.0;

      final res = await _api.generateCaptions(
        clipId: widget.clipId,
        mode: _mode,
        language: _language,
        animation: _animation,
        audioSourceClipId: audioTargetClipId,
        startTimeSec: (_session.allSegments.isNotEmpty && dur > 0) ? start : null,
        durationSec: (_session.allSegments.isNotEmpty && dur > 0) ? dur : null,
      );
      if (res['lines'] != null && (res['lines'] as List).isNotEmpty) {
        setState(() {
          _segmentCaptions[_session.activeSegmentIndex] = List<Map<String, dynamic>>.from(res['lines']);
          _activeLineIndex = 0;
        });
      }
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isGenerating = false);
    }
  }

  Future<void> _batchTranscribeAllSelectedSegments() async {
    final selected = _session.selectedSegments;
    if (selected.isEmpty) return;

    setState(() {
      _isBatchTranscribing = true;
      _batchTranscribeProgress = 0;
    });

    try {
      for (int i = 0; i < selected.length; i++) {
        final seg = selected[i];
        final segIndex = _session.allSegments.indexOf(seg);
        final start = (seg['start_time_sec'] ?? seg['timestamp_sec'] as num?)?.toDouble() ?? 0.0;
        final dur = (seg['duration_sec'] as num?)?.toDouble() ?? 30.0;
        if (segIndex != -1) {
          final res = await _api.generateCaptions(
            clipId: widget.clipId,
            mode: _mode,
            language: _language,
            animation: _animation,
            startTimeSec: start,
            durationSec: dur,
          );
          if (res['lines'] != null) {
            _segmentCaptions[segIndex] = List<Map<String, dynamic>>.from(res['lines']);
          }
        }
        if (mounted) {
          setState(() {
            _batchTranscribeProgress = i + 1;
          });
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully transcribed all ${selected.length} segments in ${_getLanguageName(_language)}!'),
            backgroundColor: const Color(0xFF00F0FF),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Batch transcription notice: $e'), backgroundColor: Colors.orange),
        );
      }
    } finally {
      if (mounted) setState(() => _isBatchTranscribing = false);
    }
  }

  void _switchActiveSegment(int index) {
    setState(() {
      _session.selectSegment(index);
      final seg = _session.activeSegment;
      if (seg != null) {
        final start = (seg['start_time_sec'] as num?)?.toDouble() ?? 0.0;
        final dur = (seg['duration_sec'] as num?)?.toDouble() ?? 30.0;
        _currentPositionSec = start;
        _seekCommandSec = start;
        _totalDurationSec = dur;
      }
      _activeLineIndex = 0;
    });
    if (!_segmentCaptions.containsKey(index)) {
      _generateCaptionsForActiveSegment();
    }
  }

  void _onVideoPositionUpdated(double positionSec) {
    setState(() {
      _currentPositionSec = positionSec;
      final lines = _segmentCaptions[_session.activeSegmentIndex] ?? [];
      if (lines.isNotEmpty) {
        for (int i = 0; i < lines.length; i++) {
          final start = (lines[i]['start'] as num).toDouble();
          final end = (lines[i]['end'] as num).toDouble();
          if (positionSec >= start && positionSec <= end) {
            if (_activeLineIndex != i) {
              _activeLineIndex = i;
            }
            break;
          }
        }
      }
    });
  }

  void _applyStylePreset(String preset) {
    setState(() {
      _activePreset = preset;
      switch (preset) {
        case 'mrbeast':
          _textColor = Colors.white;
          _highlightColor = const Color(0xFFFFD700);
          _fontFamily = 'Montserrat';
          _animation = 'popup';
          _isUppercase = true;
          _fontSize = 24.0;
          _styleBadge = true;
          _badgeColor = Colors.black.withOpacity(0.7);
          _styleGlow = true;
          _styleShadow = true;
          _styleStroke = false;
          break;
        case 'hormozi':
          _textColor = Colors.white;
          _highlightColor = Colors.white;
          _badgeColor = const Color(0xFFE50914);
          _fontFamily = 'Inter';
          _animation = 'popup-blur';
          _isUppercase = true;
          _fontSize = 24.0;
          _styleBadge = true;
          _styleGlow = false;
          _styleShadow = true;
          _styleStroke = false;
          break;
        case 'clean':
          _textColor = Colors.white;
          _highlightColor = const Color(0xFF00F0FF);
          _fontFamily = 'Poppins';
          _animation = 'fade';
          _isUppercase = false;
          _fontSize = 20.0;
          _styleBadge = true;
          _badgeColor = Colors.black.withOpacity(0.4);
          _styleGlow = false;
          _styleShadow = true;
          _styleStroke = false;
          break;
        case 'cyberpunk':
          _textColor = const Color(0xFF00FFCC);
          _highlightColor = const Color(0xFFFF007F);
          _fontFamily = 'Courier Prime';
          _animation = 'karaoke';
          _isUppercase = true;
          _fontSize = 22.0;
          _styleBadge = true;
          _badgeColor = const Color(0xFF1B003A).withOpacity(0.85);
          _styleGlow = true;
          _styleShadow = true;
          _styleStroke = true;
          _strokeWidth = 2.5;
          break;
        case 'bangla':
          _textColor = const Color(0xFFFFD700);
          _highlightColor = const Color(0xFF00FF66);
          _fontFamily = 'Hind Siliguri';
          _animation = 'popup-blur';
          _isUppercase = false;
          _fontSize = 26.0;
          _styleBadge = true;
          _badgeColor = Colors.black.withOpacity(0.6);
          _styleGlow = true;
          _styleShadow = true;
          _language = 'bn';
          break;
        case 'hindi':
          _textColor = const Color(0xFFFFD700);
          _highlightColor = const Color(0xFFFF9800);
          _fontFamily = 'Inter';
          _animation = 'popup-blur';
          _isUppercase = false;
          _fontSize = 25.0;
          _styleBadge = true;
          _badgeColor = Colors.black.withOpacity(0.6);
          _styleGlow = true;
          _styleShadow = true;
          _language = 'hi';
          break;
      }
    });
    _syncSessionStyle();
  }

  void _addManualCaptionLine() {
    final text = _manualTextController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      final lines = _segmentCaptions.putIfAbsent(_session.activeSegmentIndex, () => []);
      final lastEnd = lines.isNotEmpty ? (lines.last['end'] as num).toDouble() : 0.0;
      lines.add({
        'text': text,
        'start': lastEnd + 0.1,
        'end': lastEnd + 2.5,
        'speaker': 'Speaker 1',
      });
      _activeLineIndex = lines.length - 1;
      _manualTextController.clear();
    });
  }

  Future<void> _importCustomFontTtf() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['ttf', 'otf', 'woff', 'woff2'],
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final name = result.files.single.name;
        setState(() => _fontFamily = name.split('.').first);
        _syncSessionStyle();
      }
    } catch (_) {}
  }

  List<String> _getActiveWords() {
    final lines = _segmentCaptions[_session.activeSegmentIndex] ?? [];
    if (lines.isEmpty) return ["VIRAL", "HOOK", "MOMENT", "CAPTION", "🔥"];
    final activeIdx = _activeLineIndex.clamp(0, lines.length - 1);
    final activeLine = lines[activeIdx];
    final text = activeLine['text']?.toString() ?? '';
    final formatted = _isUppercase ? text.toUpperCase() : text;
    final words = formatted.split(' ').where((w) => w.isNotEmpty).toList();
    return words.isNotEmpty ? words : ["VIRAL", "HOOK", "PREVIEW", "🔥"];
  }

  String _getLanguageName(String code) {
    switch (code) {
      case 'bn': return 'বাংলা (Bengali)';
      case 'hi': return 'हिंदी (Hindi)';
      case 'ta': return 'தமிழ் (Tamil)';
      case 'en': return 'English';
      default: return 'Auto-Detect';
    }
  }

  String _formatTime(num sec) {
    final s = sec.toDouble();
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final remSec = (s % 60).toStringAsFixed(1).padLeft(4, '0');
    return '$m:$remSec';
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
      _syncSessionStyle();
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

  @override
  Widget build(BuildContext context) {
    final gameplayVideoUrl = 'http://127.0.0.1:8765/media/video/${widget.clipId}';
    final hasWebcam = widget.faceClipId != null && widget.faceClipId!.isNotEmpty;
    final isStreamerLayout = widget.layoutType == 'streamer' || hasWebcam;
    final facecamVideoUrl = hasWebcam
        ? 'http://127.0.0.1:8765/media/video/${widget.faceClipId}'
        : gameplayVideoUrl;

    final selectedSegments = _session.selectedSegments;
    final activeLines = _segmentCaptions[_session.activeSegmentIndex] ?? [];
    final activeWords = _getActiveWords();

    return Scaffold(
      backgroundColor: const Color(0xFF0B0C10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F111A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _navigateToRoute('/layout?clipId=${widget.clipId}'),
        ),
        title: Row(
          children: [
            const Icon(Icons.subtitles, color: Color(0xFF00F0FF), size: 22),
            const SizedBox(width: 10),
            Text('Captions Studio: ${_session.projectName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Save Project',
            icon: const Icon(Icons.save_outlined, color: Color(0xFF00F0FF)),
            onPressed: _showSaveProjectDialog,
          ),
          const SizedBox(width: 8),
          // Single Unified Primary Header Action
          ElevatedButton.icon(
            onPressed: () {
              _syncSessionStyle();
              _api.autoSaveDraft(_session.toMap());
              _navigateToRoute('/audio?clipId=${widget.clipId}');
            },
            icon: const Icon(Icons.graphic_eq, size: 16),
            label: const Text('Proceed to Audio Studio ➔'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00F0FF),
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Column(
        children: [
          // Top Multi-Segment Switcher Bar
          if (selectedSegments.isNotEmpty)
            Container(
              height: 52,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              color: const Color(0xFF141724),
              child: Row(
                children: [
                  const Row(
                    children: [
                      Icon(Icons.video_library, color: Color(0xFFFFD700), size: 18),
                      SizedBox(width: 6),
                      Text('Active Segment:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70)),
                    ],
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: selectedSegments.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (ctx, i) {
                        final seg = selectedSegments[i];
                        final segIdx = _session.allSegments.indexOf(seg);
                        final isActive = segIdx == _session.activeSegmentIndex;
                        final partNum = seg['segment_number'] ?? (i + 1);
                        final startSec = (seg['start_time_sec'] as num?)?.toDouble() ?? 0.0;
                        final durSec = (seg['duration_sec'] as num?)?.toDouble() ?? 30.0;

                        return ChoiceChip(
                          label: Text('Part $partNum (${_formatTime(startSec)} - ${_formatTime(startSec + durSec)})', style: TextStyle(fontSize: 11, fontWeight: isActive ? FontWeight.bold : FontWeight.normal)),
                          selected: isActive,
                          selectedColor: const Color(0xFF00F0FF),
                          backgroundColor: const Color(0xFF0F111A),
                          labelStyle: TextStyle(color: isActive ? Colors.black : Colors.white70),
                          onSelected: (_) => _switchActiveSegment(segIdx != -1 ? segIdx : i),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _isBatchTranscribing ? null : _batchTranscribeAllSelectedSegments,
                    icon: const Icon(Icons.auto_fix_high, size: 14),
                    label: Text(_isBatchTranscribing ? 'Transcribing ($_batchTranscribeProgress/${selectedSegments.length})...' : '⚡ Transcribe All (${selectedSegments.length})'),
                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                  ),
                ],
              ),
            ),

          const Divider(height: 1, color: Colors.white12),

          Expanded(
            child: Row(
              children: [
                // Left: Styling Controls, Drag Coordinates, Typography & Transcribed Lines
                Expanded(
                  flex: 5,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(20.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 1. Comprehensive Transcript Lines & Words Studio
                        Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF141724),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFF00F0FF).withOpacity(0.4)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  const Row(
                                    children: [
                                      Icon(Icons.format_list_bulleted, color: Color(0xFF00F0FF), size: 20),
                                      SizedBox(width: 8),
                                      Text('1. Transcribed Lines & Words Editor', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    ],
                                  ),
                                  Text('${activeLines.length} Lines • ${activeWords.length} Words', style: const TextStyle(color: Color(0xFF00F0FF), fontSize: 11, fontWeight: FontWeight.bold)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Text('Click any word to highlight, or edit subtitle lines in real-time below:', style: TextStyle(fontSize: 11, color: Colors.white60)),
                              const SizedBox(height: 12),
                              
                              // All Words Chips
                              Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: List.generate(activeWords.length, (wIdx) {
                                  final word = activeWords[wIdx];
                                  final isWordSelected = wIdx == _selectedWordIndex;
                                  return InkWell(
                                    onTap: () => setState(() => _selectedWordIndex = isWordSelected ? -1 : wIdx),
                                    borderRadius: BorderRadius.circular(6),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                      decoration: BoxDecoration(
                                        color: isWordSelected ? const Color(0xFFFFD700) : const Color(0xFF0F111A),
                                        borderRadius: BorderRadius.circular(6),
                                        border: Border.all(color: isWordSelected ? const Color(0xFFFFD700) : Colors.white24),
                                      ),
                                      child: Text(
                                        word,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: isWordSelected ? Colors.black : Colors.white,
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ),
                              const SizedBox(height: 16),
                              const Divider(color: Colors.white12),
                              const SizedBox(height: 10),

                              // Editable Lines List
                              const Text('Active Segment Lines (Click to edit text & timestamps):', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFFFFD700))),
                              const SizedBox(height: 8),
                              if (activeLines.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 8),
                                  child: Text('No transcript lines generated yet. Click "Transcribe Active Segment" or add a line below.', style: TextStyle(fontSize: 11, color: Colors.white38)),
                                )
                              else
                                ListView.builder(
                                  shrinkWrap: true,
                                  physics: const NeverScrollableScrollPhysics(),
                                  itemCount: activeLines.length,
                                  itemBuilder: (ctx, lIdx) {
                                    final line = activeLines[lIdx];
                                    final isLineActive = lIdx == _activeLineIndex;
                                    final startT = (line['start'] as num?)?.toDouble() ?? 0.0;
                                    final endT = (line['end'] as num?)?.toDouble() ?? 2.0;

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: isLineActive ? const Color(0xFF00F0FF).withOpacity(0.08) : const Color(0xFF0F111A),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(color: isLineActive ? const Color(0xFF00F0FF) : Colors.white10),
                                      ),
                                      child: Row(
                                        children: [
                                          IconButton(
                                            icon: Icon(isLineActive ? Icons.play_circle_fill : Icons.play_arrow, color: isLineActive ? const Color(0xFF00F0FF) : Colors.white38, size: 20),
                                            onPressed: () => setState(() => _activeLineIndex = lIdx),
                                            tooltip: 'Preview this line',
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                                            decoration: BoxDecoration(color: Colors.white12, borderRadius: BorderRadius.circular(4)),
                                            child: Text('${startT.toStringAsFixed(1)}s - ${endT.toStringAsFixed(1)}s', style: const TextStyle(fontSize: 10, color: Colors.white70)),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: TextFormField(
                                              initialValue: line['text']?.toString() ?? '',
                                              style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600),
                                              decoration: const InputDecoration(
                                                isDense: true,
                                                contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                                border: InputBorder.none,
                                                hintText: 'Line text...',
                                              ),
                                              onChanged: (newVal) {
                                                line['text'] = newVal;
                                                _syncSessionStyle();
                                              },
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.delete_outline, color: Colors.redAccent, size: 18),
                                            onPressed: () {
                                              setState(() {
                                                activeLines.removeAt(lIdx);
                                                if (_activeLineIndex >= activeLines.length) {
                                                  _activeLineIndex = max(0, activeLines.length - 1);
                                                }
                                              });
                                              _syncSessionStyle();
                                            },
                                            tooltip: 'Delete Line',
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              const SizedBox(height: 12),

                              // Add Extra Text / Custom Line Box
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _manualTextController,
                                      style: const TextStyle(fontSize: 12, color: Colors.white),
                                      decoration: InputDecoration(
                                        hintText: 'Type extra text to add as new caption line...',
                                        hintStyle: const TextStyle(color: Colors.white38, fontSize: 11),
                                        filled: true,
                                        fillColor: const Color(0xFF0F111A),
                                        isDense: true,
                                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                                      ),
                                      onSubmitted: (_) => _addManualCaptionLine(),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton.icon(
                                    onPressed: _addManualCaptionLine,
                                    icon: const Icon(Icons.add, size: 16),
                                    label: const Text('Add Line', style: TextStyle(fontSize: 11)),
                                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00F0FF), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10)),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // 2. Words Per Line Density Selector
                        Container(
                          padding: const EdgeInsets.all(16),
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
                                  Icon(Icons.short_text, color: Color(0xFF00F0FF), size: 20),
                                  SizedBox(width: 8),
                                  Text('2. Words Per Line (Density Granularity)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              const Text('Controls how many words appear per subtitle line:', style: TextStyle(fontSize: 11, color: Colors.white60)),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  ChoiceChip(
                                    label: const Text('⚡ 2 Words / Line (Fast Viral)', style: TextStyle(fontSize: 11)),
                                    selected: _mode == 'short',
                                    selectedColor: const Color(0xFF00F0FF),
                                    onSelected: (_) {
                                      setState(() => _mode = 'short');
                                      _generateCaptionsForActiveSegment();
                                    },
                                  ),
                                  ChoiceChip(
                                    label: const Text('🌟 3 Words / Line (Standard)', style: TextStyle(fontSize: 11)),
                                    selected: _mode == 'medium',
                                    selectedColor: const Color(0xFF00F0FF),
                                    onSelected: (_) {
                                      setState(() => _mode = 'medium');
                                      _generateCaptionsForActiveSegment();
                                    },
                                  ),
                                  ChoiceChip(
                                    label: const Text('📖 4-5 Words / Line (Full Line)', style: TextStyle(fontSize: 11)),
                                    selected: _mode == 'normal',
                                    selectedColor: const Color(0xFF00F0FF),
                                    onSelected: (_) {
                                      setState(() => _mode = 'normal');
                                      _generateCaptionsForActiveSegment();
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // 3. Multilingual Whisper Selector
                        Container(
                          padding: const EdgeInsets.all(16),
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
                                  Icon(Icons.translate, color: Color(0xFFFFD700), size: 20),
                                  SizedBox(width: 8),
                                  Text('2. Multilingual Whisper Model', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _LangSelectChip(label: '🌐 Auto-Detect', id: 'auto', current: _language, onSelect: (id) { setState(() => _language = id); _syncSessionStyle(); _generateCaptionsForActiveSegment(); }),
                                  _LangSelectChip(label: '🇧🇩 বাংলা (Bengali)', id: 'bn', current: _language, onSelect: (id) { setState(() => _language = id); _syncSessionStyle(); _generateCaptionsForActiveSegment(); }),
                                  _LangSelectChip(label: '🇮🇳 हिंदी (Hindi)', id: 'hi', current: _language, onSelect: (id) { setState(() => _language = id); _syncSessionStyle(); _generateCaptionsForActiveSegment(); }),
                                  _LangSelectChip(label: '🇮🇳 தமிழ் (Tamil)', id: 'ta', current: _language, onSelect: (id) { setState(() => _language = id); _syncSessionStyle(); _generateCaptionsForActiveSegment(); }),
                                  _LangSelectChip(label: '🇺🇸 English', id: 'en', current: _language, onSelect: (id) { setState(() => _language = id); _syncSessionStyle(); _generateCaptionsForActiveSegment(); }),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // 3. Subtitle Style Presets
                        Container(
                          padding: const EdgeInsets.all(16),
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
                                  Icon(Icons.auto_awesome, color: Color(0xFFFFD700), size: 20),
                                  SizedBox(width: 8),
                                  Text('3. Subtitle Style Presets', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _PresetButton(label: '🔥 MrBeast Gold', id: 'mrbeast', current: _activePreset, onSelect: _applyStylePreset),
                                  _PresetButton(label: '🔴 Hormozi Red Box', id: 'hormozi', current: _activePreset, onSelect: _applyStylePreset),
                                  _PresetButton(label: '✨ Clean Minimal', id: 'clean', current: _activePreset, onSelect: _applyStylePreset),
                                  _PresetButton(label: '⚡ Cyberpunk Neon', id: 'cyberpunk', current: _activePreset, onSelect: _applyStylePreset),
                                  _PresetButton(label: '🇧🇩 বাংলা Kalpurush', id: 'bangla', current: _activePreset, onSelect: _applyStylePreset),
                                  _PresetButton(label: '🇮🇳 हिंदी Bollywood', id: 'hindi', current: _activePreset, onSelect: _applyStylePreset),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // 4. Drag & Position Over Reel
                        Container(
                          padding: const EdgeInsets.all(16),
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
                                      Icon(Icons.pan_tool_alt, color: Color(0xFF00F0FF), size: 20),
                                      SizedBox(width: 8),
                                      Text('4. Position & Placement Over Reel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    ],
                                  ),
                                  Text('${(_captionPosY * 100).toInt()}% Vertical', style: const TextStyle(color: Color(0xFF00F0FF), fontWeight: FontWeight.bold, fontSize: 12)),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  ChoiceChip(label: const Text('Top (15%)', style: TextStyle(fontSize: 11)), selected: (_captionPosY - 0.15).abs() < 0.05, onSelected: (_) { setState(() => _captionPosY = 0.15); _syncSessionStyle(); }),
                                  const SizedBox(width: 6),
                                  ChoiceChip(label: const Text('Center (50%)', style: TextStyle(fontSize: 11)), selected: (_captionPosY - 0.50).abs() < 0.05, onSelected: (_) { setState(() => _captionPosY = 0.50); _syncSessionStyle(); }),
                                  const SizedBox(width: 6),
                                  ChoiceChip(label: const Text('Lower Third (72%)', style: TextStyle(fontSize: 11)), selected: (_captionPosY - 0.72).abs() < 0.05, onSelected: (_) { setState(() => _captionPosY = 0.72); _syncSessionStyle(); }),
                                  const SizedBox(width: 6),
                                  ChoiceChip(label: const Text('Bottom (88%)', style: TextStyle(fontSize: 11)), selected: (_captionPosY - 0.88).abs() < 0.05, onSelected: (_) { setState(() => _captionPosY = 0.88); _syncSessionStyle(); }),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  const Text('Vertical (Y)', style: TextStyle(fontSize: 12)),
                                  Expanded(
                                    child: Slider(
                                      value: _captionPosY,
                                      min: 0.05,
                                      max: 0.95,
                                      activeColor: const Color(0xFF00F0FF),
                                      onChanged: (v) {
                                        setState(() => _captionPosY = v);
                                        _syncSessionStyle();
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // 5. Kinetic Animation Engine
                        Container(
                          padding: const EdgeInsets.all(16),
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
                                  Icon(Icons.animation, color: Color(0xFFFFD700), size: 20),
                                  SizedBox(width: 8),
                                  Text('5. Kinetic Animation Engine', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _EffectChip(label: '🔥 Popup Scale', id: 'popup', current: _animation, onSelect: (id) { setState(() => _animation = id); _syncSessionStyle(); }),
                                  _EffectChip(label: '💨 Popup Blur', id: 'popup-blur', current: _animation, onSelect: (id) { setState(() => _animation = id); _syncSessionStyle(); }),
                                  _EffectChip(label: '🔍 Zoom Blur', id: 'zoom-blur', current: _animation, onSelect: (id) { setState(() => _animation = id); _syncSessionStyle(); }),
                                  _EffectChip(label: '🎤 Karaoke Beat', id: 'karaoke', current: _animation, onSelect: (id) { setState(() => _animation = id); _syncSessionStyle(); }),
                                  _EffectChip(label: '✨ Smooth Fade', id: 'fade', current: _animation, onSelect: (id) { setState(() => _animation = id); _syncSessionStyle(); }),
                                ],
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(height: 16),

                        // 6. Typography & Color Palette
                        Container(
                          padding: const EdgeInsets.all(16),
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
                                      Icon(Icons.font_download, color: Color(0xFF00F0FF), size: 20),
                                      SizedBox(width: 8),
                                      Text('6. Typography & Colors', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                    ],
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: _importCustomFontTtf,
                                    icon: const Icon(Icons.file_open, size: 14),
                                    label: const Text('Import TTF Font', style: TextStyle(fontSize: 11)),
                                    style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF0F111A), foregroundColor: const Color(0xFF00F0FF)),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Slider(
                                value: _fontSize,
                                min: 14.0,
                                max: 44.0,
                                activeColor: const Color(0xFF00F0FF),
                                onChanged: (v) {
                                  setState(() => _fontSize = v);
                                  _syncSessionStyle();
                                },
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  _FontChip(label: 'Montserrat (Bold)', family: 'Montserrat', current: _fontFamily, onSelect: (f) { setState(() => _fontFamily = f); _syncSessionStyle(); }),
                                  _FontChip(label: 'Inter (Modern)', family: 'Inter', current: _fontFamily, onSelect: (f) { setState(() => _fontFamily = f); _syncSessionStyle(); }),
                                  _FontChip(label: 'Poppins (Clean)', family: 'Poppins', current: _fontFamily, onSelect: (f) { setState(() => _fontFamily = f); _syncSessionStyle(); }),
                                  _FontChip(label: 'Hind Siliguri (বাংলা)', family: 'Hind Siliguri', current: _fontFamily, onSelect: (f) { setState(() => _fontFamily = f); _syncSessionStyle(); }),
                                ],
                              ),
                              const SizedBox(height: 14),
                              const Text('Text Color:', style: TextStyle(fontSize: 12, color: Colors.white70)),
                              const SizedBox(height: 6),
                              Wrap(
                                spacing: 8,
                                children: _colorSwatches.map((c) {
                                  final isSel = _textColor.value == c.value;
                                  return GestureDetector(
                                    onTap: () {
                                      setState(() => _textColor = c);
                                      _syncSessionStyle();
                                    },
                                    child: Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(color: c, shape: BoxShape.circle, border: Border.all(color: isSel ? Colors.white : Colors.transparent, width: 2.5)),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const VerticalDivider(width: 1, color: Colors.white12),

                // Right: 9:16 Video Canvas with Safe-Zone Alignment Grid & Live Subtitle Overlay
                Expanded(
                  flex: 4,
                  child: Container(
                    color: const Color(0xFF07080C),
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      children: [
                        // Grid & Alignment Toolbar
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('CANVAS PREVIEW', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white54, letterSpacing: 1.2)),
                            FilterChip(
                              label: const Text('📐 Alignment Grid', style: TextStyle(fontSize: 11)),
                              selected: _showAlignmentGrid,
                              selectedColor: const Color(0xFF00F0FF).withOpacity(0.3),
                              checkmarkColor: const Color(0xFF00F0FF),
                              onSelected: (v) => setState(() => _showAlignmentGrid = v),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        Expanded(
                          child: Center(
                            child: AspectRatio(
                              aspectRatio: 9 / 16,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: Colors.black,
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white.withOpacity(0.12)),
                                  boxShadow: [
                                    BoxShadow(color: Colors.black.withOpacity(0.6), blurRadius: 20, spreadRadius: 2),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: Stack(
                                    children: [
                                      // Video Feeds
                                      if (isStreamerLayout)
                                        Positioned.fill(
                                          child: Column(
                                            children: [
                                              Expanded(
                                                flex: (widget.faceRatio * 100).toInt(),
                                                child: CustomMediaView(
                                                  videoUrl: facecamVideoUrl,
                                                  isPlaying: _isPlaying,
                                                  seekToPositionSec: _seekCommandSec,
                                                  playbackRate: _playbackRate,
                                                  onPositionChanged: _onVideoPositionUpdated,
                                                ),
                                              ),
                                              Container(height: 2, color: const Color(0xFF6C63FF)),
                                              Expanded(
                                                flex: ((1.0 - widget.faceRatio) * 100).toInt(),
                                                child: CustomMediaView(
                                                  videoUrl: gameplayVideoUrl,
                                                  isPlaying: _isPlaying,
                                                  seekToPositionSec: _seekCommandSec,
                                                  playbackRate: _playbackRate,
                                                  onDurationChanged: (d) => setState(() => _totalDurationSec = d),
                                                  onPositionChanged: _onVideoPositionUpdated,
                                                ),
                                              ),
                                            ],
                                          ),
                                        )
                                      else
                                        Positioned.fill(
                                          child: CustomMediaView(
                                            videoUrl: gameplayVideoUrl,
                                            isPlaying: _isPlaying,
                                            seekToPositionSec: _seekCommandSec,
                                            playbackRate: _playbackRate,
                                            onDurationChanged: (d) => setState(() => _totalDurationSec = d),
                                            onPositionChanged: _onVideoPositionUpdated,
                                          ),
                                        ),

                                      // Alignment Grid Lines (Rule of Thirds & Safe Margin)
                                      if (_showAlignmentGrid)
                                        Positioned.fill(
                                          child: IgnorePointer(
                                            child: CustomPaint(
                                              painter: _AlignmentGridPainter(),
                                            ),
                                          ),
                                        ),

                                      // Live Drag-to-Position Subtitle Overlay
                                      Positioned.fill(
                                        child: Align(
                                          alignment: Alignment(_captionPosX * 2.0, (_captionPosY * 2.0) - 1.0),
                                          child: GestureDetector(
                                            onPanUpdate: (details) {
                                              setState(() {
                                                _captionPosY = (_captionPosY + details.delta.dy / 300).clamp(0.05, 0.95);
                                                _captionPosX = (_captionPosX + details.delta.dx / 300).clamp(-0.35, 0.35);
                                              });
                                              _syncSessionStyle();
                                            },
                                            child: AnimatedBuilder(
                                              animation: _animController,
                                              builder: (ctx, child) {
                                                return Transform.scale(
                                                  scale: _animation == 'popup' || _animation == 'popup-blur' ? _scaleAnimation.value : 1.0,
                                                  child: Opacity(
                                                    opacity: _animation == 'fade' ? _fadeAnimation.value : 1.0,
                                                    child: Container(
                                                      margin: const EdgeInsets.symmetric(horizontal: 16),
                                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                                      decoration: BoxDecoration(
                                                        color: _styleBadge ? _badgeColor : Colors.transparent,
                                                        borderRadius: BorderRadius.circular(12),
                                                        border: _styleStroke ? Border.all(color: _highlightColor, width: _strokeWidth) : null,
                                                      ),
                                                      child: Wrap(
                                                        alignment: WrapAlignment.center,
                                                        spacing: 6,
                                                        children: List.generate(activeWords.length, (wIdx) {
                                                          final word = activeWords[wIdx];
                                                          final isWordHighlighted = wIdx == _selectedWordIndex || (wIdx == activeWords.length - 1 && _selectedWordIndex == -1);
                                                          return Text(
                                                            word,
                                                            style: TextStyle(
                                                              fontFamily: _fontFamily,
                                                              fontSize: _fontSize,
                                                              fontWeight: FontWeight.w900,
                                                              color: isWordHighlighted ? _highlightColor : _textColor,
                                                              shadows: [
                                                                if (_styleGlow) Shadow(color: _highlightColor, blurRadius: _activePreset == 'cyberpunk' ? 14 : 6),
                                                                if (_styleShadow) const Shadow(color: Colors.black, blurRadius: 8, offset: Offset(2, 2)),
                                                              ],
                                                            ),
                                                          );
                                                        }),
                                                      ),
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                          ),
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

                        // Modern Scrubber Bar
                        ModernPlayerBar(
                          isPlaying: _isPlaying,
                          currentSec: _currentPositionSec,
                          totalSec: _totalDurationSec,
                          playbackRate: _playbackRate,
                          onTogglePlay: () => setState(() => _isPlaying = !_isPlaying),
                          onSeek: (v) => setState(() {
                            _currentPositionSec = v;
                            _seekCommandSec = v;
                          }),
                          onRateChanged: (r) => setState(() => _playbackRate = r),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AlignmentGridPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFF00F0FF).withOpacity(0.25)
      ..strokeWidth = 1.0;

    // Rule of Thirds Vertical Lines
    canvas.drawLine(Offset(size.width * 0.333, 0), Offset(size.width * 0.333, size.height), paint);
    canvas.drawLine(Offset(size.width * 0.666, 0), Offset(size.width * 0.666, size.height), paint);

    // Rule of Thirds Horizontal Lines
    canvas.drawLine(Offset(0, size.height * 0.333), Offset(size.width, size.height * 0.333), paint);
    canvas.drawLine(Offset(0, size.height * 0.666), Offset(size.width, size.height * 0.666), paint);

    // Center Crosshair
    final centerPaint = Paint()
      ..color = const Color(0xFFFFD700).withOpacity(0.35)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(size.width * 0.5, 0), Offset(size.width * 0.5, size.height), centerPaint);
    canvas.drawLine(Offset(0, size.height * 0.5), Offset(size.width, size.height * 0.5), centerPaint);

    // Safe Margin Boxes (Top 12% & Bottom 18% Danger Zones)
    final dangerPaint = Paint()
      ..color = const Color(0xFFFF0055).withOpacity(0.12)
      ..style = PaintingStyle.fill;
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height * 0.12), dangerPaint);
    canvas.drawRect(Rect.fromLTWH(0, size.height * 0.82, size.width, size.height * 0.18), dangerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _PresetButton extends StatelessWidget {
  final String label;
  final String id;
  final String current;
  final Function(String) onSelect;

  const _PresetButton({required this.label, required this.id, required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final active = id == current;
    return ElevatedButton(
      onPressed: () => onSelect(id),
      style: ElevatedButton.styleFrom(
        backgroundColor: active ? const Color(0xFFFFD700) : const Color(0xFF0F111A),
        foregroundColor: active ? Colors.black : Colors.white,
        side: BorderSide(color: active ? const Color(0xFFFFD700) : Colors.white24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      ),
      child: Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
    );
  }
}

class _LangSelectChip extends StatelessWidget {
  final String label;
  final String id;
  final String current;
  final Function(String) onSelect;

  const _LangSelectChip({required this.label, required this.id, required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final active = id == current;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 11, color: active ? Colors.white : Colors.white70)),
      selected: active,
      selectedColor: const Color(0xFF6C63FF),
      backgroundColor: const Color(0xFF0F111A),
      onSelected: (_) => onSelect(id),
    );
  }
}

class _EffectChip extends StatelessWidget {
  final String label;
  final String id;
  final String current;
  final Function(String) onSelect;

  const _EffectChip({required this.label, required this.id, required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final active = id == current;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 11, color: active ? Colors.black : Colors.white70, fontWeight: active ? FontWeight.bold : FontWeight.normal)),
      selected: active,
      selectedColor: const Color(0xFFFFD700),
      backgroundColor: const Color(0xFF0F111A),
      onSelected: (_) => onSelect(id),
    );
  }
}

class _FontChip extends StatelessWidget {
  final String label;
  final String family;
  final String current;
  final Function(String) onSelect;

  const _FontChip({required this.label, required this.family, required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final active = family == current;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 11, fontFamily: family, color: active ? Colors.black : Colors.white70, fontWeight: active ? FontWeight.bold : FontWeight.normal)),
      selected: active,
      selectedColor: const Color(0xFF00F0FF),
      backgroundColor: const Color(0xFF0F111A),
      onSelected: (_) => onSelect(family),
    );
  }
}
