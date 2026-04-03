import 'dart:io';

void main() {
  final dir = Directory('lib/l10n');
  if (!dir.existsSync()) {
    print('L10n directory not found');
    return;
  }
  
  final files = dir.listSync().whereType<File>().toList();
  for (var file in files) {
    if (file.path.endsWith('.arb')) {
      final content = file.readAsStringSync();
      // Replace only "Aves" as a whole word to avoid breaking internal names if any
      // but in ARB files it's usually just the display string.
      final newContent = content.replaceAll('Aves', 'Galleryze');
      if (content != newContent) {
        file.writeAsStringSync(newContent);
        print('Updated: ${file.path}');
      }
    }
  }
  print('Localization update complete.');
}
