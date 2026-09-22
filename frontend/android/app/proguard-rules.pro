# flutter_local_notifications stores scheduled alarms with Gson.
# Keep generic signatures and the plugin models when the release build is minified.
-keepattributes Signature
-keepattributes *Annotation*
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class * extends com.google.gson.reflect.TypeToken { *; }
