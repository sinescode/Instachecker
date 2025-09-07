import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../models/account_model.dart';

class UsernameService {
  static const String baseUrl = 'https://i.instagram.com/api/v1/users/web_profile_info/';
  static const int maxRetries = 10;
  static const int initialDelay = 1;
  static const int maxDelay = 60;
  static const int concurrentLimit = 5;

  static const Map<String, String> headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0 Safari/537.36',
    'x-ig-app-id': '936619743392459',
    'Accept': '*/*',
    'Accept-Language': 'en-US,en;q=0.9',
    'Referer': 'https://www.instagram.com/',
    'Origin': 'https://www.instagram.com',
    'Sec-Fetch-Site': 'same-origin',
  };

  final StreamController<CheckResult> _resultController = StreamController<CheckResult>.broadcast();
  final StreamController<ProcessingStats> _statsController = StreamController<ProcessingStats>.broadcast();
  final StreamController<String> _statusController = StreamController<String>.broadcast();
  
  Stream<CheckResult> get resultStream => _resultController.stream;
  Stream<ProcessingStats> get statsStream => _statsController.stream;
  Stream<String> get statusStream => _statusController.stream;

  bool _isProcessing = false;
  bool _isCancelled = false;
  ProcessingStats _currentStats = ProcessingStats(
    activeCount: 0,
    availableCount: 0,
    errorCount: 0,
    cancelledCount: 0,
    totalCount: 0,
  );

  List<AccountModel> _activeAccounts = [];

  Future<void> processUsernames(List<AccountModel> accounts) async {
    if (_isProcessing) return;
    
    _isProcessing = true;
    _isCancelled = false;
    _activeAccounts.clear();
    
    _currentStats = ProcessingStats(
      activeCount: 0,
      availableCount: 0,
      errorCount: 0,
      cancelledCount: 0,
      totalCount: accounts.length,
    );
    
    _statsController.add(_currentStats);

    // Process usernames in batches to limit concurrent requests
    final batches = _createBatches(accounts, concurrentLimit);
    
    for (final batch in batches) {
      if (_isCancelled) break;
      
      final futures = batch.map((account) => _checkUsername(account)).toList();
      await Future.wait(futures);
    }

    _isProcessing = false;
  }

  List<List<AccountModel>> _createBatches(List<AccountModel> accounts, int batchSize) {
    final batches = <List<AccountModel>>[];
    for (int i = 0; i < accounts.length; i += batchSize) {
      final end = (i + batchSize < accounts.length) ? i + batchSize : accounts.length;
      batches.add(accounts.sublist(i, end));
    }
    return batches;
  }

  Future<void> _checkUsername(AccountModel account) async {
    if (_isCancelled) {
      _updateStats('CANCELLED');
      _resultController.add(CheckResult(
        username: account.username,
        status: 'CANCELLED',
        message: 'Cancelled: ${account.username}',
      ));
      return;
    }

    final url = '$baseUrl?username=${account.username}';
    int retryCount = 0;
    double delay = initialDelay.toDouble();

    while (retryCount < maxRetries && !_isCancelled) {
      try {
        final response = await http.get(Uri.parse(url), headers: headers);
        
        if (response.statusCode == 404) {
          _updateStats('AVAILABLE');
          _resultController.add(CheckResult(
            username: account.username,
            status: 'AVAILABLE',
            message: '[AVAILABLE] ${account.username}',
          ));
          return;
        } else if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['data']?['user'] != null) {
            _updateStats('ACTIVE');
            _activeAccounts.add(account);
            _resultController.add(CheckResult(
              username: account.username,
              status: 'ACTIVE',
              message: '[ACTIVE] ${account.username}',
            ));
            return;
          } else {
            _updateStats('AVAILABLE');
            _resultController.add(CheckResult(
              username: account.username,
              status: 'AVAILABLE',
              message: '[AVAILABLE] ${account.username}',
            ));
            return;
          }
        } else {
          // Retry logic
          delay = min(maxDelay.toDouble(), delay * 2 + Random().nextDouble());
          retryCount++;
          final statusMsg = '[RETRY $retryCount/$maxRetries] ${account.username} - Status: ${response.statusCode}, Waiting: ${delay.toStringAsFixed(2)}s';
          _statusController.add(statusMsg);
          await Future.delayed(Duration(milliseconds: (delay * 1000).round()));
        }
      } catch (e) {
        delay = min(maxDelay.toDouble(), delay * 2 + Random().nextDouble());
        retryCount++;
        final statusMsg = '[RETRY $retryCount/$maxRetries] ${account.username} - Exception: $e, Waiting: ${delay.toStringAsFixed(2)}s';
        _statusController.add(statusMsg);
        await Future.delayed(Duration(milliseconds: (delay * 1000).round()));
      }
    }

    // Max retries exceeded
    _updateStats('ERROR');
    _resultController.add(CheckResult(
      username: account.username,
      status: 'ERROR',
      message: '[ERROR] ${account.username} - Max retries exceeded',
    ));
  }

  void _updateStats(String status) {
    switch (status) {
      case 'ACTIVE':
        _currentStats = ProcessingStats(
          activeCount: _currentStats.activeCount + 1,
          availableCount: _currentStats.availableCount,
          errorCount: _currentStats.errorCount,
          cancelledCount: _currentStats.cancelledCount,
          totalCount: _currentStats.totalCount,
        );
        break;
      case 'AVAILABLE':
        _currentStats = ProcessingStats(
          activeCount: _currentStats.activeCount,
          availableCount: _currentStats.availableCount + 1,
          errorCount: _currentStats.errorCount,
          cancelledCount: _currentStats.cancelledCount,
          totalCount: _currentStats.totalCount,
        );
        break;
      case 'ERROR':
        _currentStats = ProcessingStats(
          activeCount: _currentStats.activeCount,
          availableCount: _currentStats.availableCount,
          errorCount: _currentStats.errorCount + 1,
          cancelledCount: _currentStats.cancelledCount,
          totalCount: _currentStats.totalCount,
        );
        break;
      case 'CANCELLED':
        _currentStats = ProcessingStats(
          activeCount: _currentStats.activeCount,
          availableCount: _currentStats.availableCount,
          errorCount: _currentStats.errorCount,
          cancelledCount: _currentStats.cancelledCount + 1,
          totalCount: _currentStats.totalCount,
        );
        break;
    }
    _statsController.add(_currentStats);
  }

  void cancelProcessing() {
    _isCancelled = true;
    _isProcessing = false;
  }

  List<AccountModel> getActiveAccounts() => List.from(_activeAccounts);

  bool get isProcessing => _isProcessing;
  bool get isCompleted => !_isProcessing && _currentStats.processedCount > 0;

  void dispose() {
    _resultController.close();
    _statsController.close();
    _statusController.close();
  }
}