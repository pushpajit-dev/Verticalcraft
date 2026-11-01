import 'dart:convert';
import 'dart:typed_data';
import 'package:http/http.dart' as http;

class ApiClient {
  static const String _base = 'http://127.0.0.1:8765';
  final http.Client _client = http.Client();

  Future<bool> checkHealth() async {
    try {
      final res = await _client.get(Uri.parse('$_base/health'));
      return res.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getLibrary() async {
    final res = await _client.get(Uri.parse('$_base/import/library'));
    final data = _parse(res);
    return List<Map<String, dynamic>>.from(data['clips'] ?? []);
  }

  Future<void> deleteClip(String clipId) async {
    await _client.delete(Uri.parse('$_base/import/clip/$clipId'));
  }

  Future<void> clearLibrary() async {
    await _client.delete(Uri.parse('$_base/import/library/clear'));
  }

  Future<Map<String, dynamic>> getHardwareInfo() async {
    final res = await _client.get(Uri.parse('$_base/system/hardware'));
    return _parse(res);
  }

  Future<Map<String, dynamic>> importFromUrl({
    required String url,
    String quality = 'best',
    String outputFormat = 'mp4',
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/import/url'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'url': url, 'quality': quality, 'output_format': outputFormat}),
    );
    return _parse(res);
  }

  Future<List<Map<String, dynamic>>> importBatchUrls({
    required List<String> urls,
    String quality = 'best',
    String outputFormat = 'mp4',
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/import/batch-urls'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'urls': urls, 'quality': quality, 'output_format': outputFormat}),
    );
    final data = _parse(res);
    return List<Map<String, dynamic>>.from(data['results'] ?? []);
  }

  Future<Map<String, dynamic>> importFile({
    String? filePath,
    Uint8List? fileBytes,
    required String fileName,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$_base/import/file'));
    if (fileBytes != null) {
      request.files.add(http.MultipartFile.fromBytes('file', fileBytes, filename: fileName));
    } else if (filePath != null) {
      request.files.add(await http.MultipartFile.fromPath('file', filePath, filename: fileName));
    } else {
      throw Exception('No file data or path provided');
    }
    final streamed = await _client.send(request);
    final res = await http.Response.fromStream(streamed);
    return _parse(res);
  }

  Future<Map<String, dynamic>> uploadCustomBgm({
    required Uint8List fileBytes,
    required String fileName,
  }) async {
    final request = http.MultipartRequest('POST', Uri.parse('$_base/audio/upload-bgm'));
    request.files.add(http.MultipartFile.fromBytes('file', fileBytes, filename: fileName));
    final streamed = await _client.send(request);
    final res = await http.Response.fromStream(streamed);
    return _parse(res);
  }

  Future<Map<String, dynamic>> buildLayout({
    required String clipId,
    required String layoutType,
    String aspectRatio = '9:16',
    String? faceClipId,
    double zoomScale = 1.0,
    double panX = 0.0,
    double panY = 0.0,
    String? logoPath,
    double logoOpacity = 0.8,
    String logoPosition = 'top-right',
    Map<String, dynamic> config = const {},
  }) async {
    final payload = {
      'clip_id': clipId,
      'layout_type': layoutType,
      'aspect_ratio': aspectRatio,
      if (faceClipId != null) 'face_clip_id': faceClipId,
      'zoom_scale': zoomScale,
      'pan_x': panX,
      'pan_y': panY,
      if (logoPath != null) 'logo_path': logoPath,
      'logo_opacity': logoOpacity,
      'logo_position': logoPosition,
      ...config,
    };

    final res = await _client.post(
      Uri.parse('$_base/layout/build'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    return _parse(res);
  }

  Future<Map<String, dynamic>> detectVocals({required String clipId}) async {
    final res = await _client.get(Uri.parse('$_base/audio/detect-vocals?clip_id=$clipId'));
    return _parse(res);
  }

  Future<List<dynamic>> detectHighlights({
    required String clipId,
    String niche = 'general',
    int topN = 15,
    double targetDuration = 30.0,
    bool useGemini = false,
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/highlights/detect'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'clip_id': clipId,
        'niche': niche,
        'top_n': topN,
        'target_duration': targetDuration,
        'use_gemini': useGemini,
      }),
    );
    final data = _parse(res);
    return data['highlights'] as List<dynamic>;
  }

  Future<Map<String, dynamic>> generateCaptions({
    required String clipId,
    String mode = 'short',
    String language = 'auto',
    String animation = 'popup',
    String? audioSourceClipId,
    double? startTimeSec,
    double? durationSec,
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/captions/generate'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'clip_id': clipId,
        'mode': mode,
        'language': language,
        'animation': animation,
        if (audioSourceClipId != null) 'audio_source_clip_id': audioSourceClipId,
        if (startTimeSec != null) 'start_time_sec': startTimeSec,
        if (durationSec != null) 'duration_sec': durationSec,
      }),
    );
    return _parse(res);
  }

  Future<Map<String, dynamic>> runBatchPipeline({
    List<String>? clipIds,
    String stemModel = 'kim_vocals_2',
    String language = 'auto',
    String colorPreset = 'none',
    String aspectRatio = '9:16',
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/export/batch-pipeline'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        if (clipIds != null) 'clip_ids': clipIds,
        'stem_model': stemModel,
        'language': language,
        'color_preset': colorPreset,
        'aspect_ratio': aspectRatio,
      }),
    );
    return _parse(res);
  }

  Future<Map<String, dynamic>> batchProcessSegments({
    required String clipId,
    required List<Map<String, dynamic>> segments,
    Map<String, dynamic>? styleConfig,
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/export/batch-segments'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'clip_id': clipId,
        'segments': segments,
        'style_config': styleConfig ?? {},
      }),
    );
    return _parse(res);
  }

  Future<Map<String, dynamic>> getYouTubeStatus() async {
    final res = await _client.get(Uri.parse('$_base/publish/youtube-status'));
    return _parse(res);
  }

  Future<Map<String, dynamic>> loginYouTube() async {
    final res = await _client.post(
      Uri.parse('$_base/publish/youtube-login'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({}),
    );
    return _parse(res);
  }

  Future<Map<String, dynamic>> getYouTubeAuthUrl() async {
    final res = await _client.get(Uri.parse('$_base/publish/youtube-auth-url'));
    return _parse(res);
  }

  Future<Map<String, dynamic>> submitYouTubeAuthCode(String code) async {
    final res = await _client.post(
      Uri.parse('$_base/publish/youtube-auth-code'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'code': code}),
    );
    return _parse(res);
  }

  Future<Map<String, dynamic>> logoutYouTube() async {
    final res = await _client.post(
      Uri.parse('$_base/publish/youtube-logout'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({}),
    );
    return _parse(res);
  }

  Future<Map<String, dynamic>> scheduleYouTubeUpload({
    required String filename,
    required String title,
    required String description,
    required List<String> tags,
    String? scheduledTimeIso,
    String privacyStatus = 'private',
    String aspectRatio = '9:16',
    String categoryId = '20',
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/publish/youtube-schedule'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'filename': filename,
        'title': title,
        'description': description,
        'tags': tags,
        'scheduled_time': scheduledTimeIso,
        'privacy_status': privacyStatus,
        'aspect_ratio': aspectRatio,
        'category_id': categoryId,
      }),
    );
    return _parse(res);
  }

  Future<Map<String, dynamic>> splitAudio({required String clipId, String model = 'htdemucs'}) async {
    final res = await _client.post(
      Uri.parse('$_base/audio/split'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'clip_id': clipId, 'model': model}),
    );
    return _parse(res);
  }

  Future<Map<String, dynamic>> mixAudio({
    required String clipId,
    double originalVol = 1.0,
    double speaker1Vol = 1.0,
    double speaker2Vol = 1.0,
    double musicVol = 0.4,
    double sfxVol = 0.6,
    String? musicPath,
    String? sfxPath,
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/audio/mix'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'clip_id': clipId,
        'original_vol': originalVol,
        'speaker1_vol': speaker1Vol,
        'speaker2_vol': speaker2Vol,
        'music_vol': musicVol,
        'sfx_vol': sfxVol,
        if (musicPath != null) 'music_path': musicPath,
        if (sfxPath != null) 'sfx_path': sfxPath,
      }),
    );
    return _parse(res);
  }

  Future<Map<String, dynamic>> generateMetadata({
    required String clipId,
    String niche = 'gaming',
    String language = 'english',
    String topic = 'Viral Shorts Moment',
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/export/metadata'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'clip_id': clipId, 'niche': niche, 'language': language, 'topic': topic}),
    );
    return _parse(res);
  }

  Future<Map<String, dynamic>> renderVideo({
    required String clipId,
    String? outputDirectory,
    String? subtitlePath,
    String? audioPath,
    String? layoutMode,
    String? faceClipId,
    double? faceRatio,
    double zoomScale = 1.0,
    double panX = 0.0,
    double panY = 0.0,
    Map<String, dynamic>? styleConfig,
    List<dynamic>? captionLines,
    double? startTimeSec,
    double? durationSec,
    int? segmentNumber,
    int crf = 20,
    int fps = 60,
    double brightness = 0.0,
    double contrast = 1.0,
    double saturation = 1.0,
    String colorPreset = 'none',
  }) async {
    final res = await _client.post(
      Uri.parse('$_base/export/render'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'clip_id': clipId,
        if (outputDirectory != null) 'output_directory': outputDirectory,
        if (subtitlePath != null) 'subtitle_path': subtitlePath,
        if (audioPath != null) 'audio_path': audioPath,
        if (layoutMode != null) 'layout_mode': layoutMode,
        if (faceClipId != null) 'face_clip_id': faceClipId,
        if (faceRatio != null) 'face_ratio': faceRatio,
        if (startTimeSec != null) 'start_time_sec': startTimeSec,
        if (durationSec != null) 'duration_sec': durationSec,
        if (segmentNumber != null) 'segment_number': segmentNumber,
        'zoom_scale': zoomScale,
        'pan_x': panX,
        'pan_y': panY,
        if (styleConfig != null) 'style_config': styleConfig,
        if (captionLines != null) 'caption_lines': captionLines,
        'crf': crf,
        'fps': fps,
        'brightness': brightness,
        'contrast': contrast,
        'saturation': saturation,
        'color_preset': colorPreset,
      }),
    );
    return _parse(res);
  }

  Future<Map<String, dynamic>> openExportFolder() async {
    final res = await _client.post(Uri.parse('$_base/export/open-folder'));
    return _parse(res);
  }

  Future<Map<String, dynamic>> submitYouTubeToken(dynamic tokenData) async {
    final res = await _client.post(
      Uri.parse('$_base/publish/youtube-token'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({'token': tokenData}),
    );
    return _parse(res);
  }

  // Project Management Methods
  Future<Map<String, dynamic>> listProjects() async {
    final res = await _client.get(Uri.parse('$_base/projects'));
    return _parse(res);
  }

  Future<Map<String, dynamic>> saveProject(Map<String, dynamic> projectData) async {
    final res = await _client.post(
      Uri.parse('$_base/projects/save'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(projectData),
    );
    return _parse(res);
  }

  Future<Map<String, dynamic>> autoSaveDraft(Map<String, dynamic> draftData) async {
    final res = await _client.post(
      Uri.parse('$_base/projects/auto-save'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(draftData),
    );
    return _parse(res);
  }

  Future<Map<String, dynamic>> getProject(String projectId) async {
    final res = await _client.get(Uri.parse('$_base/projects/$projectId'));
    return _parse(res);
  }

  Future<Map<String, dynamic>> deleteProject(String projectId) async {
    final res = await _client.delete(Uri.parse('$_base/projects/$projectId'));
    return _parse(res);
  }

  Map<String, dynamic> _parse(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return jsonDecode(res.body) as Map<String, dynamic>;
    }
    throw Exception('API Error (${res.statusCode}): ${res.body}');
  }
}
