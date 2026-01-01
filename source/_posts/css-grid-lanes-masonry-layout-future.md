---
title: CSS Grid Lanes：瀑布流布局的未来已来
date: 2025-01-02 14:30:00
permalink: /2025/01/02/css-grid-lanes-masonry-layout-future/
tags: 
  - CSS
  - 前端开发
  - 布局技术
  - Grid Layout
categories: 
  - 技术分享
---

经过 Mozilla 的前期工作、Apple WebKit 团队多年的努力，以及 CSS 工作组与各大浏览器厂商的多轮讨论，瀑布流布局的未来终于明确了！

**CSS Grid Lanes** 正式登场。

```css
.container {
  display: grid-lanes;
  grid-template-columns: repeat(auto-fill, minmax(250px, 1fr));
  gap: 16px;
}
```

现在你可以在 [Safari Technology Preview 234](https://developer.apple.com/safari/resources/) 中体验这项技术。

## Grid Lanes 的工作原理

让我们深入了解如何创建这种经典的瀑布流布局。

![经典瀑布流布局示例](https://webkit.org/wp-content/uploads/Grid-Lanes-classic-light.png)

### 基础 HTML 结构

```html
<main class="container">
  <figure><img src="photo-1.jpg"></figure>
  <figure><img src="photo-2.jpg"></figure>
  <figure><img src="photo-3.jpg"></figure>
  <!-- 更多内容 -->
</main>
```

### 核心 CSS 实现

首先，我们给 `main` 元素应用 `display: grid-lanes` 来创建一个 Grid 容器。然后使用 `grid-template-columns` 来定义"车道"，充分利用 CSS Grid 的强大功能。

```css
.container {
  display: grid-lanes;
  grid-template-columns: repeat(auto-fill, minmax(250px, 1fr));
  gap: 16px;
}
```

就是这样！仅用三行 CSS，无需任何媒体查询或容器查询，我们就创建了一个适用于所有屏幕尺寸的灵活布局。

### 交通隧道比喻

可以把它想象成高峰期拥堵的高速公路。

![高速公路车道示意图](https://webkit.org/wp-content/uploads/Grid-Lanes-in-STP234.png)

就像经典的 [Masonry 库](https://masonry.desandro.com/) 一样，当浏览器决定放置每个项目的位置时，下一个项目会被放在能让它最接近窗口顶部的列中。就像交通一样，每辆车都会"变道"到能让它"走得最远"的车道。

## Grid 的强大功能

### 可变车道尺寸

由于 Grid Lanes 使用 CSS Grid 的全部功能来定义车道，我们可以轻松创建富有创意的设计变化。

例如，我们可以创建一个具有交替窄列和宽列的灵活布局——其中第一列和最后一列始终是窄的，即使列数随视口大小变化也是如此：

```css
.container {
  grid-template-columns: repeat(auto-fill, minmax(8rem, 1fr) minmax(16rem, 2fr)) minmax(8rem, 1fr);
}
```

![可变宽度布局示例](https://webkit.org/wp-content/uploads/Grid-Lanes-varying-widths-light.png)

### 跨列项目

由于我们拥有 Grid 布局的全部功能，当然也可以跨越多个车道。

![复杂的报纸布局示例](https://webkit.org/wp-content/uploads/Grid-Lanes-newspaper-demo-light.png)

```css
main {
  display: grid-lanes;
  grid-template-columns: repeat(auto-fill, minmax(20ch, 1fr));
  gap: 2lh;
}

article { 
  grid-column: span 1; 
}

@media (1250px < width) {
  article:nth-child(1) { 
    grid-column: span 4;             
  }
  article:nth-child(2), 
  article:nth-child(3), 
  article:nth-child(4), 
  article:nth-child(5), 
  article:nth-child(6), 
  article:nth-child(7), 
  article:nth-child(8) { 
    grid-column: span 2; 
  }
}
```

### 精确定位项目

我们还可以在使用 Grid Lanes 时显式放置项目。在下面的例子中，无论存在多少列，标题始终放置在最后一列：

```css
main {
  display: grid-lanes;
  grid-template-columns: repeat(auto-fill, minmax(24ch, 1fr));
}

header {
  grid-column: -3 / -1;
}
```

## 改变方向

是的，车道可以朝任一方向！上面的所有示例都创建了"瀑布"形状，其中内容按列布局。但 Grid Lanes 也可以用于创建另一个方向的布局，即"砖块"布局形状。

![瀑布布局与砖块布局对比](https://webkit.org/wp-content/uploads/Grid-Lanes-waterfall-v-brick-layout.png)

当你使用 `grid-template-columns` 定义列时，浏览器会自动创建瀑布布局：

```css
.container {
  display: grid-lanes;
  grid-template-columns: 1fr 1fr 1fr 1fr;
}
```

如果你想要另一个方向的砖块布局，可以使用 `grid-template-rows` 定义行：

```css
.container {
  display: grid-lanes;
  grid-template-rows: 1fr 1fr 1fr;
}
```

## 放置敏感度

"容差"是为 Grid Lanes 创建的新概念。它让你可以调整布局算法在决定放置项目位置时的挑剔程度。

通过 `item-tolerance` 属性，你可以控制只有当内容长度差异大于设定值时，才会影响下一个项目的放置位置。默认值是 `1em`。

```css
.container {
  display: grid-lanes;
  grid-template-columns: repeat(auto-fill, minmax(250px, 1fr));
  item-tolerance: 2em; /* 调整容差 */
}
```

把容差想象成你希望"司机"有多冷静。他们会为了前进几英寸而变道吗？还是只有在其他车道有很大空间时才会移动？

## 实际应用场景

Grid Lanes 不仅仅适用于图片！例如，一个充满链接的大型菜单页脚突然变得容易布局：

![大型菜单布局示例](https://webkit.org/wp-content/uploads/Grid-Lanes-mega-menu-light.png)

```css
.container {
  display: grid-lanes;
  grid-template-columns: repeat(auto-fill, minmax(max-content, 24ch));
  column-gap: 4lh;
}
```

## 浏览器支持与未来

目前，CSS Grid Lanes 可以在 Safari Technology Preview 234 中体验。CSS 工作组还有一些最后的决定要做，但总体而言，本文描述的功能已经准备就绪。

一些属性名称可能还会发生变化：
- `item-tolerance` 可能会改名为 `flow-tolerance` 或 `pack-tolerance`
- 流向控制属性的最终语法仍在讨论中

## 总结

CSS Grid Lanes 为我们带来了期待已久的原生瀑布流布局解决方案。相比传统的 JavaScript 库，它具有以下优势：

1. **性能更好**：原生 CSS 实现，无需 JavaScript 计算
2. **响应式友好**：自动适应不同屏幕尺寸
3. **可访问性更佳**：支持键盘导航和屏幕阅读器
4. **功能更强大**：结合 CSS Grid 的所有特性

虽然目前还在实验阶段，但这项技术代表了 Web 布局的未来。作为前端开发者，我们应该关注并学习这项新技术，为将来的广泛应用做好准备。

你可以在 [webkit.org/demos/grid3](https://webkit.org/demos/grid3/) 查看更多演示，开始探索 CSS Grid Lanes 的无限可能！