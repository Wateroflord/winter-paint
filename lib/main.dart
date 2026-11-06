import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'backup_io.dart';
import 'canvas_editor.dart';
import 'pixel.dart';
import 'store.dart';
import 'ui.dart';
import 'package:winter_core/winter_core.dart';

Future<void> main() => runWinterApp(repo: 'winter-paint', appName: 'Winter Paint', body: _main);

void _main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(WinterCrashBanner(child: const PaintApp()));
}

class PaintApp extends StatelessWidget {
  const PaintApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'Winter Paint',
        debugShowCheckedModeBanner: false,
        theme: winterTheme(const Color(0xFFBE8CFF)),
        home: const Home(),
      );
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  List<ProjectMeta> projects = [];
  final Map<String, Uint8List?> thumbs = {};

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    projects = await Projects.list();
    for (final p in projects) {
      thumbs[p.id] = await Projects.readBytes(p.id, 'thumb.png');
    }
    if (mounted) setState(() {});
  }

  void _snack(String t) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));

  Future<void> _backup() async {
    try {
      final path = await BackupIO.save('winter-paint-${BackupIO.stamp()}.json', await Projects.exportAll());
      if (path != null && mounted) _snack('Копия сохранена — рисунков: ${projects.length}');
    } catch (e) {
      if (mounted) _snack('Не удалось сохранить: $e');
    }
  }

  Future<void> _restore() async {
    try {
      final text = await BackupIO.open();
      if (text == null) return;
      final n = await Projects.importAll(text);
      await _reload();
      if (mounted) _snack(n == 0 ? 'Новых рисунков в копии нет' : 'Восстановлено рисунков: $n');
    } on FormatException catch (e) {
      if (mounted) _snack(e.message);
    } catch (e) {
      if (mounted) _snack('Не удалось восстановить: $e');
    }
  }

  Future<void> _open(ProjectMeta m) async {
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => m.kind == 'pixel' ? PixelEditor(meta: m) : CanvasEditor(meta: m)));
    await Future<void>.delayed(const Duration(milliseconds: 600));
    _reload();
  }

  Future<void> _new(String kind) async {
    final sizes = kind == 'pixel'
        ? [(16, 16, '16×16'), (24, 24, '24×24'), (32, 32, '32×32'), (48, 48, '48×48'), (64, 64, '64×64'), (128, 128, '128×128'), (64, 32, '64×32')]
        : [(1080, 1080, 'Квадрат 1080'), (1080, 1920, 'Телефон 1080×1920'), (1920, 1080, 'Экран 1920×1080'), (2048, 2048, 'Большой 2048'), (1240, 1754, 'Лист A4')];
    final name = TextEditingController(text: kind == 'pixel' ? 'Спрайт ${projects.length + 1}' : 'Рисунок ${projects.length + 1}');
    final pick = await showDialog<(int, int)>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(kind == 'pixel' ? 'Новый пиксель-арт' : 'Новый холст', style: W.h2),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          TextField(controller: name, style: W.body, decoration: const InputDecoration(labelText: 'Название')),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final s in sizes) ActionChip(label: Text(s.$3), onPressed: () => Navigator.pop(ctx, (s.$1, s.$2))),
          ]),
        ]),
      ),
    );
    if (pick == null) return;
    final m = ProjectMeta(Projects.newId(), name.text.trim().isEmpty ? 'Без названия' : name.text.trim(), kind, pick.$1, pick.$2, 0);
    await Projects.saveMeta(m);
    await _open(m);
  }

  Future<void> _menu(ProjectMeta m) async {
    final v = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.edit_outlined), title: const Text('Переименовать'), onTap: () => Navigator.pop(ctx, 'rename')),
          ListTile(leading: const Icon(Icons.delete_outline, color: W.bad), title: const Text('Удалить'), onTap: () => Navigator.pop(ctx, 'delete')),
        ]),
      ),
    );
    if (!mounted) return;
    if (v == 'delete' && await confirmDialog(context, 'Удалить «${m.name}»?', 'Рисунок удалится без возможности восстановления.', ok: 'Удалить')) {
      await Projects.delete(m.id);
      _reload();
    } else if (v == 'rename') {
      final c = TextEditingController(text: m.name);
      final n = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Название', style: W.h2),
          content: TextField(controller: c, autofocus: true, style: W.body),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('OK'))],
        ),
      );
      if (n != null && n.isNotEmpty) {
        m.name = n;
        await Projects.saveMeta(m);
        _reload();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: CustomScrollView(slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                Row(children: [
                  const Expanded(child: Text('Winter Paint', style: W.h1)),
                  PopupMenuButton<String>(
                    tooltip: 'Резервная копия',
                    icon: const Icon(Icons.more_vert),
                    onSelected: (v) => v == 'save' ? _backup() : _restore(),
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'save', child: Text('Сохранить все рисунки в файл')),
                      PopupMenuItem(value: 'restore', child: Text('Восстановить из файла')),
                    ],
                  ),
                ]),
                const Text('Рисуй кистями или создавай пиксельные спрайты с анимацией', style: W.small),
                const SizedBox(height: 16),
                Row(children: [
                  Expanded(child: _bigBtn(Icons.brush, 'Холст', 'Кисти, слои, нажим пера', () => _new('canvas'))),
                  const SizedBox(width: 10),
                  Expanded(child: _bigBtn(Icons.grid_on, 'Пиксель-арт', 'Спрайты, кадры, GIF', () => _new('pixel'))),
                ]),
                if (projects.isNotEmpty) const Section('Мои рисунки'),
                if (projects.isEmpty)
                  const Padding(
                    padding: EdgeInsets.only(top: 40),
                    child: Text('Пока пусто. Начни с холста или пиксель-арта 👆', textAlign: TextAlign.center, style: W.body),
                  ),
              ]),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: SliverGrid(
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(maxCrossAxisExtent: 200, mainAxisSpacing: 10, crossAxisSpacing: 10, childAspectRatio: 0.82),
              delegate: SliverChildBuilderDelegate(
                (ctx, i) {
                  final p = projects[i];
                  final t = thumbs[p.id];
                  return InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () => _open(p),
                    onLongPress: () => _menu(p),
                    onSecondaryTap: () => _menu(p),
                    child: Container(
                      decoration: BoxDecoration(color: W.surface, borderRadius: BorderRadius.circular(12), border: Border.all(color: W.border)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                            child: t == null
                                ? const ColoredBox(color: W.surface2)
                                : Image.memory(t, fit: BoxFit.contain, filterQuality: p.kind == 'pixel' ? FilterQuality.none : FilterQuality.medium),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: W.body.copyWith(fontWeight: FontWeight.w600)),
                            Text('${p.kind == 'pixel' ? 'Пиксель' : 'Холст'} · ${p.w}×${p.h}', style: W.small),
                          ]),
                        ),
                      ]),
                    ),
                  );
                },
                childCount: projects.length,
              ),
            ),
          ),
          if (Platform.isWindows)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Text('Подсказки для ПК: колесо мыши — масштаб, правая или средняя кнопка — двигать холст. Перо графического планшета учитывает нажим.', style: W.small),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _bigBtn(IconData icon, String title, String sub, VoidCallback onTap) => WCard(
        onTap: onTap,
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: W.accent, size: 30),
          const SizedBox(height: 8),
          Text(title, style: W.h2),
          Text(sub, style: W.small),
        ]),
      );
}
