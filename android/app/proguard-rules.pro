# flutter_local_notifications v19以降はプラグイン自身が必要なクラスを
# keep指定するようになったため、本来はこのファイルは不要とされています。
# ただし念のため、Gsonの型情報がR8によって削られる既知の不具合
# ("Missing type parameter" RuntimeException) を避けるための
# 保険としてルールを残しておきます。
-keep class com.google.gson.reflect.TypeToken
-keep class * extends com.google.gson.reflect.TypeToken
-keep public class * implements java.lang.reflect.Type

# Gson がリフレクションで参照するモデルクラスが難読化によって
# 壊れないようにする一般的なルール
-keepattributes Signature
-keepattributes *Annotation*