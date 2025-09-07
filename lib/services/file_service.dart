import 'dart:convert';
import 'dart:io';
import 'package:excel/excel.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import '../models/account_model.dart';

class FileService {
  static Future<List<AccountModel>> pickAndParseFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json', 'txt'],
      );

      if (result != null && result.files.single.path != null) {
        final file = File(result.files.single.path!);
        final extension = result.files.single.extension?.toLowerCase();
        
        if (extension == 'json') {
          return await _parseJsonFile(file);
        } else if (extension == 'txt') {
          return await _parseTxtFile(file);
        }
      }
      return [];
    } catch (e) {
      throw Exception('Error reading file: $e');
    }
  }

  static Future<List<AccountModel>> _parseJsonFile(File file) async {
    try {
      final content = await file.readAsString();
      final jsonData = jsonDecode(content);
      
      List<AccountModel> accounts = [];
      
      if (jsonData is List) {
        for (var item in jsonData) {
          if (item is Map<String, dynamic> && item.containsKey('username')) {
            accounts.add(AccountModel.fromJson(item));
          }
        }
      } else if (jsonData is Map<String, dynamic> && jsonData.containsKey('username')) {
        accounts.add(AccountModel.fromJson(jsonData));
      }
      
      return accounts;
    } catch (e) {
      throw Exception('Invalid JSON format: $e');
    }
  }

  static Future<List<AccountModel>> _parseTxtFile(File file) async {
    try {
      final content = await file.readAsString();
      final lines = content.split('\n')
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      
      return lines.map((username) => AccountModel(username: username)).toList();
    } catch (e) {
      throw Exception('Error reading text file: $e');
    }
  }

  static List<AccountModel> parseTextInput(String text) {
    final lines = text.split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    
    return lines.map((username) => AccountModel(username: username)).toList();
  }

  static Future<String> saveActiveAccountsAsJson(List<AccountModel> accounts, String filename) async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final jsonFilename = 'final_${filename.replaceAll('.txt', '.json').replaceAll('.json', '.json')}';
      final file = File('${directory.path}/$jsonFilename');
      
      final jsonData = accounts.map((account) => account.toJson()).toList();
      final jsonString = const JsonEncoder.withIndent('  ').convert(jsonData);
      
      await file.writeAsString(jsonString);
      return file.path;
    } catch (e) {
      throw Exception('Error saving JSON file: $e');
    }
  }

  static Future<String> convertJsonToExcel(String jsonFilePath) async {
    try {
      final file = File(jsonFilePath);
      if (!await file.exists()) {
        throw Exception('JSON file not found');
      }

      final content = await file.readAsString();
      final jsonData = jsonDecode(content) as List;
      
      // Create Excel file
      final excel = Excel.createExcel();
      final sheet = excel['Sheet1'];
      
      // Add headers
      sheet.cell(CellIndex.indexByString('A1')).value = TextCellValue('Username');
      sheet.cell(CellIndex.indexByString('B1')).value = TextCellValue('Password');
      sheet.cell(CellIndex.indexByString('C1')).value = TextCellValue('Authcode');
      sheet.cell(CellIndex.indexByString('D1')).value = TextCellValue('Email');
      
      // Add data
      for (int i = 0; i < jsonData.length; i++) {
        final account = jsonData[i];
        final rowIndex = i + 2; // Start from row 2 (after header)
        
        sheet.cell(CellIndex.indexByString('A$rowIndex')).value = 
            TextCellValue(account['username'] ?? '');
        sheet.cell(CellIndex.indexByString('B$rowIndex')).value = 
            TextCellValue(account['password'] ?? '');
        sheet.cell(CellIndex.indexByString('C$rowIndex')).value = 
            TextCellValue(account['auth_code'] ?? '');
        sheet.cell(CellIndex.indexByString('D$rowIndex')).value = 
            TextCellValue(account['email'] ?? '');
      }
      
      // Save Excel file
      final directory = await getApplicationDocumentsDirectory();
      final excelFilename = jsonFilePath.replaceAll('.json', '.xlsx').split('/').last;
      final excelFile = File('${directory.path}/$excelFilename');
      
      final excelBytes = excel.save();
      if (excelBytes != null) {
        await excelFile.writeAsBytes(excelBytes);
        return excelFile.path;
      } else {
        throw Exception('Failed to generate Excel file');
      }
    } catch (e) {
      throw Exception('Error converting to Excel: $e');
    }
  }

  static Future<void> shareFile(String filePath) async {
    try {
      final result = await Share.shareXFiles([XFile(filePath)]);
      if (result.status != ShareResultStatus.success) {
        throw Exception('Failed to share file');
      }
    } catch (e) {
      throw Exception('Error sharing file: $e');
    }
  }

  static Future<List<String>> getDownloadedFiles() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final files = directory.listSync()
          .where((entity) => entity is File)
          .map((entity) => entity.path)
          .where((path) => path.endsWith('.json') || path.endsWith('.xlsx'))
          .toList();
      
      return files;
    } catch (e) {
      return [];
    }
  }
}