using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;

public static class BgGen
{
    static Random Rng = new Random(20260711);

    static Color Lerp(Color a, Color b, float t)
    {
        if (t < 0) t = 0; if (t > 1) t = 1;
        return Color.FromArgb(255,
            (int)(a.R + (b.R - a.R) * t),
            (int)(a.G + (b.G - a.G) * t),
            (int)(a.B + (b.B - a.B) * t));
    }

    public static void Run(string outDir)
    {
        Directory.CreateDirectory(outDir);
        Sky(Path.Combine(outDir, "sky.png"));
        Clouds(Path.Combine(outDir, "clouds.png"));
        Mountains(Path.Combine(outDir, "mountains.png"));
        Mesa(Path.Combine(outDir, "mesa_0.png"), 150, 210, 12);
        Mesa(Path.Combine(outDir, "mesa_1.png"), 110, 150, 34);
        Ground(Path.Combine(outDir, "ground.png"));
        Console.WriteLine("BG DONE");
    }

    static void Sky(string path)
    {
        int w = 480, h = 270;
        var top = Color.FromArgb(46, 78, 168);
        var mid = Color.FromArgb(110, 165, 218);
        var hor = Color.FromArgb(226, 200, 158);
        using (var b = new Bitmap(w, h))
        {
            for (int y = 0; y < h; y++)
            {
                float t = (float)y / h;
                // posterize into bands
                t = (float)Math.Floor(t * 16) / 16f;
                Color c = t < 0.55f ? Lerp(top, mid, t / 0.55f) : Lerp(mid, hor, (t - 0.55f) / 0.45f);
                for (int x = 0; x < w; x++) b.SetPixel(x, y, c);
            }
            // sun with halo
            int sx = 372, sy = 52;
            for (int y = -26; y <= 26; y++)
            for (int x = -26; x <= 26; x++)
            {
                double d = Math.Sqrt(x * x + y * y);
                int px = sx + x, py = sy + y;
                if (px < 0 || py < 0 || px >= w || py >= h) continue;
                if (d < 13) b.SetPixel(px, py, Color.FromArgb(255, 252, 246, 214));
                else if (d < 17) b.SetPixel(px, py, Lerp(b.GetPixel(px, py), Color.FromArgb(250, 240, 200), 0.55f));
                else if (d < 24) b.SetPixel(px, py, Lerp(b.GetPixel(px, py), Color.FromArgb(240, 230, 190), 0.22f));
            }
            b.Save(path, ImageFormat.Png);
        }
    }

    static void Clouds(string path)
    {
        int w = 1280, h = 260;
        using (var b = new Bitmap(w, h, PixelFormat.Format32bppArgb))
        using (var g = Graphics.FromImage(b))
        {
            var shade = new SolidBrush(Color.FromArgb(235, 205, 216, 236));
            var white = new SolidBrush(Color.FromArgb(245, 250, 252, 255));
            for (int c = 0; c < 8; c++)
            {
                int cx = Rng.Next(40, w - 120), cy = Rng.Next(20, h - 60);
                int puffs = Rng.Next(5, 9);
                int cw = Rng.Next(50, 110);
                for (int p = 0; p < puffs; p++)
                {
                    int px = cx + Rng.Next(-cw / 2, cw / 2);
                    int py = cy + Rng.Next(-8, 10);
                    int rw = Rng.Next(24, 48), rh = Rng.Next(12, 20);
                    g.FillEllipse(shade, px - rw / 2, py - rh / 2 + 4, rw, rh);
                }
                for (int p = 0; p < puffs; p++)
                {
                    int px = cx + Rng.Next(-cw / 2, cw / 2);
                    int py = cy + Rng.Next(-10, 6);
                    int rw = Rng.Next(24, 46), rh = Rng.Next(12, 18);
                    g.FillEllipse(white, px - rw / 2, py - rh / 2, rw, rh);
                }
            }
            shade.Dispose(); white.Dispose();
            b.Save(path, ImageFormat.Png);
        }
    }

    static void Mountains(string path)
    {
        int w = 1280, h = 150;
        using (var b = new Bitmap(w, h, PixelFormat.Format32bppArgb))
        {
            // catena lontana: lavanda nebbiosa e chiara
            var far1 = Color.FromArgb(255, 168, 166, 202);
            var far2 = Color.FromArgb(255, 146, 145, 184);
            float rh = 85;
            for (int x = 0; x < w; x++)
            {
                rh += (float)(Rng.NextDouble() * 2 - 1) * 2.8f;
                if (Rng.Next(170) == 0) rh += Rng.Next(14, 34);
                if (rh < 38) rh = 38; if (rh > 132) rh = 132;
                int top = h - (int)rh;
                for (int y = Math.Max(0, top); y < h; y++)
                    b.SetPixel(x, y, (y - top) < 8 ? far1 : far2);
            }
            // colline vicine: ocra tenue
            var near1 = Color.FromArgb(255, 196, 164, 128);
            var near2 = Color.FromArgb(255, 176, 142, 108);
            rh = 42;
            for (int x = 0; x < w; x++)
            {
                rh += (float)(Rng.NextDouble() * 2 - 1) * 2.2f;
                if (Rng.Next(240) == 0) rh += Rng.Next(8, 22);
                if (rh < 16) rh = 16; if (rh > 72) rh = 72;
                int top = h - (int)rh;
                for (int y = Math.Max(0, top); y < h; y++)
                    b.SetPixel(x, y, (y - top) < 6 ? near1 : near2);
            }
            b.Save(path, ImageFormat.Png);
        }
    }

