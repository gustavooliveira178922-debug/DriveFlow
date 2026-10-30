import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:desktop_drop/desktop_drop.dart';

import '../../app/theme.dart';
import '../../services/native_bridge.dart';
import '../../services/telegram_service.dart';
import '../../services/local_library.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({required this.onDisconnect, super.key});
  final VoidCallback onDisconnect;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selected = 0;
  final _telegram = TelegramService(NativeBridge.load());
  List<TelegramChat> _chats = const [];
  int? _selectedChatId;
  Timer? _chatPoller;

  String get _chat {
    for (final chat in _chats) {
      if (chat.id == _selectedChatId) return chat.title;
    }
    return 'Saved Messages';
  }

  @override
  void initState() {
    super.initState();
    _refreshChats();
    _chatPoller = Timer.periodic(const Duration(seconds: 1), (_) => _refreshChats());
  }

  @override
  void dispose() {
    _chatPoller?.cancel();
    super.dispose();
  }

  Future<void> _refreshChats() async {
    try {
      final chats = await _telegram.fetchPersonalChats();
      if (!mounted) return;
      setState(() {
        _chats = chats;
        if (_selectedChatId == null && chats.isNotEmpty) _selectedChatId = chats.first.id;
      });
    } on Object {
      // TDLib may still be loading chat-list updates just after authorization.
    }
  }

  Future<void> _chooseFiles() async {
    await _chooseFilesForFolder('');
  }

  Future<void> _chooseFilesForFolder(String folderId) async {
    if (_selectedChatId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose a personal chat first.')));
      return;
    }
    final result = await FilePicker.platform.pickFiles(allowMultiple: true, withData: false);
    if (result == null || !mounted) return;
    await _sendPaths(result.files.map((file) => file.path).whereType<String>().toList(), folderId: folderId);
  }

  Future<void> _sendPaths(List<String> paths, {String folderId = ''}) async {
    if (_selectedChatId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Choose a personal chat first.')));
      return;
    }
    var sent = 0;
    // Keep two files preparing/sending at once so TDLib can overlap local
    // reads and network uploads without turning a multi-file drop into an
    // unbounded burst of disk work.
    for (var offset = 0; offset < paths.length; offset += 2) {
      final batch = paths.skip(offset).take(2).toList();
      try {
        await Future.wait(batch.map((path) => _telegram.sendFile(chatId: _selectedChatId!, path: path, folderId: folderId)));
        sent += batch.length;
      } on Object catch (error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not queue ${batch.map((path) => File(path).uri.pathSegments.last).join(', ')}: $error')));
        return;
      }
    }
    if (mounted && sent > 0) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Added $sent file(s) to the send queue for $_chat.')));
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        return Scaffold(
          body: SafeArea(
            child: Column(children: [
              Expanded(child: Row(children: [
                if (!compact) _Sidebar(selected: _selected, onSelect: (value) => setState(() => _selected = value)),
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(compact ? 16 : 32, 20, compact ? 16 : 32, 20),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_selected == 0 ? 'Overview' : const ['Overview', 'Files', 'Transfers', 'Settings'][_selected], style: Theme.of(context).textTheme.headlineMedium), const SizedBox(height: 5), const Text('Your personal cloud, in one place.', style: TextStyle(color: DriveFlowTheme.muted))])),
                    if (compact)
                      _ChatButton(chat: _chat, chats: _chats, onChanged: (value) => setState(() => _selectedChatId = value), compact: true)
                    else
                      _ChatButton(chat: _chat, chats: _chats, onChanged: (value) => setState(() => _selectedChatId = value)),
                    const SizedBox(width: 14),
                    CircleAvatar(backgroundColor: DriveFlowTheme.panelRaised, child: IconButton(tooltip: 'Disconnect', onPressed: widget.onDisconnect, icon: const Icon(Icons.person_outline, size: 19))),
                  ]),
                  const SizedBox(height: 28),
                  Expanded(child: _selected == 1
                      ? _FilesView(telegram: _telegram, chatId: _selectedChatId, onUploadToFolder: _chooseFilesForFolder)
                      : _selected == 3
                          ? _SettingsView(onDisconnect: widget.onDisconnect)
                          : _OverviewView(chat: _chat, canSend: _selectedChatId != null, onChooseFiles: _chooseFiles, onDropFiles: _sendPaths)),
                    ]),
                  ),
                ),
              ])),
              if (compact) NavigationBar(height: 64, selectedIndex: _selected, onDestinationSelected: (value) => setState(() => _selected = value), destinations: const [
                NavigationDestination(icon: Icon(Icons.grid_view_rounded), label: 'Home'),
                NavigationDestination(icon: Icon(Icons.folder_copy_outlined), label: 'Files'),
                NavigationDestination(icon: Icon(Icons.swap_vert_rounded), label: 'Transfers'),
                NavigationDestination(icon: Icon(Icons.tune_rounded), label: 'Settings'),
              ]),
            ]),
          ),
        );
      });
}

