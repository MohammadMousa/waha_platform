# Geidea POS terminal SDK (spec §3.3). Dormant today — this build's
# release buildType doesn't enable isMinifyEnabled, so nothing here is
# active yet. Kept ready for whenever minification/obfuscation is turned
# on, so it isn't forgotten and rediscovered as a runtime crash later.
-keep class geidea.net.terminal_comm_api.** {*;}
-keep class com.jcraft.jsch.jce.*
-keep class * extends com.jcraft.jsch.KeyExchange
-keep class com.jcraft.jsch.**
-keep class org.ietf.jgss.*
-dontwarn org.ietf.jgss.**
-dontwarn com.jcraft.jsch.**
