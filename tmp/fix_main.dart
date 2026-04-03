import 'dart:io';

void main() {
  final file = File(r'android/app/src/main/kotlin/com/galleryze/app/MainActivity.kt');
  if (!file.existsSync()) {
    print('File not found');
    return;
  }
  final content = file.readAsStringSync();
  final newContent = content.replaceAll('deckers.thibault.aves', 'com.galleryze.app');
  file.writeAsStringSync(newContent);
  print('MainActivity.kt fixed');
}
