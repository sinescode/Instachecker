class AccountModel {
  final String username;
  final String? password;
  final String? authCode;
  final String? email;

  AccountModel({
    required this.username,
    this.password,
    this.authCode,
    this.email,
  });

  factory AccountModel.fromJson(Map<String, dynamic> json) {
    return AccountModel(
      username: json['username'] ?? '',
      password: json['password'],
      authCode: json['auth_code'],
      email: json['email'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'password': password,
      'auth_code': authCode,
      'email': email,
    };
  }
}

class CheckResult {
  final String username;
  final String status;
  final String message;

  CheckResult({
    required this.username,
    required this.status,
    required this.message,
  });

  factory CheckResult.fromJson(Map<String, dynamic> json) {
    return CheckResult(
      username: json['username'] ?? '',
      status: json['status'] ?? '',
      message: json['message'] ?? '',
    );
  }
}

class ProcessingStats {
  final int activeCount;
  final int availableCount;
  final int errorCount;
  final int cancelledCount;
  final int totalCount;

  ProcessingStats({
    required this.activeCount,
    required this.availableCount,
    required this.errorCount,
    required this.cancelledCount,
    required this.totalCount,
  });

  factory ProcessingStats.fromJson(Map<String, dynamic> json) {
    return ProcessingStats(
      activeCount: json['active_count'] ?? 0,
      availableCount: json['available_count'] ?? 0,
      errorCount: json['error_count'] ?? 0,
      cancelledCount: json['cancelled_count'] ?? 0,
      totalCount: json['total_count'] ?? 0,
    );
  }

  int get processedCount => activeCount + availableCount + errorCount + cancelledCount;
  
  double get progress => totalCount > 0 ? processedCount / totalCount : 0.0;
}