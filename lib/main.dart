import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
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
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
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

class _HomePageState extends State<HomePage> with TickerProviderStateMixin {
  late TabController _tabController;
  final List<Map<String, String>> _results = [];
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
  String _inputFileName = "usernames";

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

    final semaphore = Semaphore(_concurrentLimit);
    final futures = usernames.map((username) => _checkUsername(username, semaphore));
    final results = await Future.wait(futures);

    if (!_isCancelled) {
      setState(() {
        _isProcessing = false;
      });
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
          return {'status': 'AVAILABLE', 'message': username};
        } else if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['data']?['user'] != null) {
            _updateCounts('ACTIVE', username);
            return {'status': 'ACTIVE', 'message': username};
          } else {
            _updateCounts('AVAILABLE', username);
            return {'status': 'AVAILABLE', 'message': username};
          }
        } else {
          delay = min(_maxDelay.toDouble(), delay * 2 + Random().nextDouble());
          retryCount++;
          await Future.delayed(Duration(seconds: delay.toInt()));
        }
      } catch (e) {
        semaphore.release();
        delay = min(_maxDelay.toDouble(), delay * 2 + Random().nextDouble());
        retryCount++;
        await Future.delayed(Duration(seconds: delay.toInt()));
      }
    }

    if (_isCancelled) return {'status': 'CANCELLED', 'message': 'Processing cancelled'};

    _updateCounts('ERROR', username);
    return {'status': 'ERROR', 'message': '$username - Max retries exceeded'};
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

      _results.add({'status': status, 'username': username});
    });
  }

  Future<void> _saveResults() async {
    if (_activeAccounts.isEmpty) return;

    final directory = await getApplicationDocumentsDirectory();
    final fileName = "final_$_inputFileName.json";
    final file = File('${directory.path}/$fileName');

    await file.writeAsString(jsonEncode(_activeAccounts));

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Active accounts saved to ${file.path}'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _downloadResults() async {
    if (_activeAccounts.isEmpty) return;

    var status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Storage permission is required to save files'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }

    try {
      Directory? downloadsDir = await getDownloadsDirectory();
      if (downloadsDir == null) {
        downloadsDir = await getExternalStorageDirectory();
      }
      if (downloadsDir == null) {
        downloadsDir = Directory('/storage/emulated/0/Download');
      }

      Directory saveDir = Directory('${downloadsDir.path}/insta_saver');
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }

      final fileName = "final_$_inputFileName.json";
      final file = File('${saveDir.path}/$fileName');

      await file.writeAsString(jsonEncode(_activeAccounts));

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Active accounts saved to ${file.path}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error saving file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _convertJsonToExcel() async {
    if (_jsonFile == null) return;

    var status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();
      if (!status.isGranted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Storage permission is required to save files'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }

    try {
      final content = await _jsonFile!.readAsString();
      final List<dynamic> data = jsonDecode(content);

      final excelFile = excel.Excel.createExcel();
      final sheetObject = excelFile['Sheet1'];

      sheetObject.cell(excel.CellIndex.indexByString('A1')).value = excel.TextCellValue('Username');
      sheetObject.cell(excel.CellIndex.indexByString('B1')).value = excel.TextCellValue('Password');
      sheetObject.cell(excel.CellIndex.indexByString('C1')).value = excel.TextCellValue('Authcode');
      sheetObject.cell(excel.CellIndex.indexByString('D1')).value = excel.TextCellValue('Email');

      for (int i = 0; i < data.length; i++) {
        final item = data[i];
        final rowIndex = i + 2;

        sheetObject.cell(excel.CellIndex.indexByString('A$rowIndex')).value = excel.TextCellValue(item['username']?.toString() ?? '');
        sheetObject.cell(excel.CellIndex.indexByString('B$rowIndex')).value = excel.TextCellValue(item['password']?.toString() ?? '');
        sheetObject.cell(excel.CellIndex.indexByString('C$rowIndex')).value = excel.TextCellValue(item['auth_code']?.toString() ?? '');
        sheetObject.cell(excel.CellIndex.indexByString('D$rowIndex')).value = excel.TextCellValue(item['email']?.toString() ?? '');
      }

      Directory? downloadsDir = await getDownloadsDirectory();
      if (downloadsDir == null) {
        downloadsDir = await getExternalStorageDirectory();
      }
      if (downloadsDir == null) {
        downloadsDir = Directory('/storage/emulated/0/Download');
      }

      Directory saveDir = Directory('${downloadsDir.path}/insta_saver');
      if (!await saveDir.exists()) {
        await saveDir.create(recursive: true);
      }

      String path = _jsonFile!.path;
      String baseName = path.split('/').last.split('.').first;
      final fileName = "$baseName.xlsx";
      final file = File('${saveDir.path}/$fileName');

      final List<int>? bytes = excelFile.save();
      if (bytes != null) {
        await file.writeAsBytes(bytes);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Excel file saved to ${file.path}'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error converting file: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
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
        title: const Row(
          children: [
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
                  const Row(
                    children: [
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
                      backgroundColor: Colors.indigo,
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
                  const Row(
                    children: [
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
                  const Row(
                    children: [
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
                      backgroundColor: Colors.indigo,
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
            const Row(
              children: [
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
                    label: const Text('Save to Device'),
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
        border: Border.all(
          color: textColor.withOpacity(0.2),
        ),
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

    final activeResults = _results.where((r) => r['status'] == 'ACTIVE').toList();
    final availableResults = _results.where((r) => r['status'] == 'AVAILABLE').toList();
    final errorResults = _results.where((r) => r['status'] == 'ERROR').toList();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
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
              height: 400,
              child: DefaultTabController(
                length: 3,
                child: Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: TabBar(
                        labelColor: Colors.white,
                        unselectedLabelColor: Colors.grey[600],
                        indicator: BoxDecoration(
                          borderRadius: BorderRadius.circular(6),
                          color: Colors.indigo,
                        ),
                        indicatorSize: TabBarIndicatorSize.tab,
                        tabs: [
                          Tab(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.person, size: 16),
                                const SizedBox(width: 4),
                                Text('Active (${activeResults.length})'),
                              ],
                            ),
                          ),
                          Tab(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.person_add, size: 16),
                                const SizedBox(width: 4),
                                Text('Available (${availableResults.length})'),
                              ],
                            ),
                          ),
                          Tab(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(Icons.warning, size: 16),
                                const SizedBox(width: 4),
                                Text('Error (${errorResults.length})'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _buildResultsList(activeResults, Colors.red[50]!, Colors.red[700]!, Icons.person),
                          _buildResultsList(availableResults, Colors.green[50]!, Colors.green[700]!, Icons.person_add),
                          _buildResultsList(errorResults, Colors.amber[50]!, Colors.amber[700]!, Icons.warning),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsList(List<Map<String, String>> results, Color bgColor, Color textColor, IconData icon) {
    if (results.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 8),
            Text(
              'No results yet',
              style: TextStyle(color: Colors.grey[600], fontSize: 16),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, index) {
        final result = results[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: textColor.withOpacity(0.2)),
          ),
          child: ListTile(
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: textColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Icon(icon, color: textColor, size: 20),
            ),
            title: Text(
              result['username'] ?? '',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
            subtitle: Text(
              _getStatusDisplayText(result['status'] ?? ''),
              style: TextStyle(
                color: textColor.withOpacity(0.8),
                fontSize: 12,
              ),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: textColor,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                result['status'] ?? '',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  String _getStatusDisplayText(String status) {
    switch (status) {
      case 'ACTIVE':
        return 'Username is taken';
      case 'AVAILABLE':
        return 'Username is available';
      case 'ERROR':
        return 'Failed to check';
      default:
        return '';
    }
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