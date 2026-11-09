import 'package:flutter/material.dart';
import 'package:good_frames/models/target_folder.dart';
import 'package:good_frames/state/settings.dart';

/// Lets the user choose (or create) the gallery folder that swiping a photo
/// down files it into. Folders used before are listed to pick again; typing
/// a new name creates the folder when the first photo is moved into it, and
/// typing an existing name uses that folder.
///
/// Remembers the choice in [settings] and returns the folder's name, or null
/// if the user closed the sheet without choosing.
Future<String?> showFolderPicker(BuildContext context, Settings settings) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _FolderSheet(settings: settings),
  );
}

class _FolderSheet extends StatefulWidget {
  const _FolderSheet({required this.settings});

  final Settings settings;

  @override
  State<_FolderSheet> createState() => _FolderSheetState();
}

class _FolderSheetState extends State<_FolderSheet> {
  final _name = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _choose(String folder) async {
    // Applies at once; only saving it can fail, and that isn't worth
    // stopping the user for.
    try {
      await widget.settings.setTargetFolder(folder);
    } catch (_) {}
    if (mounted) Navigator.pop(context, folder);
  }

  void _submitNew() {
    final folder = cleanFolderName(_name.text);
    if (folder == null) {
      setState(() {
        _error =
            'Use a plain name, without slashes or characters like : * ? " '
            '< > |, and not starting with a dot.';
      });
      return;
    }
    _choose(folder);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final current = widget.settings.targetFolder;
    final recent = widget.settings.recentFolders;
    return Padding(
      // Lifts the sheet above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Swipe down into…', style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Photos you swipe down are moved into this folder in your '
                'gallery when you confirm on the Review screen.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              for (final folder in recent)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.folder_outlined),
                  title: Text(folder),
                  trailing: folder == current
                      ? Icon(Icons.check, color: theme.colorScheme.primary)
                      : null,
                  onTap: () => _choose(folder),
                ),
              const SizedBox(height: 8),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.done,
                maxLength: 64,
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _submitNew(),
                decoration: InputDecoration(
                  labelText: 'New or existing folder name',
                  helperText: 'Found in your gallery and file manager as an album',
                  errorText: _error,
                  errorMaxLines: 3,
                  prefixIcon: const Icon(Icons.create_new_folder_outlined),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: _submitNew,
                  child: const Text('Use this folder'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
