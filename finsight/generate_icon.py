from PIL import Image, ImageDraw

def create_icon(with_bg=True, filename='assets/icon.png'):
    size = 1024
    bg_color = '#634DFF' if with_bg else (0, 0, 0, 0)
    img = Image.new('RGBA', (size, size), color=bg_color)
    draw = ImageDraw.Draw(img)

    # In Material Icons, bar_chart is three vertical bars of increasing height.
    # Actually, it's left: tall, middle: short, right: medium? No, left is medium, middle tall, right short?
    # Wait, Material 'bar_chart' is usually left short, middle tall, right medium.
    # Let's draw: left short, middle tall, right medium.
    
    # dimensions: make it fit nicely within 500x500 box centered at 512,512
    # safe zone for adaptive icons is a 600x600 circle.
    bar_width = 80
    gap = 60
    total_width = 3 * bar_width + 2 * gap # 240 + 120 = 360
    start_x = (size - total_width) // 2 # 332
    
    base_y = 662
    
    # Left bar (medium)
    left1 = start_x
    right1 = left1 + bar_width
    top1 = 482
    draw.rectangle([left1, top1, right1, base_y], fill='white')
    
    # Middle bar (tall)
    left2 = right1 + gap
    right2 = left2 + bar_width
    top2 = 362
    draw.rectangle([left2, top2, right2, base_y], fill='white')
    
    # Right bar (short)
    left3 = right2 + gap
    right3 = left3 + bar_width
    top3 = 542
    draw.rectangle([left3, top3, right3, base_y], fill='white')

    # Add corner radius if requested (iOS automatically masks, but Android non-adaptive might need it, actually flutter_launcher_icons handles adaptive).
    # Since we use this for iOS and Android default, we can just save it as a square.
    
    img.save(filename)
    print(f"Saved {filename}")

if __name__ == '__main__':
    create_icon(with_bg=True, filename='assets/icon.png')
    create_icon(with_bg=False, filename='assets/icon_foreground.png')
