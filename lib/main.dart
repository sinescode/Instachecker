import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:excel/excel.dart' as excel;

void main() {
  runApp(const InstagramUsernameChecker());
}

class InstagramUsernameChecker extends StatelessWidget {
  const InstagramUsernameChecker({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Instagram Username Checker',
      theme: ThemeData(
        primarySwatch: Colors.indigo,
        fontFamily: 'Roboto',
      ),
      home: const HomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with TickersProviderStateMixin {
  late TabController _tabController;
  final List<String> _results = [];
  bool _isProcessing = false;
  bool _isCancelled = false;
  int _processedCount = 0;
  int _activeCount = 0;
  int _availableCount = 0;
  int _errorCount = 0;
  int _totalCount = 0;
  final List<Map<String, dynamic>> _activeAccounts = [];
  final TextEditingController _textController = TextEditingController();
  File? _pickedFile;
  File? _jsonFile;
  String _inputFileName = "usernames"; // Default name for text input
  
  // Configuration
  static const int _maxRetries = 10;
  static const int _initialDelay = 1;
  static const int _maxDelay = 60;
  static const int _concurrentLimit = 5;
  static const Map<String, String> _headers = {
    "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0 Safari/537.36",
    "x-ig-app-id": "936619743392459",
    "Accept": "*/*",
    "Accept-Language": "en-US,en;q=0.9",
    "Referer": "https://www.instagram.com/",
    "Origin": "https://www.instagram.com",
    "Sec-Fetch-Site": "same-origin",
  };

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'txt'],
    );
    if (result != null) {
      setState(() {
        _pickedFile = File(result.files.single.path!);
        // Extract filename without extension
        String path = _pickedFile!.path;
        String fileName = path.split('/').last;
        _inputFileName = fileName.split('.').first;
      });
    }
  }

