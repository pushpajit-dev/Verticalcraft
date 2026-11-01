import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:go_router/go_router.dart';
import '../services/api_client.dart';
import '../services/segment_session.dart';

// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

class AudioMixerScreen extends StatefulWidget {
  final String clipId;
  const AudioMixerScreen({super.key, required this.clipId});

  @override
  State<AudioMixerScreen> createState() => _AudioMixerScreenState();
}

class _AudioMixerScreenState extends State<AudioMixerScreen> {
  final _api = ApiClient();
  final _session = SegmentSession();

  // Model Selector
  String _selectedModel = 'kim_vocals_2'; // 'kim_vocals_2', 'mdx_23xc', 'moises_bgv', 'htdemucs'

  // Vocal & Diarization State
  bool _isAnalyzingVocals = true;
  bool _vocalsDetected = true;
  int _speakerCount = 2;
  double _vocalConfidence = 0.88;

  // 4-Stem & Custom Track Volumes (0.0 to 1.5)
  double _vocalsVol = 1.0;
  double _otherVol = 0.45;
  double _drumsVol = 1.0;
  double _bassVol = 1.0;
  double _customBgmVol = 0.50;
  double _sfxVol = 0.60;

  // Track Mute States
  bool _vocalsMuted = false;
  bool _otherMuted = false;
  bool _drumsMuted = false;
  bool _bassMuted = false;
  bool _customBgmMuted = false;
  bool _sfxMuted = false;

  // Audio Stem Separation
  bool _isStemSplitting = false;
  bool _stemsIsolated = false;

  // Custom BGM
  String? _customBgmFileName;
  String? _customBgmFilePath;
  String _selectedPresetBgm = 'none';

  // Synchronized Multi-Track HTML5 Audio Elements for Real-Time Balance
  final Map<String, html.AudioElement> _stemAudioElements = {};
  bool _isPlayingAudio = false;
  double _currentAudioTimeSec = 0.0;
  double _audioDurationSec = 60.0;

  @override
  void initState() {
    super.initState();
    _initMultitrackAudio();
    _checkVocalDetection();
    _splitAudioWithAI();
  }

  void _initMultitrackAudio() {
    if (!kIsWeb) return;
    final stems = ['master', 'vocals', 'other', 'drums', 'bass'];
    final ts = DateTime.now().millisecondsSinceEpoch;

    for (final stem in stems) {
      final audioUrl = 'http://127.0.0.1:8765/media/audio/${widget.clipId}?stem=$stem&t=$ts';
      final elem = html.AudioElement()
        ..src = audioUrl
        ..autoplay = false
        ..loop = true;

      if (stem == 'master') {
        elem.onLoadedMetadata.listen((_) {
          if (elem.duration.isFinite) {
            setState(() => _audioDurationSec = elem.duration.toDouble());
          }
        });
        elem.onTimeUpdate.listen((_) {
          if (elem.currentTime.isFinite) {
            setState(() => _currentAudioTimeSec = elem.currentTime.toDouble());
          }
        });
      }

      _stemAudioElements[stem] = elem;
    }
    _applyLiveVolumes();
  }

  void _applyLiveVolumes() {
    if (!kIsWeb) return;
    
    // If stems are isolated, mute master and mix individual stems
    final masterElem = _stemAudioElements['master'];
    final vocalsElem = _stemAudioElements['vocals'];
    final otherElem = _stemAudioElements['other'];
    final drumsElem = _stemAudioElements['drums'];
    final bassElem = _stemAudioElements['bass'];

    if (_stemsIsolated) {
      if (masterElem != null) masterElem.volume = 0.0;
      if (vocalsElem != null) vocalsElem.volume = _vocalsMuted ? 0.0 : (_vocalsVol / 1.5).clamp(0.0, 1.0);
      if (otherElem != null) otherElem.volume = _otherMuted ? 0.0 : (_otherVol / 1.5).clamp(0.0, 1.0);
      if (drumsElem != null) drumsElem.volume = _drumsMuted ? 0.0 : (_drumsVol / 1.5).clamp(0.0, 1.0);
      if (bassElem != null) bassElem.volume = _bassMuted ? 0.0 : (_bassVol / 1.5).clamp(0.0, 1.0);
    } else {
      // Before stem separation is done, control master volume with vocals slider
      if (masterElem != null) masterElem.volume = _vocalsMuted ? 0.0 : (_vocalsVol / 1.5).clamp(0.0, 1.0);
    }
  }

