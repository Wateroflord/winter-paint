import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'ui.dart';

/// Проект: холст или пиксель-арт. Хранится в папке приложения.
class ProjectMeta {
  final String id;
  String name;
  final String kind; // canvas | pixel
  final int w, h;
  int updated;
  ProjectMeta(this.id, this.name, this.kind, this.w, this.h, this.updated);

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'kind': kind, 'w': w, 'h': h, 'u': updated};
  static ProjectMeta fromJson(Map j) =>
      ProjectMeta('${j['id']}', '${j['name']}', '${j['kind']}', (j['w'] as num).toInt(), (j['h'] as num).toInt(), (j['u'] as num?)?.toInt() ?? 0);
}

class Projects {
  static Future<Directory> root() async {
    final d = Directory('${(await dataDir()).path}${Platform.pathSeparator}projects');
    await d.create(recursive: true);
    return d;
  }

  static Future<Directory> dir(String id) async {
    final d = Directory('${(await root()).path}${Platform.pathSeparator}$id');
    await d.create(recursive: true);
    return d;
  }

  static Future<List<ProjectMeta>> list() async {
    final out = <ProjectMeta>[];
    await for (final e in (await root()).list()) {
      if (e is! Directory) continue;
      final f = File('${e.path}${Platform.pathSeparator}meta.json');
      try {
        if (await f.exists()) out.add(ProjectMeta.fromJson(jsonDecode(await f.readAsString()) as Map));
      } catch (_) {}
    }
    out.sort((a, b) => b.updated.compareTo(a.updated));
    return out;
  }

  static Future<void> saveMeta(ProjectMeta m) async {
    m.updated = DateTime.now().millisecondsSinceEpoch;
    await File('${(await dir(m.id)).path}${Platform.pathSeparator}meta.json').writeAsString(jsonEncode(m.toJson()));
  }

  static Future<File> file(String id, String name) async => File('${(await dir(id)).path}${Platform.pathSeparator}$name');

  static Future<void> writeBytes(String id, String name, Uint8List b) async => (await file(id, name)).writeAsBytes(b, flush: true);

  static Future<Uint8List?> readBytes(String id, String name) async {
    final f = await file(id, name);
    return await f.exists() ? f.readAsBytes() : null;
  }

  static Future<void> delete(String id) async {
    try {
      await (await dir(id)).delete(recursive: true);
    } catch (_) {}
  }

  /// Все рисунки одним файлом (JSON, содержимое файлов в base64).
  static Future<String> exportAll() async {
    final out = <Map<String, dynamic>>[];
    await for (final e in (await root()).list()) {
      if (e is! Directory) continue;
      final files = <String, String>{};
      await for (final f in e.list()) {
        if (f is File) files[f.uri.pathSegments.last] = base64Encode(await f.readAsBytes());
      }
      if (files.containsKey('meta.json')) out.add({'id': e.uri.pathSegments.where((s) => s.isNotEmpty).last, 'files': files});
    }
    return jsonEncode({'app': 'winter-paint', 'version': 1, 'projects': out});
  }

  /// Восстановить рисунки из копии. Уже существующие не трогаем. Возвращает число добавленных.
  static Future<int> importAll(String raw) async {
    final Object? j;
    try {
      j = jsonDecode(raw.trim());
    } catch (_) {
      throw const FormatException('Это не файл резервной копии');
    }
    if (j is! Map || j['app'] != 'winter-paint') throw const FormatException('Это не копия Winter Paint');
    final existing = {for (final m in await list()) m.id};
    var n = 0;
    for (final p in (j['projects'] as List? ?? const [])) {
      if (p is! Map || p['files'] is! Map) continue;
      final id = '${p['id']}'.replaceAll(RegExp(r'[^0-9A-Za-z_-]'), '');
      if (id.isEmpty || existing.contains(id)) continue;
      final files = (p['files'] as Map).map((k, v) => MapEntry('$k'.replaceAll(RegExp(r'[/\\]'), ''), '$v'));
      if (!files.containsKey('meta.json')) continue;
      for (final e in files.entries) {
        await writeBytes(id, e.key, base64Decode(e.value));
      }
      n++;
    }
    return n;
  }

  static String newId() => DateTime.now().microsecondsSinceEpoch.toString();
}