class _OverviewView extends StatelessWidget {
  const _OverviewView({required this.chat, required this.canSend, required this.onChooseFiles, required this.onDropFiles});
  final String chat;
  final bool canSend;
  final VoidCallback onChooseFiles;
  final ValueChanged<List<String>> onDropFiles;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
    final compact = constraints.maxWidth < 820;
    final cardWidth = compact ? constraints.maxWidth : (constraints.maxWidth - 32) / 3;
    return SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 16, runSpacing: 16, children: [
          SizedBox(width: cardWidth, child: _StorageCard()),
          SizedBox(width: cardWidth, child: const _StatCard(icon: Icons.folder_open_rounded, label: 'Indexed files', value: '0', hint: 'No local folders indexed', color: DriveFlowTheme.blue)),
          SizedBox(width: cardWidth, child: const _StatCard(icon: Icons.swap_vert_rounded, label: 'Transfers', value: '0', hint: 'Nothing in progress', color: Color(0xFFBE9AFF))),
        ]),
        const SizedBox(height: 22),
        if (compact) ...[
          _RecentFilesPanel(height: 180),
          const SizedBox(height: 16),
          _TransferQueuePanel(chat: chat, height: 160),
        ] else Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 3, child: _RecentFilesPanel(height: 208)),
          const SizedBox(width: 18),
          Expanded(flex: 2, child: _TransferQueuePanel(chat: chat, height: 208)),
        ]),
        const SizedBox(height: 22),
        _DropPanel(chat: chat, canSend: canSend, onChooseFiles: onChooseFiles, onDropFiles: onDropFiles),
      ]));
  });
}

class _RecentFilesPanel extends StatelessWidget {
  const _RecentFilesPanel({required this.height});
  final double height;

  @override
  Widget build(BuildContext context) => _Panel(
        title: 'Recent files',
        action: 'Browse files',
        child: SizedBox(
          height: height,
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.insert_drive_file_outlined, size: 30, color: DriveFlowTheme.muted.withValues(alpha: .7)),
              const SizedBox(height: 10),
              const Text('Your recent files will show up here', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              const Text('Add a folder to start building your local index.', style: TextStyle(fontSize: 12, color: DriveFlowTheme.muted)),
            ]),
          ),
        ),
      );
}

class _TransferQueuePanel extends StatelessWidget {
  const _TransferQueuePanel({required this.chat, required this.height});
  final String chat;
  final double height;

  @override
  Widget build(BuildContext context) => _Panel(
        title: 'Transfer queue',
        action: 'View all',
        child: SizedBox(
          height: height,
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.cloud_queue_outlined, size: 30, color: DriveFlowTheme.muted),
              const SizedBox(height: 10),
              const Text('Queue is clear', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('New files will be sent to $chat.', style: const TextStyle(fontSize: 12, color: DriveFlowTheme.muted)),
            ]),
          ),
        ),
      );
}

class _StorageCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Container(height: 132, padding: const EdgeInsets.all(20), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFF173A37), Color(0xFF152621)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(18), border: Border.all(color: DriveFlowTheme.accent.withValues(alpha: .2))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [const Icon(Icons.cloud_outlined, size: 18, color: DriveFlowTheme.accent), const SizedBox(width: 8), const Text('Telegram storage', style: TextStyle(color: Color(0xFFBCD8D0), fontSize: 12)), const Spacer(), Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), decoration: BoxDecoration(color: DriveFlowTheme.accent.withValues(alpha: .12), borderRadius: BorderRadius.circular(20)), child: const Text('CONNECTED', style: TextStyle(color: DriveFlowTheme.accent, fontSize: 9, letterSpacing: .8, fontWeight: FontWeight.w700)))]),
        const Spacer(),
        const Text('Ready for your files', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 17)),
        const SizedBox(height: 3),
        const Text('Messages go directly to your Telegram chat', style: TextStyle(color: Color(0xFF91AAA2), fontSize: 11)),
      ]));
}