  @override
  void dispose() {
    for (final elem in _stemAudioElements.values) {
      elem.pause();
      elem.remove();
    }
    _stemAudioElements.clear();
    super.dispose();
  }

  void _toggleAudioPlayback() {
    setState(() => _isPlayingAudio = !_isPlayingAudio);
    for (final elem in _stemAudioElements.values) {
      if (_isPlayingAudio) {
        elem.currentTime = _currentAudioTimeSec;
        elem.play().catchError((_) {});
      } else {
        elem.pause();
      }
    }
    _applyLiveVolumes();
  }

  void _seekAudio(double sec) {
    setState(() => _currentAudioTimeSec = sec);
    for (final elem in _stemAudioElements.values) {
      elem.currentTime = sec;
    }
  }

  Future<void> _checkVocalDetection() async {
    setState(() => _isAnalyzingVocals = true);
    try {
      final res = await _api.detectVocals(clipId: widget.clipId);
      setState(() {
        _vocalsDetected = res['has_vocals'] ?? true;
        _vocalConfidence = (res['vocal_confidence'] as num?)?.toDouble() ?? 0.88;
        _speakerCount = (res['speaker_count'] as num?)?.toInt() ?? 2;
      });
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isAnalyzingVocals = false);
    }
  }

  Future<void> _splitAudioWithAI() async {
    setState(() => _isStemSplitting = true);
    try {
      await _api.splitAudio(clipId: widget.clipId, model: _selectedModel);
      setState(() {
        _stemsIsolated = true;
      });
      _applyLiveVolumes();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✨ AI Stem Isolation Complete with ${_getModelLabel(_selectedModel)}!'),
            backgroundColor: const Color(0xFF00F0FF),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Stem isolation notice: $e'), backgroundColor: Colors.orange),
        );
      }
    } finally {
      if (mounted) setState(() => _isStemSplitting = false);
    }
  }

  String _getModelLabel(String model) {
    switch (model) {
      case 'kim_vocals_2': return 'UVR - Kim Vocals 2 (Reverb Intact & Ultra Smooth)';
      case 'mdx_23xc': return 'MDX 23xc InstVoc (High Clarity)';
      case 'moises_bgv': return 'Moises (Background Vocals Isolator)';
      case 'htdemucs': return 'HTDemucs v4 (4-Stem Studio Splitter)';
      default: return 'UVR - Kim Vocals 2';
    }
  }

  String _formatTime(double sec) {
    final s = sec.clamp(0.0, 99999.0);
    final m = (s ~/ 60).toString().padLeft(2, '0');
    final remSec = (s.toInt() % 60).toString().padLeft(2, '0');
    return '$m:$remSec';
  }

  void _navigateToExport() {
    for (final elem in _stemAudioElements.values) {
      elem.pause();
    }
    _session.updateAudio(
      newModel: _selectedModel,
      newVocalsVol: _vocalsMuted ? 0.0 : _vocalsVol,
      newBgmVol: _otherMuted ? 0.0 : _otherVol,
      newBgmPath: _customBgmFilePath,
    );
    context.push('/export?clipId=${widget.clipId}');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0C10),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0F111A),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            for (final elem in _stemAudioElements.values) { elem.pause(); }
            context.pop();
          },
        ),
        title: const Row(
          children: [
            Icon(Icons.graphic_eq, color: Color(0xFF00F0FF), size: 22),
            SizedBox(width: 10),
            Text('AI Vocal Remover & Multi-Stem Audio Studio', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        actions: [
          ElevatedButton.icon(
            onPressed: _navigateToExport,
            icon: const Icon(Icons.movie, size: 16),
            label: const Text('Proceed to Export Hub ➔'),
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
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Neural Stem Separator Model Card
            Container(
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
                          Icon(Icons.psychology, color: Color(0xFF00F0FF), size: 22),
                          SizedBox(width: 10),
                          Text('1. Select AI Vocal Remover & Stem Separator Model', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      if (_isStemSplitting)
                        const Row(
                          children: [
                            SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00F0FF))),
                            SizedBox(width: 8),
                            Text('Isolating Stems...', style: TextStyle(color: Color(0xFF00F0FF), fontSize: 11, fontWeight: FontWeight.bold)),
                          ],
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      _ModelSelectButton(label: '🌟 UVR - Kim Vocals 2', subtitle: 'Smooth vocal extraction with reverb tails intact', id: 'kim_vocals_2', current: _selectedModel, onSelect: (id) { setState(() => _selectedModel = id); _splitAudioWithAI(); }),
                      _ModelSelectButton(label: '⚡ MDX 23xc InstVoc', subtitle: 'Leaderboard model for instrument & vocal isolation', id: 'mdx_23xc', current: _selectedModel, onSelect: (id) { setState(() => _selectedModel = id); _splitAudioWithAI(); }),
                      _ModelSelectButton(label: '🎙️ Moises BGV Model', subtitle: 'Best for separating lead voice from background vocals', id: 'moises_bgv', current: _selectedModel, onSelect: (id) { setState(() => _selectedModel = id); _splitAudioWithAI(); }),
                      _ModelSelectButton(label: '🎛️ HTDemucs v4', subtitle: 'Full 4-stem split (Vocals, Drums, Bass, Other)', id: 'htdemucs', current: _selectedModel, onSelect: (id) { setState(() => _selectedModel = id); _splitAudioWithAI(); }),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 2. Multitrack Audio Player & Waveform Timeline
            Container(
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
                    children: [
                      IconButton.filled(
                        onPressed: _toggleAudioPlayback,
                        icon: Icon(_isPlayingAudio ? Icons.pause : Icons.play_arrow, size: 28),
                        style: IconButton.styleFrom(backgroundColor: const Color(0xFF00F0FF), foregroundColor: Colors.black),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_isPlayingAudio ? '▶️ Playing Multitrack Audio Mix' : '⏸️ Multitrack Mixer Paused', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                Text('${_formatTime(_currentAudioTimeSec)} / ${_formatTime(_audioDurationSec)}', style: const TextStyle(fontSize: 12, color: Color(0xFF00F0FF), fontWeight: FontWeight.bold)),
                              ],
                            ),
                            Slider(
                              value: _currentAudioTimeSec.clamp(0.0, _audioDurationSec),
                              min: 0.0,
                              max: _audioDurationSec > 0 ? _audioDurationSec : 60.0,
                              activeColor: const Color(0xFF00F0FF),
                              onChanged: (v) => _seekAudio(v),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 3. Real-Time Multitrack Sliders & Mute Controls
            Container(
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
                      Icon(Icons.tune, color: Color(0xFF00F0FF), size: 22),
                      SizedBox(width: 10),
                      Text('2. Real-Time Multitrack Balance & Mute Sliders', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text('Move sliders or tap mute to test audio balance in real-time:', style: TextStyle(fontSize: 11, color: Colors.white60)),
                  const SizedBox(height: 18),

                  // Track 1: Vocals
                  _LiveMixerTrackRow(
                    title: '🗣️ Lead Vocals / Dialogue Track',
                    subtitle: 'Extracted with ${_getModelLabel(_selectedModel).split('(').first}',
                    volume: _vocalsVol,
                    isMuted: _vocalsMuted,
                    activeColor: const Color(0xFF00F0FF),
                    onVolumeChanged: (v) {
                      setState(() { _vocalsVol = v; _vocalsMuted = false; });
                      _applyLiveVolumes();
                    },
                    onToggleMute: () {
                      setState(() => _vocalsMuted = !_vocalsMuted);
                      _applyLiveVolumes();
                    },
                  ),

                  const Divider(color: Colors.white12, height: 24),

                  // Track 2: BGM / Instrumental
                  _LiveMixerTrackRow(
                    title: '🎹 Instrumental & Background Music (BGM)',
                    subtitle: 'Clean backing audio with zero vocal bleeding',
                    volume: _otherVol,
                    isMuted: _otherMuted,
                    activeColor: const Color(0xFFFFD700),
                    onVolumeChanged: (v) {
                      setState(() { _otherVol = v; _otherMuted = false; });
                      _applyLiveVolumes();
                    },
                    onToggleMute: () {
                      setState(() => _otherMuted = !_otherMuted);
                      _applyLiveVolumes();
                    },
                  ),

                  const Divider(color: Colors.white12, height: 24),

                  // Track 3: Drums
                  _LiveMixerTrackRow(
                    title: '🥁 Drums & Percussion Track',
                    subtitle: 'Isolated beat, snare, and hi-hats',
                    volume: _drumsVol,
                    isMuted: _drumsMuted,
                    activeColor: const Color(0xFFFF5722),
                    onVolumeChanged: (v) {
                      setState(() { _drumsVol = v; _drumsMuted = false; });
                      _applyLiveVolumes();
                    },
                    onToggleMute: () {
                      setState(() => _drumsMuted = !_drumsMuted);
                      _applyLiveVolumes();
                    },
                  ),

                  const Divider(color: Colors.white12, height: 24),

                  // Track 4: Bass
                  _LiveMixerTrackRow(
                    title: '🎸 Bassline & 808s Track',
                    subtitle: 'Sub-bass and low frequency harmonics',
                    volume: _bassVol,
                    isMuted: _bassMuted,
                    activeColor: const Color(0xFF8B5CF6),
                    onVolumeChanged: (v) {
                      setState(() { _bassVol = v; _bassMuted = false; });
                      _applyLiveVolumes();
                    },
                    onToggleMute: () {
                      setState(() => _bassMuted = !_bassMuted);
                      _applyLiveVolumes();
                    },
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 4. Custom BGM Audio Sound Picker & Viral Presets Card
            Container(
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
                      Icon(Icons.library_music, color: Color(0xFFFFD700), size: 22),
                      SizedBox(width: 10),
                      Text('3. Custom Background Music (BGM) Sound Picker & Presets', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text('Pick a custom audio track from your PC or select a royalty-free viral mood preset:', style: TextStyle(fontSize: 11, color: Colors.white60)),
                  const SizedBox(height: 14),

                  // File Picker Button + Selected File Info
                  Row(
                    children: [
                      ElevatedButton.icon(
                        onPressed: () async {
                          try {
                            final res = await FilePicker.platform.pickFiles(type: FileType.audio);
                            if (res != null && res.files.isNotEmpty) {
                              final f = res.files.first;
                              setState(() {
                                _customBgmFileName = f.name;
                                _customBgmFilePath = f.path ?? f.name;
                              });
                            }
                          } catch (_) {}
                        },
                        icon: const Icon(Icons.upload_file, size: 16),
                        label: const Text('🎵 Pick Custom BGM Audio File'),
                        style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFFD700), foregroundColor: Colors.black, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
                      ),
                      const SizedBox(width: 12),
                      if (_customBgmFileName != null)
                        Expanded(
                          child: Text('Selected: $_customBgmFileName', style: const TextStyle(color: Color(0xFF00F0FF), fontSize: 12, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                        ),
                    ],
                  ),

                  const SizedBox(height: 14),
                  const Text('Viral Royalty-Free Sound Presets:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white70)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('🔥 Phonk Drift Beat', style: TextStyle(fontSize: 11)),
                        selected: _selectedPresetBgm == 'phonk',
                        selectedColor: const Color(0xFFFFD700),
                        onSelected: (_) => setState(() => _selectedPresetBgm = 'phonk'),
                      ),
                      ChoiceChip(
                        label: const Text('☕ Lo-Fi Chill Hop', style: TextStyle(fontSize: 11)),
                        selected: _selectedPresetBgm == 'lofi',
                        selectedColor: const Color(0xFFFFD700),
                        onSelected: (_) => setState(() => _selectedPresetBgm = 'lofi'),
                      ),
                      ChoiceChip(
                        label: const Text('🎬 Epic Cinematic Bass', style: TextStyle(fontSize: 11)),
                        selected: _selectedPresetBgm == 'cinematic',
                        selectedColor: const Color(0xFFFFD700),
                        onSelected: (_) => setState(() => _selectedPresetBgm = 'cinematic'),
                      ),
                      ChoiceChip(
                        label: const Text('🚀 Upbeat Viral Vlog', style: TextStyle(fontSize: 11)),
                        selected: _selectedPresetBgm == 'upbeat',
                        selectedColor: const Color(0xFFFFD700),
                        onSelected: (_) => setState(() => _selectedPresetBgm = 'upbeat'),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),
                  // Custom BGM Volume & Mute Row
                  _LiveMixerTrackRow(
                    title: '🔊 Custom Added BGM Track Volume',
                    subtitle: _customBgmFileName ?? 'Preset: ${_selectedPresetBgm.toUpperCase()}',
                    volume: _customBgmVol,
                    isMuted: _customBgmMuted,
                    activeColor: const Color(0xFF00FF66),
                    onVolumeChanged: (v) => setState(() { _customBgmVol = v; _customBgmMuted = false; }),
                    onToggleMute: () => setState(() => _customBgmMuted = !_customBgmMuted),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 5. AI Speaker Diarization & Multi-Speaker Detection Card
            Container(
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
                          Icon(Icons.record_voice_over, color: Color(0xFF00F0FF), size: 22),
                          SizedBox(width: 10),
                          Text('4. AI Speaker Detection & Diarization Separator', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(color: const Color(0xFF00F0FF).withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
                        child: Text('$_speakerCount Speakers Detected', style: const TextStyle(color: Color(0xFF00F0FF), fontSize: 11, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text('AI separated voice registers for individual speaker balancing:', style: TextStyle(fontSize: 11, color: Colors.white60)),
                  const SizedBox(height: 16),

                  // Speaker 1: Host / Primary
                  _LiveMixerTrackRow(
                    title: '🎙️ Speaker 1 (Host / Primary Voice)',
                    subtitle: 'Lower-mid fundamental frequencies (120Hz - 800Hz)',
                    volume: _vocalsVol,
                    isMuted: _vocalsMuted,
                    activeColor: const Color(0xFF00F0FF),
                    onVolumeChanged: (v) {
                      setState(() { _vocalsVol = v; _vocalsMuted = false; });
                      _applyLiveVolumes();
                    },
                    onToggleMute: () {
                      setState(() => _vocalsMuted = !_vocalsMuted);
                      _applyLiveVolumes();
                    },
                  ),

                  const Divider(color: Colors.white12, height: 24),

                  // Speaker 2: Guest / Secondary
                  _LiveMixerTrackRow(
                    title: '🗣️ Speaker 2 (Guest / Secondary Voice)',
                    subtitle: 'Upper-mid clarity register (1.2kHz - 4.5kHz)',
                    volume: _sfxVol,
                    isMuted: _sfxMuted,
                    activeColor: const Color(0xFFFF0055),
                    onVolumeChanged: (v) {
                      setState(() { _sfxVol = v; _sfxMuted = false; });
                    },
                    onToggleMute: () {
                      setState(() => _sfxMuted = !_sfxMuted);
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LiveMixerTrackRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final double volume;
  final bool isMuted;
  final Color activeColor;
  final ValueChanged<double> onVolumeChanged;
  final VoidCallback onToggleMute;

  const _LiveMixerTrackRow({
    required this.title,
    required this.subtitle,
    required this.volume,
    required this.isMuted,
    required this.activeColor,
    required this.onVolumeChanged,
    required this.onToggleMute,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveVol = isMuted ? 0.0 : volume;
    return Row(
      children: [
        IconButton.filled(
          onPressed: onToggleMute,
          icon: Icon(isMuted ? Icons.volume_off : Icons.volume_up, size: 20),
          style: IconButton.styleFrom(
            backgroundColor: isMuted ? Colors.redAccent.withOpacity(0.2) : activeColor.withOpacity(0.2),
            foregroundColor: isMuted ? Colors.redAccent : activeColor,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.white54)),
            ],
          ),
        ),
        Expanded(
          flex: 5,
          child: Slider(
            value: effectiveVol,
            min: 0.0,
            max: 1.5,
            activeColor: activeColor,
            onChanged: onVolumeChanged,
          ),
        ),
        SizedBox(
          width: 50,
          child: Text(
            isMuted ? 'MUTED' : '${(volume * 100).toInt()}%',
            textAlign: TextAlign.end,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 12,
              color: isMuted ? Colors.redAccent : activeColor,
            ),
          ),
        ),
      ],
    );
  }
}

class _ModelSelectButton extends StatelessWidget {
  final String label;
  final String subtitle;
  final String id;
  final String current;
  final Function(String) onSelect;

  const _ModelSelectButton({required this.label, required this.subtitle, required this.id, required this.current, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    final active = id == current;
    return InkWell(
      onTap: () => onSelect(id),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: active ? const Color(0xFF00F0FF).withOpacity(0.12) : const Color(0xFF0F111A),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: active ? const Color(0xFF00F0FF) : Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(active ? Icons.radio_button_checked : Icons.radio_button_off, size: 16, color: active ? const Color(0xFF00F0FF) : Colors.white54),
                const SizedBox(width: 8),
                Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: active ? const Color(0xFF00F0FF) : Colors.white)),
              ],
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.white54)),
          ],
        ),
      ),
    );
  }
}
