import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

void main() async {
  final url =
      'https://skyblue-raven-196549.hostingersite.com/api/attendance.php';

  // Try to test with salesman_id 1 to 5, and also maybe print whatever comes back
  for (int i = 1; i <= 5; i++) {
    debugPrint('Testing salesman_id: $i');
    try {
      final response = await http.post(Uri.parse(url),
          body: jsonEncode(
              {"action": "get_history", "salesman_id": i.toString()}),
          headers: {'Content-Type': 'application/json'});

      final data = jsonDecode(response.body);
      debugPrint(
          'Response for $i: ${data.toString().substring(0, data.toString().length > 300 ? 300 : data.toString().length)}...');
      if (data['status'] == 'success') {
        final history = data['data'] as List;
        if (history.isNotEmpty) {
          debugPrint(
              'Found history for salesman $i. Total records: ${history.length}');
          for (int j = 0; j < 3 && j < history.length; j++) {
            debugPrint('Record $j: ${jsonEncode(history[j])}');
          }
          break; // Found one, we can stop
        }
      }
    } catch (e) {
      debugPrint('Error on $i: $e');
    }
  }
}
