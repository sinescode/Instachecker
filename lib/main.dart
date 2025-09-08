import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:open_file/open_file.dart';
import 'package:excel/excel.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'InstaCheck',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with SingleTickerProviderStateMixin {
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
        title: Text('InstaCheck'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: 'File Check'),
            Tab(text: 'Text Check'),
            Tab(text: 'JSON to Excel'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          FileCheckTab(),
          TextCheckTab(),
          JsonToExcelTab(),
        ],
      ),
    );
  }
}

class FileCheckTab extends StatefulWidget {
  @override
  _FileCheckTabState createState() => _FileCheckTabState();
}

class _FileCheckTabState extends State<FileCheckTab> {
  PlatformFile? _selectedFile;
  bool _isProcessing = false;
  bool _isCancelled = false;
  int _processedCount = 0;
  int _activeCount = 0;
  int _availableCount = 0;
  int _errorCount = 0;
  int _cancelledCount = 0;
  int _totalCount = 0;
  List<ResultItem> _results = [];
  List<Map<String, dynamic>> _activeAccounts = [];
  String _originalFileName = "";
  final _scrollController = ScrollController();
  final _semaphore = StreamController<bool>.broadcast();
  final _maxConcurrent = 5;

  final Map<String, String> _headers = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0 Safari/537.36",
    "x-ig-app-id": "936619743392459",
    "Accept": "*/*",
    "Accept-Language": "en-US,en;q=0.9",
    "Referer": "https://www.instagram.com/",
    "Origin": "https://www.instagram.com",
    "Sec-Fetch-Site": "same-origin"
  };

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < _maxConcurrent; i++) {
      _semaphore.sink.add(true);
    }
  }

  @override
  void dispose() {
    _semaphore.close();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'txt'],
    );

    if (result != null) {
      setState(() {
        _selectedFile = result.files.first;
        _originalFileName = _selectedFile!.name.split('.').first;
      });
    }
  }

  Future<void> _startProcessing() async {
    if (_selectedFile == null) {
      _showError('Please select a file first');
      return;
    }

    List<String> usernames = [];
    Map<String, dynamic> accountData = {};

    try {
      String content = String.fromCharCodes(_selectedFile!.bytes!);
      
      if (_selectedFile!.extension == 'txt') {
        usernames = content.split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
        
        for (String username in usernames) {
          accountData[username] = {'username': username};
        }
      } else if (_selectedFile!.extension == 'json') {
        List<dynamic> jsonArray = json.decode(content);
        for (var item in jsonArray) {
          String username = item['username'];
          usernames.add(username);
          accountData[username] = item;
        }
      } else {
        _showError('File must be .json or .txt format');
        return;
      }
    } catch (e) {
      _showError('Error reading file: $e');
      return;
    }

    if (usernames.isEmpty) {
      _showError('No valid usernames found');
      return;
    }

    _resetStats();
    setState(() {
      _isProcessing = true;
      _isCancelled = false;
      _totalCount = usernames.length;
    });

    _processUsernames(usernames, accountData);
  }

  Future<void> _processUsernames(List<String> usernames, Map<String, dynamic> accountData) async {
    List<Future> futures = [];
    
    for (String username in usernames) {
      if (_isCancelled) break;
      
      futures.add(_processUsername(username, accountData));
    }
    
    await Future.wait(futures);
    
    setState(() {
      _isProcessing = false;
    });
    
    _showSuccess('Processing completed! Found ${_activeAccounts.length} active accounts.');
  }

  Future<void> _processUsername(String username, Map<String, dynamic> accountData) async {
    // Wait for a semaphore slot
    await _semaphore.stream.firstWhere((available) => available);
    _semaphore.sink.add(false); // Take a slot
    
    try {
      const maxRetries = 10;
      const initialDelay = 1000;
      const maxDelay = 60000;
      int retryCount = 0;
      int delayMs = initialDelay;
      final random = Random();
      
      while (retryCount < maxRetries && !_isCancelled) {
        try {
          final url = 'https://i.instagram.com/api/v1/users/web_profile_info/?username=$username';
          final response = await http.get(Uri.parse(url), headers: _headers);
          
          if (response.statusCode == 404) {
            _updateResult('AVAILABLE', '$username - Available', username);
            return;
          } else if (response.statusCode == 200) {
            final jsonData = json.decode(response.body);
            final status = (jsonData['data'] != null && jsonData['data']['user'] != null) 
                ? 'ACTIVE' 
                : 'AVAILABLE';
            
            _updateResult(status, '$username - $status', username);
            
            if (status == 'ACTIVE') {
              setState(() {
                _activeAccounts.add(accountData[username]!);
              });
            }
            return;
          } else {
            retryCount++;
            _updateStatus('Retry $retryCount/$maxRetries for $username (Status: ${response.statusCode})', username);
          }
        } catch (e) {
          retryCount++;
          String errorMsg = e.toString();
          if (errorMsg.length > 30) errorMsg = errorMsg.substring(0, 30) + '...';
          _updateStatus('Retry $retryCount/$maxRetries for $username ($errorMsg)', username);
        }
        
        await Future.delayed(Duration(milliseconds: delayMs));
        delayMs = min(maxDelay, (delayMs * 2 + random.nextInt(1000)));
      }
      
      if (!_isCancelled) {
        _updateResult('ERROR', '$username - Error (Max retries exceeded)', username);
      } else {
        _updateResult('CANCELLED', '$username - Cancelled', username);
      }
    } finally {
      _semaphore.sink.add(true); // Release the slot
    }
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
      
      // Auto-scroll to top when new results arrive
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  void _updateStatus(String message, String username) {
    setState(() {
      _results.insert(0, ResultItem('INFO', message));
    });
  }

  void _resetStats() {
    setState(() {
      _processedCount = 0;
      _activeCount = 0;
      _availableCount = 0;
      _errorCount = 0;
      _cancelledCount = 0;
      _activeAccounts.clear();
      _results.clear();
    });
  }

  void _cancelProcessing() {
    setState(() {
      _isCancelled = true;
      _isProcessing = false;
    });
    _updateStatus('Processing cancelled by user', '');
    _showInfo('Processing cancelled');
  }

  Future<void> _downloadResults() async {
    if (_activeAccounts.isEmpty) {
      _showError('No active accounts to download');
      return;
    }
    
    try {
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Results',
        fileName: 'final_${_originalFileName}_${_getTimestamp()}.json',
        allowedExtensions: ['json'],
      );
      
      if (outputFile != null) {
        File file = File(outputFile);
        await file.writeAsString(json.encode(_activeAccounts));
        _showSuccess('Results saved successfully! (${_activeAccounts.length} active accounts)');
      }
    } catch (e) {
      _showError('Failed to save file: $e');
    }
  }

  String _getTimestamp() {
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
           '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      )
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      )
    );
  }

  void _showInfo(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!_isProcessing) ...[
            ElevatedButton(
              onPressed: _pickFile,
              child: Text(_selectedFile != null ? _selectedFile!.name : 'Select File'),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _startProcessing,
              child: Text('Start Processing'),
            ),
          ],
          if (_isProcessing) ...[
            LinearProgressIndicator(
              value: _totalCount > 0 ? _processedCount / _totalCount : 0,
            ),
            SizedBox(height: 8),
            Text('Progress: $_processedCount/$_totalCount (${_totalCount > 0 ? (_processedCount * 100 / _totalCount).round() : 0}%)'),
            SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatCard('Active', _activeCount, Colors.green),
                _buildStatCard('Available', _availableCount, Colors.blue),
                _buildStatCard('Error', _errorCount, Colors.orange),
                _buildStatCard('Total', _totalCount, Colors.grey),
              ],
            ),
            SizedBox(height: 8),
            ElevatedButton(
              onPressed: _cancelProcessing,
              child: Text('Cancel Processing'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            ),
          ],
          if (_activeAccounts.isNotEmpty && !_isProcessing) 
            ElevatedButton(
              onPressed: _downloadResults,
              child: Text('Download Results'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            ),
          SizedBox(height: 16),
          Text('Results:', style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(
            child: ListView.builder(
              controller: _scrollController,
              reverse: true,
              itemCount: _results.length,
              itemBuilder: (context, index) {
                final item = _results[index];
                return _buildResultItem(item);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, int count, Color color) {
    return Column(
      children: [
        Text(title, style: TextStyle(fontSize: 12)),
        SizedBox(height: 4),
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('$count', style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        ),
      ],
    );
  }

  Widget _buildResultItem(ResultItem item) {
    Color bgColor;
    Color textColor;
    IconData icon;
    Color indicatorColor;

    switch (item.status) {
      case 'ACTIVE':
        bgColor = Color(0xFFFECACA);
        textColor = Color(0xFFDC2626);
        icon = Icons.error;
        indicatorColor = Color(0xFFDC2626);
        break;
      case 'AVAILABLE':
        bgColor = Color(0xFFD1FAE5);
        textColor = Color(0xFF059669);
        icon = Icons.check_circle;
        indicatorColor = Color(0xFF059669);
        break;
      case 'ERROR':
        bgColor = Color(0xFFFEF3C7);
        textColor = Color(0xFFD97706);
        icon = Icons.warning;
        indicatorColor = Color(0xFFD97706);
        break;
      default:
        bgColor = Color(0xFFF9FAFB);
        textColor = Color(0xFF6B7280);
        icon = Icons.info;
        indicatorColor = Color(0xFF6B7280);
    }

    return Container(
      margin: EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 48,
            color: indicatorColor,
          ),
          SizedBox(width: 8),
          Icon(icon, color: textColor),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              item.message,
              style: TextStyle(color: textColor),
            ),
          ),
        ],
      ),
    );
  }
}

