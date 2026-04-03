import 'dart:io';

void main() {
  final root = Directory('android/app/src/main/kotlin/com/galleryze/app');
  if (!root.existsSync()) {
    print('Directory not found: ${root.path}');
    return;
  }

  int count = 0;
  root.listSync(recursive: true).forEach((entity) {
    if (entity is File && entity.path.endsWith('.kt')) {
      final content = entity.readAsStringSync();
      if (content.contains('deckers.thibault.aves')) {
        final newContent = content.replaceAll('deckers.thibault.aves', 'com.galleryze.app');
        entity.writeAsStringSync(newContent);
        print('Repaired: ${entity.path}');
        count++;
      }
    }
  });
  print('Total files repaired: $count');
}
