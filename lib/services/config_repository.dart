import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/tvbox_config.dart';

class ConfigRepository {
  static const _lastUrlKey = 'last_successful_config_url';

  Future<TvBoxConfig> importFromUrl(String input) async {
    final uri = Uri.tryParse(input.trim());
    if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
      throw const FormatException('请输入有效的 HTTPS 配置地址');
    }

    final response = await http.get(uri, headers: {'Accept': 'application/json'})
        .timeout(const Duration(seconds: 20));
    if (response.statusCode != 200) {
      throw FormatException('服务器返回状态码：${response.statusCode}');
    }

    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('配置内容必须是 JSON 对象');
    }

    final config = TvBoxConfig.fromJson(decoded);
    if (config.siteCount == 0 && config.liveCount == 0) {
      throw const FormatException('配置中没有可识别的站点或直播列表');
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_lastUrlKey, uri.toString());
    return config;
  }

  Future<String?> lastSuccessfulUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_lastUrlKey);
  }
}
