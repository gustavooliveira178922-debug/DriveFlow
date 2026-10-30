import 'package:flutter/material.dart';

import '../../app/theme.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({required this.onDisconnect, super.key});
  final VoidCallback onDisconnect;

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _selected = 0;
  String _chat = 'Saved Messages';

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
                      PopupMenuButton<String>(onSelected: (value) => setState(() => _chat = value), itemBuilder: (context) => const [PopupMenuItem(value: 'Saved Messages', child: Text('Saved Messages')), PopupMenuItem(value: 'Choose chat…', child: Text('Choose chat…'))], icon: const Icon(Icons.send_rounded, color: DriveFlowTheme.blue))
                    else
                      _ChatButton(chat: _chat, onChanged: (value) => setState(() => _chat = value)),
                    const SizedBox(width: 14),
                    CircleAvatar(backgroundColor: DriveFlowTheme.panelRaised, child: IconButton(tooltip: 'Disconnect', onPressed: widget.onDisconnect, icon: const Icon(Icons.person_outline, size: 19))),
                  ]),
                  const SizedBox(height: 28),
                  Expanded(child: _selected == 3 ? _SettingsView(onDisconnect: widget.onDisconnect) : _OverviewView(chat: _chat)),
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
  const _OverviewView({required this.chat});
  final String chat;

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
          _Panel(title: 'Recent files', action: 'Browse files', child: SizedBox(height: 180, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.insert_drive_file_outlined, size: 30, color: DriveFlowTheme.muted.withValues(alpha: .7)), const SizedBox(height: 10), const Text('Your recent files will show up here', style: TextStyle(fontWeight: FontWeight.w600)), const SizedBox(height: 4), const Text('Add a folder to start building your local index.', style: TextStyle(fontSize: 12, color: DriveFlowTheme.muted))])))),
          const SizedBox(height: 16),
          _Panel(title: 'Transfer queue', action: 'View all', child: SizedBox(height: 160, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.cloud_queue_outlined, size: 30, color: DriveFlowTheme.muted), const SizedBox(height: 10), const Text('Queue is clear', style: TextStyle(fontWeight: FontWeight.w600)), const SizedBox(height: 4), Text('New files will be sent to $chat.', style: const TextStyle(fontSize: 12, color: DriveFlowTheme.muted))])))),
        ] else Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 3, child: _Panel(title: 'Recent files', action: 'Browse files', child: SizedBox(height: 208, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.insert_drive_file_outlined, size: 30, color: DriveFlowTheme.muted.withValues(alpha: .7)), const SizedBox(height: 10), const Text('Your recent files will show up here', style: TextStyle(fontWeight: FontWeight.w600)), const SizedBox(height: 4), const Text('Add a folder to start building your local index.', style: TextStyle(fontSize: 12, color: DriveFlowTheme.muted))])))),
          const SizedBox(width: 18),
          Expanded(flex: 2, child: _Panel(title: 'Transfer queue', action: 'View all', child: SizedBox(height: 208, child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [const Icon(Icons.cloud_queue_outlined, size: 30, color: DriveFlowTheme.muted), const SizedBox(height: 10), const Text('Queue is clear', style: TextStyle(fontWeight: FontWeight.w600)), const SizedBox(height: 4), Text('New files will be sent to $chat.', style: const TextStyle(fontSize: 12, color: DriveFlowTheme.muted))]))))),
        ]),
        const SizedBox(height: 22),
        _DropPanel(chat: chat),
      ]));
  });
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
  const _Panel({required this.title, required this.action, required this.child});
  final String title;
  final String action;
  final Widget child;

  @override
  Widget build(BuildContext context) => Container(padding: const EdgeInsets.fromLTRB(20, 17, 20, 12), decoration: BoxDecoration(color: DriveFlowTheme.panel, borderRadius: BorderRadius.circular(18), border: Border.all(color: DriveFlowTheme.line)), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)), const Spacer(), TextButton(onPressed: () {}, child: Text(action, style: const TextStyle(fontSize: 11, color: DriveFlowTheme.accent)))]), child]));
}