class _StatCard extends StatelessWidget {
  const _StatCard({required this.icon, required this.label, required this.value, required this.hint, required this.color});
  final IconData icon;
  final String label;
  final String value;
  final String hint;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(height: 132, padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: DriveFlowTheme.panel, borderRadius: BorderRadius.circular(18), border: Border.all(color: DriveFlowTheme.line)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Icon(icon, size: 17, color: color), const SizedBox(width: 8), Text(label, style: const TextStyle(color: DriveFlowTheme.muted, fontSize: 12))]), const Spacer(), Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700)), Text(hint, style: const TextStyle(fontSize: 10, color: DriveFlowTheme.muted))]));
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.action, required this.child, this.onAction});
  final String title;
  final String action;
  final Widget child;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.fromLTRB(20, 17, 20, 12), decoration: BoxDecoration(color: DriveFlowTheme.panel, borderRadius: BorderRadius.circular(18), border: Border.all(color: DriveFlowTheme.line)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)), const Spacer(), if (action.isNotEmpty) TextButton(onPressed: onAction, child: Text(action, style: const TextStyle(fontSize: 11, color: DriveFlowTheme.accent)))]), child]));
}

class _DropPanel extends StatefulWidget {
  const _DropPanel({required this.chat, required this.canSend, required this.onChooseFiles, required this.onDropFiles});
  final String chat;
  final bool canSend;
  final VoidCallback onChooseFiles;
  final ValueChanged<List<String>> onDropFiles;

  @override
  State<_DropPanel> createState() => _DropPanelState();
}

class _DropPanelState extends State<_DropPanel> {
  bool _dragging = false;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxWidth < 500;
        final message = Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Add files to DriveFlow', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)), const SizedBox(height: 4), Text('Choose files or drop them here to send to ${widget.chat}.', style: const TextStyle(fontSize: 12, color: DriveFlowTheme.muted))]);
        final button = OutlinedButton.icon(onPressed: widget.canSend ? widget.onChooseFiles : null, icon: const Icon(Icons.upload_file_rounded, size: 17), label: const Text('Choose files'), style: OutlinedButton.styleFrom(foregroundColor: DriveFlowTheme.accent, side: const BorderSide(color: DriveFlowTheme.line)));
        return DropTarget(
          onDragEntered: (_) => setState(() => _dragging = true),
          onDragExited: (_) => setState(() => _dragging = false),
          onDragDone: (details) {
            setState(() => _dragging = false);
            widget.onDropFiles(details.files.map((file) => file.path).where((path) => path.isNotEmpty).toList());
          },
          child: AnimatedContainer(duration: const Duration(milliseconds: 160), height: compact ? 166 : 124, padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 26, vertical: compact ? 14 : 0), decoration: BoxDecoration(color: _dragging ? DriveFlowTheme.accent.withValues(alpha: .12) : DriveFlowTheme.panel.withValues(alpha: .68), borderRadius: BorderRadius.circular(18), border: Border.all(color: _dragging ? DriveFlowTheme.accent : DriveFlowTheme.line, width: _dragging ? 1.5 : 1)), child: compact
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Container(width: 42, height: 42, decoration: BoxDecoration(color: DriveFlowTheme.accent.withValues(alpha: .1), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.add_rounded, color: DriveFlowTheme.accent)), const SizedBox(width: 12), Expanded(child: message)]), const Spacer(), Align(alignment: Alignment.centerRight, child: button)])
            : Row(children: [Container(width: 48, height: 48, decoration: BoxDecoration(color: DriveFlowTheme.accent.withValues(alpha: .1), borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.add_rounded, color: DriveFlowTheme.accent)), const SizedBox(width: 16), Expanded(child: message), button, const SizedBox(width: 22)])),
        );
      });
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.selected, required this.onSelect});
  final int selected;
  final ValueChanged<int> onSelect;
  static const _items = [(Icons.grid_view_rounded, 'Overview'), (Icons.folder_copy_outlined, 'Files'), (Icons.swap_vert_rounded, 'Transfers'), (Icons.tune_rounded, 'Settings')];

  @override
  Widget build(BuildContext context) => Container(width: 220, padding: const EdgeInsets.fromLTRB(18, 22, 14, 18), decoration: const BoxDecoration(border: Border(right: BorderSide(color: DriveFlowTheme.line))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Container(width: 32, height: 32, decoration: BoxDecoration(color: DriveFlowTheme.accent, borderRadius: BorderRadius.circular(11)), child: const Icon(Icons.cloud_done_rounded, size: 18, color: DriveFlowTheme.background)), const SizedBox(width: 9), const Text('driveflow', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17))]), const SizedBox(height: 42), const Text('WORKSPACE', style: TextStyle(fontSize: 9, color: DriveFlowTheme.muted, letterSpacing: 1.3, fontWeight: FontWeight.w700)), const SizedBox(height: 12), for (var i = 0; i < _items.length; i++) _NavItem(index: i, selected: selected, onSelect: onSelect), const Spacer(), Container(padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: DriveFlowTheme.panel, borderRadius: BorderRadius.circular(14), border: Border.all(color: DriveFlowTheme.line)), child: const Row(children: [Icon(Icons.shield_outlined, size: 17, color: DriveFlowTheme.accent), SizedBox(width: 9), Expanded(child: Text('Private by design\nDirect to Telegram', style: TextStyle(fontSize: 10, height: 1.5, color: DriveFlowTheme.muted)))])), const SizedBox(height: 10), const Padding(padding: EdgeInsets.only(left: 4), child: Text('DRIVEFLOW  ·  1.0.15', style: TextStyle(fontSize: 9, letterSpacing: .7, color: DriveFlowTheme.muted)))]));
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.index, required this.selected, required this.onSelect});
  final int index;
  final int selected;
  final ValueChanged<int> onSelect;
  static const items = _Sidebar._items;

  @override
  Widget build(BuildContext context) {
    final active = selected == index;
    return Padding(padding: const EdgeInsets.only(bottom: 5), child: InkWell(borderRadius: BorderRadius.circular(11), onTap: () => onSelect(index), child: AnimatedContainer(duration: const Duration(milliseconds: 180), padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10), decoration: BoxDecoration(color: active ? DriveFlowTheme.accent.withValues(alpha: .1) : Colors.transparent, borderRadius: BorderRadius.circular(11)), child: Row(children: [Icon(items[index].$1, size: 17, color: active ? DriveFlowTheme.accent : DriveFlowTheme.muted), const SizedBox(width: 11), Text(items[index].$2, style: TextStyle(fontSize: 12, color: active ? DriveFlowTheme.accent : DriveFlowTheme.muted, fontWeight: active ? FontWeight.w600 : FontWeight.w400))]))));
  }
}

