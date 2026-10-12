import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/spotify_import_service.dart';
import '../services/spotify_service.dart';
import '../services/youtube_service.dart';

/// Where and how a Spotify playlist should be saved.
class SpotifyFolderChoice {
  const SpotifyFolderChoice({
    required this.folderName,
    required this.reconnect,
  });

  final String folderName;

  /// True when the playlist should reuse a folder that already holds its
  /// downloaded songs, instead of creating a new one.
  final bool reconnect;
}

/// Asks for a Spotify playlist link. Returns the trimmed link, or null when
/// cancelled.
Future<String?> showSpotifyLinkDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => _PlaylistLinkDialog(
      title: 'Import from Spotify',
      description:
          'Paste a public playlist link. Each song is matched on YouTube, '
          'then you choose what to download.',
      invalidMessage:
          'Paste a Spotify playlist link, like open.spotify.com/playlist/…',
      isValid: (input) => SpotifyService.playlistIdFromInput(input) != null,
    ),
  );
}

/// Asks for a YouTube playlist link. Returns the trimmed link, or null when
/// cancelled.
Future<String?> showYouTubeLinkDialog(BuildContext context) {
  return showDialog<String>(
    context: context,
    builder: (_) => _PlaylistLinkDialog(
      title: 'Import from YouTube',
      description:
          'Paste a public playlist link. You choose which videos to '
          'download as songs.',
      invalidMessage:
          'Paste a YouTube playlist link, like youtube.com/playlist?list=…',
      isValid: (input) => YouTubeService.playlistIdFromInput(input) != null,
    ),
  );
}

class _PlaylistLinkDialog extends StatefulWidget {
  const _PlaylistLinkDialog({
    required this.title,
    required this.description,
    required this.invalidMessage,
    required this.isValid,
  });

  final String title;
  final String description;
  final String invalidMessage;
  final bool Function(String input) isValid;

  @override
  State<_PlaylistLinkDialog> createState() => _PlaylistLinkDialogState();
}

class _PlaylistLinkDialogState extends State<_PlaylistLinkDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final input = _controller.text.trim();
    if (!widget.isValid(input)) {
      setState(() => _error = widget.invalidMessage);
      return;
    }
    Navigator.of(context).pop(input);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.description),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'Playlist link',
              errorText: _error,
            ),
            onChanged: (_) {
              if (_error != null) setState(() => _error = null);
            },
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Continue')),
      ],
    );
  }
}

/// Asks where the playlist folder should be. When [existingFolderName] is set,
/// the user can reconnect that folder instead of creating a new one.
Future<SpotifyFolderChoice?> showSpotifyFolderDialog(
  BuildContext context, {
  required String suggestedName,
  String? existingFolderName,
  String rootFolderLabel = 'Spotify',
}) {
  return showDialog<SpotifyFolderChoice>(
    context: context,
    builder: (_) => _SpotifyFolderDialog(
      suggestedName: suggestedName,
      existingFolderName: existingFolderName,
      rootFolderLabel: rootFolderLabel,
    ),
  );
}

class _SpotifyFolderDialog extends StatefulWidget {
  const _SpotifyFolderDialog({
    required this.suggestedName,
    required this.rootFolderLabel,
    this.existingFolderName,
  });

  final String suggestedName;
  final String? existingFolderName;
  final String rootFolderLabel;

  @override
  State<_SpotifyFolderDialog> createState() => _SpotifyFolderDialogState();
}

class _SpotifyFolderDialogState extends State<_SpotifyFolderDialog> {
  late final TextEditingController _controller;
  late bool _reconnect;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.suggestedName);
    _reconnect = widget.existingFolderName != null;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _reconnect && widget.existingFolderName != null
        ? widget.existingFolderName!
        : sanitizeFolderName(_controller.text);
    Navigator.of(
      context,
    ).pop(SpotifyFolderChoice(folderName: name, reconnect: _reconnect));
  }

  @override
  Widget build(BuildContext context) {
    final existing = widget.existingFolderName;
    return AlertDialog(
      title: const Text('Playlist folder'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (existing != null) ...[
            Text(
              'This playlist was already imported into “$existing”. '
              'Reconnect it to keep the songs you downloaded.',
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Reconnect existing folder'),
              value: _reconnect,
              onChanged: (value) => setState(() => _reconnect = value),
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: _controller,
            enabled: !_reconnect,
            decoration: const InputDecoration(labelText: 'Folder name'),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          Text(
            'Saved in your library under ${widget.rootFolderLabel}/.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _submit, child: const Text('Continue')),
      ],
    );
  }
}

/// Shows a non-dismissable progress dialog. Close it with
/// `Navigator.of(context, rootNavigator: true).pop()`.
void showSpotifyBusyDialog(
  BuildContext context,
  ValueListenable<String> message,
) {
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(
          children: [
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: message,
                builder: (_, text, _) => Text(text),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Lists the matched YouTube results and returns the ones to download, or
/// null when dismissed.
Future<List<SpotifyTrackMatch>?> showSpotifyReviewSheet(
  BuildContext context, {
  required String playlistName,
  required List<SpotifyTrackMatch> matches,
  String? notice,
}) {
  return showModalBottomSheet<List<SpotifyTrackMatch>>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    showDragHandle: true,
    builder: (_) => _SpotifyReviewSheet(
      playlistName: playlistName,
      matches: matches,
      notice: notice,
    ),
  );
}

class _SpotifyReviewSheet extends StatefulWidget {
  const _SpotifyReviewSheet({
    required this.playlistName,
    required this.matches,
    this.notice,
  });

  final String playlistName;
  final List<SpotifyTrackMatch> matches;
  final String? notice;

  @override
  State<_SpotifyReviewSheet> createState() => _SpotifyReviewSheetState();
}

class _SpotifyReviewSheetState extends State<_SpotifyReviewSheet> {
  late final Set<int> _selected = {
    for (var i = 0; i < widget.matches.length; i++)
      if (widget.matches[i].matched) i,
  };

  List<SpotifyTrackMatch> get _matched =>
      widget.matches.where((match) => match.matched).toList();

  List<SpotifyTrackMatch> get _chosen => [
    for (var i = 0; i < widget.matches.length; i++)
      if (_selected.contains(i)) widget.matches[i],
  ];

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final matchedCount = _matched.length;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.playlistName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 4),
                Text(
                  '$matchedCount of ${widget.matches.length} songs matched on '
                  'YouTube',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
          if (widget.notice != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: Text(
                widget.notice!,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colorScheme.error),
              ),
            ),
          Expanded(
            child: ListView.builder(
              itemCount: widget.matches.length,
              itemBuilder: (context, index) {
                final match = widget.matches[index];
                final result = match.result;
                return CheckboxListTile(
                  value: _selected.contains(index),
                  onChanged: match.matched
                      ? (value) => setState(() {
                          if (value == true) {
                            _selected.add(index);
                          } else {
                            _selected.remove(index);
                          }
                        })
                      : null,
                  title: Text(
                    match.track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    result == null
                        ? '${match.track.artist} · No YouTube match'
                        : '${match.track.artist} · ${result.title}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  controlAffinity: ListTileControlAffinity.leading,
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _selected.isEmpty
                        ? null
                        : () => Navigator.of(context).pop(_chosen),
                    child: Text('Download selected (${_selected.length})'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: matchedCount == 0
                        ? null
                        : () => Navigator.of(context).pop(_matched),
                    child: const Text('Download all'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
