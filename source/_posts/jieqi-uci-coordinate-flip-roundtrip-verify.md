---
title: 揭棋接引擎：UCI 坐标翻转这一行不难，难的是你怎么证明它是对的
date: 2026-11-23 12:10:00
type: tech
permalink: /2026/11/23/jieqi-uci-coordinate-flip-roundtrip-verify/
tags:
  - 揭棋
  - UCI
  - 坐标映射
  - 交叉编译
  - 测试
categories:
  - 工程实践
---

上一篇写了揭棋的规则内核。这一篇写 M3：把一个 GPL 的象棋引擎接到自己的规则内核上。

主角是 Pikafish 的 `jieqi_old` 分支。查过之后，能拿来做对拍的揭棋引擎就那么几家：Pikafish 的 `jieqi` / `jieqi_old` 分支（GPL-3.0）、一个 wasm 快照、一个 MIT 协议的桌面端。GPL 意味着不能内联进我的代码，只能独立进程 + UCI 协议通信。这部分没什么好讲的。

真正卡住我的是最后一步：引擎返回 `bestmove h0g2` 这种坐标，我前端认的是 `{row, col}`。**两行映射写起来，验证它花了我一整个下午。**

## 问题不在"写出来"，在"证明它对"

引擎用 UCI 坐标：`file` 是 `a`-`i`，`rank` 是 `0`-`9`。我的棋盘是 `row 0`（黑方底线）到 `row 9`（红方底线），`col 0`-`8`。

映射的最终形态是这样的，`packages/engine/src/uci.ts:31-34`：

```ts
const col = uci.charCodeAt(0) - 97;          // file → col，同向，a = col 0
const row = 9 - (uci.charCodeAt(1) - 48);    // rank → row，翻转
const trow = 9 - (uci.charCodeAt(3) - 48);
```

`file = col` 不用镜像，`rank = 9 - row` 要翻转。就这两条。写出来十秒钟。

下午花在哪里？花在我**没法确定这两条谁对谁错**。因为引擎的 rank 语义不写在文档里，`position.cpp` 里那行从 `SQ_A9` 起解析、每行 `sq += 2*SOUTH` 的代码，能读出"FEN 第 10 行落在内部 rank 0"，但读不出"rank 0 到底对应我前端的哪一行"。

中途我真的改成过恒等映射（`row = rank`），理由是"看起来更自然"。实测对不上，才回退成翻转。

这就是坐标映射最烦的地方：**它对与错在代码上长得一样好看**，`row = rank` 和 `row = 9 - rank` 都类型正确、都能编译、都返回合法坐标。没有编译器能帮你拦住。

## 解法：别去推理坐标，去喂一个语义不变量

我停下来的那一刻是想通的：不要再盯着 `rank`、`row`、`翻转`、`镜像` 这些抽象词了。

改用引擎**自己走出来的那一步**做交叉验证。规则内核里红方起始局面、红方先行是确定的，那么引擎返回的第一手必然是红方的一枚暗子。把它过一遍映射，看落点符不符合这枚子的走法形状——这是引擎行为本身给出的、我完全独立于坐标系统的事实。

实测：

```
bestmove h0g2
  h0 = file h, rank 0
  g2 = file g, rank 2
```

过映射：`h0` → `col 7`、`rank 0` → `row 9`，即 `(row 9, col 7)`，正是红方底线的马位。`g2` → `(row 7, col 6)`。

红马在 `(9,7)` 跳到 `(7,6)`：**纵向 2、横向 1，正是马走日字。** 完全吻合。同时 `row 9` 由红方走出，红方先行也对上了。

一行代码、一个下午、一个真实 bug。中间那趟恒等映射的弯路，就是因为我一直在"想"坐标，而不是"跑"一步。

## 顺手把 file 镜像这个坑也堵了

值得单独记一笔，因为它更隐蔽，而且我差点中招。

`rank` 翻转一眼看得出来：引擎的 `rank 0` 是黑方底线，我前端的 `row 0` 是黑方底线，两者方向一致——不对，等等。我前端的 `row 0` 是黑方底线，但 `row` 编号是往上递增还是往下？翻来覆去之后才确认：**我前端的 `row 9` 是红方底线，引擎的 `rank 0` 也是红方那边**（因为 `SOUTH` 是从 FEN 最后一行往上累加的）。所以 `rank 0 ↔ row 9`，翻转成立。

真正难的是 `file`。直觉上"黑方从自己的视角看棋盘，左右是反的，所以 `file` 应该镜像成 `col = 8 - file`"。

