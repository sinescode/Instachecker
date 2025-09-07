// widgets/result_item.dart
import 'package:flutter/material.dart';

class ResultItem extends StatelessWidget {
  final Map<String, dynamic> result;

  const ResultItem({Key? key, required this.result}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Color backgroundColor;
    Color textColor;
    IconData icon;

    switch (result['status']) {
      case 'ACTIVE':
        backgroundColor = Colors.red.shade100;
        textColor = Colors.red.shade900;
        icon = Icons.person;
        break;
      case 'AVAILABLE':
        backgroundColor = Colors.green.shade100;
        textColor = Colors.green.shade900;
        icon = Icons.check_circle;
        break;
      case 'ERROR':
        backgroundColor = Colors.yellow.shade100;
        textColor = Colors.yellow.shade900;
        icon = Icons.error;
        break;
      default:
        backgroundColor = Colors.grey.shade100;
        textColor = Colors.grey.shade900;
        icon = Icons.help;
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      color: backgroundColor,
      child: ListTile(
        leading: Icon(icon, color: textColor),
        title: Text(
          result['message'],
          style: TextStyle(color: textColor),
        ),
      ),
    );
  }
}