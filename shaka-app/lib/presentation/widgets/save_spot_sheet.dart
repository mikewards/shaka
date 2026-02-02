import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../data/api/shaka_api_client.dart';

/// Bottom sheet for saving a new spot at a pinned location.
class SaveSpotSheet extends StatefulWidget {
  final double latitude;
  final double longitude;
  
  const SaveSpotSheet({
    super.key,
    required this.latitude,
    required this.longitude,
  });

  /// Show the save spot sheet and return true if saved successfully
  static Future<bool> show({
    required BuildContext context,
    required double latitude,
    required double longitude,
  }) async {
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SaveSpotSheet(
        latitude: latitude,
        longitude: longitude,
      ),
    );
    return result ?? false;
  }

  @override
  State<SaveSpotSheet> createState() => _SaveSpotSheetState();
}

class _SaveSpotSheetState extends State<SaveSpotSheet> {
  final _nameController = TextEditingController();
  final _apiClient = ShakaApiClient();
  
  bool _isLoading = false;
  String? _errorMessage;

  static const _bgColor = Color(0xFF0D0D0D);
  static const _cardColor = Color(0xFF1A1A1A);

  @override
  void initState() {
    super.initState();
    _nameController.text = '';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  String _formatCoordinate(double value, bool isLatitude) {
    final direction = isLatitude 
        ? (value >= 0 ? 'N' : 'S')
        : (value >= 0 ? 'E' : 'W');
    return '${value.abs().toStringAsFixed(4)}° $direction';
  }

  Future<void> _saveSpot() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _errorMessage = 'Please enter a name for this spot');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    debugPrint('📍 SaveSpot: Saving spot "$name" at (${widget.latitude}, ${widget.longitude})');

    try {
      final result = await _apiClient.createUserSpot(
        name: name,
        latitude: widget.latitude,
        longitude: widget.longitude,
      );

      debugPrint('📍 SaveSpot: SUCCESS! Saved spot id=${result.id}, name=${result.name}');
      HapticFeedback.mediumImpact();
      
      if (mounted) {
        // No snackbar - just close the sheet
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      debugPrint('📍 SaveSpot: FAILED! Error: $e');
      HapticFeedback.heavyImpact();
      String errorMsg = 'Failed to save spot. Please try again.';
      
      final errorStr = e.toString();
      if (errorStr.contains('404') || errorStr.contains('Unable to connect')) {
        errorMsg = 'Saved spots feature coming soon! Backend update required.';
      } else if (errorStr.contains('Duplicate') || errorStr.contains('409')) {
        errorMsg = 'You already have a spot at this location.';
      } else if (errorStr.contains('limit') || errorStr.contains('100')) {
        errorMsg = 'Spot limit reached (100 max). Delete some spots first.';
      }
      
      setState(() {
        _isLoading = false;
        _errorMessage = errorMsg;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).viewInsets.bottom;
    
    return Container(
      width: double.infinity,  // CRITICAL: explicit width prevents gaps
      padding: EdgeInsets.only(bottom: bottomPadding),
      decoration: const BoxDecoration(
        color: _bgColor,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            MediaQuery.of(context).padding.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Handle
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              
              // Title
              const Text(
                'Save Spot',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 16),
              
              // Coordinates display
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _cardColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on, color: Colors.white38, size: 18),
                    const SizedBox(width: 10),
                    Text(
                      '${_formatCoordinate(widget.latitude, true)}  ${_formatCoordinate(widget.longitude, false)}',
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              
              // Name input
              TextField(
                controller: _nameController,
                enabled: !_isLoading,
                autofocus: true,
                autocorrect: false,
                enableSuggestions: false,
                textInputAction: TextInputAction.done,
                style: const TextStyle(color: Colors.white, fontSize: 16),
                decoration: InputDecoration(
                  hintText: 'Name this spot...',
                  hintStyle: TextStyle(color: Colors.white.withOpacity(0.3)),
                  filled: true,
                  fillColor: _cardColor,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: const BorderSide(color: Colors.white24),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                ),
              ),
              
              // Error message
              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _errorMessage!,
                          style: const TextStyle(color: Colors.red, fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              
              const SizedBox(height: 20),
              
              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: _isLoading ? null : () => Navigator.of(context).pop(false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: _cardColor,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Center(
                          child: Text(
                            'Cancel',
                            style: TextStyle(
                              color: Colors.white70,
                              fontSize: 15,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: GestureDetector(
                      onTap: _isLoading ? null : _saveSpot,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: _isLoading ? Colors.white54 : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: _isLoading
                              ? const SizedBox(
                                  height: 20,
                                  width: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Color(0xFF1A1A1A),
                                  ),
                                )
                              : const Text(
                                  'Save',
                                  style: TextStyle(
                                    color: Color(0xFF1A1A1A),
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
