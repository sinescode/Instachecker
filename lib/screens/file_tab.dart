// screens/file_tab.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:instachecker/services/instagram_service.dart';
import 'package:instachecker/widgets/result_item.dart';
import 'package:instachecker/widgets/progress_stats.dart';

class FileTab extends StatefulWidget {
  const FileTab({Key? key}) : super(key: key);

  @override
  _FileTabState createState() => _FileTabState();
}

class _FileTabState extends State<FileTab> {
  final InstagramService _instagramService = InstagramService();
  String? _filePath;
  String _fileName = 'No file selected';
  bool _isProcessing = false;
  List<Map<String, dynamic>> _results = [];
  int _processedCount = 0;
  int _activeCount = 0;
  int _availableCount = 0;
  int _errorCount = 0;

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json', 'txt'],
    );

    if (result != null) {
      setState(() {
        _filePath = result.files.single.path;
        _fileName = result.files.single.name;
      });
    }
  }

  Future<void> _startProcessing() async {
    if (_filePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a file first')),
      );
      return;
    }

    setState(() {
      _isProcessing = true;
      _results = [];
      _processedCount = 0;
      _activeCount = 0;
      _availableCount = 0;
      _errorCount = 0;
    });

    List<String> usernames = [];
    try {
      final file = File(_filePath!);
      final contents = await file.readAsString();
      
      if (_fileName.endsWith('.json')) {
        final data = jsonDecode(contents) as List;
        usernames = data.map((e) => e['username'].toString()).toList();
      } else {
        usernames = contents.split('\n').where((e) => e.trim().isNotEmpty).toList();
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error reading file: $e')),
      );
      setState(() => _isProcessing = false);
      return;
    }

    if (usernames.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No valid usernames found')),
      );
      setState(() => _isProcessing = false);
      return;
    }

    for (final username in usernames) {
      if (!mounted) return;
      
      final result = await _instagramService.checkUsername(username);
      setState(() {
        _results.add(result);
        _processedCount++;
        
        if (result['status'] == 'ACTIVE') {
          _activeCount++;
        } else if (result['status'] == 'AVAILABLE') {
          _availableCount++;
        } else {
          _errorCount++;
        }
      });
    }

    setState(() => _isProcessing = false);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Processing completed! Found $_activeCount active accounts.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Card(
            elevation: 4,
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select File',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _fileName,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      ElevatedButton(
                        onPressed: _pickFile,
                        child: const Text('Browse'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : _startProcessing,
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Start Processing'),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (_isProcessing) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text(
              'Processing: $_processedCount usernames...',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
          ],
          ProgressStats(
            activeCount: _activeCount,
            availableCount: _availableCount,
            errorCount: _errorCount,
            totalCount: _processedCount,
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.builder(
              itemCount: _results.length,
              itemBuilder: (context, index) {
                return ResultItem(result: _results[index]);
              },
            ),
          ),
        ],
      ),
    );
  }
}