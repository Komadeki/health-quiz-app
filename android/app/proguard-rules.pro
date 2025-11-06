# =========================================
# flutter_local_notifications の BroadcastReceiver を保持
# =========================================
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# （オプション）Flutter Engine 関連も安全に保持
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.** { *; }

# （オプション）Proguard の警告を抑制
-dontwarn io.flutter.**
