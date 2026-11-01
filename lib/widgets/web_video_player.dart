import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// ignore: avoid_web_libraries_in_flutter
import 'dart:ui_web' as ui_web;
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

class CustomMediaView extends StatefulWidget {
  final String videoUrl;
  final String? audioUrl;
  final double zoomScale;
  final double panX;
  final double panY;
  final bool isPlaying;
  final bool isMuted;
  final double? seekToPositionSec;
  final Function(double duration)? onDurationChanged;
  final Function(double position)? onPositionChanged;
  final Function(bool isPlaying)? onPlayStateChanged;
  final String? filterStyle; // CSS filter for live Color Grading preview
  final double playbackRate;

  static final Set<html.VideoElement> _activeVideos = {};

  static void stopAllBackgroundPlayback() {
    if (!kIsWeb) return;
    for (final v in _activeVideos) {
      try {
        v.pause();
        v.muted = true;
      } catch (_) {}
    }
  }

  const CustomMediaView({
    super.key,
    required this.videoUrl,
    this.audioUrl,
    this.zoomScale = 1.0,
    this.panX = 0.0,
    this.panY = 0.0,
    this.isPlaying = true,
    this.isMuted = false,
    this.seekToPositionSec,
    this.onDurationChanged,
    this.onPositionChanged,
    this.onPlayStateChanged,
    this.filterStyle,
    this.playbackRate = 1.0,
  });

  @override
  State<CustomMediaView> createState() => _CustomMediaViewState();
}

class _CustomMediaViewState extends State<CustomMediaView> {
  html.VideoElement? _videoElement;
  String _viewId = '';

  @override
  void initState() {
    super.initState();
    _initPlayer();
  }

  void _initPlayer() {
    if (kIsWeb) {
      _viewId = 'video-element-${widget.videoUrl.hashCode}-${DateTime.now().microsecondsSinceEpoch}';
      _videoElement = html.VideoElement()
        ..src = widget.videoUrl
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'cover'
        ..style.filter = widget.filterStyle ?? 'none'
        ..playbackRate = widget.playbackRate
        ..autoplay = widget.isPlaying
        ..loop = true
        ..muted = widget.isMuted
        ..controls = false;

      CustomMediaView._activeVideos.add(_videoElement!);

      ui_web.platformViewRegistry.registerViewFactory(
        _viewId,
        (int viewId) => _videoElement!,
      );

      _videoElement!.onLoadedMetadata.listen((_) {
        if (_videoElement != null && _videoElement!.duration.isFinite) {
          widget.onDurationChanged?.call(_videoElement!.duration.toDouble());
        }
      });

      _videoElement!.onTimeUpdate.listen((_) {
        if (_videoElement != null && _videoElement!.currentTime.isFinite) {
          widget.onPositionChanged?.call(_videoElement!.currentTime.toDouble());
        }
      });

      _videoElement!.onPlay.listen((_) {
        widget.onPlayStateChanged?.call(true);
      });

      _videoElement!.onPause.listen((_) {
        widget.onPlayStateChanged?.call(false);
      });
    }
  }

  @override
  void didUpdateWidget(covariant CustomMediaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_videoElement != null) {
      if (oldWidget.isMuted != widget.isMuted) {
        _videoElement!.muted = widget.isMuted;
      }

      // Handle filter style updates
      if (oldWidget.filterStyle != widget.filterStyle) {
        _videoElement!.style.filter = widget.filterStyle ?? 'none';
      }

      // Handle playback rate
      if (oldWidget.playbackRate != widget.playbackRate) {
        _videoElement!.playbackRate = widget.playbackRate;
      }

      // Handle Play/Pause
      if (oldWidget.isPlaying != widget.isPlaying) {
        if (widget.isPlaying) {
          _videoElement!.play().catchError((_) {});
        } else {
          _videoElement!.pause();
        }
      }

      // Handle seeking
      if (widget.seekToPositionSec != null && widget.seekToPositionSec != oldWidget.seekToPositionSec) {
        if ((_videoElement!.currentTime - widget.seekToPositionSec!).abs() > 0.3) {
          _videoElement!.currentTime = widget.seekToPositionSec!;
        }
      }

      // Handle URL change
      if (oldWidget.videoUrl != widget.videoUrl) {
        _videoElement!.pause();
        _videoElement!.src = widget.videoUrl;
        _videoElement!.load();
        if (widget.isPlaying) {
          _videoElement!.play().catchError((_) {});
        }
      }
    }
  }

  @override
  void dispose() {
    // Strictly terminate media element playback on dispose to avoid background audio/video leaking
    if (_videoElement != null) {
      CustomMediaView._activeVideos.remove(_videoElement);
      _videoElement!.pause();
      _videoElement!.muted = true;
      _videoElement!.src = '';
      _videoElement!.load();
      _videoElement!.remove();
      _videoElement = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb && _viewId.isNotEmpty) {
      return ClipRect(
        child: Transform.scale(
          scale: widget.zoomScale,
          alignment: Alignment(widget.panX, widget.panY),
          child: HtmlElementView(viewType: _viewId),
        ),
      );
    }

    return Container(
      color: Colors.black,
      child: const Center(
        child: Icon(Icons.video_library, color: Colors.white24, size: 48),
      ),
    );
  }
}

