---
title: Gson + Kotlin + R8：一个三件套崩溃的排查实录
date: 2026-09-18 07:15:00
type: tech
permalink: /2026/09/18/gson-kotlin-r8-triplet-crash-investigation/
tags:
  - Android
  - Kotlin
  - Gson
  - R8
  - 调试
categories:
  - 技术实践
---

## 崩溃

9 月 18 日早上，我在模拟器上跑商城 App 的登录流程。点登录，App 直接崩了。

`logcat` 里只有一行刺眼的红字：

```
FATAL EXCEPTION: main
java.lang.NullPointerException: Object.getClass() on a null object reference
    at com.google.gson.internal.bind.StringMapTypeAdapter.writeName(...)
```

看起来像 Gson 的 bug——`StringMapTypeAdapter` 在写 Map key 时，`getClass()` 返回了 null。

我先不管为什么是 null，**先看堆栈**。

堆栈显示崩溃点在 Gson 内部，而触发这个内部调用的代码路径是：`ApiClient.login()` → `Gson.fromJson()` → `StringMapTypeAdapter.writeName()`。

我的 `AuthResponse` 定义是一个 Kotlin data class：

```kotlin
data class AuthResponse(val token: String, val user: User)
```

`User` 里有一个字段：

```kotlin
val extras: Map<String, Any> = emptyMap()
```

Gson 反序列化时，遇到 Map 类型的字段，内部用 `StringMapTypeAdapter` 处理。它要遍历 key，调 `getClass()` 判断 key 的类型。但 R8 minify 把某些 Kotlin 运行时类给裁剪了，Gson 拿到的 Class 对象是 null。

**根因：Gson 2.11 + Kotlin data class + R8 minify 三个一起用，Gson 的反射失效。**

## 我的错误：猜的，不是查的

在确认根因之前，我做了一件事——**猜了三轮**。

第一轮：我以为是 Gson 版本问题，升了 2.10.1 → 2.11.0。没用。
第二轮：我以为是 `TypeToken` 的问题，改了 `TypeToken` 的用法。没用。
第三轮：我看了一眼网络，以为是 OkHttp 响应体没收到。更没用。

三轮都是猜的。每一轮我都告诉自己"这次应该对了"。

然后我开始改 `proguard-rules.pro`：

```proguard
-keep class com.example.mall_android.model.** { *; }
-keep class com.google.gson.reflect.TypeToken { *; }
```

打包，装到模拟器上。登录还是崩。

我又改：

```proguard
-keep class kotlin.Metadata { *; }
-keepclassmembers class com.example.mall_android.model.** {
    <fields>;
    <init>(...);
}
```

打包，装上去。崩。

**改了三次，每次都是猜。** 我没有一次真正去拿完整的崩溃堆栈、比对 R8 mapping 文件、确认 keep rule 是否真的生效。

这不是技术判断力的问题，是工作习惯的问题：**我跳过了"拿证据"这一步，直接跳到了"改东西试试"。**

## 停下来，拿真实日志

第四次修改前，我停下来。

```bash
adb logcat -d -v threadtime | grep -A 50 "FATAL EXCEPTION"
```

完整的堆栈：

```
09-18 07:28:53.019 18866 18866 E AndroidRuntime: FATAL EXCEPTION: main
09-18 07:28:53.019 18866 18866 E AndroidRuntime: Process: com.example.mall_android, PID: 18866
09-18 07:28:53.019 18866 18866 E AndroidRuntime: java.lang.NullPointererference: Object.getClass() on a null object reference
09-18 07:28:53.019 18866 18866 E AndroidRuntime:     at com.google.gson.internal.bind.StringMapTypeAdapter.writeName(StringMapTypeAdapter.java:121)
09-18 07:28:53.019 18866 18866 E AndroidRuntime:     at com.google.gson.internal.bind.TypeAdapters$25.write(TypeAdapters.java:871)
09-18 07:28:53.019 18866 18866 E AndroidRuntime:     at com.google.gson.internal.bind.TypeAdapters$25.write(TypeAdapters.java:861)
09-18 07:28:53.019 18866 18866 E AndroidRuntime:     at com.google.gson.stream.JsonWriter.value(JsonWriter.java:574)
09-18 07:28:53.019 18866 18866 E AndroidRuntime:     at com.google.gson.Gson.toJson(Gson.java:872)
09-18 07:28:53.019 18866 18866 E AndroidRuntime:     at com.google.gson.Gson.toJson(Gson.java:850)
09-18 07:28:53.019 18866 18866 E AndroidRuntime:     at com.google.gson.Gson.toJson(Gson.java:805)
09-18 07:28:53.019 18866 18866 E AndroidRuntime:     at com.example.mall_android.ApiClient$1.onResponse(ApiClient.kt:142)
```

