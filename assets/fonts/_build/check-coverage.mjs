#!/usr/bin/env node
// 核对「站点实际用字」是否都被生成的字子集覆盖。
//
// build-fonts.mjs 的字符集里掺了预设区段（制表符、竖排标点、全角符号……），
// 字体本身没有这些码位，直接比较会得到几百个「缺失」，不能说明问题。
// 这个脚本只拿内容用字 + 主题 UI 文案去比 cmap。
//
// 用法：node check-coverage.mjs [--strict]
//   --strict  有缺失就 exit 1；默认只报告，exit 0
import { readFileSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';
import fontverter from 'fontverter';

const HERE = import.meta.dirname;
const SITE = path.resolve(process.env.FONT_SITE || path.join(HERE, '..', '..', '..'));
const CONTENT_SITE = path.resolve(process.env.FONT_CONTENT_SITE || SITE);
const FONTS = path.join(SITE, 'assets', 'fonts');

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

const THEME_UI =
  '首页 归档 分类 标签 关于 搜索 目录 阅读时间 分享 复制 已复制 返回顶部 上一篇 下一篇 ' +
  '第 页 共 条 暂无 加载中 深色 浅色 主题 文章 更新于 发布于 作者 评论 相关推荐 本站 ' +
  '分钟 秒 小时 天 年 月 日 更多 收起 展开 全部 搜索文章 清除 确认 取消 关闭 打开 排序';

function tables(buf) {
  const numTables = buf.readUInt16BE(4);
  const out = {};
  for (let i = 0; i < numTables; i++) {
    const off = 12 + i * 16;
    out[buf.toString('ascii', off, off + 4)] = {
      offset: buf.readUInt32BE(off + 8),
      length: buf.readUInt32BE(off + 12),
    };
  }
  return out;
}

// 只解析 format 4 / 12 的 cmap（subset-font 产出就这两种）。
function cmap(buf, t) {
  const c = t.cmap;
  const n = buf.readUInt16BE(c.offset + 2);
  const cps = new Set();
  for (let i = 0; i < n; i++) {
    const rec = c.offset + 4 + i * 8;
    const platformID = buf.readUInt16BE(rec);
    const offset = c.offset + buf.readUInt32BE(rec + 4);
    if (platformID !== 3 && platformID !== 0) continue;
    const format = buf.readUInt16BE(offset);
    if (format === 4) {
      const segX2 = buf.readUInt16BE(offset + 6);
      const ends = offset + 14;
      const starts = ends + segX2 + 2;
      const deltas = starts + segX2;
      const ranges = deltas + segX2;
      for (let s = 0; s < segX2 / 2; s++) {
        const end = buf.readUInt16BE(ends + s * 2);
        const start = buf.readUInt16BE(starts + s * 2);
        const delta = buf.readUInt16BE(deltas + s * 2);
        const ro = buf.readUInt16BE(ranges + s * 2);
        if (start === 0xffff) continue;
        for (let cp = start; cp <= end; cp++) {
          let g;
          if (ro === 0) g = (cp + delta) & 0xffff;
          else {
            const gi = ranges + s * 2 + ro + (cp - start) * 2;
            if (gi + 1 >= buf.length) continue;
            g = buf.readUInt16BE(gi);
            if (g !== 0) g = (g + delta) & 0xffff;
          }
          if (g !== 0) cps.add(cp);
        }
      }
    } else if (format === 12) {
      const nGroups = buf.readUInt32BE(offset + 12);
      for (let g = 0; g < nGroups; g++) {
        const base = offset + 16 + g * 12;
        const start = buf.readUInt32BE(base);
        const end = buf.readUInt32BE(base + 4);
        for (let cp = start; cp <= end; cp++) cps.add(cp);
      }
    }
  }
  return cps;
}

const chars = new Set();
for (const ch of THEME_UI) if (ch.trim()) chars.add(ch);
let contentFiles = 0;
for (const f of walk(CONTENT_SITE)) {
  contentFiles++;
  for (const ch of readFileSync(f, 'utf8')) chars.add(ch);
}
chars.delete('\ufeff');
chars.delete('\r');

const charset = [...chars].sort((a, b) => a.codePointAt(0) - b.codePointAt(0));
const strict = process.argv.includes('--strict');
let bad = 0;

for (const name of ['maplen-mono-nf-cn-regular.woff2', 'maplen-mono-nf-cn-bold.woff2']) {
  const file = path.join(FONTS, name);
  const buf = await fontverter.convert(readFileSync(file), 'sfnt');
  const t = tables(buf);
  const cps = cmap(buf, t);
  const missing = charset.filter((ch) => !cps.has(ch.codePointAt(0)));
  const missingCJK = missing.filter((ch) => ch.codePointAt(0) >= 0x3000 && ch.codePointAt(0) <= 0x9fff);
  const label = (ch) => (ch.codePointAt(0) < 0x20 ? `\\u${ch.codePointAt(0).toString(16)}` : ch);

  console.log(`${name}: ${contentFiles} files / ${charset.length} chars, missing ${missing.length} (CJK ${missingCJK.length})`);
  if (missing.length) {
    console.log(`  not in font (fallback to system font): ${missing.map(label).join(' ')}`);
  }
  if (missingCJK.length) {
    console.error(`  [error] CJK missing: ${missingCJK.join('')}`);
    bad++;
  }
  if (strict && missing.length) bad++;
}

if (bad) process.exit(1);