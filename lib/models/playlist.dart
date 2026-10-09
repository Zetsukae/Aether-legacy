class Playlist {
  const Playlist({
    required this.id,
    required this.name,
    required this.trackPaths,
    this.coverPath,
  });

  final String id;
  final String name;
  final List<String> trackPaths;
  final String? coverPath;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'trackPaths': trackPaths,
        'coverPath': coverPath,
      };

  factory Playlist.fromJson(Map<String, dynamic> json) => Playlist(
        id: json['id'] as String,
        name: json['name'] as String,
        trackPaths: (json['trackPaths'] as List<dynamic>).cast<String>(),
        coverPath: json['coverPath'] as String?,
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
