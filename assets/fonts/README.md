# Maple Mono NF CN（站点正文字体）

这里放的是按本站实际用字裁剪过的 Maple Mono NF CN 子集字体，站点的 `assets/css/jekyll-theme-chirpy.scss` 用 `@font-face` 引用它们。

| 文件 | 大小 | 说明 |
| --- | --- | --- |
| `maplen-mono-nf-cn-regular.woff2` | 311,288 B (304 KiB) | 字重 400 |
| `maplen-mono-nf-cn-bold.woff2` | 319,628 B (312 KiB) | 字重 700 |
| `LICENSE-MapleMono.txt` | 4,394 B | 原字体 OFL 许可证，**随字体一起发布，不要删** |

> 文件名里的 `maplen` 是早期笔误（应为 `maple`），改名要同时动 `@font-face` 和本目录三个文件，暂时保持原样。

## 为什么要裁剪

原包 `MapleMono-NF-CN-unhinted.zip`（v7.8）里单个 TTF 就有 20 MB（`Regular` 20,563,148 B，`Bold` 20,516,304 B），四个字重全上接近 100 MB。本站正文只有一千多个不同的字，按用字裁剪后 woff2 每个只剩 300 KiB 出头，首屏代价从 20 MB 降到约 0.6 MB。

只保留 400 / 700 两个字重：正文用 400，`<strong>`、标题加粗用 700；主题里出现的 600（Medium）会被浏览器按「最近可用字重」选中 700，不单做一份。

## 覆盖情况

`node check-coverage.mjs` 报告（内容文件 68 个、用字 1,259 个；另一个统计口径含 `assets/lib` 下的第三方 JS 时为 2,901 字符）：

- 覆盖 1,232 字，**中文零缺失**（码位 U+3000–U+9FFF 全部命中）。
- 缺失 27 个，都是 Maple Mono 本身没有的码位，浏览器会回落到系统字体（Windows 上是微软雅黑/彩色 emoji 字体），不影响阅读：
  - 空白控制符：`\t`、`\n`
  - ① ② ③、❗、⃣（组合键帽）、️（VS16）、１２３４、＞
  - emoji：🌞 🌟 🎈 🏷 👍 👎 💬 📀 📜 🔖 🚩 🚫
  - U+2003（em space）、U+2049（⁉）

如果以后正文里出现新字，重建一次即可（见下）。

## 重建

```powershell
# 1. 解压字体包，只取需要的两个 TTF 和许可证
#    D:\Download\Edge\MapleMono-NF-CN-unhinted.zip
#    → assets/fonts/_build/raw/MapleMono-NF-CN-Regular.ttf
#    → assets/fonts/_build/raw/MapleMono-NF-CN-Bold.ttf
#    → assets/fonts/_build/raw/LICENSE.txt

cd assets/fonts/_build
npm install --prefix .          # 装 subset-font / fontverter（被 .gitignore 忽略）
node build-fonts.mjs            # 重新生成两个 woff2 + LICENSE-MapleMono.txt
node check-coverage.mjs         # 核对用字覆盖；加 --strict 时有缺失就 exit 1
```

`build-fonts.mjs` 的字符集由三部分组成：主题 UI 文案（来自 gem 的 `_locales/zh-CN.yml`，仓库里没有，脚本内手抄了一份）、`_build` 目录外的站点全部 `.md/.html/.yml/.json/.xml/.txt`、以及一段预设区段（ASCII、Latin-1、CJK 标点、全角字符、箭头、数学符号等，字体没有的码位会被自动忽略）。

`_build` 以 `_` 开头，Jekyll 不会把它复制进 `_site`，所以脚本、`raw/`、`node_modules/` 都不会被发布；`raw/` 与 `node_modules/` 另外写进了 `.gitignore`，40 MB 的 TTF 不进仓库。

## 启用方式：首访兜底，之后才是 Maple

不做「先画兜底、字体到了再换」——实测换字必然重排。`assets/css/jekyll-theme-chirpy.scss` 不覆盖 `$font-family-base`，而是把所有 Maple 规则挂在 `html.maple-font` 下，`@font-face` 用 `font-display: block`。加不加这个类，由 `_includes/head.html` 里的内联脚本在**渲染前**决定：

1. 读 `localStorage['maple-font'] === '1'`，命中才给 `<html>` 加 `maple-font`；
2. 同页两条 `rel="preload" as="font" type="font/woff2" crossorigin` 把两个 woff2 拉进 HTTP 缓存；
3. `DOMContentLoaded` 后 `document.fonts.load("400 16px 'Maple Mono NF CN'")` 成功，才写入该标记。只等 400：700 的 FontFace 在没人使用时会一直停在 `unloaded`，等两个都 ready 标记就永远写不进去；
4. 内联脚本里只能写 `/* */` 块注释：站点用 jekyll-compress-html，会把 `<script>` 的换行压成空格，`//` 行注释会吞掉后面的代码（实测报 `Uncaught SyntaxError: Unexpected end of input`）。

代价：首次访问（或清缓存、隐私模式）落地页是主题原来的 Source Sans Pro / 微软雅黑，跳一次页或再次访问起，首帧就是 Maple。

为什么不靠 `font-display` 硬扛（Edge 157，CDP 限速 60KB/s，`layout-shift` 实测）：

| 取值 | 首屏行为 | FCP 之后 CLS |
| --- | --- | --- |
| `swap` | 先画兜底，字体到达后换 | 0.1287 |
| `optional` | 同样换了一次 | 0.1287 |
| `block` | 文字先不可见，出现后仍推图 | 0.1285 |

同一篇文章整页高差 445px：40px 的 `MMMMM` 在 Maple 下 51.8px、兜底下 84.4px。

## 站点侧引用

改字体时四处要一起看：

1. `assets/css/jekyll-theme-chirpy.scss` 的两个 `@font-face`，路径 `/assets/fonts/maplen-mono-nf-cn-*.woff2`；
2. `html.maple-font { --bs-font-monospace: ... }`，让 `code`/`pre`/`kbd` 也走同一套字体；
3. 主题里写死 `Lato`/`Oswald`/`sans-serif` 的残留规则（`body`、标题、`header .post-desc`、`#toc-bar .label`、`kbd`、`.pagination`、`#archives .date.day`、`.tag span`、`#topbar-title`、`#toc-popup` 等）统一列在同一组 `html.maple-font` 选择器里；
4. `_includes/head.html` 的标记脚本、两条 preload、预热脚本。

> 同批修掉的另一个位移源跟字体无关：`_plugins/img-size-hook.rb` 给懒加载图片补 `width`/`height`，否则图片解码完成会把正文推下约 400px（CLS 0.1287）。CI 用 `bundle exec jekyll build`，自定义插件会执行。

## 来源与许可

Maple Mono（v7.8，含 Nerd Font 3.4.0 图标与 CN 变体）采用 SIL Open Font License 1.1，允许子集化与再分发，但必须附带原始许可证文件——即 `LICENSE-MapleMono.txt`。