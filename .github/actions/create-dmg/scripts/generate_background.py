#!/usr/bin/env python3
import sys
from PIL import Image, ImageDraw, ImageFont

def create_background(output_path):
    width, height = 700, 500
    background_color = (240, 240, 240)  # Light gray
    arrow_color = (100, 100, 100)       # Dark gray
    text_color = (80, 80, 80)           # Darker gray

    # Create image
    img = Image.new('RGB', (width, height), color=background_color)
    draw = ImageDraw.Draw(img)

    # Coordinates
    icon_y = 225 + 70  # Center of icon (roughly)
    start_x = 180 + 70 + 20 # Right edge of app icon
    end_x = 520 - 20        # Left edge of Applications icon
    
    # Draw arrow
    # Line
    draw.line([(start_x, icon_y), (end_x, icon_y)], fill=arrow_color, width=4)
    # Arrowhead
    arrow_head = [(end_x, icon_y), (end_x - 15, icon_y - 10), (end_x - 15, icon_y + 10)]
    draw.polygon(arrow_head, fill=arrow_color)

    # Add text
    text = "Drag CopyShot to Applications"
    try:
        # Try to use a system font
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 24)
    except IOError:
        # Fallback to default if system font not found (e.g. on Linux runner)
        font = ImageFont.load_default()
    
    # Calculate text position (centered above arrow)
    text_bbox = draw.textbbox((0, 0), text, font=font)
    text_width = text_bbox[2] - text_bbox[0]
    text_x = start_x + (end_x - start_x - text_width) // 2
    text_y = icon_y - 40
    
    draw.text((text_x, text_y), text, fill=text_color, font=font)

    # Save
    img.save(output_path)
    print(f"Background saved to {output_path}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: generate_background.py <output_path>")
        sys.exit(1)
    
    create_background(sys.argv[1])
