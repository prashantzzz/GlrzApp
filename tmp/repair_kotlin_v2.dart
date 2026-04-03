import 'dart:io';

void main() {
  final dirPath = r'c:\Users\Prashant\Documents\Prashant_coder\NoCodeApps\GlrzApp_aves\android\app\src\main\kotlin\com\galleryze\app';
  final dir = Directory(dirPath);
  if (!dir.existsSync()) {
    print('Error: Directory $dirPath not found');
    return;
  }
  
  final regexDot = RegExp(r'deckers\.thibault\.aves');
  final regexSlash = RegExp(r'deckers\.thibault/aves');
  
  dir.listSync(recursive: true).forEach((entity) {
    if (entity is File && (entity.path.endsWith('.kt') || entity.path.endsWith('.java'))) {
      try {
        final content = entity.readAsStringSync();
        var newContent = content.replaceAll(regexDot, 'com.galleryze.app');
        newContent = newContent.replaceAll(regexSlash, 'com.galleryze.app');
        
        if (newContent != content) {
          entity.writeAsStringSync(newContent);
          print('Updated: ${entity.path}');
        }
      } catch (e) {
        print('Error processing ${entity.path}: $e');
      }
    }
  });
}
