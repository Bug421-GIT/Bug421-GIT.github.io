#!/usr/bin/env ruby
# frozen_string_literal: true

# _posts 静态检查。下面这些问题 Jekyll 一律不报错，只是渲染结果不对，
# 所以放在 build 之前跑一遍，省得靠肉眼在页面上找。
#
#   ruby bin/check-posts.rb                    # 扫 _posts，只列错误和警告
#   ruby bin/check-posts.rb _posts/vueBase     # 只扫指定目录
#   ruby bin/check-posts.rb -v                 # 连「提示」级也逐条列出
#   ruby bin/check-posts.rb -w                 # 警告也当失败（CI 用）
#
# 检查项：
#   文件名       必须是 YYYY-MM-DD-标题.md，缺标题段会被静默忽略
#   front matter  title / date / categories / layout
#   标题         行首缩进的 # 不会被识别（kramdown 要求顶格，不像 CommonMark 允许 3 空格）
#   代码段       单个反引号后紧跟空白不会被识别（kramdown 特有，结尾空白反而是允许的）
#   反引号       没有闭合的会原样显示在页面上
#   加粗         闭合 ** 前有空白不会被识别（这条 CommonMark 也一样）
#   竖线         正文裸写 | 会被当成表格（kramdown 不要求 |---| 分隔行，行内代码里的除外）
#   行内 HTML    <u> 里的 markdown 不会被解析
#   Liquid       render_with_liquid: false 时 {% raw %} 会原样显示在页面上
#   围栏         未闭合、语言名 Rouge 认不出（认不出就退化成无高亮的裸 pre）
#   字符         围栏内的不间断空格 U+00A0
#
# 有意不查：围栏内的中文标点（，：、）。中文注释里出现这些是正常的，查了全是误报。

require 'optparse'

begin
  require 'rouge'
  ROUGE_LOADED = true
rescue LoadError
  ROUGE_LOADED = false
end

options = { strict: false, verbose: false }
OptionParser.new do |o|
  o.banner = '用法: ruby bin/check-posts.rb [目录或文件...] [-w] [-v]'
  o.on('-w', '--warnings-as-errors', '把警告也算作失败') { options[:strict] = true }
  o.on('-v', '--verbose', '连「提示」级也逐条列出') { options[:verbose] = true }
  o.on('-h', '--help') { puts o; exit 0 }
end.parse!

targets = ARGV.empty? ? ['_posts'] : ARGV

files = targets.flat_map do |t|
  if File.directory?(t)
    Dir.glob(File.join(t, '**', '*.md'))
  elsif File.file?(t)
    [t]
  else
    warn "找不到: #{t}"
    []
  end
end.sort

if files.empty?
  warn '没有找到任何 .md 文件'
  exit 1
end

# level: :error 渲染一定错 / :warn 很可能错 / :info 只是不干净
# kind 只用于汇总分组，避免把消息里的 U+200B 这类数字抹掉。
Problem = Struct.new(:file, :line, :level, :kind, :message)

KIND_LABEL = {
  filename: '文件名不合规（Jekyll 会静默忽略）',
  fm_unclosed: 'front matter 未闭合',
  fm_missing: 'front matter 缺必填键',
  layout: 'layout 不是 post',
  raw_unbalanced: '{% raw %} 与 {% endraw %} 数量不等',
  raw_liquid_off: 'render_with_liquid: false 下的 {% raw %}',
  fence_lang: '围栏语言名 Rouge 认不出',
  fence_unclosed: '围栏未闭合',
  nbsp: '围栏内不间断空格 U+00A0',
  heading_indent: '标题 # 前有缩进',
  zwsp: '行首零宽空格 U+200B',
  tick_unclosed: '反引号没有闭合',
  tick_leading_space: '单反引号后紧跟空白',
  bold_unclosed: '加粗 ** 数量为奇数',
  bold_leading_space: '加粗开头 ** 后紧跟空白',
  bold_trailing_space: '加粗闭合 ** 前有空白',
  inline_html_md: '<u> 里包了 markdown',
  bare_pipe: '正文裸竖线'
}.freeze

