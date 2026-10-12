class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.trackPaths,
    this.coverPath,
    this.spotifyFolderPath,
  });

  final String id;
  final String name;
  final List<String> trackPaths;
  final String? coverPath;

  /// Folder holding the files and `aether_playlist.json` of a playlist
  /// imported from Spotify. Null for playlists created in the app.
  final String? spotifyFolderPath;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'trackPaths': trackPaths,
    'coverPath': coverPath,
    'spotifyFolderPath': spotifyFolderPath,
  };

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
    id: json['id'] as String,
    name: json['name'] as String,
    trackPaths: (json['trackPaths'] as List<dynamic>).cast<String>(),
    coverPath: json['coverPath'] as String?,
    spotifyFolderPath: json['spotifyFolderPath'] as String?,
  );
}

class PlaylistDraft {
  const PlaylistDraft({
    required this.name,
    required this.trackPaths,
    this.coverSourcePath,
  });

  final String name;
  final List<String> trackPaths;
  final String? coverSourcePath;
}
