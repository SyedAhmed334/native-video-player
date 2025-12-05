import 'package:permission_handler/permission_handler.dart';

/// Helper class to handle runtime permissions for video player
class PermissionHelper {
  /// Request storage permission for offline playback
  /// Returns true if permission is granted
  static Future<bool> requestStoragePermission() async {
    // Check Android version
    if (await Permission.videos.isGranted) {
      return true;
    }

    // Request permission
    final status = await Permission.videos.request();

    if (status.isGranted) {
      return true;
    } else if (status.isPermanentlyDenied) {
      // User has permanently denied permission
      // Open app settings
      await openAppSettings();
      return false;
    }

    return false;
  }

  /// Check if storage permission is granted
  static Future<bool> hasStoragePermission() async {
    return await Permission.videos.isGranted;
  }
}
