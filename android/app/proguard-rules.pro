# Aturan untuk Google ML Kit (Text Recognition)
-keep class com.google.mlkit.** { *; }

# Aturan untuk Huawei (Scan Kit)
-dontwarn com.huawei.**
-keep class com.huawei.** { *; }

# Aturan untuk BouncyCastle (Kriptografi yang dipakai Huawei)
-dontwarn org.bouncycastle.**
-keep class org.bouncycastle.** { *; }

# ML Kit Text Recognition - Keep all language options
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

-keep class com.google.mlkit.vision.text.chinese.** { *; }
-keep class com.google.mlkit.vision.text.devanagari.** { *; }
-keep class com.google.mlkit.vision.text.japanese.** { *; }
-keep class com.google.mlkit.vision.text.korean.** { *; }