import 'package:flutter/material.dart';
import 'package:photo_swipe/data/photo_repository.dart';
import 'package:photo_swipe/models/chosen_folder.dart';
import 'package:photo_swipe/theme/glass.dart';
import 'package:photo_swipe/widgets/message_view.dart';

/// The folders Good Frames may see: add more, stop sharing some, or switch to
/// all photos instead.
///
/// Pops with true if the user chose all photos instead (having stopped
/// sharing every folder), so the screen behind can ask for that access.
class ManageFoldersScreen extends StatefulWidget {
  const ManageFoldersScreen({super.key, required this.folders});

  final ChosenFoldersRepository folders;

  @override
  State<ManageFoldersScreen> createState() => _ManageFoldersScreenState();
}

class _ManageFoldersScreenState extends State<ManageFoldersScreen> {
  late Future<List<ChosenFolder>> _list = widget.folders.chosenFolders();
  bool _working = false;

  void _reload() {
    setState(() {
      _list = widget.folders.chosenFolders();
    });
  }

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _working = true);
    try {
      await action();
    } finally {
      if (mounted) {
        _working = false;
        _reload();
      }
    }
  }

  Future<void> _add() => _run(() async {
    await widget.folders.chooseFolder();
  });

  Future<void> _remove(ChosenFolder folder) =>
      _run(() => widget.folders.forgetFolder(folder));

  Future<void> _useAllPhotos() async {
    setState(() => _working = true);
    for (final folder in await widget.folders.chosenFolders()) {
      await widget.folders.forgetFolder(folder);
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Folders')),
      body: FutureBuilder(
        future: _list,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return MessageView(
              'Could not list the folders.\n${snapshot.error}',
            );
          }
          final folders = snapshot.data;
          if (folders == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (folders.isEmpty) {
            return const MessageView(
              'No folders shared. Add one, or go back to choose all photos.',
            );
          }
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            children: [
              Glass(
                child: Material(
                  type: MaterialType.transparency,
                  child: Column(
                    children: [
                      for (final folder in folders)
                        ListTile(
                          leading: const Icon(Icons.folder_outlined),
                          title: Text(folder.name),
                          subtitle: Text(folder.path),
                          trailing: IconButton(
                            onPressed: _working ? null : () => _remove(folder),
                            icon: const Icon(Icons.close),
                            tooltip: 'Stop sharing ${folder.name}',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              // Below the folders, so with large text they still come first.
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
                child: Text(
                  'Good Frames can see these folders and the folders inside '
                  'them, and nothing else on this phone.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: GlassBar(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton.icon(
              onPressed: _working ? null : _add,
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('Add a folder'),
            ),
            const SizedBox(height: 4),
            TextButton(
              onPressed: _working ? null : _useAllPhotos,
              child: const Text('Use all photos instead'),
            ),
          ],
        ),
      ),
    );
  }
}
