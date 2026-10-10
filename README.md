# Aether

A lightweight Material 3 local music player targeting Android, iOS, Windows, and Linux.

## Set up

Install Flutter 3.38 or later and fetch packages:

```sh
flutter pub get
flutter run -d linux
```

Use **Add music files** to import local audio files. Aether copies selected songs into its app storage, reads common title, artist, album, duration, and embedded cover-art tags, then restores the library after relaunch. The original files are left untouched. Favorites are saved too.

Open **Playlists** and choose **New** to create a playlist with a name, optional image cover, and selected songs. Playlists, their track membership, and copied cover images are saved across launches. Removing the app or clearing its app data removes Aether's imported copies.

Open **Appearance** in the top bar to choose system, light, or dark theme and an accent color. On Android, device wallpaper colors can be used in place of the selected accent. Appearance preferences are saved across launches.

The **Experimental** switch in **About** enables YouTube search on Windows and Linux. Aether bundles yt-dlp 2026.08.19 for search and audio downloads; playback starts after the audio has been saved to a local cache. Availability depends on YouTube. You can also submit a direct HTTP(S) audio URL for a file you own or are authorized to download; Aether validates and imports audio files up to 1 GB into the local library. Direct URL downloads do not use YouTube extraction.

Android and iOS use `just_audio` native playback with background audio and lock-screen/notification controls. Windows and Linux use its media_kit adapter. Linux builds may need the system `mpv` runtime in addition to Flutter's desktop build dependencies. Android uses the system dynamic color palette when available, with a seeded Material 3 fallback elsewhere.

## Build

Build each target on its supported host platform:

```sh
flutter build apk
flutter build ios
flutter build windows
flutter build linux
```

iOS builds require macOS and Xcode. Windows builds require Windows and Visual Studio's C++ desktop workload. Linux builds require the Flutter Linux toolchain and `mpv` runtime.