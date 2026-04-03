import 'dart:io';

void main() {
  final dir = Directory('android/app/src/main/kotlin/com/galleryze/app');
  if (!dir.existsSync()) {
    print('Directory not found');
    exit(1);
  }

  dir.listSync(recursive: true).whereType<File>().forEach((file) {
    if (file.path.endsWith('.kt')) {
      final content = file.readAsStringSync();
      final updatedContent = content
          .replaceAll('package deckers.thibault.aves', 'package com.galleryze.app')
          .replaceAll('import deckers.thibault.aves', 'import com.galleryze.app');
      
      if (content != updatedContent) {
        file.writeAsStringSync(updatedContent);
        print('Updated: ${file.path}');
      }
    }
  });
}
