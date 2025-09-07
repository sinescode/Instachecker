// screens/converter_tab.dart
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:excel/excel.dart';
import 'package:instachecker/services/excel_service.dart';

class ConverterTab extends StatefulWidget {
  const ConverterTab({Key? key}) : super(key: key);

  @override
  _ConverterTabState createState() => _ConverterTabState();
}

class _ConverterTabState extends State<ConverterTab> {
  final ExcelService _excelService = ExcelService();
  String? _filePath;
  String _fileName = 'No file selected';
  bool _isConverting = false;

  Future<void> _pickFile() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['json'],
    );

    if (result != null) {
      setState(() {
        _filePath = result.files.single.path;
        _fileName = result.files.single.name;
      });
    }
  }

  Future<void> _convertToExcel() async {
    if (_filePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a JSON file first')),
      );
      return;
    }

    setState(() => _isConverting = true);

    try {
      final file = File(_filePath!);
      final contents = await file.readAsString();
      final data = jsonDecode(contents) as List;

      if (data.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('The selected JSON file is empty')),
        );
        return;
      }

      final bytes = await _excelService.convertJsonToExcel(data);
      
      // Save the file
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final output = File('/storage/emulated/0/Download/converted_$timestamp.xlsx');
      await output.writeAsBytes(bytes!);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Excel file saved to ${output.path}')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error converting file: $e')),
      );
    } finally {
      setState(() => _isConverting = false);
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
                    'JSON to Excel Converter',
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
                      onPressed: _isConverting ? null : _convertToExcel,
                      icon: const Icon(Icons.file_download),
                      label: const Text('Convert to Excel'),
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
          if (_isConverting) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            const Text(
              'Converting file...',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
          ],
          const Expanded(
            child: Center(
              child: Text(
                'Select a JSON file to convert to Excel format',
                style: TextStyle(fontSize: 16),
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ],
      ),
    );
  }
}