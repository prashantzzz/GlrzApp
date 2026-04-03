import 'dart:io';

void main() {
  final oldDir = Directory('android/app/src/test/kotlin/deckers/thibault/aves');
  final newDir = Directory('android/app/src/test/kotlin/com/galleryze/app');
  
  if (!oldDir.existsSync()) {
    print('Old test directory not found');
    return;
  }

  // Relocate files
  if (!newDir.existsSync()) {
    newDir.createSync(recursive: true);
  }

  // Move files recursively
  void relocate(Directory source, Directory target) {
    if (!target.existsSync()) target.createSync(recursive: true);
    for (var entity in source.listSync()) {
      final name = entity.path.split(Platform.pathSeparator).last;
      if (entity is Directory) {
        relocate(entity, Directory('${target.path}${Platform.pathSeparator}$name'));
      } else if (entity is File && name.endsWith('.kt')) {
        final targetPath = '${target.path}${Platform.pathSeparator}$name';
        entity.renameSync(targetPath);
        print('Moved: ${entity.path} -> $targetPath');
        
        // Fix content
        final file = File(targetPath);
        final content = file.readAsStringSync();
        final updatedContent = content
            .replaceAll('package deckers.thibault.aves', 'package com.galleryze.app')
            .replaceAll('import deckers.thibault.aves', 'import com.galleryze.app');
        if (content != updatedContent) {
          file.writeAsStringSync(updatedContent);
          print('Updated content: $targetPath');
        }
      }
    }
  }

  relocate(oldDir, newDir);
  
  // Clean up empty old directories
  // (Simplified: we'll just leave them for now or delete them if we're sure)
}