class _DropPanel extends StatelessWidget {
  const _DropPanel({required this.chat});
  final String chat;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final compact = constraints.maxWidth < 500;
        final message = Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [const Text('Add files to DriveFlow', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)), const SizedBox(height: 4), Text('Choose files or drop them here to send to $chat.', style: const TextStyle(fontSize: 12, color: DriveFlowTheme.muted))]);
        final button = OutlinedButton.icon(onPressed: () {}, icon: const Icon(Icons.upload_file_rounded, size: 17), label: const Text('Choose files'), style: OutlinedButton.styleFrom(foregroundColor: DriveFlowTheme.accent, side: const BorderSide(color: DriveFlowTheme.line)));
        return Container(height: compact ? 166 : 124, padding: EdgeInsets.symmetric(horizontal: compact ? 16 : 26, vertical: compact ? 14 : 0), decoration: BoxDecoration(color: DriveFlowTheme.panel.withValues(alpha: .68), borderRadius: BorderRadius.circular(18), border: Border.all(color: DriveFlowTheme.line)), child: compact
            ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Container(width: 42, height: 42, decoration: BoxDecoration(color: DriveFlowTheme.accent.withValues(alpha: .1), borderRadius: BorderRadius.circular(14)), child: const Icon(Icons.add_rounded, color: DriveFlowTheme.accent)), const SizedBox(width: 12), Expanded(child: message)]), const Spacer(), Align(alignment: Alignment.centerRight, child: button)])
            : Row(children: [Container(width: 48, height: 48, decoration: BoxDecoration(color: DriveFlowTheme.accent.withValues(alpha: .1), borderRadius: BorderRadius.circular(15)), child: const Icon(Icons.add_rounded, color: DriveFlowTheme.accent)), const SizedBox(width: 16), Expanded(child: message), button, const SizedBox(width: 22)]));
      });
}

class _Sidebar extends StatelessWidget {
  const _Sidebar({required this.selected, required this.onSelect});
  final int selected;
  final ValueChanged<int> onSelect;
  static const _items = [(Icons.grid_view_rounded, 'Overview'), (Icons.folder_copy_outlined, 'Files'), (Icons.swap_vert_rounded, 'Transfers'), (Icons.tune_rounded, 'Settings')];

  @override
  Widget build(BuildContext context) => Container(width: 220, padding: const EdgeInsets.fromLTRB(18, 22, 14, 18), decoration: const BoxDecoration(border: Border(right: BorderSide(color: DriveFlowTheme.line))), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Container(width: 32, height: 32, decoration: BoxDecoration(color: DriveFlowTheme.accent, borderRadius: BorderRadius.circular(11)), child: const Icon(Icons.cloud_done_rounded, size: 18, color: DriveFlowTheme.background)), const SizedBox(width: 9), const Text('driveflow', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17))]), const SizedBox(height: 42), const Text('WORKSPACE', style: TextStyle(fontSize: 9, color: DriveFlowTheme.muted, letterSpacing: 1.3, fontWeight: FontWeight.w700)), const SizedBox(height: 12), for (var i = 0; i < _items.length; i++) _NavItem(index: i, selected: selected, onSelect: onSelect), const Spacer(), Container(padding: const EdgeInsets.all(13), decoration: BoxDecoration(color: DriveFlowTheme.panel, borderRadius: BorderRadius.circular(14), border: Border.all(color: DriveFlowTheme.line)), child: const Row(children: [Icon(Icons.shield_outlined, size: 17, color: DriveFlowTheme.accent), SizedBox(width: 9), Expanded(child: Text('Private by design\nDirect to Telegram', style: TextStyle(fontSize: 10, height: 1.5, color: DriveFlowTheme.muted)))])), const SizedBox(height: 10), const Padding(padding: EdgeInsets.only(left: 4), child: Text('DRIVEFLOW  ·  1.0.0', style: TextStyle(fontSize: 9, letterSpacing: .7, color: DriveFlowTheme.muted)))]));
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
  const _ChatButton({required this.chat, required this.onChanged});
  final String chat;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => PopupMenuButton<String>(onSelected: onChanged, itemBuilder: (context) => const [PopupMenuItem(value: 'Saved Messages', child: Text('Saved Messages')), PopupMenuItem(value: 'Personal chat', child: Text('Personal chat')), PopupMenuItem(value: 'Choose chat…', child: Text('Choose chat…'))], child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9), decoration: BoxDecoration(color: DriveFlowTheme.panel, borderRadius: BorderRadius.circular(12), border: Border.all(color: DriveFlowTheme.line)), child: Row(children: [const Icon(Icons.send_rounded, color: DriveFlowTheme.blue, size: 15), const SizedBox(width: 8), Text(chat, style: const TextStyle(fontSize: 11)), const SizedBox(width: 8), const Icon(Icons.expand_more, size: 16, color: DriveFlowTheme.muted)])));
}

class _SettingsView extends StatelessWidget {
  const _SettingsView({required this.onDisconnect});
  final VoidCallback onDisconnect;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) => Align(alignment: Alignment.topLeft, child: SizedBox(width: constraints.maxWidth < 620 ? constraints.maxWidth : 620, child: _Panel(title: 'Account & privacy', action: '', child: Column(children: [ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.account_circle_outlined, color: DriveFlowTheme.blue), title: const Text('Telegram account'), subtitle: const Text('Connected account session is managed by TDLib.'), trailing: TextButton(onPressed: onDisconnect, child: const Text('Disconnect'))), const Divider(color: DriveFlowTheme.line), const ListTile(contentPadding: EdgeInsets.zero, leading: Icon(Icons.key_outlined, color: DriveFlowTheme.accent), title: Text('Encrypted local session'), subtitle: Text('TDLib database key should be held in OS secure storage.'))])))));
}
