import 'package:flutter/services.dart';

/// Native iOS folder access. Folders picked through the document picker are
/// security-scoped, so the native side keeps access alive via a stored bookmark.
class LibraryFolderChannel {
  const LibraryFolderChannel._();

  static const _channel = MethodChannel('aether/library_folder');

  static Future<String?> pickFolder() =>
      _channel.invokeMethod<String>('pickFolder');

  static Future<String?> restoreFolder() =>
      _channel.invokeMethod<String>('restoreFolder');

  /// Returns the Aether Documents folder inside the app's iCloud container, or
  /// null when iCloud Drive is unavailable.
  static Future<String?> iCloudDocuments() =>
      _channel.invokeMethod<String>('iCloudDocuments');
}