class TextCheckTab extends StatefulWidget {
  @override
  _TextCheckTabState createState() => _TextCheckTabState();
}

class _TextCheckTabState extends State<TextCheckTab> {
  final _textController = TextEditingController();
  bool _isProcessing = false;
  bool _isCancelled = false;
  int _processedCount = 0;
  int _activeCount = 0;
  int _availableCount = 0;
  int _errorCount = 0;
  int _cancelledCount = 0;
  int _totalCount = 0;
  List<ResultItem> _results = [];
  List<Map<String, dynamic>> _activeAccounts = [];
  final _scrollController = ScrollController();
  final _semaphore = StreamController<bool>.broadcast();
  final _maxConcurrent = 5;

  final Map<String, String> _headers = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0 Safari/537.36",
    "x-ig-app-id": "936619743392459",
    "Accept": "*/*",
    "Accept-Language": "en-US,en;q=0.9",
    "Referer": "https://www.instagram.com/",
    "Origin": "https://www.instagram.com",
    "Sec-Fetch-Site": "same-origin"
  };

  @override
  void initState() {
    super.initState();
    for (int i = 0; i < _maxConcurrent; i++) {
      _semaphore.sink.add(true);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _semaphore.close();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _startProcessing() async {
    String text = _textController.text.trim();
    if (text.isEmpty) {
      _showError('Please enter at least one username');
      return;
    }

    List<String> usernames = text.split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
    
    Map<String, dynamic> accountData = {};
    for (String username in usernames) {
      accountData[username] = {'username': username};
    }

    if (usernames.isEmpty) {
      _showError('No valid usernames found');
      return;
    }

    _resetStats();
    setState(() {
      _isProcessing = true;
      _isCancelled = false;
      _totalCount = usernames.length;
    });

    _processUsernames(usernames, accountData);
  }

  Future<void> _processUsernames(List<String> usernames, Map<String, dynamic> accountData) async {
    List<Future> futures = [];
    
    for (String username in usernames) {
      if (_isCancelled) break;
      
      futures.add(_processUsername(username, accountData));
    }
    
    await Future.wait(futures);
    
    setState(() {
      _isProcessing = false;
    });
    
    _showSuccess('Processing completed! Found ${_activeAccounts.length} active accounts.');
  }

  Future<void> _processUsername(String username, Map<String, dynamic> accountData) async {
    // Wait for a semaphore slot
    await _semaphore.stream.firstWhere((available) => available);
    _semaphore.sink.add(false); // Take a slot
    
    try {
      const maxRetries = 10;
      const initialDelay = 1000;
      const maxDelay = 60000;
      int retryCount = 0;
      int delayMs = initialDelay;
      final random = Random();
      
      while (retryCount < maxRetries && !_isCancelled) {
        try {
          final url = 'https://i.instagram.com/api/v1/users/web_profile_info/?username=$username';
          final response = await http.get(Uri.parse(url), headers: _headers);
          
          if (response.statusCode == 404) {
            _updateResult('AVAILABLE', '$username - Available', username);
            return;
          } else if (response.statusCode == 200) {
            final jsonData = json.decode(response.body);
            final status = (jsonData['data'] != null && jsonData['data']['user'] != null) 
                ? 'ACTIVE' 
                : 'AVAILABLE';
            
            _updateResult(status, '$username - $status', username);
            
            if (status == 'ACTIVE') {
              setState(() {
                _activeAccounts.add(accountData[username]!);
              });
            }
            return;
          } else {
            retryCount++;
            _updateStatus('Retry $retryCount/$maxRetries for $username (Status: ${response.statusCode})', username);
          }
        } catch (e) {
          retryCount++;
          String errorMsg = e.toString();
          if (errorMsg.length > 30) errorMsg = errorMsg.substring(0, 30) + '...';
          _updateStatus('Retry $retryCount/$maxRetries for $username ($errorMsg)', username);
        }
        
        await Future.delayed(Duration(milliseconds: delayMs));
        delayMs = min(maxDelay, (delayMs * 2 + random.nextInt(1000)));
      }
      
      if (!_isCancelled) {
        _updateResult('ERROR', '$username - Error (Max retries exceeded)', username);
      } else {
        _updateResult('CANCELLED', '$username - Cancelled', username);
      }
    } finally {
      _semaphore.sink.add(true); // Release the slot
    }
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
      
      // Auto-scroll to top when new results arrive
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scrollController.hasClients) {
          _scrollController.animateTo(
            0,
            duration: Duration(milliseconds: 300),
            curve: Curves.easeOut,
          );
        }
      });
    });
  }

  void _updateStatus(String message, String username) {
    setState(() {
      _results.insert(0, ResultItem('INFO', message));
    });
  }

  void _resetStats() {
    setState(() {
      _processedCount = 0;
      _activeCount = 0;
      _availableCount = 0;
      _errorCount = 0;
      _cancelledCount = 0;
      _activeAccounts.clear();
      _results.clear();
    });
  }

  void _cancelProcessing() {
    setState(() {
      _isCancelled = true;
      _isProcessing = false;
    });
    _updateStatus('Processing cancelled by user', '');
    _showInfo('Processing cancelled');
  }

  Future<void> _downloadResults() async {
    if (_activeAccounts.isEmpty) {
      _showError('No active accounts to download');
      return;
    }
    
    try {
      String? outputFile = await FilePicker.platform.saveFile(
        dialogTitle: 'Save Results',
        fileName: 'final_manual_input_${_getTimestamp()}.json',
        allowedExtensions: ['json'],
      );
      
      if (outputFile != null) {
        File file = File(outputFile);
        await file.writeAsString(json.encode(_activeAccounts));
        _showSuccess('Results saved successfully! (${_activeAccounts.length} active accounts)');
      }
    } catch (e) {
      _showError('Failed to save file: $e');
    }
  }

  String _getTimestamp() {
    final now = DateTime.now();
    return '${now.year}${now.month.toString().padLeft(2, '0')}${now.day.toString().padLeft(2, '0')}_'
           '${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}${now.second.toString().padLeft(2, '0')}';
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      )
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      )
    );
  }

  void _showInfo(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: TextField(
              controller: _textController,
              decoration: InputDecoration(
                labelText: 'Enter usernames (one per line)',
                border: OutlineInputBorder(),
              ),
              maxLines: null,
              expands: true,
              textAlignVertical: TextAlignVertical.top,
            ),
          ),
          SizedBox(height: 16),
          if (!_isProcessing)
            ElevatedButton(
              onPressed: _startProcessing,
              child: Text('Start Processing'),
            ),
          if (_isProcessing) ...[
            LinearProgressIndicator(
              value: _totalCount > 0 ? _processedCount / _totalCount : 0,
            ),
            SizedBox(height: 8),
            Text('Progress: $_processedCount/$_totalCount (${_totalCount > 0 ? (_processedCount * 100 / _totalCount).round() : 0}%)'),
            SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatCard('Active', _activeCount, Colors.green),
                _buildStatCard('Available', _availableCount, Colors.blue),
                _buildStatCard('Error', _errorCount, Colors.orange),
                _buildStatCard('Total', _totalCount, Colors.grey),
              ],
            ),
            SizedBox(height: 8),
            ElevatedButton(
              onPressed: _cancelProcessing,
              child: Text('Cancel Processing'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            ),
          ],
          if (_activeAccounts.isNotEmpty && !_isProcessing) 
            ElevatedButton(
              onPressed: _downloadResults,
              child: Text('Download Results'),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            ),
          SizedBox(height: 16),
          Text('Results:', style: TextStyle(fontWeight: FontWeight.bold)),
          Expanded(
            flex: 2,
            child: ListView.builder(
              controller: _scrollController,
              reverse: true,
              itemCount: _results.length,
              itemBuilder: (context, index) {
                final item = _results[index];
                return _buildResultItem(item);
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, int count, Color color) {
    return Column(
      children: [
        Text(title, style: TextStyle(fontSize: 12)),
        SizedBox(height: 4),
        Container(
          padding: EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text('$count', style: TextStyle(fontWeight: FontWeight.bold, color: color)),
        ),
      ],
    );
  }

  Widget _buildResultItem(ResultItem item) {
    Color bgColor;
    Color textColor;
    IconData icon;
    Color indicatorColor;

    switch (item.status) {
      case 'ACTIVE':
        bgColor = Color(0xFFFECACA);
        textColor = Color(0xFFDC2626);
        icon = Icons.error;
        indicatorColor = Color(0xFFDC2626);
        break;
      case 'AVAILABLE':
        bgColor = Color(0xFFD1FAE5);
        textColor = Color(0xFF059669);
        icon = Icons.check_circle;
        indicatorColor = Color(0xFF059669);
        break;
      case 'ERROR':
        bgColor = Color(0xFFFEF3C7);
        textColor = Color(0xFFD97706);
        icon = Icons.warning;
        indicatorColor = Color(0xFFD97706);
        break;
      default:
        bgColor = Color(0xFFF9FAFB);
        textColor = Color(0xFF6B7280);
        icon = Icons.info;
        indicatorColor = Color(0xFF6B7280);
    }

    return Container(
      margin: EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Container(
            width: 4,
            height: 48,
            color: indicatorColor,
          ),
          SizedBox(width: 8),
          Icon(icon, color: textColor),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              item.message,
              style: TextStyle(color: textColor),
            ),
          ),
        ],
      ),
    );
  }
}

