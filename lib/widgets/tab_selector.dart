import 'package:flutter/material.dart';

class TabSelector extends StatelessWidget {
  final TabController controller;
  final List<Tab> tabs;

  const TabSelector({
    super.key,
    required this.controller,
    required this.tabs,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: TabBar(
        controller: controller,
        indicator: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.indigo[50],
        ),
        labelColor: Colors.indigo[700],
        unselectedLabelColor: Colors.grey[700],
        labelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        unselectedLabelStyle: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        tabs: tabs.map((tab) => Tab(
          icon: SizedBox(
            height: 20,
            child: tab.icon,
          ),
          text: tab.text,
        )).toList(),
      ),
    );
  }
}