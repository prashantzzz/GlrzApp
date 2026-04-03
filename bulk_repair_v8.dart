import 'dart:io';

void main() {
  final rootPath = r'c:\Users\Prashant\Documents\Prashant_coder\NoCodeApps\GlrzApp_aves\android\app\src\main\kotlin\com\galleryze\app';
  final root = Directory(rootPath);
  if (!root.existsSync()) {
    print('Directory not found: $rootPath');
    return;
  }

  int count = 0;
  root.listSync(recursive: true).forEach((entity) {
    if (entity is File && entity.path.endsWith('.kt')) {
      try {
        final content = entity.readAsStringSync();
        if (content.contains('deckers.thibault.aves')) {
          final newContent = content.replaceAll('deckers.thibault.aves', 'com.galleryze.app');
          entity.writeAsStringSync(newContent);
          print('Repaired: ${entity.path}');
          count++;
        }
      } catch (e) {
        print('Error processing ${entity.path}: $e');
      }
    }
  });
  print('Total files repaired: $count');
}
