with open('rgb332.pal', 'wb') as f:
    for i in range(256):
        r = i & 0b11100000
        g = i & 0b00011100
        b = i & 0b00000011
        r >>= 5
        g >>= 2

        r = int(r * 9)
        g = int(g * 9)
        b = int(b * 21)
        f.write(bytes([r, g, b]))
