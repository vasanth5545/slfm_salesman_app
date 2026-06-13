import 'dart:io';

void main() async {
  var file = File('admin_control.html');
  var lines = await file.readAsLines();
  for (int i = 0; i < lines.length; i++) {
    if (lines[i].toLowerCase().contains('edit lunch record')) {
      // ignore: avoid_print
      print('Line ${i + 1}: ${lines[i]}');
    }
    if (lines[i].toLowerCase().contains('selfie previews')) {
      // ignore: avoid_print
      print('Line ${i + 1}: ${lines[i]}');
    }
  }
}
