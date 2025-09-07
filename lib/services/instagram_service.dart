// services/instagram_service.dart
import 'dart:async';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:http/retry.dart';

class InstagramService {
  final String _baseUrl = 'https://i.instagram.com/api/v1/users/web_profile_info/?username=';
  final Map<String, String> _headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/115.0 Safari/537.36',
    'x-ig-app-id': '936619743392459',
    'Accept': '*/*',
    'Accept-Language': 'en-US,en;q=0.9',
    'Referer': 'https://www.instagram.com/',
    'Origin': 'https://www.instagram.com',
    'Sec-Fetch-Site': 'same-origin',
  };

  Future<Map<String, dynamic>> checkUsername(String username) async {
    final client = RetryClient(
      http.Client(),
      retries: 3,
      when: (response) {
        return response.statusCode == 429 || response.statusCode == 500 || response.statusCode == 503;
      },
      onRetry: (req, res, retryCount) {
        final delay = min(1000 * pow(2, retryCount), 60000).toInt();
        return Future.delayed(Duration(milliseconds: delay));
      },
    );

    try {
      final response = await client.get(
        Uri.parse('$_baseUrl$username'),
        headers: _headers,
      );

      if (response.statusCode == 404) {
        return {
          'status': 'AVAILABLE',
          'message': '$username - Available',
          'username': username,
        };
      } else if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['data'] != null && data['data']['user'] != null) {
          return {
            'status': 'ACTIVE',
            'message': '$username - Active',
            'username': username,
            'data': data['data']['user'],
          };
        } else {
          return {
            'status': 'AVAILABLE',
            'message': '$username - Available',
            'username': username,
          };
        }
      } else {
        return {
          'status': 'ERROR',
          'message': '$username - Error (HTTP ${response.statusCode})',
          'username': username,
        };
      }
    } catch (e) {
      return {
        'status': 'ERROR',
        'message': '$username - Error (${e.toString()})',
        'username': username,
      };
    } finally {
      client.close();
    }
  }
}