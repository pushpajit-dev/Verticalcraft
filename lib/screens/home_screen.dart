import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../services/api_client.dart';
import '../services/segment_session.dart';
import '../widgets/web_video_player.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final ApiClient _api = ApiClient();
  final SegmentSession _session = SegmentSession();

  bool _isLoading = true;
  List<Map<String, dynamic>> _projects = [];
  Map<String, dynamic>? _draft;
  String _hardwareInfo = 'Auto-Detecting GPU...';
  String _hardwareType = 'GPU / NVENC';

  @override
  void initState() {
    super.initState();
    CustomMediaView.stopAllBackgroundPlayback();
    _loadDashboardData();
  }

  Future<void> _loadDashboardData() async {
    setState(() => _isLoading = true);
    try {
      final hw = await _api.getHardwareInfo();
      final pRes = await _api.listProjects();

      if (mounted) {
        setState(() {
          _hardwareInfo = hw['gpu_name'] ?? hw['recommended_encoder'] ?? 'GPU Accelerated';
          _hardwareType = hw['device_type'] ?? 'NVENC';
          _projects = List<Map<String, dynamic>>.from(pRes['projects'] ?? []);
          _draft = pRes['draft'];
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _resumeDraft() async {
    if (_draft == null) return;
    try {
      final data = await _api.getProject('draft');
      _session.loadProject(data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('📂 Resumed Draft: ${_session.projectName}', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            backgroundColor: const Color(0xFF00F0FF),
          ),
        );
        context.push('/layout');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load draft: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _discardDraft() async {
    try {
      await _api.deleteProject('draft');
      setState(() => _draft = null);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Draft discarded.'), backgroundColor: Colors.white24),
        );
      }
    } catch (_) {}
  }

  Future<void> _openProject(String projectId) async {
    try {
      final data = await _api.getProject(projectId);
      _session.loadProject(data);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🚀 Loaded Project: ${_session.projectName}', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            backgroundColor: const Color(0xFF00F0FF),
          ),
        );
        context.push('/layout');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load project: $e'), backgroundColor: Colors.redAccent),
        );
      }
    }
  }

  Future<void> _deleteProject(String projectId, String projectName) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141724),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: const BorderSide(color: Colors.redAccent)),
        title: const Row(
          children: [
            Icon(Icons.delete_outline, color: Colors.redAccent),
            SizedBox(width: 8),
            Text('Delete Project?'),
          ],
        ),
        content: Text('Are you sure you want to delete "$projectName"? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel', style: TextStyle(color: Colors.white70))),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, foregroundColor: Colors.white),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _api.deleteProject(projectId);
        _loadDashboardData();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Deleted project "$projectName"'), backgroundColor: Colors.white24),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to delete: $e'), backgroundColor: Colors.redAccent),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0C14),
      body: SafeArea(
        child: Column(
          children: [
            // Top Navigation & Branding Bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
              decoration: const BoxDecoration(
                color: Color(0xFF0F111A),
                border: Border(bottom: BorderSide(color: Color(0xFF1F2232), width: 1.5)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF00F0FF), Color(0xFF7000FF)]),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.movie_creation_outlined, color: Colors.black, size: 22),
                  ),
                  const SizedBox(width: 14),
                  const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'VerticalCraft Studio',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 0.8, color: Colors.white),
                      ),
                      Text(
                        'AI-Powered Vertical Shorts & Reels Engine',
                        style: TextStyle(fontSize: 11, color: Colors.white54),
                      ),
                    ],
                  ),
                  const Spacer(),

                  // Hardware Acceleration Pill
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF141724),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF00F0FF).withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.bolt, color: Color(0xFFFFD700), size: 16),
                        const SizedBox(width: 6),
                        Text(
                          '$_hardwareType • $_hardwareInfo',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF00F0FF)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),

                  // New Project Button
                  ElevatedButton.icon(
                    onPressed: () {
                      _session.resetSession();
                      context.push('/import');
                    },
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('New Project', style: TextStyle(fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00F0FF),
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      elevation: 4,
                    ),
                  ),
                ],
              ),
            ),

            // Main Dashboard Body
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          CircularProgressIndicator(color: Color(0xFF00F0FF)),
                          SizedBox(height: 16),
                          Text('Loading Projects & AI Engine...', style: TextStyle(color: Colors.white60)),
                        ],
                      ),
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // 1. Active Draft / Auto-Saved Session Recovery Banner
                          if (_draft != null) ...[
                            Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  colors: [
                                    const Color(0xFF7000FF).withValues(alpha: 0.25),
                                    const Color(0xFF00F0FF).withValues(alpha: 0.1),
                                  ],
                                ),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(color: const Color(0xFF00F0FF), width: 1.5),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(color: const Color(0xFF00F0FF).withValues(alpha: 0.15), shape: BoxShape.circle),
                                    child: const Icon(Icons.restore_page_rounded, color: Color(0xFF00F0FF), size: 24),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            const Text(
                                              'Unfinished Project Draft Found',
                                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white),
                                            ),
                                            const SizedBox(width: 10),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(color: const Color(0xFFFFD700), borderRadius: BorderRadius.circular(4)),
                                              child: const Text('AUTO-SAVED', style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.black)),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${_draft?['project_name'] ?? 'Untitled Draft'} • Last updated: ${_draft?['updated_at'] ?? 'Recently'}',
                                          style: const TextStyle(fontSize: 12, color: Colors.white70),
                                        ),
                                      ],
                                    ),
                                  ),
                                  OutlinedButton.icon(
                                    onPressed: _discardDraft,
                                    icon: const Icon(Icons.close, size: 14),
                                    label: const Text('Discard'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.white60,
                                      side: const BorderSide(color: Colors.white24),
                                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  ElevatedButton.icon(
                                    onPressed: _resumeDraft,
                                    icon: const Icon(Icons.play_arrow_rounded, size: 18),
                                    label: const Text('Resume Draft', style: TextStyle(fontWeight: FontWeight.bold)),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF00F0FF),
                                      foregroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 28),
                          ],

                          // 2. Saved Projects Header & Filter
                          Row(
                            children: [
                              const Icon(Icons.folder_special_rounded, color: Color(0xFF00F0FF), size: 20),
                              const SizedBox(width: 8),
                              Text(
                                'Projects (${_projects.length})',
                                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              const Spacer(),
                              IconButton(
                                onPressed: _loadDashboardData,
                                icon: const Icon(Icons.refresh_rounded, color: Colors.white60),
                                tooltip: 'Refresh Projects',
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),

                          // 3. Projects Grid or Empty State
                          if (_projects.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(vertical: 60, horizontal: 20),
                              decoration: BoxDecoration(
                                color: const Color(0xFF0F111A),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFF1F2232)),
                              ),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.video_library_outlined, size: 64, color: Colors.white.withValues(alpha: 0.2)),
                                  const SizedBox(height: 16),
                                  const Text('No Saved Projects Yet', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                                  const SizedBox(height: 6),
                                  const Text(
                                    'Import a landscape gaming video or podcast to generate 9:16 Shorts with AI captions & audio separation.',
                                    style: TextStyle(fontSize: 13, color: Colors.white54),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 24),
                                  ElevatedButton.icon(
                                    onPressed: () {
                                      _session.resetSession();
                                      context.push('/import');
                                    },
                                    icon: const Icon(Icons.video_call_rounded),
                                    label: const Text('Create First Project'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFF00F0FF),
                                      foregroundColor: Colors.black,
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            GridView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                maxCrossAxisExtent: 360,
                                mainAxisExtent: 220,
                                crossAxisSpacing: 18,
                                mainAxisSpacing: 18,
                              ),
                              itemCount: _projects.length,
                              itemBuilder: (ctx, idx) {
                                final p = _projects[idx];
                                final pId = p['project_id'] ?? '';
                                final pName = p['project_name'] ?? 'Untitled Project';
                                final segCount = p['segments_count'] ?? 0;
                                final layoutMode = p['layout_mode'] ?? 'normal';
                                final preset = p['preset'] ?? 'mrbeast';
                                final updatedAt = p['updated_at'] ?? '';

                                return Container(
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF141724),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(color: const Color(0xFF1F2232), width: 1.5),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Project Card Header
                                      Container(
                                        padding: const EdgeInsets.all(14),
                                        decoration: const BoxDecoration(
                                          color: Color(0xFF0F111A),
                                          borderRadius: BorderRadius.vertical(top: Radius.circular(13)),
                                        ),
                                        child: Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.all(6),
                                              decoration: BoxDecoration(color: const Color(0xFF7000FF).withValues(alpha: 0.3), borderRadius: BorderRadius.circular(6)),
                                              child: const Icon(Icons.movie_outlined, color: Color(0xFF00F0FF), size: 16),
                                            ),
                                            const SizedBox(width: 10),
                                            Expanded(
                                              child: Text(
                                                pName,
                                                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            IconButton(
                                              onPressed: () => _deleteProject(pId, pName),
                                              icon: const Icon(Icons.delete_outline, color: Colors.white38, size: 18),
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(),
                                              tooltip: 'Delete Project',
                                            ),
                                          ],
                                        ),
                                      ),

                                      // Project Details
                                      Expanded(
                                        child: Padding(
                                          padding: const EdgeInsets.all(14),
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                    decoration: BoxDecoration(color: const Color(0xFF00F0FF).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                                                    child: Text(
                                                      '$segCount Segments',
                                                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFF00F0FF)),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                    decoration: BoxDecoration(color: const Color(0xFFFFD700).withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)),
                                                    child: Text(
                                                      layoutMode == 'streamer' ? 'Streamer Split' : 'Framed',
                                                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Color(0xFFFFD700)),
                                                    ),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                                    decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(4)),
                                                    child: Text(
                                                      preset.toString().toUpperCase(),
                                                      style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white70),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const Spacer(),
                                              Text(
                                                'Edited: $updatedAt',
                                                style: const TextStyle(fontSize: 11, color: Colors.white38),
                                              ),
                                              const SizedBox(height: 10),
                                              SizedBox(
                                                width: double.infinity,
                                                child: ElevatedButton.icon(
                                                  onPressed: () => _openProject(pId),
                                                  icon: const Icon(Icons.launch_rounded, size: 14),
                                                  label: const Text('Open Project', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                                  style: ElevatedButton.styleFrom(
                                                    backgroundColor: const Color(0xFF1F2232),
                                                    foregroundColor: const Color(0xFF00F0FF),
                                                    padding: const EdgeInsets.symmetric(vertical: 10),
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8), side: const BorderSide(color: Color(0xFF00F0FF), width: 0.8)),
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
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

