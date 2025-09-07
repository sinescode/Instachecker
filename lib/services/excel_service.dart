// services/excel_service.dart
import 'package:excel/excel.dart';

class ExcelService {
  Future<List<int>?> convertJsonToExcel(List<dynamic> data) async {
    var excel = Excel.createExcel();
    Sheet sheetObject = excel['Sheet1'];

    // Create header row
    List<String> headers = ['Username', 'Password', 'Auth Code', 'Email'];
    for (int i = 0; i < headers.length; i++) {
      var cell = sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: i, rowIndex: 0));
      cell.value = TextCellValue(headers[i]);
      
      // Apply cell style directly without Font object
      cell.cellStyle = CellStyle(
        bold: true,
        fontColorHex: "#FFFFFF",  // Use fontColorHex instead of Font
        backgroundColorHex: '#4F81BD',
      );
    }

    // Add data rows
    for (int i = 0; i < data.length; i++) {
      final item = data[i];
      
      var usernameCell = sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 0, rowIndex: i + 1));
      usernameCell.value = TextCellValue(item['username']?.toString() ?? '');
      
      var passwordCell = sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 1, rowIndex: i + 1));
      passwordCell.value = TextCellValue(item['password']?.toString() ?? '');
      
      var authCodeCell = sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 2, rowIndex: i + 1));
      authCodeCell.value = TextCellValue(item['auth_code']?.toString() ?? '');
      
      var emailCell = sheetObject.cell(CellIndex.indexByColumnRow(columnIndex: 3, rowIndex: i + 1));
      emailCell.value = TextCellValue(item['email']?.toString() ?? '');
    }

    // Auto-size columns
    for (int i = 0; i < headers.length; i++) {
      sheetObject.setColumnAutoFit(i);
    }

    return excel.save();
  }
}