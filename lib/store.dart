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

  static String newId() => DateTime.now().microsecondsSinceEpoch.toString();
}