    static void Mesa(string path, int w, int h, int seedShift)
    {
        var rng = new Random(777 + seedShift);
        var band1 = Color.FromArgb(255, 198, 142, 90);
        var band2 = Color.FromArgb(255, 174, 118, 70);
        var dark = Color.FromArgb(255, 96, 62, 42);
        var top = Color.FromArgb(255, 152, 120, 88);
        var rim = Color.FromArgb(255, 232, 184, 124);
        using (var b = new Bitmap(w, h, PixelFormat.Format32bppArgb))
        {
            float topw = w * 0.62f, basew = w * 0.94f;
            for (int y = 6; y < h; y++)
            {
                float t = (float)(y - 6) / (h - 6);
                float ww = topw + (basew - topw) * t;
                ww += (float)Math.Sin(y * 0.35 + seedShift) * 4 + rng.Next(-2, 3);
                int x0 = (int)((w - ww) / 2), x1 = (int)((w + ww) / 2);
                for (int x = Math.Max(0, x0); x < Math.Min(w, x1); x++)
                {
                    // bande orizzontali sottili + variazione casuale (roccia, non legno)
                    float bandMix = 0.5f + 0.5f * (float)Math.Sin(y * 0.45 + seedShift);
                    Color c = Lerp(band1, band2, bandMix);
                    int n = rng.Next(-7, 8);
                    c = Color.FromArgb(255,
                        Math.Max(0, Math.Min(255, c.R + n)),
                        Math.Max(0, Math.Min(255, c.G + n)),
                        Math.Max(0, Math.Min(255, c.B + n)));
                    if (y % 17 == 0) c = Lerp(c, dark, 0.3f);               // seam sottile
                    if (x - x0 < 3 || y < 10) c = Lerp(c, rim, 0.45f);      // bordo sinistro illuminato
                    else if (x1 - x < 6) c = Lerp(c, dark, 0.45f);          // lato destro in ombra
                    if (y < 9) c = top;
                    b.SetPixel(x, y, c);
                }
                if (x0 >= 0 && x0 < w) b.SetPixel(x0, y, dark);
                if (x1 - 1 >= 0 && x1 - 1 < w) b.SetPixel(x1 - 1, y, dark);
            }
            // top outline
            for (int x = (int)((w - topw) / 2); x < (w + topw) / 2; x++)
                if (x >= 0 && x < w) b.SetPixel(x, 6, dark);
            // cracks
            for (int c = 0; c < 5; c++)
            {
                int cx = rng.Next(w / 4, w * 3 / 4), cy = rng.Next(20, h - 24);
                int len = rng.Next(8, 22);
                for (int i = 0; i < len; i++)
                {
                    if (cx >= 1 && cx < w - 1 && cy < h && b.GetPixel(cx, cy).A > 0)
                        b.SetPixel(cx, cy, dark);
                    cy += 1; cx += rng.Next(-1, 2);
                }
            }
            b.Save(path, ImageFormat.Png);
        }
    }

    static void Ground(string path)
    {
        int w = 256, h = 360;
        var rim = Color.FromArgb(255, 224, 180, 122);
        var dirtA = Color.FromArgb(255, 198, 146, 94);
        var deep = Color.FromArgb(255, 74, 46, 32);
        var crack = Color.FromArgb(255, 120, 84, 56);
        using (var b = new Bitmap(w, h))
        {
            for (int y = 0; y < h; y++)
            {
                Color baseC;
                if (y < 4) baseC = rim;
                else if (y < 90) baseC = Lerp(dirtA, Color.FromArgb(150, 104, 66), (y - 4) / 86f);
                else baseC = Lerp(Color.FromArgb(150, 104, 66), deep, (y - 90f) / (h - 90f));
                for (int x = 0; x < w; x++)
                {
                    int n = Rng.Next(-8, 9);
                    if (y < 2) n = Rng.Next(-4, 5);
                    var c = Color.FromArgb(255,
                        Math.Max(0, Math.Min(255, baseC.R + n)),
                        Math.Max(0, Math.Min(255, baseC.G + n)),
                        Math.Max(0, Math.Min(255, baseC.B + n)));
                    b.SetPixel(x, y, c);
                }
            }
            // cracks in top region (kept away from tile edges)
            for (int c = 0; c < 9; c++)
            {
                int cx = Rng.Next(10, w - 10), cy = Rng.Next(6, 70);
                int len = Rng.Next(10, 30);
                for (int i = 0; i < len; i++)
                {
                    if (cx >= 8 && cx < w - 8 && cy < 86) b.SetPixel(cx, cy, crack);
                    cy += Rng.Next(0, 2); cx += Rng.Next(-1, 2);
                }
            }
            // pebbles
            for (int p = 0; p < 40; p++)
            {
                int px = Rng.Next(4, w - 6), py = Rng.Next(8, 80);
                var pc = Rng.Next(2) == 0 ? Color.FromArgb(255, 226, 186, 140) : Color.FromArgb(255, 130, 92, 62);
                int r = Rng.Next(1, 3);
                for (int y = 0; y < r; y++)
                    for (int x = 0; x < r + 1; x++)
                        b.SetPixel(px + x, py + y, pc);
            }
            b.Save(path, ImageFormat.Png);
        }
    }
}
