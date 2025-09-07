import 'package:flutter/material.dart';
import '../services/file_service.dart';
import '../models/account_model.dart';

class FileUploadTab extends StatefulWidget {
  final Function(List<AccountModel>) onStartProcessing;

  const FileUploadTab({
    super.key,
    required this.onStartProcessing,
  });

  @override
  State<FileUploadTab> createState() => _FileUploadTabState();
}

class _FileUploadTabState extends State<FileUploadTab> {
  String? _selectedFileName;
  List<AccountModel> _selectedAccounts = [];
  bool _isLoading = false;

  Future<void> _pickFile() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final accounts = await FileService.pickAndParseFile();
      if (accounts.isNotEmpty) {
        setState(() {
          _selectedAccounts = accounts;
          _selectedFileName = 'Selected ${accounts.length} usernames';
        });
      } else {
        _showSnackBar('No valid usernames found in the file', Colors.orange);
      }
    } catch (e) {
      _showSnackBar('Error reading file: ${e.toString()}', Colors.red);
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
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

  void _startProcessing() {
    if (_selectedAccounts.isEmpty) {
      _showSnackBar('Please select a file first', Colors.orange);
      return;
    }
    widget.onStartProcessing(_selectedAccounts);
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
              Icon(Icons.file_upload, color: Colors.indigo[500], size: 24),
              const SizedBox(width: 8),
              const Text(
                'Upload a file',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'JSON or TXT — one username per line (or an array in JSON).',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(height: 16),
          
          // File picker button
          InkWell(
            onTap: _isLoading ? null : _pickFile,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey[300]!),
                borderRadius: BorderRadius.circular(8),
                color: _isLoading ? Colors.grey[50] : Colors.white,
              ),
              child: Row(
                children: [
                  if (_isLoading)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Icon(
                      Icons.attach_file,
                      color: Colors.grey[600],
                      size: 20,
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _selectedFileName ?? 'Choose file...',
                      style: TextStyle(
                        fontSize: 14,
                        color: _selectedFileName != null
                            ? Colors.black87
                            : Colors.grey[600],
                        fontWeight: _selectedFileName != null
                            ? FontWeight.w500
                            : FontWeight.normal,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          const SizedBox(height: 20),
          
          // Start button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _selectedAccounts.isEmpty ? null : _startProcessing,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red[600],
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 2,
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.search, size: 20),
                  SizedBox(width: 8),
                  Text(
                    'Start Checking',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}