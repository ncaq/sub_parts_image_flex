# -*- coding: utf-8 -*-
miquire :mui, 'sub_parts_helper'

require 'gtk2'
require 'cairo'

Plugin.create :sub_parts_image do
  defimageopener('youtube thumbnail (shrinked)', /^http:\/\/youtu.be\/([^\?\/\#]+)/) do |url|
    /^http:\/\/youtu.be\/([^\?\/\#]+)/.match(url)
    open("http://img.youtube.com/vi/#{$1}/0.jpg")
  end

  defimageopener('youtube thumbnail', /^https?:\/\/www\.youtube\.com\/watch\?v=([^\&]+)/) do |url|
    /^https?:\/\/www\.youtube\.com\/watch\?v=([^\&]+)/.match(url)
    open("http://img.youtube.com/vi/#{$1}/0.jpg")
  end

  defimageopener('niconico video thumbnail(shrinked)', /^http:\/\/nico.ms\/sm([0-9]+)/) do |url|
    /^http:\/\/nico.ms\/sm([0-9]+)/.match(url)
    open("http://tn-skr#{($1.to_i % 4) + 1}.smilevideo.jp/smile?i=#{$1}")
  end

  defimageopener('niconico video thumbnail', /nicovideo\.jp\/watch\/sm([0-9]+)/) do |url|
    /nicovideo\.jp\/watch\/sm([0-9]+)/.match(url)
    open("http://tn-skr#{($1.to_i % 4) + 1}.smilevideo.jp/smile?i=#{$1}")
  end

  # サブパーツ
  class Gdk::SubPartsImage < Gdk::SubParts
    regist

    # イメージ取得完了
    def on_image_loaded(pos, pixbuf)
      # puts "#{@helper_message[0..10]} image loaded start #{pos}"

      if !helper.destroyed?
        # 再描画イベント
        sid = helper.ssc(:expose_event, helper) {
          # サブパーツ描画
          helper.on_modify
          helper.signal_handler_disconnect(sid)
          false
        }
      end

      # サブパーツ描画
      @main_icons[pos] = pixbuf

      # puts "#{@helper_message[0..10]} draw ready #{pos}"

      Delayer.new {
        # puts "#{@helper_message[0..10]} draw image #{pos}"
        helper.on_modify
      }
    end

    # 画像URLが解決したタイミング
    def on_image_information(urls)
      if urls.length == 0
        return
      end

      helper.reset_height

      if !helper.destroyed?
        # クリックイベント
        @ignore_event = false

        helper.ssc(:click) { |this, e, x, y|
          # クリック位置の特定
          offset = helper.mainpart_height

          helper.subparts.each { |part|
            if part == self
              break
            end

            offset += part.height
          }

          clicked_url, = urls.lazy.with_index.map{|url, pos|
            rect = image_draw_area(pos, self.width)
            [url, rect.x ... rect.x+rect.width, rect.y+offset ... rect.y+offset+rect.height]
          }.find{|url, xrange, yrange|
            xrange.include?(x) and yrange.include?(y) }
          case e.button
          when 1
            Plugin.call(:openimg_open, clicked_url) if clicked_url
          end

        }
      end
    end

    # コンストラクタ
    def initialize(*args)
      super
      @main_icons = []

      if helper.message
        # イメージ読み込みスレッドを起こす
        Thread.new(helper.message) { |message|
          urls = message.entity
                 .select{ |entity| %i<urls media>.include? entity[:slug] }
                 .map { |entity|
            case entity[:slug]
            when :urls
              entity[:expanded_url]
            when :media
              entity[:media_url]
            end
          } + Array(message[:subparts_images])

          streams = urls.map{ |url| Plugin.filtering(:openimg_raw_image_from_display_url, url, nil) }
                    .select{ |pair| pair.last }

          Delayer.new{ on_image_information streams.map(&:first) }

          streams.each.with_index do |pair, index|
            _, stream = *pair
            Thread.new {
              pixbuf = Gdk::PixbufLoader.open{ |loader|
                loader.write(stream.read)
                stream.close
              }.pixbuf

              Delayer.new {
                on_image_loaded(index, pixbuf)
              }
            }.trap{ |exception|
              error exception
            }
          end
        }.trap{ |exception| error exception }
      end
    end

    # 画像を描画する座標とサイズを返す
    # ==== Args
    # [pos] Fixnum 画像インデックス
    # [canvas_width] Fixnum キャンバスの幅(px)
    # ==== Return
    # Gdk::Rectangle その画像を描画する場所
    def image_draw_area(pos, canvas_width)
      width = canvas_width / @main_icons.length
      height = width / Rational(16, 9)
      x = width * pos
      y = 0
      Gdk::Rectangle.new(x, y, width, height)
    end

    # サブパーツを描画
    def render(context)
      @main_icons.compact.each.with_index { |icon, pos|
        draw_rect = image_draw_area(pos, self.width)
        wscale = draw_rect.width.to_f  / icon.width
        hscale = draw_rect.height.to_f / icon.height
        scale = [wscale, hscale].min # アスペクト比を保ち,はみ出さない範囲のスケール
        icon = icon.scale(icon.width * scale, icon.height * scale)
        context.save {
          context.translate(draw_rect.x, draw_rect.y)
          context.set_source_pixbuf(icon)
          context.paint
        }
      }
    end

    def height
      if @main_icons.length == 0
        0
      else
        draw_rect = image_draw_area(@main_icons.length - 1, self.width)
        draw_rect.y + draw_rect.height
      end
    end
  end
end
