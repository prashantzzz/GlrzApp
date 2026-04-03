import 'dart:io';

void main() {
  final dir = Directory('android/app/src/main/kotlin/com/galleryze/app');
  final regexPackage = RegExp(r'package deckers\.thibault\.aves');
  final regexImport = RegExp(r'import deckers\.thibault\.aves');
  final regexReference = RegExp(r'deckers\.thibault\.aves');

  if (!dir.existsSync()) {
    print('Error: Directory ${dir.path} not found');
    return;
  }

  void process(Directory d) {
    d.listSync(recursive: true).forEach((entity) {
      if (entity is File && (entity.path.endsWith('.kt') || entity.path.endsWith('.java'))) {
        try {
          final content = entity.readAsStringSync();
          var newContent = content.replaceAll(regexPackage, 'package com.galleryze.app');
          newContent = newContent.replaceAll(regexImport, 'import com.galleryze.app');
          newContent = newContent.replaceAll(regexReference, 'com.galleryze.app');
          
          if (newContent != content) {
            entity.writeAsStringSync(newContent);
            print('Repaired: ${entity.path}');
          }
        } catch (e) {
          print('Error processing ${entity.path}: $e');
        }
      }
    });
  }

  process(dir);
  print('Kotlin repair completed.');
}
