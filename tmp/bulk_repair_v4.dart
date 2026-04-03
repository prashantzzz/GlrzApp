import 'dart:io';

void main() {
  final rootDir = Directory(r'android/app/src/main/kotlin/com/galleryze/app');
  if (!rootDir.existsSync()) {
    print('Error: Directory not found');
    return;
  }

  final files = rootDir.listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.kt') || file.path.endsWith('.java'))
      .toList();

  print('Found ${files.length} files to scan.');
  int updatedCount = 0;

  for (final file in files) {
    try {
      final content = file.readAsStringSync();
      var newContent = content;
      
      // Update package declarations
      newContent = newContent.replaceAll('package deckers.thibault.aves', 'package com.galleryze.app');
      // Update imports
      newContent = newContent.replaceAll('import deckers.thibault.aves', 'import com.galleryze.app');
      // Update R class references
      newContent = newContent.replaceAll('deckers.thibault.aves.R', 'com.galleryze.app.R');

      if (content != newContent) {
        file.writeAsStringSync(newContent);
        updatedCount++;
        print('Updated: ${file.path}');
      }
    } catch (e) {
      print('Error processing ${file.path}: $e');
    }
  }

  print('Bulk repair complete. Updated $updatedCount files.');
}
