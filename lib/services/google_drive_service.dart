import 'dart:typed_data';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;

class GoogleDriveService {
  static String? _accessToken;

  // 手動設定 Access Token
  static void setAccessToken(String token) {
    _accessToken = token;
    print('✅ Google Drive Access Token 已設定');
  }

  // 上傳圖片到 Google Drive
  static Future<String?> uploadImage(
    Uint8List imageBytes,
    String fileName,
  ) async {
    try {
      print('🔄 開始上傳圖片到 Google Drive...');

      // 檢查是否有 Access Token
      if (_accessToken == null) {
        print('❌ 尚未設定 Google Drive Access Token');
        return null;
      }

      final client = AuthenticatedClient(_accessToken!);
      final driveApi = drive.DriveApi(client);

      final file = drive.File();
      file.name = '$fileName.jpg';
      file.parents = ['appDataFolder']; // 存到應用資料夾

      print('📤 上傳檔案: ${file.name} (${imageBytes.length} bytes)');

      final response = await driveApi.files.create(
        file,
        uploadMedia: drive.Media(
          http.ByteStream.fromBytes(imageBytes),
          imageBytes.length,
        ),
      );

      print('✅ 檔案上傳成功，ID: ${response.id}');

      // 設定公開權限
      await driveApi.permissions.create(
        drive.Permission()
          ..role = 'reader'
          ..type = 'anyone',
        response.id!,
      );

      final imageUrl = 'https://drive.google.com/uc?id=${response.id}';
      print('🔗 圖片網址: $imageUrl');

      return imageUrl;
    } catch (error) {
      print('❌ Google Drive 上傳錯誤: $error');
      return null;
    }
  }

  static bool get isSignedIn => _accessToken != null;
}

class AuthenticatedClient extends http.BaseClient {
  final String _accessToken;
  final http.Client _client = http.Client();

  AuthenticatedClient(this._accessToken);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers['Authorization'] = 'Bearer $_accessToken';
    return _client.send(request);
  }
}
