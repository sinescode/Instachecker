// screens/home_screen.dart
import 'package:flutter/material.dart';
import 'package:instachecker/screens/file_tab.dart';
import 'package:instachecker/screens/text_tab.dart';
import 'package:instachecker/screens/converter_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('InstaChecker'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'File'),
            Tab(text: 'Text'),
            Tab(text: 'Converter'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: const [
          FileTab(),
          TextTab(),
          ConverterTab(),
        ],
      ),
    );
  }
}