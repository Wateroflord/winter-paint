import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Резервная копия в файл: сохранить (пользователь выбирает куда — например,
/// «Загрузки» или Google Диск) и открыть обратно.
class BackupIO {
  /// null — пользователь отменил. Иначе — куда сохранено.
  static Future<String?> save(String fileName, String text) async {
    final bytes = Uint8List.fromList(utf8.encode(text));
    final path = await FilePicker.platform.saveFile(
      dialogTitle: 'Куда сохранить копию',
      fileName: fileName,
      bytes: bytes,
    );
    if (path == null) return null;
    // На ПК плагин только спрашивает путь, файл пишем сами.
    if (!Platform.isAndroid && !Platform.isIOS) await File(path).writeAsBytes(bytes, flush: true);
    return path;
  }

  /// Текст выбранного файла или null, если ничего не выбрано.
  static Future<String?> open() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.any, withData: true);
    final f = r?.files.single;
    if (f == null) return null;
    final bytes = f.bytes ?? (f.path == null ? null : await File(f.path!).readAsBytes());
    return bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
  }

  static String stamp() {
    final d = DateTime.now();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }
}
