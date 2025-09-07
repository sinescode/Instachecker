import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import '../services/file_service.dart';
import 'dart:io';

class JsonToExcelTab extends StatefulWidget {
  const JsonToExcelTab({super.key});

  @override
  State<JsonToExcelTab> createState() => _JsonToExcelTabState();
}

class _JsonToExcelTabState extends State<JsonToExcelTab> {
  String? _selectedJsonFile;
  bool _isConverting = false;
  List<String> _downloadedFiles = [];

  @override
  void initState() {
    super.initState();
    _loadDownloadedFiles();
  }

  Future<void> _loadDownloadedFiles() async {
    final files = await FileService.getDownloadedFiles();
    setState(() {
      _downloadedFiles = files;
    });
  }

  void _showSnackBar(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Future<void> _pickJsonFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result != null && result.files.single.path != null) {
        setState(() {
          _selectedJsonFile = result.files.single.path;
        });
      }
    } catch (e) {
      _showSnackBar('Error selecting file: ${e.toString()}', Colors.red);
    }
  }

  Future<void> _convertToExcel() async {
    if (_selectedJsonFile == null) {
      _showSnackBar('Please select a JSON file first', Colors.orange);
      return;
    }

    setState(() {
      _isConverting = true;
    });

    try {
      final excelPath = await FileService.convertJsonToExcel(_selectedJsonFile!);
      _showSnackBar('✅ Converted successfully!', Colors.green);
      
      // Share the file
      await FileService.shareFile(excelPath);
      
      // Refresh downloaded files list
      await _loadDownloadedFiles();
      
      setState(() {
        _selectedJsonFile = null;
      });
    } catch (e) {
      _showSnackBar('Error converting file: ${e.toString()}', Colors.red);
    } finally {
      setState(() {
        _isConverting = false;
      });
    }
  }

  Future<void> _shareFile(String filePath) async {
    try {
      await FileService.shareFile(filePath);
    } catch (e) {
      _showSnackBar('Error sharing file: ${e.toString()}', Colors.red);
    }
  }

  String _getFileName(String path) {
    return path.split('/').last;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
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
              Icon(Icons.table_chart, color: Colors.indigo[500], size: 24),
              const SizedBox(width: 8),
              const Text(
                'JSON to Excel Converter',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Convert JSON files to Excel format with Username, Password, Authcode, and Email columns.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 20),
          
          // File selection
          InkWell(
            onTap: _isConverting ? null : _pickJsonFile,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
                color: _isConverting ? Colors.grey[50] : Colors.white,
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.attach_file,
                    color: Colors.grey[600],
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _selectedJsonFile != null
                          ? _getFileName(_selectedJsonFile!)
                          : 'Choose JSON file...',
                      style: TextStyle(
                        fontSize: 14,
                        color: _selectedJsonFile != null
                            ? Colors.black87
                            : Colors.grey[600],
                        fontWeight: _selectedJsonFile != null
                            ? FontWeight.w500
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 16),
          
          // Convert button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isConverting ? null : _convertToExcel,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              child: _isConverting
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        ),
                        SizedBox(width: 12),
                        Text('Converting...'),
                      ],
                    )
                  : const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.transform, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Convert to Excel',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Downloaded files section
          if (_downloadedFiles.isNotEmpty) ...[
            Text(
              'Downloaded Files',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.grey[800],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: _downloadedFiles.length,
                itemBuilder: (context, index) {
                  final filePath = _downloadedFiles[index];
                  final fileName = _getFileName(filePath);
                  final isExcel = fileName.endsWith('.xlsx');
                  
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: Icon(
                        isExcel ? Icons.table_chart : Icons.code,
                        color: isExcel ? Colors.green[600] : Colors.blue[600],
                      ),
                      title: Text(
                        fileName,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      subtitle: Text(
                        isExcel ? 'Excel File' : 'JSON File',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey[600],
                        ),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.share),
                        onPressed: () => _shareFile(filePath),
                        tooltip: 'Share file',
                      ),
                    ),
                  );
                },
              ),
            ),
          ] else ...[
            const SizedBox(height: 20),
            Center(
              child: Column(
                children: [
                  Icon(
                    Icons.folder_open,
                    size: 48,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'No files yet',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey[600],
                    ),
                  ),
                  Text(
                    'Convert some JSON files to see them here',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}