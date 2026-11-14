#!/usr/bin/env node
// 把 Maple Mono NF CN 的完整 TTF 裁剪成「站点实际用字」子集，输出 woff2 到 <站点>/assets/fonts/。
//
// 依赖：subset-font（Harfbuzz 的 wasm 版本）。在 assets/fonts/_build 目录里执行一次：
//   npm install --prefix . subset-font fontverter
// （fontverter 只给 check-coverage.mjs 用，装在一起省事。）
//
// 输入：把 MapleMono-NF-CN-unhinted.zip 里这两个文件放进 _build/raw/：
//   MapleMono-NF-CN-Regular.ttf   MapleMono-NF-CN-Bold.ttf   LICENSE.txt
//
// 输出：
//   assets/fonts/maplen-mono-nf-cn-regular.woff2
//   assets/fonts/maplen-mono-nf-cn-bold.woff2
//   assets/fonts/LICENSE-MapleMono.txt
//
// 环境变量（调试用，正常不必设）：
//   FONT_RAW_DIR        原始 TTF 所在目录，默认 _build/raw
//   FONT_SITE           站点根目录，产物写到 <FONT_SITE>/assets/fonts，默认 _build 往上三级
//   FONT_CONTENT_SITE   扫描用字的根目录，默认同 FONT_SITE
//
// 注意：Jekyll 不发布以 _ 开头的目录，所以 _build 下的 raw/ 与 node_modules/ 不会进 _site。
import { readFileSync, writeFileSync, readdirSync, statSync, mkdirSync, copyFileSync, existsSync } from 'node:fs';
import path from 'node:path';
import subsetFont from 'subset-font';

const HERE = import.meta.dirname;
const SITE = path.resolve(process.env.FONT_SITE || path.join(HERE, '..', '..', '..'));
const CONTENT_SITE = path.resolve(process.env.FONT_CONTENT_SITE || SITE);
const RAW = path.resolve(process.env.FONT_RAW_DIR || path.join(HERE, 'raw'));
const OUT = path.join(SITE, 'assets', 'fonts');

// _site 是构建产物；assets/lib、assets/js 是第三方/压缩脚本，扫进去只会把 JS 里的零散字符混进字符集。
const SKIP_DIRS = new Set([
  '_site',
  '.git',
  '.jekyll-cache',
  '.sass-cache',
  'node_modules',
  '.obsidian',
  '.workbuddy',
  '_build',
  'lib',
  'js',
]);
const EXT = new Set(['.md', '.html', '.htm', '.yml', '.yaml', '.json', '.xml', '.txt']);

function walk(dir, files = []) {
  for (const name of readdirSync(dir)) {
    if (SKIP_DIRS.has(name)) continue;
    const p = path.join(dir, name);
    const st = statSync(p);
    if (st.isDirectory()) walk(p, files);
    else if (EXT.has(path.extname(name).toLowerCase())) files.push(p);
  }
  return files;
}

// 主题自己渲染的 UI 文案来自 gem 的 _locales/zh-CN.yml，不在本仓库里，
// 但页面会用到，所以在这里补一份；漏字会掉进系统字体，一眼能看出来。
const THEME_UI =
  '首页 归档 分类 标签 关于 搜索 目录 阅读时间 分享 复制 已复制 返回顶部 上一篇 下一篇 ' +
  '第 页 共 条 暂无 加载中 深色 浅色 主题 文章 更新于 发布于 作者 评论 相关推荐 本站 ' +
  '分钟 秒 小时 天 年 月 日 更多 收起 展开 全部 搜索文章 清除 确认 取消 关闭 打开 排序';

// 预设区段：正文里最常见、但可能没出现在当前文章里的字符（全角标点、箭头、数学符号等）。
// 字体本身没有的码位会被 subset-font 忽略，不会有事。
const RANGES = [
  [0x0020, 0x007e], // ASCII 可打印
  [0x00a0, 0x00ff], // Latin-1
  [0x2010, 0x2027], // 破折号、引号、省略号
  [0x2030, 0x205e], // 其它标点
  [0x20ac, 0x20ac], // €
  [0x2116, 0x2116], // №
  [0x2190, 0x21ff], // 箭头
  [0x2200, 0x22ff], // 数学运算符
  [0x2460, 0x24ff], // 带圈数字
  [0x2500, 0x257f], // 制表符
  [0x25a0, 0x25ff], // 几何图形
  [0x2600, 0x26ff], // 杂项符号
  [0x2700, 0x27bf], // dingbats
  [0x3000, 0x303f], // CJK 标点
  [0xfe10, 0xfe1f], // 竖排标点
  [0xff00, 0xffef], // 全角字符
];

const chars = new Set();
for (const ch of THEME_UI) if (ch.trim()) chars.add(ch);
for (const [a, b] of RANGES) for (let cp = a; cp <= b; cp++) chars.add(String.fromCodePoint(cp));

const contentFiles = walk(CONTENT_SITE);
for (const f of contentFiles) {
  for (const ch of readFileSync(f, 'utf8')) chars.add(ch);
}
chars.delete('\ufeff');

const charset = [...chars].sort((a, b) => a.codePointAt(0) - b.codePointAt(0));
const text = charset.join('');
console.log(`content root: ${CONTENT_SITE}`);
console.log(`content files: ${contentFiles.length}, distinct chars: ${charset.length}`);

mkdirSync(OUT, { recursive: true });

const weights = [
  ['Regular', 'maplen-mono-nf-cn-regular.woff2'],
  ['Bold', 'maplen-mono-nf-cn-bold.woff2'],
];
for (const [weight, outName] of weights) {
  const srcPath = path.join(RAW, `MapleMono-NF-CN-${weight}.ttf`);
  const src = readFileSync(srcPath);
  const subset = await subsetFont(src, text, { targetFormat: 'woff2' });
  const dest = path.join(OUT, outName);
  writeFileSync(dest, subset);
  console.log(
    `${outName}: ${subset.length.toLocaleString()} B (${(subset.length / 1024).toFixed(1)} KiB), ` +
      `source ${src.length.toLocaleString()} B`,
  );
}

const license = path.join(RAW, 'LICENSE.txt');
if (existsSync(license)) {
  copyFileSync(license, path.join(OUT, 'LICENSE-MapleMono.txt'));
  console.log('license copied');
} else {
  console.warn(`[warn] ${license} 不存在，跳过许可证复制`);
}