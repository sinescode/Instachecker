import 'package:flutter/material.dart';
import '../widgets/tab_selector.dart';
import '../widgets/file_upload_tab.dart';
import '../widgets/text_input_tab.dart';
import '../widgets/json_to_excel_tab.dart';
import '../widgets/progress_section.dart';
import '../widgets/results_section.dart';
import '../services/username_service.dart';
import '../models/account_model.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  final UsernameService _usernameService = UsernameService();
  
  List<CheckResult> _results = [];
  List<String> _statusUpdates = [];
  ProcessingStats _stats = ProcessingStats(
    activeCount: 0,
    availableCount: 0,
    errorCount: 0,
    cancelledCount: 0,
    totalCount: 0,
  );

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _setupStreams();
  }

  void _setupStreams() {
    _usernameService.resultStream.listen((result) {
      setState(() {
        _results.insert(0, result);
      });
    });

    _usernameService.statsStream.listen((stats) {
      setState(() {
        _stats = stats;
      });
    });

    _usernameService.statusStream.listen((status) {
      setState(() {
        _statusUpdates.insert(0, status);
        // Keep only last 50 status updates to prevent memory issues
        if (_statusUpdates.length > 50) {
          _statusUpdates = _statusUpdates.take(50).toList();
        }
      });
    });
  }

  void _startProcessing(List<AccountModel> accounts) {
    setState(() {
      _results.clear();
      _statusUpdates.clear();
      _stats = ProcessingStats(
        activeCount: 0,
        availableCount: 0,
        errorCount: 0,
        cancelledCount: 0,
        totalCount: accounts.length,
      );
    });
    
    _usernameService.processUsernames(accounts);
  }

  void _cancelProcessing() {
    _usernameService.cancelProcessing();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _usernameService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: Container(
              constraints: const BoxConstraints(maxWidth: 600),
              child: Card(
                elevation: 8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Header
                      Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.camera_alt,
                                color: Colors.indigo[600],
                                size: 28,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Instagram Username Checker',
                                style: TextStyle(
                                  fontSize: 24,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.indigo[600],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Check many usernames quickly — optimized for mobile',
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      
                      // Tab Selector
                      TabSelector(
                        controller: _tabController,
                        tabs: const [
                          Tab(
                            icon: Icon(Icons.file_upload),
                            text: 'Upload File',
                          ),
                          Tab(
                            icon: Icon(Icons.keyboard),
                            text: 'Enter Text',
                          ),
                          Tab(
                            icon: Icon(Icons.table_chart),
                            text: 'JSON to Excel',
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      
                      // Tab Content
                      Expanded(
                        child: TabBarView(
                          controller: _tabController,
                          children: [
                            FileUploadTab(onStartProcessing: _startProcessing),
                            TextInputTab(onStartProcessing: _startProcessing),
                            const JsonToExcelTab(),
                          ],
                        ),
                      ),
                      
                      // Progress Section (only show for first two tabs)
                      if (_tabController.index < 2) ...[
                        const SizedBox(height: 20),
                        ProgressSection(
                          stats: _stats,
                          isProcessing: _usernameService.isProcessing,
                          isCompleted: _usernameService.isCompleted,
                          onCancel: _cancelProcessing,
                          activeAccounts: _usernameService.getActiveAccounts(),
                        ),
                      ],
                      
                      // Results Section (only show for first two tabs)
                      if (_tabController.index < 2) ...[
                        const SizedBox(height: 20),
                        ResultsSection(
                          results: _results,
                          statusUpdates: _statusUpdates,
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}