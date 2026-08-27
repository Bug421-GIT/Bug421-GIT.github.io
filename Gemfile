source "https://rubygems.org"

# Jekyll 核心与 Chirpy 主题
gem "jekyll", "~> 4.3.2"
gem "jekyll-theme-chirpy", "~> 7.5"

# Chirpy 依赖的插件（GitHub Pages 自带 Jekyll 不支持自定义 gem，
# 所以必须用 GitHub Actions 构建，不能用 "Deploy from a branch"）
group :jekyll_plugins do
  gem "jekyll-archives"
  gem "jekyll-paginate"
  gem "jekyll-redirect-from"
  gem "jekyll-seo-tag"
  gem "jekyll-sitemap"
  gem "jekyll-feed"
  gem "jekyll-imagemagick"
end

# Ruby 3.4+ 不再默认包含这些 gem，Jekyll 4.3.x 启动时会报 LoadError
gem "csv"
gem "base64"

# 时区支持（_config.yml 设了 timezone: Asia/Shanghai，Windows 需要 tzinfo-data）
gem "tzinfo"
gem "tzinfo-data"

# 本地预览需要
gem "webrick", "~> 1.8"
