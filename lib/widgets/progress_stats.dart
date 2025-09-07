// widgets/progress_stats.dart
import 'package:flutter/material.dart';

class ProgressStats extends StatelessWidget {
  final int activeCount;
  final int availableCount;
  final int errorCount;
  final int totalCount;

  const ProgressStats({
    Key? key,
    required this.activeCount,
    required this.availableCount,
    required this.errorCount,
    required this.totalCount,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 4,
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Statistics',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _StatCard(
                  title: 'Active',
                  value: activeCount.toString(),
                  color: Colors.red,
                ),
                _StatCard(
                  title: 'Available',
                  value: availableCount.toString(),
                  color: Colors.green,
                ),
                _StatCard(
                  title: 'Errors',
                  value: errorCount.toString(),
                  color: Colors.yellow,
                ),
              ],
            ),
            const SizedBox(height: 16),
            Center(
              child: Text(
                'Total: $totalCount',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final String title;
  final String value;
  final Color color;

  const _StatCard({
    Key? key,
    required this.title,
    required this.value,
    required this.color,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.2),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Column(
        children: [
          Text(
            value,
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(
              fontSize: 14,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}