class JsonToExcelTab extends StatefulWidget {
  @override
  _JsonToExcelTabState createState() => _JsonToExcelTabState();
}

class _JsonToExcelTabState extends State<JsonToExcelTab> {
  PlatformFile? _selectedFile;
  bool _isConverting = false;

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result != null) {
      setState(() {
        _selectedFile = result.files.first;
      });
    }
  }

  Future<void> _convertToExcel() async {
    if (_selectedFile == null) {
      _showError('Please select a JSON file first');
      return;
    }

    setState(() {
      _isConverting = true;
    });

    try {
      String content = String.fromCharCodes(_selectedFile!.bytes!);
      List<dynamic> jsonData = json.decode(content);
      
      // Create Excel workbook
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];
      
      // Add headers with proper CellValue objects
      sheet.appendRow([
        TextCellValue('Username'),
        TextCellValue('Password'),
        TextCellValue('Authcode'),
        TextCellValue('Email')
      ]);
      
      // Add data with proper CellValue objects
      for (var item in jsonData) {
        sheet.appendRow([
          TextCellValue(item['username']?.toString() ?? ''),
          TextCellValue(item['password']?.toString() ?? ''),
          TextCellValue(item['auth_code']?.toString() ?? ''),
          TextCellValue(item['email']?.toString() ?? '')
        ]);
      }
      
      // Generate file bytes
      final fileBytes = excel.encode();
      
      if (fileBytes != null) {
        // Get the original file name without extension
        String originalName = _selectedFile!.name.split('.').first;
        
        // Save file
        String? outputFile = await FilePicker.platform.saveFile(
          dialogTitle: 'Save Excel File',
          fileName: '$originalName.xlsx',
          allowedExtensions: ['xlsx'],
        );
        
        if (outputFile != null) {
          File file = File(outputFile);
          await file.writeAsBytes(fileBytes);
          
          // Open the file
          OpenFile.open(outputFile);
          
          _showSuccess('✅ Converted: ${_selectedFile!.name} → $outputFile');
        }
      } else {
        _showError('Failed to create Excel file');
      }
    } catch (e) {
      _showError('Error converting file: $e');
    } finally {
      setState(() {
        _isConverting = false;
      });
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
      )
    );
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
      )
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Convert JSON files to Excel format with columns: Username, Password, Authcode, Email',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
          SizedBox(height: 32),
          ElevatedButton(
            onPressed: _pickFile,
            child: Text(_selectedFile != null ? _selectedFile!.name : 'Select JSON File'),
          ),
          SizedBox(height: 16),
          if (_isConverting)
            CircularProgressIndicator(),
          if (!_isConverting)
            ElevatedButton(
              onPressed: _convertToExcel,
              child: Text('Convert to Excel'),
            ),
        ],
      ),
    );
  }
}

class ResultItem {
  final String status;
  final String message;

  ResultItem(this.status, this.message);
}