FENCE_OPEN = /\A\s*(`{3,}|~{3,})\s*(\S*)/
FILENAME   = /\A\d{4}-\d{1,2}-\d{1,2}-.+\.md\z/
REQUIRED   = %w[title date categories layout].freeze

# kramdown 的代码段规则（本机实测，和 CommonMark 不一样）：
#   ` x`    → 不解析，原样显示（单个反引号，内容以空白开头）
#   `x `    → <code>x </code>（结尾空白反而允许）
#   `` x `` → <code>x</code>（两个及以上反引号，首尾空白都会被 strip）
#   `` 空 `` → 不解析
# 所以「前导空白」这条只对长度为 1 的反引号成立。
#
# 返回 [issues, ranges]：
#   issues 是 [[类型, 行内下标], ...]
#   ranges 是代码段的 [起, 止) 区间，给竖线检测用
def scan_code_spans(line)
  issues = []
  ranges = []
  i = 0
  len = line.length

  while i < len
    unless line[i] == '`' && (i.zero? || line[i - 1] != '\\')
      i += 1
      next
    end

    j = i
    j += 1 while j < len && line[j] == '`'
    run = j - i

    close_at = nil
    k = j
    while k < len
      if line[k] == '`' && line[k - 1] != '\\'
        m = k
        m += 1 while m < len && line[m] == '`'
        if (m - k) == run
          close_at = m
          break
        end
        k = m
      else
        k += 1
      end
    end

    if close_at.nil?
      issues << [:tick_unclosed, i]
      i = j
    else
      # 空内容（`` 中间什么都没有）本来就不解析，不算「前导空白」的错。
      issues << [:tick_leading_space, i] if run == 1 && j < len && line[j].match?(/[ \t]/) && j != close_at - 1
      ranges << [i, close_at]
      i = close_at
    end
  end

  [issues, ranges]
end

def strip_ranges(line, ranges)
  out = line.dup
  ranges.reverse_each { |s, e| out[s...e] = ' ' * (e - s) }
  out
end

# 表格行判定：kramdown 只要一行里有竖线就成表，所以「故意写的表格」只能靠上下文认。
# 认三种：以 | 开头（表头或数据行）、下一行是分隔行（本行是表头）、本行就是分隔行。
DELIM_CELL = /:?-+:?/
def delimiter_row?(text)
  t = text.strip
  return false unless t.include?('-') && t.include?('|')

  t.match?(%r{\A\|?\s*#{DELIM_CELL}\s*(\|\s*#{DELIM_CELL}\s*)*\|?\z})
end

problems = []

files.each do |path|
  lines = File.read(path, encoding: 'UTF-8').split("\n").map { |l| l.chomp("\r") }

  add = ->(ln, level, kind, msg) { problems << Problem.new(path, ln, level, kind, msg) }

  # ---------- 文件名 ----------
  base = File.basename(path)
  unless base.match?(FILENAME)
    add.call(nil, :error, :filename, "文件名必须是 YYYY-MM-DD-标题.md，现在是 #{base}")
  end

  # ---------- front matter ----------
  front = {}
  body_start = 0
  if lines[0]&.strip == '---'
    close = (1...lines.size).find { |i| lines[i].strip == '---' }
    if close.nil?
      add.call(1, :error, :fm_unclosed, '开头有 --- 但后面没有闭合的 ---')
    else
      lines[1...close].each do |l|
        m = /\A([A-Za-z_][\w-]*)\s*:\s*(.*)\z/.match(l)
        front[m[1]] = m[2] if m
      end
      body_start = close + 1
    end
  else
    add.call(1, :error, :fm_unclosed, '文件开头没有 front matter（--- 包起来的那段）')
  end

  REQUIRED.each do |key|
    add.call(nil, :error, :fm_missing, "缺少 #{key}") if front[key].to_s.strip.empty?
  end
  if front['layout'] && front['layout'].strip != 'post'
    add.call(nil, :warn, :layout, "layout 是 #{front['layout'].strip}，文章一般是 post")
  end

  # ---------- {% raw %} 配对 ----------
  raw_open  = lines.count { |l| l.include?('{% raw %}') }
  raw_close = lines.count { |l| l.include?('{% endraw %}') }
  if raw_open != raw_close
    add.call(nil, :error, :raw_unbalanced, "{% raw %} #{raw_open} 个，{% endraw %} #{raw_close} 个")
  end
  liquid_off = front['render_with_liquid'].to_s.strip == 'false'

  # ---------- 逐行 ----------
  in_fence  = false
  fence_ln  = nil

  lines.each_with_index do |line, idx|
    ln = idx + 1
    next if ln <= body_start

    if (m = FENCE_OPEN.match(line))
      if in_fence
        in_fence = false
      else
        in_fence = true
        fence_ln = ln
        tag = m[2]

        if ROUGE_LOADED && !tag.empty?
          lexer = begin
            Rouge::Lexer.find_fancy(tag, '')
          rescue StandardError
            nil
          end
          if lexer.nil?
            add.call(ln, :error, :fence_lang,
                     "语言名 #{tag.inspect} Rouge 认不出（退化成无高亮的裸 pre）")
          end
        end
      end
      next
    end

    if in_fence
      add.call(ln, :warn, :nbsp, '代码块里有不间断空格 U+00A0（复制会带出来）') if line.include?("\u00a0")
      next
    end

    next if line.strip.empty?

    # 行首缩进的标题。1~3 空格一定是正文；4 空格以上可能是故意的缩进代码块，降一级。
    if line.match?(/\A[ \t]+\#{1,6}\s/)
      indent = line[/\A[ \t]+/].length
      if indent >= 4
        add.call(ln, :warn, :heading_indent, "缩进 #{indent} 个空格，会被当成代码块")
      else
        add.call(ln, :error, :heading_indent, "缩进 #{indent} 个空格，kramdown 要求顶格，会当成正文")
      end
    end

    if line.start_with?("\u200b")
      add.call(ln, :info, :zwsp, '行首有零宽空格 U+200B')
    end

    if liquid_off && line.include?('{% raw %}')
      add.call(ln, :error, :raw_liquid_off, 'render_with_liquid: false 时 {% raw %} 会原样显示在页面上')
    end

    # 代码段
    tick_issues, code_ranges = scan_code_spans(line)
    tick_issues.each do |kind, at|
      msg = case kind
            when :tick_unclosed then '反引号没有闭合，会原样显示在页面上'
            else '单个反引号后紧跟空白，kramdown 不把它当代码段'
            end
      add.call(ln, :error, kind, msg)
    end

    # 加粗
    positions = []
    cursor = 0
    while (i = line.index('**', cursor))
      positions << i
      cursor = i + 2
    end
    if positions.size.odd?
      add.call(ln, :error, :bold_unclosed, "本行有 #{positions.size} 个 **，无法配对")
    else
      positions.each_slice(2) do |open_i, close_i|
        if line[open_i + 2]&.match?(/\s/)
          add.call(ln, :error, :bold_leading_space, '开头 ** 后面紧跟空白，不会被解析')
        end
        if close_i.positive? && line[close_i - 1]&.match?(/\s/)
          add.call(ln, :error, :bold_trailing_space, '闭合 ** 前面有空白，不会被解析')
        end
      end
    end

    # 行内 HTML 里的 markdown
    line.scan(%r{<u>(.*?)</u>}) do |(inner)|
      if inner.match?(/`|\*\*|\[/)
        add.call(ln, :error, :inline_html_md, '<u> 里的 markdown 不会被解析，把 <u> 挪到标记外面')
      end
    end

    # 裸竖线。先抹掉代码段（里面的 | 安全），再去掉已转义的 \|。
    no_code = strip_ranges(line, code_ranges)
    no_esc  = no_code.gsub('\\|', '')
    next if no_esc.empty?

    table_row = line.strip.start_with?('|') ||
                delimiter_row?(line) ||
                delimiter_row?(lines[idx + 1].to_s)

    if no_esc.include?('|') && !table_row
      add.call(ln, :error, :bare_pipe, '正文里的 | 会被 kramdown 当成表格，要写成 \|')
    end
  end

  add.call(fence_ln, :error, :fence_unclosed, '围栏没有闭合') if in_fence
end

# ---------- 输出 ----------
MARK  = { error: 'x', warn: '!', info: '.' }.freeze
LABEL = { error: '错误', warn: '警告', info: '提示' }.freeze
shown = options[:verbose] ? %i[error warn info] : %i[error warn]

visible = problems.select { |p| shown.include?(p.level) }

visible.group_by(&:file).sort.each do |file, list|
  puts file
  list.sort_by { |p| p.line.to_i }.first(8).each do |p|
    loc = p.line ? format('%4d', p.line) : '   -'
    puts "  #{loc}  #{MARK[p.level]} #{LABEL[p.level]}  #{p.message}"
  end
  puts "        …另有 #{list.size - 8} 条" if list.size > 8
  puts
end

counts = Hash.new(0)
problems.each { |p| counts[p.level] += 1 }

puts '—' * 68
puts "扫描 #{files.size} 个文件：#{counts[:error]} 个错误，#{counts[:warn]} 个警告，#{counts[:info]} 个提示"

unless problems.empty?
  puts
  puts '按类型汇总：'
  problems.group_by { |p| [p.level, p.kind] }
          .sort_by { |(lv, _), v| [-v.size, lv.to_s] }
          .each do |(lv, kind), v|
    puts format('  %-4s %-4d %s', LABEL[lv], v.size, KIND_LABEL[kind] || kind)
  end
  unless options[:verbose]
    puts
    puts '加 -v 可以看到「提示」级的逐条位置。'
  end
end

exit 1 if counts[:error].positive? || (options[:strict] && counts[:warn].positive?)
exit 0
