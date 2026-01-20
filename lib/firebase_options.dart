import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      default:
        return android;
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'WEB_API_KEY',
    appId: 'WEB_APP_ID',
    messagingSenderId: 'WEB_MESSAGING_SENDER_ID',
    projectId: 'WEB_PROJECT_ID',
    authDomain: 'WEB_AUTH_DOMAIN',
    storageBucket: 'WEB_STORAGE_BUCKET',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyAkPB57sJJjdnZTLvj_NZurTcCHcYpyqyQ',
    appId: '1:483155719934:android:c4187719571ebde091d7af',
    messagingSenderId: '483155719934',
    projectId: 'seetheworld-57efc',
    storageBucket: 'seetheworld-57efc.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'IOS_API_KEY',
    appId: 'IOS_APP_ID',
    messagingSenderId: 'IOS_MESSAGING_SENDER_ID',
    projectId: 'IOS_PROJECT_ID',
    storageBucket: 'IOS_STORAGE_BUCKET',
    iosBundleId: 'com.example.travelApp',
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'MACOS_API_KEY',
    appId: 'MACOS_APP_ID',
    messagingSenderId: 'MACOS_MESSAGING_SENDER_ID',
    projectId: 'MACOS_PROJECT_ID',
    storageBucket: 'MACOS_STORAGE_BUCKET',
    iosBundleId: 'com.example.travelApp',
  );
}
