import 'dart:io';

void main() {
  final logFile = File('tmp/repair_log.txt');
  logFile.writeAsStringSync('Starting repair...\n');
  
  final dir = Directory('android/app/src/main/kotlin/com/galleryze/app');
  if (!dir.existsSync()) {
    logFile.writeAsStringSync('Error: Directory not found\n', mode: FileMode.append);
    return;
  }
  
  final files = dir.listSync(recursive: true).whereType<File>().toList();
  logFile.writeAsStringSync('Found ${files.length} files\n', mode: FileMode.append);
  
  for (var file in files) {
    if (file.path.endsWith('.kt') || file.path.endsWith('.java')) {
      try {
        final content = file.readAsStringSync();
        final newContent = content.replaceAll('deckers.thibault.aves', 'com.galleryze.app');
        if (content != newContent) {
          file.writeAsStringSync(newContent);
          logFile.writeAsStringSync('Fixed: ${file.path}\n', mode: FileMode.append);
        }
      } catch (e) {
        logFile.writeAsStringSync('Error in ${file.path}: $e\n', mode: FileMode.append);
      }
    }
  }
  logFile.writeAsStringSync('Repair complete.\n', mode: FileMode.append);
}