/// Ultra-Modern Glassmorphic Video Scrubber & Playback Controller
class ModernPlayerBar extends StatelessWidget {
  final bool isPlaying;
  final double currentSec;
  final double totalSec;
  final double playbackRate;
  final VoidCallback onTogglePlay;
  final Function(double) onSeek;
  final Function(double)? onRateChanged;

  const ModernPlayerBar({
    super.key,
    required this.isPlaying,
    required this.currentSec,
    required this.totalSec,
    this.playbackRate = 1.0,
    required this.onTogglePlay,
    required this.onSeek,
    this.onRateChanged,
  });

  String _format(double sec) {
    final s = sec.clamp(0.0, 99999.0);
    final h = (s ~/ 3600);
    final m = ((s % 3600) ~/ 60).toString().padLeft(2, '0');
    final remSec = (s.toInt() % 60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$remSec' : '$m:$remSec';
  }

  @override
  Widget build(BuildContext context) {
    final dur = totalSec > 0 ? totalSec : 60.0;
    final pos = currentSec.clamp(0.0, dur);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF0F111A).withOpacity(0.95),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.4), blurRadius: 16, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          // Play / Pause Button with Neon Cyan Ring
          InkWell(
            onTap: onTogglePlay,
            borderRadius: BorderRadius.circular(24),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [Color(0xFF00F0FF), Color(0xFF0072FF)]),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: const Color(0xFF00F0FF).withOpacity(0.35), blurRadius: 10, spreadRadius: 1),
                ],
              ),
              child: Icon(isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.black, size: 20),
            ),
          ),
          const SizedBox(width: 12),

          // Current Time Display
          Text(
            _format(pos),
            style: const TextStyle(color: Color(0xFF00F0FF), fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'monospace'),
          ),
          const SizedBox(width: 8),

          // Smooth Progress Scrubber
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 4,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: const Color(0xFF00F0FF),
                inactiveTrackColor: Colors.white12,
                thumbColor: Colors.white,
                overlayColor: const Color(0xFF00F0FF).withOpacity(0.2),
              ),
              child: Slider(
                value: pos,
                min: 0.0,
                max: dur,
                onChanged: onSeek,
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Total Duration Display
          Text(
            _format(dur),
            style: TextStyle(color: Colors.white.withOpacity(0.5), fontSize: 12, fontFamily: 'monospace'),
          ),
          const SizedBox(width: 10),

          // Playback Speed Selector (Optional)
          if (onRateChanged != null)
            PopupMenuButton<double>(
              tooltip: 'Playback Speed',
              initialValue: playbackRate,
              onSelected: onRateChanged,
              color: const Color(0xFF1B1E2E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10), side: const BorderSide(color: Colors.white12)),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: Colors.white.withOpacity(0.08), borderRadius: BorderRadius.circular(6)),
                child: Text('${playbackRate}x', style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.white70)),
              ),
              itemBuilder: (ctx) => [
                const PopupMenuItem(value: 0.75, child: Text('0.75x Slow')),
                const PopupMenuItem(value: 1.0, child: Text('1.0x Normal')),
                const PopupMenuItem(value: 1.25, child: Text('1.25x Fast')),
                const PopupMenuItem(value: 1.5, child: Text('1.5x Turbo')),
                const PopupMenuItem(value: 2.0, child: Text('2.0x Double')),
              ],
            ),
        ],
      ),
    );
  }
}
