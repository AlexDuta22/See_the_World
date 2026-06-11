import 'package:shared_preferences/shared_preferences.dart';

class SharedpreferenceHelper {
  static String userNameKey = "USERNAMEKEY";

  Future<bool> saveUserDisplayName(String getUserName) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.setString(userNameKey, getUserName);
  }

  Future<String?> getUserDisplayName() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    return prefs.getString(userNameKey);
  }
}
