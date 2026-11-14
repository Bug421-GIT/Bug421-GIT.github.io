# frozen_string_literal: true

# 给正文里缺尺寸的站内图片补上 width/height，让浏览器在图片解码前就能按宽高比占位。
# 为什么需要：Chirpy 会给正文图片加 loading="lazy"，图片没有内在尺寸时，解码完成
# 会把下方内容整体顶下去（实测 68142 B 的 PNG 撑出 413px，CLS 0.1287）。
# 只处理「以 / 开头的站内路径 + 能在 source 里找到的文件」，外链、data URI、
# 已经带 width 的标签一律不动；识别不了格式就跳过，交给原来的行为。
module ChirpyImageSize
  module_function

  def png_size(io)
    head = io.read(24)
    return nil unless head && head.bytesize == 24 && head.start_with?("\x89PNG\r\n\x1A\n".b)

    head[16, 8].unpack('N2')
  end

  def gif_size(io)
    head = io.read(10)
    return nil unless head && head.start_with?('GIF8')

    head[6, 4].unpack('v2')
  end

  def jpeg_size(io)
    return nil unless io.read(2) == "\xFF\xD8".b

    loop do
      marker = io.read(2)
      return nil unless marker && marker.getbyte(0) == 0xFF

      type = marker.getbyte(1)
      next if type == 0xFF # 填充字节

      length = io.read(2)&.unpack1('n')
      return nil unless length

      # SOF0/1/2/3/5/6/7/9/10/11/13/14/15 都是带尺寸的帧头，排除 DHT/JPG/DAC。
      if (0xC0..0xCF).cover?(type) && ![0xC4, 0xC8, 0xCC].include?(type)
        io.read(1) # 精度
        height, width = io.read(4).unpack('n2')
        return [width, height]
      end

      io.seek(length - 2, IO::SEEK_CUR)
    end
  end

  def size_of(path)
    File.open(path, 'rb') do |io|
      case File.extname(path).downcase
      when '.png' then png_size(io)
      when '.gif' then gif_size(io)
      when '.jpg', '.jpeg' then jpeg_size(io)
      end
    end
  rescue StandardError
    nil
  end
end

Jekyll::Hooks.register [:documents, :pages], :post_render do |doc|
  next unless doc.output&.include?('<img')

  source = doc.site.source
  doc.output = doc.output.gsub(%r{<img\b[^>]*>}) do |tag|
    next tag if tag.match?(/\bwidth=/i)

    src = tag[/\bsrc="([^"]+)"/, 1]
    next tag unless src&.start_with?('/')

    path = File.join(source, src.delete_prefix('/'))
    next tag unless File.file?(path)

    width, height = ChirpyImageSize.size_of(path)
    next tag unless width.to_i.positive? && height.to_i.positive?

    tag.sub(/>$/, %( width="#{width}" height="#{height}">))
  end
end