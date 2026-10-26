import AppKit

/// 贴图图片的变换：旋转、翻转（右键菜单里的“向左/向右旋转、水平/垂直翻转”）
public enum PinImageOps {
    public enum Transform {
        case rotateLeft, rotateRight, flipHorizontal, flipVertical
    }

    /// 生成变换后的新图片；旋转会交换宽高
    public static func apply(_ transform: Transform, to image: CGImage) -> CGImage? {
        let w = image.width, h = image.height
        let rotates = transform == .rotateLeft || transform == .rotateRight
        let outW = rotates ? h : w, outH = rotates ? w : h
        guard let space = image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: outW, height: outH, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        // 先把坐标系变换好，再按原尺寸画进去
        switch transform {
        case .rotateLeft:  // 逆时针 90°
            context.translateBy(x: CGFloat(outW), y: 0)
            context.rotate(by: .pi / 2)
        case .rotateRight:  // 顺时针 90°
            context.translateBy(x: 0, y: CGFloat(outH))
            context.rotate(by: -.pi / 2)
        case .flipHorizontal:
            context.translateBy(x: CGFloat(outW), y: 0)
            context.scaleBy(x: -1, y: 1)
        case .flipVertical:
            context.translateBy(x: 0, y: CGFloat(outH))
            context.scaleBy(x: 1, y: -1)
        }
        context.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return context.makeImage()
    }

    /// 把文字（可带格式）画成图片：白底、四周留 10 点边距，按 scale 倍像素输出
    public static func image(from text: NSAttributedString, scale: CGFloat, maxWidth: CGFloat = 600) -> CGImage? {
        guard text.length > 0 else { return nil }
        let padding: CGFloat = 10
        let bounds = text.boundingRect(with: CGSize(width: maxWidth, height: .greatestFiniteMagnitude),
                                       options: [.usesLineFragmentOrigin, .usesFontLeading])
        let size = CGSize(width: ceil(bounds.width) + padding * 2, height: ceil(bounds.height) + padding * 2)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: Int(size.width * scale), height: Int(size.height * scale),
                                      bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(origin: .zero, size: size))

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        text.draw(with: CGRect(x: padding, y: padding, width: maxWidth, height: bounds.height),
                  options: [.usesLineFragmentOrigin, .usesFontLeading])
        NSGraphicsContext.restoreGraphicsState()
        return context.makeImage()
    }

    /// 贴图显示用的图片：先切圆角，再在四周留 6 点画光晕（同 iShot 的 addRoundImgae + resizeImage:scale:addShadowWithColor:）
    /// - glow: 光晕颜色，nil 表示不画（仍保留留边，窗口大小不变）
    public static func decorated(_ image: CGImage, pixelScale: CGFloat, cornerRadius: CGFloat,
                                 glow: CGColor?) -> CGImage? {
        let w = image.width, h = image.height
        let pad = Int(PinRules.glowPadding * pixelScale)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let rounded = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
              let canvas = CGContext(data: nil, width: w + pad * 2, height: h + pad * 2, bitsPerComponent: 8,
                                     bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }

        // 1. 圆角：按圆角路径裁剪后画原图
        let radius = min(cornerRadius * pixelScale, CGFloat(min(w, h)) / 2)
        rounded.addPath(CGPath(roundedRect: CGRect(x: 0, y: 0, width: w, height: h),
                               cornerWidth: radius, cornerHeight: radius, transform: nil))
        rounded.clip()
        rounded.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        guard let roundedImage = rounded.makeImage() else { return nil }

        // 2. 光晕：带阴影画到留边的画布中间，阴影不偏移、模糊 9 点
        if let glow {
            canvas.setShadow(offset: .zero, blur: PinRules.glowBlur * pixelScale, color: glow)
        }
        canvas.draw(roundedImage, in: CGRect(x: pad, y: pad, width: w, height: h))
        return canvas.makeImage()
    }

    /// 以 anchor（窗口内的点）为不动点缩放窗口：滚轮缩放时鼠标下的内容保持不动
    public static func zoomedFrame(_ frame: CGRect, from oldScale: CGFloat, to newScale: CGFloat,
                                   anchor: CGPoint) -> CGRect {
        let ratio = newScale / oldScale
        let size = CGSize(width: frame.width * ratio, height: frame.height * ratio)
        let origin = CGPoint(x: frame.minX + anchor.x * (1 - ratio), y: frame.minY + anchor.y * (1 - ratio))
        return CGRect(origin: origin, size: size)
    }
}
