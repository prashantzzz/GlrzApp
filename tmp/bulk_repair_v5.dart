import 'dart:io';

void main() {
  final rootPath = r'android/app/src/main/kotlin/com/galleryze/app';
  final rootDir = Directory(rootPath);

  if (!rootDir.existsSync()) {
    print('Error: Directory $rootPath not found.');
    return;
  }

  print('Starting bulk repair in $rootPath...');

  final files = rootDir.listSync(recursive: true);
  int updatedCount = 0;

  for (var entity in files) {
    if (entity is File && (entity.path.endsWith('.kt') || entity.path.endsWith('.java'))) {
      String content = entity.readAsStringSync();
      String newContent = content
          .replaceAll('deckers.thibault.aves', 'com.galleryze.app')
          .replaceAll('package deckers.thibault.aves', 'package com.galleryze.app')
          .replaceAll('import deckers.thibault.aves', 'import com.galleryze.app');

      if (content != newContent) {
        entity.writeAsStringSync(newContent);
        updatedCount++;
        print('Updated: ${entity.path}');
      }
    }
  }

  print('Bulk repair completed. Updated $updatedCount files.');
}