class _ChatButton extends StatelessWidget {
  const _ChatButton({required this.chat, required this.chats, required this.onChanged, this.compact = false});
  final String chat;
  final List<TelegramChat> chats;
  final ValueChanged<int> onChanged;
  final bool compact;

  @override
  Widget build(BuildContext context) => PopupMenuButton<int>(onSelected: onChanged, itemBuilder: (context) => chats.map((item) => PopupMenuItem(value: item.id, child: Text(item.title, overflow: TextOverflow.ellipsis))).toList(), icon: compact ? const Icon(Icons.send_rounded, color: DriveFlowTheme.blue) : null, child: compact ? null : Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9), decoration: BoxDecoration(color: DriveFlowTheme.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: DriveFlowTheme.line)), child: Row(children: [const Icon(Icons.send_rounded, color: DriveFlowTheme.blue, size: 15), const SizedBox(width: 8), Text(chat, style: const TextStyle(fontSize: 11)), const SizedBox(width: 8), const Icon(Icons.expand_more, size: 16, color: DriveFlowTheme.muted)])));
}

class _SettingsView extends StatelessWidget {
  const _SettingsView({required this.onDisconnect});
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) => Align(alignment: Alignment.topLeft, child: SizedBox(width: constraints.maxWidth < 620 ? constraints.maxWidth : 620, child: _Panel(title: 'Account & privacy', action: '', child: Column(children: [ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.account_circle_outlined, color: DriveFlowTheme.blue), title: const Text('Telegram account'), subtitle: const Text('Connected account session is managed by TDLib.'), trailing: TextButton(onPressed: onDisconnect, child: const Text('Disconnect'))), const Divider(color: DriveFlowTheme.line), const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.key_outlined, color: DriveFlowTheme.accent), title: Text('Encrypted local session'), subtitle: Text('TDLib database key should be held in OS secure storage.'))])))));
}