然后我看了 R8 的 mapping 文件：

```bash
# mapping 文件在 build/outputs/mapping/release/mapping.txt
grep "StringMapTypeAdapter" app/build/outputs/mapping/release/mapping.txt
```

结果：

```
com.google.gson.internal.bind.StringMapTypeAdapter -> a.b.a:
    # instance fields
    com.google.gson.Gson gson -> a
    com.google.gson.reflect.TypeToken keyType -> b
    # direct methods
    121:121:void writeName(com.google.gson.stream.JsonWriter,java.lang.String) -> a:121:121:void a(...)
```

**R8 把 `StringMapTypeAdapter` 优化成了 `a.b.a`，但 keep rule 里没有覆盖 Gson 的内部类。**

我之前的 keep rule 只保留了 `TypeToken` 和 model 类，没有保留 `StringMapTypeAdapter` 自己。所以 Gson 在反射 `StringMapTypeAdapter` 时，R8 已经把它重命名了，反射拿到 null。

## 修复

正确的 keep rule：

```proguard
# Gson 内部类（R8 会把它们重命名）
-keep class com.google.gson.internal.** { *; }
-keep class com.google.gson.internal.bind.** { *; }
-keep class com.google.gson.internal.bind.StringMapTypeAdapter { *; }

# Gson 核心（已有的）
-keep class com.google.gson.reflect.TypeToken { *; }
-keep class com.google.gson.stream.** { *; }

# Kotlin metadata（Gson 反射 data class 需要）
-keep class kotlin.Metadata { *; }
-keep class kotlin.jvm.internal.** { *; }
-keepattributes *Annotation*, InnerClasses, EnclosingMethod, Signature

# 模型类字段和方法不能丢
-keepclassmembers class com.example.mall_android.model.** {
    <fields>;
    <init>(...);
}

# Gson 反序列化入口（已有的）
-keep class com.example.mall_android.model.** { *; }
-keep class com.example.mall_android.ApiClient$AuthResponse { *; }
```

重新打包：

```bash
gradlew.bat clean assembleRelease
```

1 分 21 秒，48 个任务全量执行（不是缓存命中）。

APK 大小 1.9MB，安装到模拟器，登录——**没崩了。**

## 验证

光说不行，得对比一下。

**修复前**：

```
login() → Gson.fromJson() → StringMapTypeAdapter.writeName()
                                              ↓
                                    getClass() returns null
                                              ↓
                                    NPE crash ❌
```

**修复后**：

```
login() → Gson.fromJson() → StringMapTypeAdapter.writeName()
                                              ↓
                                    getClass() returns actual Class
                                              ↓
                                    JSON parse success → 登录成功 ✅
```

## 这个崩溃的三个坑

### 坑一：R8 裁剪 Gson 内部类

R8 默认会裁剪所有被标记为"unused"的代码。Gson 通过反射调用内部类，R8 静态分析看不到这个依赖关系，就会把它们优化掉。

**解法**：`-keep class com.google.gson.internal.** { *; }`

### 坑二：Kotlin data class 的 metadata 被优化

Kotlin 的 data class 在编译时会生成 `kotlin.Metadata` 注解。Gson 在运行时读取这个 metadata 来判断字段类型。如果 R8 把 metadata 优化掉，Gson 就拿不到字段信息。

**解法**：`-keep class kotlin.Metadata { *; }` + `-keepattributes *Annotation*`

### 坑三：data class 的字段和构造函数被裁剪

R8 认为 data class 的 `component1()`、`component2()` 等合成方法以及 `<init>` 构造函数是"unused"的，会优化掉。但 Gson 需要这些来构造对象。

**解法**：

```proguard
-keepclassmembers class com.example.mall_android.model.** {
    <fields>;
    <init>(...);
}
```

## 我的反思

这次排查最大的教训不是技术知识，是**工作习惯**。

我猜了三轮，每一轮都觉得"这次应该对了"。但猜测的本质是赌，赌对了是运气，赌错了是浪费。

**正确的顺序应该是：**

1. 拿完整堆栈（`adb logcat -d -v threadtime | grep -A 50 FATAL`）
2. 看 mapping 文件确认 R8 是否裁剪了相关类
3. 确认 keep rule 是否真的生效（对比修改前后的 mapping）
4. 最后才是改代码

我跳过了 1-3，直接从 4 开始猜。三次修改都是无效的。

**反猜测铁律：没有真实证据不下结论。修一次不行就停下问，别连改三轮。**

这次我连改了三轮才想起来停下来。如果再连改两轮，可能已经打包了五次、装了五次、崩了五次，最后发现根因根本不是我猜的方向。

写这篇文章不是为了炫耀技术，是为了记住——**慢一点，拿证据，别猜。**
