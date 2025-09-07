// screens/text_tab.dart
import 'package:flutter/material.dart';
import 'package:instachecker/services/instagram_service.dart';
import 'package:instachecker/widgets/result_item.dart';
import 'package:instachecker/widgets/progress_stats.dart';

class TextTab extends StatefulWidget {
  const TextTab({Key? key}) : super(key: key);

  @override
  _TextTabState createState() => _TextTabState();
}

class _TextTabState extends State<TextTab> {
  final InstagramService _instagramService = InstagramService();
  final TextEditingController _controller = TextEditingController();
  bool _isProcessing = false;
  List<Map<String, dynamic>> _results = [];
  int _processedCount = 0;
  int _activeCount = 0;
  int _availableCount = 0;
  int _errorCount = 0;

  Future<void> _startProcessing() async {
    if (_controller.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter at least one username')),
      );
      return;
    }

    final usernames = _controller.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (usernames.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No valid usernames found')),
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
                    'Enter Usernames',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _controller,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: 'Enter one username per line',
                      labelText: 'Usernames',
                    ),
                    maxLines: 5,
                    enabled: !_isProcessing,
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