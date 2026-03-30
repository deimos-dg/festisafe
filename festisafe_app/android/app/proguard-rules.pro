# FestiSafe ProGuard Rules
# Mantener clases necesarias para las librerías usadas

# Flutter
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Firebase
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.firebase.**

# Dio / OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }
-keep class okio.** { *; }

# flutter_blue_plus / BLE
-keep class com.boskokg.flutter_blue_plus.** { *; }

# flutter_background_service
-keep class id.flutter.flutter_background_service.** { *; }

# geolocator
-keep class com.baseflow.geolocator.** { *; }

# flutter_local_notifications
-keep class com.dexterous.flutterlocalnotifications.** { *; }

# ObjectBox (flutter_map_tile_caching)
-keep class io.objectbox.** { *; }
-dontwarn io.objectbox.**

# Kotlin
-keep class kotlin.** { *; }
-dontwarn kotlin.**

# Serialización JSON — evitar que ProGuard elimine campos de modelos
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes EnclosingMethod