  Future<void> _pickJsonFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );
    if (result != null) {
      setState(() {
        _jsonFile = File(result.files.single.path!);
      });
    }
  }

  Future<void> _uploadFile() async {
    if (_pickedFile == null) return;
    
    final content = await _pickedFile!.readAsString();
    List<String> usernames = [];
    
    if (_pickedFile!.path.endsWith('.json')) {
      final List<dynamic> data = jsonDecode(content);
      for (var entry in data) {
        if (entry['username'] != null) {
          usernames.add(entry['username']);
        }
      }
    } else {
      usernames = content.split('\n').where((line) => line.trim().isNotEmpty).toList();
    }
    
    _startProcessing(usernames);
  }

  Future<void> _uploadText() async {
    final text = _textController.text;
    if (text.trim().isEmpty) return;
    
    // For text input, use default filename
    setState(() {
      _inputFileName = "usernames";
    });
    
    final usernames = text.split('\n').where((line) => line.trim().isNotEmpty).toList();
    _startProcessing(usernames);
  }

  Future<void> _startProcessing(List<String> usernames) async {
    setState(() {
      _isProcessing = true;
      _isCancelled = false;
      _processedCount = 0;
      _activeCount = 0;
      _availableCount = 0;
      _errorCount = 0;
      _totalCount = usernames.length;
      _results.clear();
      _activeAccounts.clear();
    });

    // Create a semaphore to limit concurrent requests
    final semaphore = Semaphore(_concurrentLimit);
    
    // Process all usernames
    final futures = usernames.map((username) => _checkUsername(username, semaphore));
    final results = await Future.wait(futures);
    
    if (!_isCancelled) {
      setState(() {
        _isProcessing = false;
      });
      
      // Save active accounts to file
      await _saveResults();
    }
  }

  Future<Map<String, dynamic>> _checkUsername(String username, Semaphore semaphore) async {
    if (_isCancelled) return {'status': 'CANCELLED', 'message': 'Processing cancelled'};
    
    final url = Uri.parse('https://i.instagram.com/api/v1/users/web_profile_info/?username=$username');
    int retryCount = 0;
    double delay = _initialDelay.toDouble();
    
    while (retryCount < _maxRetries && !_isCancelled) {
      await semaphore.acquire();
      
      try {
        final response = await http.get(url, headers: _headers).timeout(const Duration(seconds: 30));
        
        semaphore.release();
        
        if (response.statusCode == 404) {
          _updateCounts('AVAILABLE', username);
          return {'status': 'AVAILABLE', 'message': '[AVAILABLE] $username'};
        } else if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['data']?['user'] != null) {
            _updateCounts('ACTIVE', username);
            return {'status': 'ACTIVE', 'message': '[ACTIVE] $username'};
          } else {
            _updateCounts('AVAILABLE', username);
            return {'status': 'AVAILABLE', 'message': '[AVAILABLE] $username'};
          }
        } else {
          // Exponential backoff with jitter
          delay = min(_maxDelay.toDouble(), delay * 2 + Random().nextDouble());
          retryCount++;
          await Future.delayed(Duration(seconds: delay.toInt()));
        }
      } catch (e) {
        semaphore.release();
        // Exponential backoff with jitter
        delay = min(_maxDelay.toDouble(), delay * 2 + Random().nextDouble());
        retryCount++;
        await Future.delayed(Duration(seconds: delay.toInt()));
      }
    }
    
    if (_isCancelled) return {'status': 'CANCELLED', 'message': 'Processing cancelled'};
    
    _updateCounts('ERROR', username);
    return {'status': 'ERROR', 'message': '[ERROR] $username - Max retries exceeded'};
  }

  void _updateCounts(String status, String username) {
    if (_isCancelled) return;
    
    setState(() {
      _processedCount++;
      
      switch (status) {
        case 'ACTIVE':
          _activeCount++;
          _activeAccounts.add({'username': username});
          break;
        case 'AVAILABLE':
          _availableCount++;
          break;
        case 'ERROR':
          _errorCount++;
          break;
      }
      
      _results.add('[${status.toUpperCase()}] $username');
    });
  }

  Future<void> _saveResults() async {
    if (_activeAccounts.isEmpty) return;
    
    final directory = await getApplicationDocumentsDirectory();
    // File naming logic: final_{name}.json
    final fileName = "final_$_inputFileName.json";
    final file = File('${directory.path}/$fileName');
    
    await file.writeAsString(jsonEncode(_activeAccounts));
    
    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Active accounts saved to ${file.path}'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _downloadResults() async {
    if (_activeAccounts.isEmpty) return;
    
    final directory = await getApplicationDocumentsDirectory();
    // File naming logic: final_{name}.json
    final fileName = "final_$_inputFileName.json";
    final file = File('${directory.path}/$fileName');
    
    await file.writeAsString(jsonEncode(_activeAccounts));
    
    // Share the file
    await Share.shareFiles([file.path], text: 'Active Instagram Accounts');
  }

  Future<void> _convertJsonToExcel() async {
    if (_jsonFile == null) return;
    
    try {
      final content = await _jsonFile!.readAsString();
      final List<dynamic> data = jsonDecode(content);
      
      // Create Excel workbook
      final excel.Workbook workbook = excel.Workbook();
      final excel.Worksheet sheet = workbook.worksheets[0];
      
      // Add headers
      sheet.cell(excel.CellIndex.indexByString('A1')).value = 'Username';
      sheet.cell(excel.CellIndex.indexByString('B1')).value = 'Password';
      sheet.cell(excel.CellIndex.indexByString('C1')).value = 'Authcode';
      sheet.cell(excel.CellIndex.indexByString('D1')).value = 'Email';
      
      // Add data
      for (int i = 0; i < data.length; i++) {
        final item = data[i];
        final rowIndex = i + 2; // Start from row 2 (after headers)
        
        sheet.cell(excel.CellIndex.indexByString('A$rowIndex')).value = item['username'] ?? '';
        sheet.cell(excel.CellIndex.indexByString('B$rowIndex')).value = item['password'] ?? '';
        sheet.cell(excel.CellIndex.indexByString('C$rowIndex')).value = item['auth_code'] ?? '';
        sheet.cell(excel.CellIndex.indexByString('D$rowIndex')).value = item['email'] ?? '';
      }
      
      // Save file
      final directory = await getApplicationDocumentsDirectory();
      // File naming logic: {name}.xlsx (same name as input file but with .xlsx extension)
      String path = _jsonFile!.path;
      String baseName = path.split('/').last.split('.').first;
      final fileName = "$baseName.xlsx";
      final file = File('${directory.path}/$fileName');
      
      // Write the file
      final List<int> bytes = workbook.save();
      workbook.dispose();
      
      await file.writeAsBytes(bytes);
      
      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Excel file saved to ${file.path}'),
          backgroundColor: Colors.green,
        ),
      );
      
      // Share the file
      await Share.shareFiles([file.path], text: 'Converted Excel File');
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error converting file: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _cancelProcessing() {
    setState(() {
      _isCancelled = true;
      _isProcessing = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      appBar: AppBar(
        title: Row(
          children: const [
            Icon(Icons.camera_alt, color: Colors.white),
            SizedBox(width: 8),
            Text('Instagram Username Checker'),
          ],
        ),
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Upload File'),
            Tab(text: 'Enter Text'),
            Tab(text: 'Convert Excel'),
          ],
          indicatorColor: Colors.white,
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildFileTab(),
          _buildTextTab(),
          _buildExcelTab(),
        ],
      ),
    );
  }

  Widget _buildFileTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.file_upload, color: Colors.indigo),
                      SizedBox(width: 8),
                      Text(
                        'Upload a file',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'JSON or TXT — one username per line (or an array in JSON).',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _pickFile,
                    icon: const Icon(Icons.folder_open),
                    label: Text(_pickedFile == null ? 'Select File' : _pickedFile!.path.split('/').last),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _uploadFile,
                    icon: const Icon(Icons.search),
                    label: const Text('Start Checking'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[600],
                      minimumSize: const Size(double.infinity, 50),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _buildProgressSection(),
          const SizedBox(height: 20),
          _buildResultsSection(),
        ],
      ),
    );
  }

  Widget _buildTextTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.keyboard, color: Colors.indigo),
                      SizedBox(width: 8),
                      Text(
                        'Enter Usernames',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'One username per line.',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _textController,
                    maxLines: 6,
                    decoration: InputDecoration(
                      hintText: 'user1\nuser2\n...',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _isProcessing ? null : _uploadText,
                    icon: const Icon(Icons.search),
                    label: const Text('Start Checking'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[600],
                      minimumSize: const Size(double.infinity, 50),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          _buildProgressSection(),
          const SizedBox(height: 20),
          _buildResultsSection(),
        ],
      ),
    );
  }

  Widget _buildExcelTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: const [
                      Icon(Icons.table_chart, color: Colors.indigo),
                      SizedBox(width: 8),
                      Text(
                        'Convert JSON to Excel',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Upload a JSON file to convert it to Excel format with proper column names.',
                    style: TextStyle(color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _pickJsonFile,
                    icon: const Icon(Icons.folder_open),
                    label: Text(_jsonFile == null ? 'Select JSON File' : _jsonFile!.path.split('/').last),
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                    ),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: _jsonFile == null ? null : _convertJsonToExcel,
                    icon: const Icon(Icons.file_download),
                    label: const Text('Convert to Excel'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[600],
                      minimumSize: const Size(double.infinity, 50),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildProgressSection() {
    if (!_isProcessing && _processedCount == 0) return const SizedBox();
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.bar_chart, color: Colors.indigo),
                SizedBox(width: 8),
                Text(
                  'Progress',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: _totalCount > 0 ? _processedCount / _totalCount : 0,
              backgroundColor: Colors.grey[200],
              valueColor: AlwaysStoppedAnimation<Color>(Colors.green[600]!),
            ),
            const SizedBox(height: 8),
            Text(
              'Processed: $_processedCount/$_totalCount (${_totalCount > 0 ? ((_processedCount / _totalCount) * 100).toStringAsFixed(0) : 0}%)',
              style: const TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard('Active', _activeCount, Colors.red[50]!, Colors.red[600]!, Icons.person),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatCard('Available', _availableCount, Colors.green[50]!, Colors.green[700]!, Icons.person_add),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _buildStatCard('Error', _errorCount, Colors.yellow[50]!, Colors.yellow[700]!, Icons.warning),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildStatCard('Total', _totalCount, Colors.grey[50]!, Colors.grey[700]!, Icons.format_list_numbered),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isProcessing ? _cancelProcessing : null,
                    icon: const Icon(Icons.cancel),
                    label: const Text('Cancel'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red[600],
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _processedCount > 0 && !_isProcessing ? _downloadResults : null,
                    icon: const Icon(Icons.download),
                    label: const Text('Download'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green[600],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String title, int value, Color bgColor, Color textColor, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: textColor.withOpacity(0.2)),
      ),
      child: Column(
        children: [
          Text(
            value.toString(),
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: textColor,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 14, color: textColor),
              const SizedBox(width: 4),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  color: textColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResultsSection() {
    if (_results.isEmpty) return const SizedBox();
    
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: const [
                Icon(Icons.list_alt, color: Colors.indigo),
                SizedBox(width: 8),
                Text(
                  'Results',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 300,
              child: ListView.builder(
                itemCount: _results.length,
                itemBuilder: (context, index) {
                  final result = _results[index];
                  Color textColor = Colors.black;
                  
                  if (result.startsWith('[ACTIVE]')) {
                    textColor = Colors.red[700]!;
                  } else if (result.startsWith('[AVAILABLE]')) {
                    textColor = Colors.green[700]!;
                  } else if (result.startsWith('[ERROR]')) {
                    textColor = Colors.yellow[700]!;
                  }
                  
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4.0),
                    child: Text(
                      result,
                      style: TextStyle(color: textColor),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class Semaphore {
  final int maxConcurrent;
  int _current = 0;
  final List<Completer<void>> _waiters = [];
  
  Semaphore(this.maxConcurrent);
  
  Future<void> acquire() async {
    if (_current < maxConcurrent) {
      _current++;
      return;
    }
    
    final completer = Completer<void>();
    _waiters.add(completer);
    await completer.future;
  }
  
  void release() {
    if (_waiters.isNotEmpty) {
      final completer = _waiters.removeAt(0);
      completer.complete();
    } else {
      _current--;
    }
  }
}