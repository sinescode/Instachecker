import 'package:flutter/material.dart';
import '../models/account_model.dart';

class ResultsSection extends StatelessWidget {
  final List<CheckResult> results;
  final List<String> statusUpdates;

  const ResultsSection({
    super.key,
    required this.results,
    required this.statusUpdates,
  });

  @override
  Widget build(BuildContext context) {
    final allItems = <Widget>[];
    
    // Add status updates
    for (final status in statusUpdates) {
      allItems.add(_StatusUpdateItem(message: status));
    }
    
    // Add results
    for (final result in results) {
      allItems.add(_ResultItem(result: result));
    }

    return Container(
      height: 300,
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
              Icon(Icons.list_alt, color: Colors.indigo[500], size: 24),
              const SizedBox(width: 8),
              const Text(
                'Results',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Expanded(
            child: allItems.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.hourglass_empty,
                          size: 48,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Results will appear here',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: allItems.length,
                    itemBuilder: (context, index) => allItems[index],
                    padding: const EdgeInsets.only(bottom: 8),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ResultItem extends StatelessWidget {
  final CheckResult result;

  const _ResultItem({required this.result});

  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    Color textColor;
    Color borderColor;
    IconData icon;

    switch (result.status) {
      case 'ACTIVE':
        backgroundColor = Colors.red[50]!;
        textColor = Colors.red[700]!;
        borderColor = Colors.red[100]!;
        icon = Icons.person_check;
        break;
      case 'AVAILABLE':
        backgroundColor = Colors.green[50]!;
        textColor = Colors.green[700]!;
        borderColor = Colors.green[100]!;
        icon = Icons.person_add;
        break;
      case 'ERROR':
        backgroundColor = Colors.orange[50]!;
        textColor = Colors.orange[700]!;
        borderColor = Colors.orange[100]!;
        icon = Icons.error;
        break;
      default:
        backgroundColor = Colors.grey[50]!;
        textColor = Colors.grey[700]!;
        borderColor = Colors.grey[100]!;
        icon = Icons.help;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
      ),
      child: Row(
        children: [
          Icon(icon, color: textColor, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              result.username,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: textColor,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusUpdateItem extends StatelessWidget {
  final String message;

  const _StatusUpdateItem({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[100]!),
      ),
      child: Row(
        children: [
          Icon(Icons.info, color: Colors.blue[500], size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
          ),
        ],
      ),
    );
  }
}