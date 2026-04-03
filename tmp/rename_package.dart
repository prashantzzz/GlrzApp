import 'dart:io';

void main() {
  final dir = Directory('android');
  final pluginsDir = Directory('plugins');
  final regex = RegExp(r'deckers\.thibault\.aves(?![_])');
  
  void process(Directory d) {
    if (!d.existsSync()) return;
    d.listSync(recursive: true).forEach((entity) {
      if (entity is File && (entity.path.endsWith('.kt') || entity.path.endsWith('.java') || entity.path.endsWith('.xml'))) {
        try {
          final content = entity.readAsStringSync();
          if (regex.hasMatch(content)) {
            final newContent = content.replaceAll(regex, 'com.galleryze.app');
            entity.writeAsStringSync(newContent);
            print('Updated: ${entity.path}');
          }
        } catch (e) {
          // Skip binary or unreadable files
        }
      }
    });
  }

  process(dir);
  process(pluginsDir);
}
