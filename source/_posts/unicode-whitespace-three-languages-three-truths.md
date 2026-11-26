---
title: 同一个「是不是空格」，Python、Java、JavaScript 给出了三个不同的答案
date: 2026-11-26 08:30:00
type: thought
permalink: /2026/11/26/unicode-whitespace-three-languages-three-truths/
tags:
  - Unicode
  - Java
  - Python
  - JavaScript
  - 技术细节
categories:
  - 技术思考
---

阮一峰周刊第 420 期「文章」栏第 3 条引了一篇英文文章：[How hard is it to check for whitespace?](https://serce.me/posts/2026-10-30-how-hard-is-it-to-check-for-whitespace)（[周刊链接](https://www.ruanyifeng.com/blog/2026/11/weekly-issue-420.html)）。

作者的起点很有意思——他不是先想到「空白字符」这个概念，而是在 review 代码时撞见 Guava 里的一个方法，发现它远比 `c == ' '` 复杂得多，于是开始追它为什么这么写。

他最后的结论我读到时愣了一下。

他说这篇文章本身是「写自己」：在 AI-first 的时代，很少有人再愿意去看 `isWhitespace` 这种函数内部。

**我不这么看。** 恰恰是因为 AI 能一句话生成 `text.trim()`，我们才更应该知道 `trim()` 到底 trim 了什么。生成的代码不会告诉你它用哪个规则集判断空白——而规则集不一样，线上就会出现「我在本地测过了」。

所以我做了一件事：把原文里「Python、Java、JavaScript 对空白字符各有各的定义」这句话，跑了一遍。

不是引用别人的结果，是我自己数。

## 先把三个数字摆出来

我扫了从 U+0000 到 U+10FFFF 的全部码点，让三个运行时各自报数。

| 运行时 | 判定方式 | 识别的空白字符数 |
| --- | --- | --- |
| Java 1.8.0_231 | `Character.isWhitespace()` | **26** |
| Python 3.14.9 | `str.isspace()` | **29** |
| Node v24.18.0 | 正则 `\s` | **25** |

作为参照，Unicode 标准里的 `White_Space` 属性是 **25** 个。

也就是说，**没有一家的判定集和 Unicode 完全一致**。

先拆 Java：26 个，比 Unicode 多 1。

多出来的是 **U+001C、U+001D、U+001E、U+001F** 这 4 个 ASCII 文件分隔符，加一个 **U+180E**——一共 5 个。同时 Java **丢掉**了 4 个：U+0085、U+00A0、U+2007、U+202F。一进一出，25 + 5 − 4 = 26。

Python 的 29 好解释。它的 25 个 Unicode 空白里，额外收了 **U+001C、U+001D、U+001E、U+001F** 这 4 个文件分隔符，25 + 4 = 29，正好。

这和原文的说法一致：作者特别点名了 `FILE SEPARATOR (U+001C)`——它是 ASCII 控制字符，本来是用来分隔信息块的，不在 Unicode 的 `White_Space` 里，但 Python 认它为空白。

于是真正的分歧全在这 4 个文件分隔符上：**Java 和 Python 都收，JavaScript 都不收。**

而 U+00A0（不换行空格）这一家子，才是各说各话的地方——同样是「不换行空格」，三个运行时的处理互不相同。

这个差别不是无关紧要：U+202F 大量出现在**法语数字**里（`1 000 000` 千位分隔），也是德语的十进制小数点。做 i18n 校验时，「数字格式对不对」这个问题，在你用什么语言判空白之前就没有唯一答案。

## JavaScript 是那个最奇怪的

Node v24.18.0 的 `\s` 报了 25，和 Unicode 的 25 数字一样——但它**不是**同一组 25。

它是：Unicode 的 25 个里剔掉 **U+0085（NEXT LINE）**，再塞进 **U+FEFF（ZERO WIDTH NO-BREAK SPACE）**。

| 码点 | Java | Python | JS `\s` | Unicode `White_Space` |
| --- | --- | --- | --- | --- |
| U+0085 NEXT LINE | ✗ | ✓ | **✗** | ✓ |
| U+FEFF ZWNBSP | ✗ | ✗ | **✓** | ✗ |
| U+00A0 NBSP | ✗ | ✓ | ✓ | ✓ |
| U+202F NARROW NBSP | ✗ | ✓ | ✓ | ✓ |

U+FEFF 这一行是我觉得最该记住的。

它在 Unicode 里**不是**空白。它叫 Zero Width No-Break Space，本质是个格式字符——作用是让编辑器不要在它的位置断行，本身不产生可见间距。

但 JavaScript 认。

后果非常具体：一个带 BOM 的 UTF-8 文件，BOM 解出来就是 U+FEFF，落在字符串开头。

- Python：`"\ufeff".isspace()` 是 `False`，所以 `str.strip()` **不会**把它去掉——我实测 `"\ufeffhello".strip()` 还是 `'\ufeffhello'`。
- JavaScript：`"\ufeff".trim()` **会**把它去掉，返回空串——因为 `\s` 认它。我实测 `"\ufeffhello".trim()` 是 `'hello'`。

同一个 BOM，一种语言里是脏字符，另一种语言里被自动清理了。这不叫 bug，这叫两个运行时各自做了一个设计决定，然后都没写进你读的那行代码。

## U+180E：一个会消失的空白

原文里有一段关于时间线的东西，我觉得是全篇最微妙的一点。

`MONGOLIAN VOWEL SEPARATOR (U+180E)` 在 Unicode 6.3 之前有 `White_Space` 属性，6.3 把它从 space separator 重新分类为 format character，**属性被移除了**。Unicode 的空白集合从 26 个变成 25 个。

我跑的 Java 8，对 U+180E 返回 `true`。

也就是说，**Java 8 的字符属性表定格在 Unicode 6.3 之前**。这个语言标准库为了向后兼容把老行为保留了，代价是它和当前 Unicode 不一致。

作者用了一句话概括这种处境：Unicode 不是冻结的，而语言的标准库想尽可能稳定。这两件事互相拉扯。

我实测的 Java 是 1.8.0_231，2017 年的版本。我没法替更新的 JDK 判断——但「哪个字符算空白」这个问题，**至少有一个答案会随语言版本漂移**。这意味着「升级 JDK 之后某些校验开始失败」是一条真实存在、且很好排查却不好预判的风险。

## Guava 那个乘数：我顺手验证了

原文提到 Guava 的实现核心是一个「完美哈希函数」：

```java
int slot = (1682554634 * c) >>> 27;
return TABLE.charAt(slot) == c;
```

一个 32 字符的表，用 `(乘数 × 字符) >>> 27` 取高 5 位做下标，查表再和原字符比对。

我把它跑了一遍，验证这个乘数确实有效：25 个字符落到 **25 个互不相同**的槽位，没有碰撞，没有越界。

原文说「1682554634 这个数字看起来很神秘，我不清楚它怎么来的」。

我也跑了一个暴力搜索找出所有满足条件的乘数。结果：**247201 个**，第一个是 `150812695`。

所以它不是唯一解，也不是巧合解——它是从 24 万多个可用乘数里挑出来的一个。这个「魔法数字」背后有一整个可枚举的解空间，这件事比这个数字本身有意思得多。

## 真正的问题不在算法

回到开头。

作者说他担心的是：AI-first 的世界里，很少有人再会去看 `isWhitespace` 里面。

我的看法是反过来的。以前你写代码会停下来想「这个空格到底算不算」；现在你让 AI 写一行 `trim()` 就过去了，**你不再有机会停下来想**。

于是「三种语言三个答案」这种差异，就从「知道的人少」变成了「知道的人在变少」。

具体到我自己的工作方式：跨端校验用户输入时，前端在浏览器（JavaScript）做一遍 `trim()`，后端在 Node 再 `trim()`，如果哪天后端换成 Java 或 Python，同一份输入会被三种规则集各判一次。测试全绿，线上偶发报错。

我的结论就一句话：**写「判空白」的代码之前，先把要清的字符集写成一个显式的码点列表，而不是依赖 `trim` 这类名字。** 那些名字在不同运行时里指向不同的集合。

我拿一个真实字符串验了一下这个差别，输入是 `'\u0020 a\u00a0b\tc\n\u2028d\u2029e\ufeff'`：

```js
x.replace(/\s/g, '')        // "abcde"     —— U+FEFF 被当空白清掉了
// 换成 29 个码点的显式集合（不含 FEFF）:
// "abcde\ufeff"            —— U+FEFF 留着
```

我实测这两种写法**不相等**，唯一的分歧点就是 U+FEFF。

换句话说：同一个 `x`，用正则 `\s` 清完和用显式集合清完，字符串长度都不一样。如果你前端用一种、后端用另一种，两边拿到的「已清洗」字符串在字节层面就不同。

至于 Guava 那个完美哈希，它教给我的不是「哈希可以这么用」，而是另一件事：一个函数如果复杂到你看不懂，**值得花十分钟把它跑一遍**，而不是换个库绕过去。

那十分钟，AI 现在很难替你省掉——它能给你答案，但给不了你「这个答案在 Java 8 上会怎么变」。

---

*引用来源：阮一峰周刊第 420 期[《最分心的一年》](https://www.ruanyifeng.com/blog/2026/11/weekly-issue-420.html)「文章」栏第 3 条，原文 [How hard is it to check for whitespace?](https://serce.me/posts/2026-10-30-how-hard-is-it-to-check-for-whitespace)（Sergey Tselovalnikov，2026-10-30）。文中的三个数字与差异码点均由我在本机实测：Java 1.8.0_231、Python 3.14.9、Node v24.18.0。*
