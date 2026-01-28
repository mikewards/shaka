import 'package:flutter/material.dart';
import '../../../../data/models/offline_region.dart';
import '../../../../data/services/offline_download_service.dart';

/// Bottom sheet showing downloaded offline regions
class OfflineRegionsSheet extends StatefulWidget {
  const OfflineRegionsSheet({super.key});

  @override
  State<OfflineRegionsSheet> createState() => _OfflineRegionsSheetState();
}

class _OfflineRegionsSheetState extends State<OfflineRegionsSheet> {
  final _downloadService = OfflineDownloadService();
  List<OfflineRegion>? _regions;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadRegions();
  }

  Future<void> _loadRegions() async {
    final regions = await _downloadService.getRegions();
    if (mounted) {
      setState(() {
        _regions = regions;
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteRegion(OfflineRegion region) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Delete Region?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Delete "${region.name}"? This will remove ${region.formattedSize} of cached data.',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _downloadService.deleteRegion(region.id);
      _loadRegions();
    }
  }

  Future<void> _clearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A1A),
        title: const Text('Clear All Data?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'This will delete all downloaded regions and clear the tile cache.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Clear All', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _downloadService.clearAll();
      _loadRegions();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Color(0xFF0D0D0D),
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 8, bottom: 16),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),

          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                const Icon(Icons.offline_pin, color: Colors.white, size: 24),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Offline Regions',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                if (_regions != null && _regions!.isNotEmpty)
                  TextButton(
                    onPressed: _clearAll,
                    child: const Text('Clear All', style: TextStyle(color: Colors.red, fontSize: 12)),
                  ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // Content
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(40),
              child: CircularProgressIndicator(color: Colors.white),
            )
          else if (_regions == null || _regions!.isEmpty)
            _buildEmptyState()
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _regions!.length,
                itemBuilder: (context, index) => _buildRegionTile(_regions![index]),
              ),
            ),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(Icons.cloud_off, size: 48, color: Colors.white24),
          const SizedBox(height: 16),
          const Text(
            'No offline regions',
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          const SizedBox(height: 8),
          const Text(
            'Download a region to use charts without internet',
            style: TextStyle(color: Colors.white54, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildRegionTile(OfflineRegion region) {
    final statusColor = region.status == DownloadStatus.completed
        ? Colors.green
        : region.status == DownloadStatus.failed
            ? Colors.red
            : Colors.orange;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: region.isStale
            ? Border.all(color: Colors.orange.withValues(alpha: 0.5))
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      region.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: statusColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          region.formattedSize,
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${region.layerIds.length} layers',
                          style: const TextStyle(color: Colors.white54, fontSize: 12),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: Colors.white38),
                onPressed: () => _deleteRegion(region),
              ),
            ],
          ),
          if (region.isStale) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.warning_amber, size: 14, color: Colors.orange.shade300),
                  const SizedBox(width: 4),
                  Text(
                    'Data is ${DateTime.now().difference(region.dataDate).inDays} days old',
                    style: TextStyle(color: Colors.orange.shade300, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            'Data from ${_formatDate(region.dataDate)} UTC',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }
}
