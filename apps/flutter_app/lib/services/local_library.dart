import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// Keeps user-selected library roots in app support storage and performs
/// folder operations directly on the selected local filesystem.
class LocalLibrary {
  Future<File> get _index async {
    final support = await getApplicationSupportDirectory();
    return File('${support.path}${Platform.pathSeparator}library-roots.json');
  }

  Future<List<String>> roots() async {
    final index = await _index;
    if (!await index.exists()) return const [];
    final values = jsonDecode(await index.readAsString()) as List<dynamic>;
    return values.cast<String>().where((path) => Directory(path).existsSync()).toList();
  }

  Future<void> addRoot(String path) async {
    final roots = await this.roots();
    if (!roots.contains(path)) roots.add(path);
    await (await _index).writeAsString(jsonEncode(roots), flush: true);
  }

  Future<void> removeRoot(String path) async {
    final roots = await this.roots()..remove(path);
    await (await _index).writeAsString(jsonEncode(roots), flush: true);
  }

  Future<List<FileSystemEntity>> contents(String root) async {
    final entries = await Directory(root).list(followLinks: false).toList();
    entries.sort((a, b) {
      final aFolder = a is Directory;
      final bFolder = b is Directory;
      if (aFolder != bFolder) return aFolder ? -1 : 1;
      return a.uri.pathSegments.last.toLowerCase().compareTo(b.uri.pathSegments.last.toLowerCase());
    });
    return entries;
  }

  Future<Directory> createFolder(String parent, String name) async {
    final safe = _validateName(name);
    final folder = Directory('$parent${Platform.pathSeparator}$safe');
    if (await folder.exists()) throw FileSystemException('A folder with that name already exists.', folder.path);
    return folder.create();
  }

  Future<Directory> renameFolder(Directory folder, String name) async {
    final safe = _validateName(name);
    final destination = Directory('${folder.parent.path}${Platform.pathSeparator}$safe');
    if (await destination.exists()) throw FileSystemException('A folder with that name already exists.', destination.path);
    return folder.rename(destination.path);
  }

  String _validateName(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty || trimmed == '.' || trimmed == '..' || trimmed.contains(RegExp(r'[\\/:*?"<>|]'))) {
      throw const FormatException('Enter a valid folder name.');
    }
    return trimmed;
  }
}
