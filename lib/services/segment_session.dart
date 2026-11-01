import 'package:flutter/foundation.dart';

class SegmentSession extends ChangeNotifier {
  static final SegmentSession _instance = SegmentSession._internal();
  factory SegmentSession() => _instance;
  SegmentSession._internal();

  String projectId = '';
  String projectName = 'Untitled Project';
  String clipName = 'Primary Video';
  String clipId = '';
  List<Map<String, dynamic>> allSegments = [];
  Set<int> selectedIndices = {0};
  int activeSegmentIndex = 0;

  // Shared Unified Style Config
  String font = 'Montserrat';
  double fontSize = 24.0;
  String animation = 'popup-blur';
  String preset = 'mrbeast';
  String language = 'auto';
  String textColorHex = '#FFFFFF';
  String highlightColorHex = '#FFD700';
  String badgeColorHex = '#000000';
  double posY = 0.72;
  double posX = 0.0;
  String stemModel = 'kim_vocals_2';
  String layoutMode = 'normal';
  double faceRatio = 0.38;
  String? faceClipId;

  // Custom User-Edited Caption Lines Map by Segment Index
  Map<int, List<Map<String, dynamic>>> segmentCaptions = {};

  Map<String, List<Map<String, dynamic>>> get jsonSerializableSegmentCaptions {
    return segmentCaptions.map((k, v) => MapEntry(k.toString(), v));
  }

  List<Map<String, dynamic>> get activeSegmentCaptions {
    return segmentCaptions[activeSegmentIndex] ?? [];
  }

  void saveSegmentCaptions(int segmentIndex, List<Map<String, dynamic>> lines) {
    segmentCaptions[segmentIndex] = List.from(lines);
    notifyListeners();
  }

  List<Map<String, dynamic>> get selectedSegments {
    if (allSegments.isEmpty) return [];
    return selectedIndices.map((i) => (i >= 0 && i < allSegments.length) ? allSegments[i] : null).whereType<Map<String, dynamic>>().toList();
  }

  Map<String, dynamic>? get activeSegment {
    if (allSegments.isEmpty || activeSegmentIndex < 0 || activeSegmentIndex >= allSegments.length) return null;
    return allSegments[activeSegmentIndex];
  }

  void setSegments(String targetClipId, List<Map<String, dynamic>> segments, {Set<int>? initialSelected}) {
    clipId = targetClipId;
    allSegments = List.from(segments);
    selectedIndices = initialSelected ?? (segments.isNotEmpty ? List.generate(segments.length, (i) => i).toSet() : {0});
    activeSegmentIndex = 0;
    notifyListeners();
  }

  void selectSegment(int index) {
    if (index >= 0 && index < allSegments.length) {
      activeSegmentIndex = index;
      notifyListeners();
    }
  }

  void toggleIndex(int index) {
    if (selectedIndices.contains(index)) {
      if (selectedIndices.length > 1) {
        selectedIndices.remove(index);
      }
    } else {
      selectedIndices.add(index);
    }
    notifyListeners();
  }

  void selectAll() {
    selectedIndices = List.generate(allSegments.length, (i) => i).toSet();
    notifyListeners();
  }

  void updateStyle({
    String? newFont,
    double? newFontSize,
    String? newAnimation,
    String? newPreset,
    String? newLanguage,
    String? newTextColor,
    String? newHighlightColor,
    String? newBadgeColor,
    double? newPosY,
    double? newPosX,
    String? newStemModel,
    String? newLayoutMode,
    double? newFaceRatio,
    String? newFaceClipId,
  }) {
    if (newFont != null) font = newFont;
    if (newFontSize != null) fontSize = newFontSize;
    if (newAnimation != null) animation = newAnimation;
    if (newPreset != null) preset = newPreset;
    if (newLanguage != null) language = newLanguage;
    if (newTextColor != null) textColorHex = newTextColor;
    if (newHighlightColor != null) highlightColorHex = newHighlightColor;
    if (newBadgeColor != null) badgeColorHex = newBadgeColor;
    if (newPosY != null) posY = newPosY;
    if (newPosX != null) posX = newPosX;
    if (newStemModel != null) stemModel = newStemModel;
    if (newLayoutMode != null) layoutMode = newLayoutMode;
    if (newFaceRatio != null) faceRatio = newFaceRatio;
    if (newFaceClipId != null) faceClipId = newFaceClipId;
    notifyListeners();
  }