class _FilesView extends StatefulWidget {
  const _FilesView({required this.telegram, required this.chatId, required this.onUploadToFolder});
  final TelegramService telegram;
  final int? chatId;
  final ValueChanged<String> onUploadToFolder;

  @override
  State<_FilesView> createState() => _FilesViewState();
}

class _FilesViewState extends State<_FilesView> {
  final _library = LocalLibrary();
  List<String> _roots = const [];
  String? _root;
  List<FileSystemEntity> _items = const [];
  List<TelegramRemoteFile> _remoteFiles = const [];
  List<TelegramRemoteFolder> _remoteFolders = const [];
  String _remoteFolderPath = '';
  final Map<int, String> _pendingSaveDirectories = {};
  final Map<int, String> _pendingMerges = {};
  final Set<int> _requestedMergeParts = {};
  Timer? _remotePoller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reloadRoots();
    _refreshRemoteFiles();
    _remotePoller = Timer.periodic(const Duration(seconds: 2), (_) => _refreshRemoteFiles());
  }

  @override
  void didUpdateWidget(covariant _FilesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chatId != widget.chatId) {
      _remoteFiles = const [];
      _refreshRemoteFiles();
    }
  }

  @override
  void dispose() {
    _remotePoller?.cancel();
    super.dispose();
  }

  Future<void> _refreshRemoteFiles() async {
    final chatId = widget.chatId;
    if (chatId == null) return;
    try {
      final snapshot = await widget.telegram.fetchChatFiles(chatId);
      if (!mounted) return;
      setState(() {
        _remoteFiles = snapshot.files;
        _remoteFolders = snapshot.folders;
      });
      for (final file in snapshot.files) {
        final directory = _pendingSaveDirectories[file.id];
        if (!file.downloaded || directory == null || file.localPath.isEmpty) continue;
        _pendingSaveDirectories.remove(file.id);
        await _copyDownloadedFile(file, directory);
      }
      for (final entry in _pendingMerges.entries.toList()) {
        final manifestFile = _findRemote(snapshot.files, (file) => file.id == entry.key);
        if (manifestFile == null || !manifestFile.downloaded || manifestFile.localPath.isEmpty) continue;
        if (!_requestedMergeParts.contains(entry.key)) {
          await _requestManifestParts(manifestFile, entry.value, snapshot.files);
          continue;
        }
        final manifest = jsonDecode(await File(manifestFile.localPath).readAsString()) as Map<String, dynamic>;
        final names = (manifest['parts'] as List<dynamic>).cast<String>();
        final partFiles = names.map((name) => _findRemote(snapshot.files, (file) => file.name == name)).toList();
        if (partFiles.any((part) => part == null || !part.downloaded || part.localPath.isEmpty)) continue;
        _pendingMerges.remove(entry.key);
        _requestedMergeParts.remove(entry.key);
        final result = await widget.telegram.joinParts(manifestPath: manifestFile.localPath, selectedPartPaths: partFiles.cast<TelegramRemoteFile>().map((part) => part.localPath).toList(), outputDirectory: entry.value);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Rebuilt complete file: $result')));
      }
    } on Object {
      // TDLib may still be filling the selected chat's history.
    }
  }

  Future<void> _saveRemoteFile(TelegramRemoteFile file) async {
    final directory = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Choose where to save ${file.name}');
    if (directory == null) return;
    if (file.name.toLowerCase().endsWith('.driveflow.json')) {
      _pendingMerges[file.id] = directory;
      if (file.downloaded && file.localPath.isNotEmpty) {
        await _requestManifestParts(file, directory, _remoteFiles);
      } else {
        try {
          await widget.telegram.downloadFile(file.id);
          if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Downloading the manifest; DriveFlow will fetch and join every part automatically.')));
        } on Object catch (error) {
          _pendingMerges.remove(file.id);
          _showError(error);
        }
      }
      return;
    }
    if (file.downloaded && file.localPath.isNotEmpty) {
      await _copyDownloadedFile(file, directory);
      return;
    }
    _pendingSaveDirectories[file.id] = directory;
    try {
      await widget.telegram.downloadFile(file.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Downloading ${file.name} from Telegram…')));
    } on Object catch (error) {
      _pendingSaveDirectories.remove(file.id);
      _showError(error);
    }
  }

  Future<void> _requestManifestParts(TelegramRemoteFile manifestFile, String directory, List<TelegramRemoteFile> available) async {
    try {
      final manifest = jsonDecode(await File(manifestFile.localPath).readAsString()) as Map<String, dynamic>;
      if (manifest['format'] != 'driveflow-parts-v1') throw const FormatException('This is not a DriveFlow recovery manifest.');
      final names = (manifest['parts'] as List<dynamic>).cast<String>();
      final byName = {for (final file in available) file.name: file};
      final parts = names.map((name) => byName[name]).toList();
      if (parts.any((part) => part == null)) throw StateError('This chat is missing one or more parts for this file.');
      _requestedMergeParts.add(manifestFile.id);
      for (final part in parts.cast<TelegramRemoteFile>()) {
        if (!part.downloaded && !part.downloading) await widget.telegram.downloadFile(part.id);
      }
      if (parts.every((part) => part!.downloaded)) {
        _pendingMerges.remove(manifestFile.id);
        _requestedMergeParts.remove(manifestFile.id);
        final output = await widget.telegram.joinParts(manifestPath: manifestFile.localPath, selectedPartPaths: parts.cast<TelegramRemoteFile>().map((part) => part.localPath).toList(), outputDirectory: directory);
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Rebuilt complete file: $output')));
      }
    } on Object catch (error) {
      _pendingMerges.remove(manifestFile.id);
      _requestedMergeParts.remove(manifestFile.id);
      _showError(error);
    }
  }

  Future<void> _copyDownloadedFile(TelegramRemoteFile file, String directory) async {
    final destination = File('$directory${Platform.pathSeparator}${file.name}');
    try {
      if (await destination.exists()) throw StateError('A file named ${file.name} already exists in that folder.');
      await File(file.localPath).copy(destination.path);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved ${file.name}')));
    } on Object catch (error) { _showError(error); }
  }

  Future<void> _reloadRoots() async {
    final roots = await _library.roots();
    if (!mounted) return;
    setState(() {
      _roots = roots;
      _root = roots.contains(_root) ? _root : (roots.isEmpty ? null : roots.first);
      _loading = false;
    });
    await _reloadContents();
  }

  Future<void> _reloadContents() async {
    final root = _root;
    if (root == null) {
      if (mounted) setState(() => _items = const []);
      return;
    }
    try {
      final items = await _library.contents(root);
      if (mounted) setState(() => _items = items);
    } on Object catch (error) {
      _showError(error);
    }
  }

  List<String> _remoteChildFolderPaths() {
    final paths = <String>{
      ..._remoteFolders.map((folder) => folder.path),
      ..._remoteFiles.map((file) => file.folderPath),
    }..removeWhere((path) => path.isEmpty);
    final current = _remoteFolderPath.isEmpty ? const <String>[] : _remoteFolderPath.split('/');
    final children = <String>{};
    for (final path in paths) {
      final parts = path.split('/');
      if (parts.length <= current.length || !List.generate(current.length, (i) => parts[i] == current[i]).every((same) => same)) continue;
      children.add([...current, parts[current.length]].join('/'));
    }
    return children.toList()..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  }

  String _folderIdForPath(String path) {
    for (final folder in _remoteFolders) {
      if (folder.path == path) return folder.id;
    }
    return '';
  }

  Future<void> _createRemoteFolder() async {
    final chatId = widget.chatId;
    if (chatId == null) return;
    final name = await _askName('Create Telegram folder');
    if (name == null || name.trim().isEmpty) return;
    final safeName = name.trim().replaceAll('/', '-').replaceAll('\\', '-');
    final path = _remoteFolderPath.isEmpty ? safeName : '$_remoteFolderPath/$safeName';
    try {
      widget.telegram.createFolder(chatId, path);
      await _refreshRemoteFiles();
    } on Object catch (error) { _showError(error); }
  }

  Future<void> _renameRemoteFolder(String oldPath) async {
    final chatId = widget.chatId;
    if (chatId == null) return;
    final oldName = oldPath.split('/').last;
    final name = await _askName('Rename Telegram folder', initial: oldName);
    if (name == null || name.trim().isEmpty) return;
    final safeName = name.trim().replaceAll('/', '-').replaceAll('\\', '-');
    final parent = oldPath.contains('/') ? oldPath.substring(0, oldPath.lastIndexOf('/')) : '';
    final newPath = parent.isEmpty ? safeName : '$parent/$safeName';
    if (newPath == oldPath) return;
    try {
      final snapshot = TelegramChatFiles(files: _remoteFiles, folders: _remoteFolders);
      await widget.telegram.renameFolder(chatId, oldPath, newPath, snapshot);
      if (_remoteFolderPath == oldPath || _remoteFolderPath.startsWith('$oldPath/')) {
        setState(() => _remoteFolderPath = newPath + _remoteFolderPath.substring(oldPath.length));
      }
      await _refreshRemoteFiles();
    } on Object catch (error) { _showError(error); }
  }

  Future<void> _addRoot() async {
    final path = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Choose a DriveFlow folder');
    if (path == null) return;
    await _library.addRoot(path);
    if (!mounted) return;
    setState(() => _root = path);
    await _reloadRoots();
  }

  Future<String?> _askName(String title, {String initial = ''}) async {
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(context: context, builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(controller: controller, autofocus: true, decoration: const InputDecoration(labelText: 'Folder name'), onSubmitted: (value) => Navigator.pop(context, value)),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save'))],
    ));
    controller.dispose();
    return result;
  }

  Future<void> _createFolder() async {
    final root = _root;
    if (root == null) return;
    final name = await _askName('Create folder');
    if (name == null || name.trim().isEmpty) return;
    try {
      await _library.createFolder(root, name);
      await _reloadContents();
    } on Object catch (error) { _showError(error); }
  }

  Future<void> _renameFolder(Directory directory) async {
    final name = await _askName('Rename folder', initial: directory.uri.pathSegments.where((e) => e.isNotEmpty).last);
    if (name == null || name.trim().isEmpty) return;
    try {
      await _library.renameFolder(directory, name);
      await _reloadContents();
    } on Object catch (error) { _showError(error); }
  }

  Future<void> _removeRoot(String root) async {
    await _library.removeRoot(root);
    await _reloadRoots();
  }

  Future<void> _joinParts() async {
    try {
      final manifest = await FilePicker.platform.pickFiles(dialogTitle: 'Choose the DriveFlow recovery manifest', type: FileType.custom, allowedExtensions: ['json'], allowMultiple: false);
      final manifestPath = manifest?.files.single.path;
      if (manifestPath == null) return;
      final parts = await FilePicker.platform.pickFiles(dialogTitle: 'Select every part listed in the manifest', allowMultiple: true);
      if (parts == null) return;
      final outputDirectory = await FilePicker.platform.getDirectoryPath(dialogTitle: 'Choose where to save the reconstructed file');
      if (outputDirectory == null) return;
      final result = await widget.telegram.joinParts(manifestPath: manifestPath, selectedPartPaths: parts.files.map((file) => file.path).whereType<String>().toList(), outputDirectory: outputDirectory);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Rebuilt file: $result')));
    } on Object catch (error) { _showError(error); }
  }

  void _showError(Object error) {
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(error.toString())));
  }

  String _name(FileSystemEntity item) => item.uri.pathSegments.where((part) => part.isNotEmpty).last;
  String _rootLabel(String path) {
    final segments = Directory(path).uri.pathSegments.where((part) => part.isNotEmpty).toList();
    return segments.isEmpty ? path : segments.last;
  }
  TelegramRemoteFile? _findRemote(List<TelegramRemoteFile> files, bool Function(TelegramRemoteFile) test) {
    for (final file in files) { if (test(file)) return file; }
    return null;
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(child: _Panel(title: 'Files & folders', action: 'Refresh local files', onAction: _reloadContents, child: _loading
      ? const SizedBox(height: 180, child: Center(child: CircularProgressIndicator()))
      : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Expanded(child: Text('Telegram cloud folders', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
            IconButton(tooltip: 'Refresh Telegram files', onPressed: _refreshRemoteFiles, icon: const Icon(Icons.refresh_rounded, size: 18)),
          ]),
          Text(_remoteFolderPath.isEmpty ? 'Saved Messages /' : 'Saved Messages / $_remoteFolderPath', style: const TextStyle(color: DriveFlowTheme.muted, fontSize: 11)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonalIcon(onPressed: widget.chatId == null ? null : _createRemoteFolder, icon: const Icon(Icons.create_new_folder_outlined, size: 17), label: const Text('New cloud folder')),
            OutlinedButton.icon(onPressed: widget.chatId == null ? null : () => widget.onUploadToFolder(_folderIdForPath(_remoteFolderPath)), icon: const Icon(Icons.upload_file_rounded, size: 17), label: const Text('Upload here')),
            if (_remoteFolderPath.isNotEmpty)
              TextButton.icon(onPressed: () => setState(() => _remoteFolderPath = _remoteFolderPath.contains('/') ? _remoteFolderPath.substring(0, _remoteFolderPath.lastIndexOf('/')) : ''), icon: const Icon(Icons.arrow_upward_rounded, size: 16), label: const Text('Up')),
          ]),
          if (widget.chatId == null) const Padding(padding: EdgeInsets.symmetric(vertical: 18), child: Text('Connect Telegram to organize files in Saved Messages.', style: TextStyle(color: DriveFlowTheme.muted)))
          else ...[
            for (final folderPath in _remoteChildFolderPaths())
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_rounded, color: DriveFlowTheme.accent),
                title: Text(folderPath.split('/').last, overflow: TextOverflow.ellipsis),
                subtitle: const Text('Telegram folder', style: TextStyle(color: DriveFlowTheme.muted, fontSize: 11)),
                onTap: () => setState(() => _remoteFolderPath = folderPath),
                trailing: IconButton(tooltip: 'Rename cloud folder', onPressed: () => _renameRemoteFolder(folderPath), icon: const Icon(Icons.edit_outlined, size: 18)),
              ),
            for (final file in _remoteFiles.where((file) => file.folderPath == _remoteFolderPath))
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.cloud_download_outlined, color: DriveFlowTheme.blue),
                title: Text(file.name, overflow: TextOverflow.ellipsis),
                subtitle: Text(file.downloaded ? 'Downloaded · ${_formatBytes(file.size)}' : file.downloading ? 'Downloading · ${_formatBytes(file.size)}' : _formatBytes(file.size), style: const TextStyle(color: DriveFlowTheme.muted, fontSize: 11)),
                trailing: IconButton(tooltip: 'Save file to this device', onPressed: file.downloading ? null : () => _saveRemoteFile(file), icon: Icon(file.downloaded ? Icons.save_alt_rounded : Icons.download_rounded, size: 19)),
              ),
            if (_remoteChildFolderPaths().isEmpty && !_remoteFiles.any((file) => file.folderPath == _remoteFolderPath))
              const Padding(padding: EdgeInsets.symmetric(vertical: 18), child: Text('This Telegram folder is empty.', style: TextStyle(color: DriveFlowTheme.muted))),
          ],
          const Divider(color: DriveFlowTheme.line, height: 28),
          const Text('This device', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
            for (final root in _roots)
              InputChip(label: Text(_rootLabel(root), overflow: TextOverflow.ellipsis), selected: root == _root, onPressed: () async { setState(() => _root = root); await _reloadContents(); }, onDeleted: () => _removeRoot(root)),
            OutlinedButton.icon(onPressed: _addRoot, icon: const Icon(Icons.add_rounded, size: 16), label: const Text('Add folder')),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            FilledButton.tonalIcon(onPressed: _root == null ? null : _createFolder, icon: const Icon(Icons.create_new_folder_outlined, size: 17), label: const Text('New folder')),
            OutlinedButton.icon(onPressed: _joinParts, icon: const Icon(Icons.unarchive_outlined, size: 17), label: const Text('Rebuild split file')),
          ]),
          const SizedBox(height: 12),
          if (_root == null) const Padding(padding: EdgeInsets.symmetric(vertical: 44), child: Center(child: Text('Add a local folder to organize and rename folders here.', textAlign: TextAlign.center, style: TextStyle(color: DriveFlowTheme.muted))))
          else if (_items.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 32), child: Center(child: Text('This folder is empty.', style: TextStyle(color: DriveFlowTheme.muted))))
          else for (final item in _items)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(item is Directory ? Icons.folder_rounded : Icons.insert_drive_file_outlined, color: item is Directory ? DriveFlowTheme.accent : DriveFlowTheme.blue),
              title: Text(_name(item), overflow: TextOverflow.ellipsis),
              subtitle: Text(item is Directory ? 'Folder' : 'Local file', style: const TextStyle(color: DriveFlowTheme.muted, fontSize: 11)),
              trailing: item is Directory ? IconButton(tooltip: 'Rename folder', onPressed: () => _renameFolder(item), icon: const Icon(Icons.edit_outlined, size: 18)) : null,
            ),
        ]),
  ));

  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    if (bytes >= 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / 1024).toStringAsFixed(0)} KB';
  }
}
