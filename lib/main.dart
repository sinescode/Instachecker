import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:http/http.dart' as http;
import 'package:excel/excel.dart';
import 'package:path/path.dart' as path;
import 'package:synchronized/synchronized.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InstaCheck',
      theme: ThemeData(
        primaryColor: Colors.blue,
        primarySwatch: Colors.blue,
        scaffoldBackgroundColor: Colors.grey[50],
        cardColor: Colors.white,
        textTheme: const TextTheme(
          bodyLarge: TextStyle(color: Colors.black87),
          bodyMedium: TextStyle(color: Colors.black54),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
        colorScheme: ColorScheme.fromSwatch().copyWith(
          secondary: Colors.green,
          error: Colors.red,
        ),
      ),
      home: const MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  const MainScreen({super.key});

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _currentTab = 0; // 0: File, 1: Text, 2: Convert
  final List<String> _tabNames = ['File Input', 'Text Input', 'Convert JSON to Excel'];

  // Shared variables
  final Map<String, String> _headers = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0 Safari/537.36",
    "x-ig-app-id": "936619743392459",
    "Accept": "*/*",
    "Accept-Language": "en-US,en;q=0.9",
    "Referer": "https://www.instagram.com/",
    "Origin": "https://www.instagram.com",
    "Sec-Fetch-Site": "same-origin",
  };

  final int maxRetries = 10;
  final int initialDelay = 1000;
  final int maxDelay = 60000;
  final int concurrentLimit = 5;

  // For processing (File and Text tabs)
  PlatformFile? _selectedFile;
  String _originalFileName = '';
  List<String> _usernames = [];
  Map<String, Map<String, dynamic>> _accountData = {};
  List<Map<String, dynamic>> _activeAccounts = [];
  int _processedCount = 0;
  int _activeCount = 0;
  int _availableCount = 0;
  int _errorCount = 0;
  int _cancelledCount = 0;
  bool _isProcessing = false;
  final List<ResultItem> _results = [];
  Completer<void>? _canceller;
  final _lock = Lock(); // From synchronized package for semaphore-like behavior
  final GlobalKey<ScaffoldMessengerState> _scaffoldKey = GlobalKey();

  // For Text tab
  final TextEditingController _textController = TextEditingController();

  // For Convert tab
  PlatformFile? _selectedJsonFile;

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _switchTab(int index) {
    setState(() {
      _currentTab = index;
    });
  }

  Future<void> _pickFileForProcessing() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'json'],
    );
    if (result != null) {
      setState(() {
        _selectedFile = result.files.first;
        _originalFileName = path.basenameWithoutExtension(_selectedFile!.name);
      });
    }
  }

  Future<void> _startProcessingFromFile() async {
    if (_selectedFile == null) {
      _showError('Please select a file first');
      return;
    }
    final extension = _selectedFile!.extension;
    if (extension != 'json' && extension != 'txt') {
      _showError('File must be .json or .txt format');
      return;
    }
    await _loadUsernamesFromFile(_selectedFile!, extension!);
    await _startProcessing();
  }

  Future<void> _startProcessingFromText() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _showError('Please enter at least one username');
      return;
    }
    _usernames = text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
    for (var u in _usernames) {
      _accountData[u] = {'username': u};
    }
    _originalFileName = 'manual_input';
    await _startProcessing();
  }

  Future<void> _loadUsernamesFromFile(PlatformFile file, String type) async {
    final bytes = await File(file.path!).readAsBytes();
    if (type == 'txt') {
      final content = utf8.decode(bytes);
      _usernames = content.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      for (var u in _usernames) {
        _accountData[u] = {'username': u};
      }
    } else { // json
      final content = utf8.decode(bytes);
      try {
        final List<dynamic> array = jsonDecode(content);
        _usernames = array.map((e) => e['username'] as String).toList();
        for (int i = 0; i < _usernames.length; i++) {
          _accountData[_usernames[i]] = array[i] as Map<String, dynamic>;
        }
      } catch (e) {
        _showError('Invalid JSON format');
      }
    }
  }

  Future<void> _startProcessing() async {
    if (_usernames.isEmpty) {
      _showError('No valid usernames found');
      return;
    }
    _resetStats();
    setState(() {
      _isProcessing = true;
    });
    _canceller = Completer();
    final client = http.Client();
    final futures = <Future>[];
    int activePermits = 0;

    for (var username in _usernames) {
      futures.add(_processWithSemaphore(() async {
        if (_canceller!.isCompleted) return;
        await _checkUsername(client, username);
      }));
    }

    await Future.wait(futures);
    if (!_canceller!.isCompleted) {
      setState(() {
        _isProcessing = false;
      });
      _showSuccess('Processing completed! Found ${_activeAccounts.length} active accounts.');
    }
  }

  Future<void> _processWithSemaphore(Future<void> Function() task) async {
    await _lock.synchronized(task);
  }

  Future<void> _checkUsername(http.Client client, String username) async {
    final url = Uri.parse('https://i.instagram.com/api/v1/users/web_profile_info/?username=$username');
    int retryCount = 0;
    int delayMs = initialDelay;

    while (retryCount < maxRetries) {
      if (_canceller!.isCompleted) {
        _updateResult('CANCELLED', 'Cancelled: $username', username);
        return;
      }

      try {
        final response = await client.get(url, headers: _headers);
        final code = response.statusCode;

        if (code == 404) {
          final result = ' $username - Available';
          _updateResult('AVAILABLE', result, username);
          return;
        } else if (code == 200) {
          final body = response.body;
          final json = jsonDecode(body);
          final status = json['data']?['user'] != null ? 'ACTIVE' : 'AVAILABLE';
          final result = status == 'ACTIVE' ? ' $username - Active' : ' $username - Available';
          _updateResult(status, result, username);
          if (status == 'ACTIVE') {
            final data = _accountData[username];
            if (data != null) _activeAccounts.add(data);
          }
          return;
        } else {
          retryCount++;
          final statusMsg = ' Retry $retryCount/$maxRetries for $username (Status: $code)';
          _updateStatus(statusMsg, username);
        }
      } catch (e) {
        retryCount++;
        final statusMsg = ' Retry $retryCount/$maxRetries for $username (${e.toString().substring(0, min(30, e.toString().length))}...)';
        _updateStatus(statusMsg, username);
      }
      await Future.delayed(Duration(milliseconds: delayMs));
      delayMs = min(maxDelay, (delayMs * 2 + Random().nextInt(1000)).toInt());
    }
    final result = ' $username - Error (Max retries exceeded)';
    _updateResult('ERROR', result, username);
  }

  void _updateResult(String status, String message, String username) {
    setState(() {
      _processedCount++;
      switch (status) {
        case 'ACTIVE':
          _activeCount++;
          break;
        case 'AVAILABLE':
          _availableCount++;
          break;
        case 'ERROR':
          _errorCount++;
          break;
        case 'CANCELLED':
          _cancelledCount++;
          break;
      }
      _results.insert(0, ResultItem(status, message));
    });
  }

  void _updateStatus(String message, String username) {
    setState(() {
      _results.insert(0, ResultItem('INFO', message));
    });
  }

  void _resetStats() {
    _processedCount = 0;
    _activeCount = 0;
    _availableCount = 0;
    _errorCount = 0;
    _cancelledCount = 0;
    _activeAccounts.clear();
    _results.clear();
    setState(() {});
  }

  void _cancelProcessing() {
    _canceller?.complete();
    setState(() {
      _isProcessing = false;
    });
    _showInfo('Processing cancelled');
  }

  Future<void> _downloadResults() async {
    if (_activeAccounts.isEmpty) {
      _showError('No active accounts to download');
      return;
    }
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '').split('.').first;
    final fileName = 'final_$_originalFileName_$timestamp.json';
    final result = await FilePicker.platform.saveFile(
      fileName: fileName,
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result != null) {
      final jsonArray = jsonEncode(_activeAccounts);
      await File(result).writeAsString(jsonArray);
      _showSuccess('Results saved successfully! (${_activeAccounts.length} active accounts)');
    }
  }

  // Convert tab logic
  Future<void> _pickJsonForConvert() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result != null) {
      setState(() {
        _selectedJsonFile = result.files.first;
      });
    }
  }

  Future<void> _convertJsonToExcel() async {
    if (_selectedJsonFile == null) {
      _showError('Please select a JSON file first');
      return;
    }
    try {
      final bytes = await File(_selectedJsonFile!.path!).readAsBytes();
      final content = utf8.decode(bytes);
      final List<dynamic> data = jsonDecode(content);

      // Create Excel
      var excel = Excel.createExcel();
      Sheet sheet = excel['Sheet1'];

      // Headers
      sheet.appendRow([
        TextCellValue('Username'), 
        TextCellValue('Password'), 
        TextCellValue('Authcode'), 
        TextCellValue('Email')
      ]);

      // Data rows, only include if fields exist
      for (var row in data) {
        final map = row as Map<String, dynamic>;
        sheet.appendRow([
          TextCellValue(map['username'] ?? ''),
          TextCellValue(map['password'] ?? ''),
          TextCellValue(map['auth_code'] ?? ''),
          TextCellValue(map['email'] ?? ''),
        ]);
      }

      // Save
      final baseName = path.basenameWithoutExtension(_selectedJsonFile!.name);
      final excelPath = await FilePicker.platform.saveFile(
        fileName: '$baseName.xlsx',
        type: FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (excelPath != null) {
        final bytes = excel.encode();
        if (bytes != null) {
          await File(excelPath).writeAsBytes(bytes);
          _showSuccess('Converted: ${_selectedJsonFile!.name} → $baseName.xlsx');
        }
      }
    } catch (e) {
      _showError('Failed to convert: $e');
    }
  }

  void _showSuccess(String message) {
    Fluttertoast.showToast(msg: message, toastLength: Toast.LENGTH_LONG, gravity: ToastGravity.BOTTOM);
  }

  void _showError(String message) {
    Fluttertoast.showToast(msg: message, toastLength: Toast.LENGTH_LONG, gravity: ToastGravity.BOTTOM, backgroundColor: Colors.red);
  }

  void _showInfo(String message) {
    Fluttertoast.showToast(msg: message, toastLength: Toast.LENGTH_SHORT, gravity: ToastGravity.BOTTOM);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      appBar: AppBar(
        title: const Text('InstaCheck'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(_tabNames.length, (index) {
              return Expanded(
                child: TextButton(
                  onPressed: () => _switchTab(index),
                  style: TextButton.styleFrom(
                    backgroundColor: _currentTab == index ? Theme.of(context).primaryColor.withOpacity(0.1) : Colors.grey[100],
                    foregroundColor: _currentTab == index ? Theme.of(context).primaryColor : Colors.grey[600],
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  child: Text(_tabNames[index]),
                ),
              );
            }),
          ),
          Expanded(
            child: _buildTabContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildTabContent() {
    switch (_currentTab) {
      case 0: // File Input
        return _buildFileTab();
      case 1: // Text Input
        return _buildTextTab();
      case 2: // Convert
        return _buildConvertTab();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildFileTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton.icon(
            onPressed: _pickFileForProcessing,
            icon: const Icon(Icons.attach_file),
            label: Text(_selectedFile?.name ?? 'Pick File'),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _isProcessing ? null : _startProcessingFromFile,
            child: const Text('Start Processing'),
          ),
          if (_isProcessing) ..._buildProcessingUI(),
        ],
      ),
    );
  }

  Widget _buildTextTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _textController,
            maxLines: 10,
            decoration: const InputDecoration(
              labelText: 'Enter usernames (one per line)',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _isProcessing ? null : _startProcessingFromText,
            child: const Text('Start Processing'),
          ),
          if (_isProcessing) ..._buildProcessingUI(),
        ],
      ),
    );
  }

  Widget _buildConvertTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ElevatedButton.icon(
            onPressed: _pickJsonForConvert,
            icon: const Icon(Icons.attach_file),
            label: Text(_selectedJsonFile?.name ?? 'Pick JSON File'),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: _convertJsonToExcel,
            child: const Text('Convert to Excel'),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildProcessingUI() {
    final percentage = _usernames.isNotEmpty ? (_processedCount * 100 / _usernames.length).toInt() : 0;
    return [
      const SizedBox(height: 24),
      LinearProgressIndicator(value: percentage / 100),
      const SizedBox(height: 8),
      Text('Progress: $_processedCount/${_usernames.length} ($percentage%)', textAlign: TextAlign.center),
      const SizedBox(height: 16),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _buildStatCard('Total', _usernames.length.toString(), Colors.blue),
          _buildStatCard('Active', _activeCount.toString(), Colors.red),
          _buildStatCard('Available', _availableCount.toString(), Colors.green),
          _buildStatCard('Errors', _errorCount.toString(), Colors.orange),
        ],
      ),
      const SizedBox(height: 16),
      ElevatedButton(
        onPressed: _cancelProcessing,
        style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
        child: const Text('Cancel'),
      ),
      if (!_isProcessing && _activeAccounts.isNotEmpty)
        ElevatedButton(
          onPressed: _downloadResults,
          child: const Text('Download Active Accounts'),
        ),
      const SizedBox(height: 16),
      const Text('Results:', style: TextStyle(fontWeight: FontWeight.bold)),
      ListView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        itemCount: _results.length,
        itemBuilder: (context, index) {
          final item = _results[index];
          return Card(
            color: _getBackgroundColor(item.status),
            child: ListTile(
              leading: Icon(_getIcon(item.status), color: _getTextColor(item.status)),
              title: Text(item.message, style: TextStyle(color: _getTextColor(item.status))),
            ),
          );
        },
      ),
    ];
  }

  Widget _buildStatCard(String label, String value, Color color) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Text(value, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }

  IconData _getIcon(String status) {
    switch (status) {
      case 'ACTIVE':
        return Icons.cancel;
      case 'AVAILABLE':
        return Icons.check_circle;
      case 'ERROR':
        return Icons.error;
      default:
        return Icons.info;
    }
  }

  Color _getBackgroundColor(String status) {
    switch (status) {
      case 'ACTIVE':
        return const Color(0xFFFECACA);
      case 'AVAILABLE':
        return const Color(0xFFD1FAE5);
      case 'ERROR':
        return const Color(0xFFFEF3C7);
      default:
        return const Color(0xFFF9FAFB);
    }
  }

  Color _getTextColor(String status) {
    switch (status) {
      case 'ACTIVE':
        return const Color(0xFFDC2626);
      case 'AVAILABLE':
        return const Color(0xFF059669);
      case 'ERROR':
        return const Color(0xFFD97706);
      default:
        return const Color(0xFF6B7280);
    }
  }
}

class ResultItem {
  final String status;
  final String message;

  ResultItem(this.status, this.message);
}