我用起始 FEN 验了一下：黑方将在 `xxxxkxxxx` 的第 5 个字符，即 `file e`（index 4）。我的黑将也在 `col 4`。**中心对称，两个映射都成立，验不出来。**

再往下走一步才定生死：黑方视角的左是 `file a`，而屏幕左是 `col 0`——黑方朝下看，它的左就是屏幕的左，**没有镜像**。`file = col` 成立。

中心对称的轴测不出翻转，只有边缘的不对称能测出来。这条经验我觉得比坐标本身更有用。

## 怎么把这件事变成不会回归的测试

映射写对只是第一次。我要的是它**永远写对**。

做法是 6 条单元测试覆盖 `uci.ts` 的四个方向（`uciToMove` / `moveToUci` 的正反向 + 边界格），再加一条端到端对拍：让引擎连走 10 步，每一步的坐标转换后，都要能在本地规则内核的 `legalMoves` 里找到。

```ts
it("引擎着法必须是本地规则内核认可的合法着法（10 步抽样）", async () => {
  let pos = posFromFen(START_FEN);
  for (let i = 0; i < 10; i++) {
    const mv = await engine.bestMove(pos, { moveTimeMs: 60 });
    const legal = legalMoves(pos, /* side */ pos.turn);
    // 断言 mv.from/mv.to 在 legal 里
    ...
  }
});
```

这条测试的价值在于：它不依赖任何"正确答案"，只依赖两个引擎各自独立的判定。坐标映射错了，第一步就会因为 `from` 落在非法格上而炸掉，而不是走到第 8 步才出现奇怪的行为。

第二条是自对弈走到底：

```
✓ AI 引擎对拍 > 引擎着法必须是本地规则内核认可的合法着法（10 步抽样） 860ms
✓ AI 引擎对拍 > AI 自对弈能完整走到底且无死循环 2863ms
自对弈 46 步，终局类型: checkmate

 Test Files  2 passed (2)
      Tests  8 passed (8)
```

两次跑分别走到 52 步和 46 步（引擎会探索暗子的所有可能身份，所以每次不同），都以 `checkmate` 终局、无死循环。

## 顺带：把 Windows 引擎二进制编译出来

前半段还有个前置问题：引擎是 Linux/C++，我要在 Windows 上以独立进程跑它。

答案是 Docker + mingw-w64 交叉编译，`engine/build-mingw.sh`：

```bash
MSYS_NO_PATHCONV=1 docker run --rm \
  -v "C:/yoyac-work/chinese-cheese/engine-src/src:/src" -w /src \
  ubuntu:22.04 bash -c "
    apt-get install -y -qq g++-mingw-w64-x86-64 make
    make -j4 ARCH=x86-64 COMP=mingw build
  "
```

产物验证过：

```
./engine/bin/PikaJieQi.exe: PE32+ executable (console) x86-64, for MS Windows
3464587 bytes
```

两个坑：

1. **git-bash 会把路径转成 `C:\c\...`**。`docker cp` 传不进去。加 `MSYS_NO_PATHCONV=1`，并且 Docker 的源路径用 `C:/` 正斜杠，才通。
2. **容器内 HTTP 80 全被墙，只有 HTTPS 443 通**。我一开始配清华源（也是证书不受信），折腾十几分钟。最后换成阿里云的 HTTPS 源才装上 mingw。

握手链路端到端通：

```
$ printf "uci\nisready\nposition fen %s\ngo movetime 200\nquit\n" "$START" | ./engine/bin/PikaJieQi.exe
uciok
readyok
bestmove a0a1
```

`a0a1` 和我上次跑的 `h0g2` 不一样，这不矛盾——揭棋引擎要在身份池里枚举暗子的所有可能身份来搜索，同一个起始局面可以有多个最优解。这也解释了为什么我的自对弈步数每次都不一样。

## 小结

坐标映射的教训浓缩成一句话：**别用推理去证明一个抽象转换，用源系统自己输出的行为去圆环它。**

`row = 9 - rank` 这行代码不值一提。值一提的是我拿引擎自己的 `bestmove` 反推过去、发现落点正好符合马走日字的那一刻——那是一个独立于我全部坐标假设的事实。

测试也一样：不要写"这个坐标应该等于那个坐标"的断言，那只是把你的猜测固化成测试。要写"引擎认为合法的着法，在本地规则内核里也必须合法"——让两套独立实现互相校验。