  void updateAudio({
    String? newModel,
    double? newVocalsVol,
    double? newBgmVol,
    String? newBgmPath,
  }) {
    if (newModel != null) stemModel = newModel;
    notifyListeners();
  }

  Map<String, dynamic> toMap() {
    return {
      'project_id': projectId,
      'project_name': projectName,
      'clip_id': clipId,
      'face_clip_id': faceClipId,
      'clip_name': clipName,
      'segments': allSegments,
      'selected_indices': selectedIndices.toList(),
      'active_segment_index': activeSegmentIndex,
      'layout_mode': layoutMode,
      'face_ratio': faceRatio,
      'font': font,
      'font_size': fontSize,
      'animation': animation,
      'preset': preset,
      'language': language,
      'text_color_hex': textColorHex,
      'highlight_color_hex': highlightColorHex,
      'badge_color_hex': badgeColorHex,
      'pos_y': posY,
      'pos_x': posX,
      'stem_model': stemModel,
      'segment_captions': jsonSerializableSegmentCaptions,
    };
  }

  void loadProject(Map<String, dynamic> data) {
    projectId = data['project_id'] ?? '';
    projectName = data['project_name'] ?? 'Untitled Project';
    clipName = data['clip_name'] ?? 'Primary Video';
    clipId = data['clip_id'] ?? '';
    faceClipId = data['face_clip_id'];
    allSegments = List<Map<String, dynamic>>.from(data['segments'] ?? []);
    
    final sel = data['selected_indices'];
    if (sel is List) {
      selectedIndices = sel.map((e) => (e as num).toInt()).toSet();
    } else {
      selectedIndices = allSegments.isNotEmpty ? List.generate(allSegments.length, (i) => i).toSet() : {0};
    }
    
    activeSegmentIndex = (data['active_segment_index'] as num?)?.toInt() ?? 0;
    layoutMode = data['layout_mode'] ?? 'normal';
    faceRatio = (data['face_ratio'] as num?)?.toDouble() ?? 0.38;
    font = data['font'] ?? 'Montserrat';
    fontSize = (data['font_size'] as num?)?.toDouble() ?? 24.0;
    animation = data['animation'] ?? 'popup-blur';
    preset = data['preset'] ?? 'mrbeast';
    language = data['language'] ?? 'auto';
    textColorHex = data['text_color_hex'] ?? '#FFFFFF';
    highlightColorHex = data['highlight_color_hex'] ?? '#FFD700';
    badgeColorHex = data['badge_color_hex'] ?? '#000000';
    posY = (data['pos_y'] as num?)?.toDouble() ?? 0.72;
    posX = (data['pos_x'] as num?)?.toDouble() ?? 0.0;
    stemModel = data['stem_model'] ?? 'kim_vocals_2';

    // Parse segment captions
    segmentCaptions.clear();
    final caps = data['segment_captions'];
    if (caps is Map) {
      caps.forEach((k, v) {
        final idx = int.tryParse(k.toString());
        if (idx != null && v is List) {
          segmentCaptions[idx] = List<Map<String, dynamic>>.from(v);
        }
      });
    }

    notifyListeners();
  }

  void resetSession() {
    projectId = '';
    projectName = 'Untitled Project';
    clipName = 'Primary Video';
    clipId = '';
    faceClipId = null;
    allSegments = [];
    selectedIndices = {0};
    activeSegmentIndex = 0;
    segmentCaptions.clear();
    layoutMode = 'normal';
    notifyListeners();
  }
}
