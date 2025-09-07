import 'package:flutter/material.dart';
import '../models/account_model.dart';
import '../services/file_service.dart';

class ProgressSection extends StatelessWidget {
  final ProcessingStats stats;
  final bool isProcessing;
  final bool isCompleted;
  final VoidCallback onCancel;
  final List<AccountModel> activeAccounts;

  const ProgressSection({
    super.key,
    required this.stats,
    required this.isProcessing,
    required this.isCompleted,
    required this.onCancel,
    required this.activeAccounts,
  });

  void _showSnackBar(BuildContext context, String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<void> _downloadResults(BuildContext context) async {
    if (activeAccounts.isEmpty) {
      _showSnackBar(context, 'No active accounts to download', Colors.orange);
      return;
    }

    try {
      final filePath = await FileService.saveActiveAccountsAsJson(
        activeAccounts,
        'final_active_accounts.json',
      );
      await FileService.shareFile(filePath);
      _showSnackBar(context, 'Results downloaded and shared!', Colors.green);
    } catch (e) {
      _showSnackBar(context, 'Error downloading results: ${e.toString()}', Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (stats.totalCount == 0) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[200]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.bar_chart, color: Colors.indigo[500], size: 24),
              const SizedBox(width: 8),
              const Text(
                'Progress',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Progress bar
          Container(
            width: double.infinity,
            height: 16,
            decoration: BoxDecoration(
              color: Colors.grey[200],
              borderRadius: BorderRadius.circular(8),
            ),
            child: FractionallySizedBox(
              alignment: Alignment.centerLeft,
              widthFactor: stats.progress,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.green[600],
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Processed: ${stats.processedCount}/${stats.totalCount} (${(stats.progress * 100).toStringAsFixed(1)}%)',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Stats grid
          Row(
            children: [
              Expanded(
                child: _StatCard(
                  count: stats.activeCount,
                  label: 'Active',
                  color: Colors.red,
                  icon: Icons.person_check,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatCard(
                  count: stats.availableCount,
                  label: 'Available',
                  color: Colors.green,
                  icon: Icons.person_add,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatCard(
                  count: stats.errorCount,
                  label: 'Error',
                  color: Colors.orange,
                  icon: Icons.error,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _StatCard(
                  count: stats.totalCount,
                  label: 'Total',
                  color: Colors.grey,
                  icon: Icons.list,
                ),
              ),
            ],
          ),
          
          const SizedBox(height: 16),
          
          // Action buttons
          Row(
            children: [
              if (isProcessing) ...[
                Expanded(
                  child: ElevatedButton(
                    onPressed: onCancel,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.close, size: 16),
                        SizedBox(width: 4),
                        Text('Cancel'),
                      ],
                    ),
                  ),
                ),
              ],
              if (isCompleted) ...[
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => _downloadResults(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[600],
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.download, size: 16),
                        SizedBox(width: 4),
                        Text('Download'),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final int count;
  final String label;
  final Color color;
  final IconData icon;

  const _StatCard({
    required this.count,
    required this.label,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color[700],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 12, color: Colors.grey[500]),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey[500],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}