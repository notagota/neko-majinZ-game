using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;

// Asset della mappa "lago" a partire da sshaohmarubg.gif (fondale spiaggia):
//   bg2_sky.png    - fascia cielo+mare usata come fondale fisso a schermo
//   bg2_ground.png - tile 256x360 di sabbia crepata per la riva (bordi raccordati)
// Genera anche assets/sfx/splash.wav (tuffo in acqua).
// Uso (PowerShell):
//   Add-Type -Path tools\LakeGen.cs
//   [LakeGen]::Run("sshaohmarubg.gif", "assets\bg"); [LakeGen]::Splash("assets\sfx\splash.wav")
public static class LakeGen
{
    static Color Lerp(Color a, Color b, float t)
    {
        if (t < 0) t = 0; if (t > 1) t = 1;
        return Color.FromArgb(255,
            (int)(a.R + (b.R - a.R) * t),
            (int)(a.G + (b.G - a.G) * t),
            (int)(a.B + (b.B - a.B) * t));
    }

    public static void Run(string gifPath, string outDir)
    {
        using (var src = new Bitmap(gifPath))
        {
            Console.WriteLine("GIF " + src.Width + "x" + src.Height);
            // fascia cielo + mare (fondale fisso)
            int skyH = Math.Min(305, src.Height);
            using (var sky = src.Clone(new Rectangle(0, 0, src.Width, skyH), PixelFormat.Format32bppArgb))
                sky.Save(Path.Combine(outDir, "bg2_sky.png"), ImageFormat.Png);

            // tile del terreno sabbioso: 256 di crop + estensione scura fino a 360
            int cw = 256, srcY = Math.Min(326, src.Height - 76), srcH = Math.Min(74, src.Height - srcY);
            var rng = new Random(4242);
            using (var tile = new Bitmap(cw, 360, PixelFormat.Format32bppArgb))
            {
                var deep = Color.FromArgb(255, 88, 76, 56);
                for (int y = 0; y < srcH; y++)
                    for (int x = 0; x < cw; x++)
                        tile.SetPixel(x, y, src.GetPixel(60 + x, srcY + y));
                // colore medio dell'ultima riga come base dell'estensione
                long ar = 0, ag = 0, ab = 0;
                for (int x = 0; x < cw; x++)
                {
                    var c0 = tile.GetPixel(x, srcH - 1);
                    ar += c0.R; ag += c0.G; ab += c0.B;
                }
                var baseC = Color.FromArgb(255, (int)(ar / cw), (int)(ag / cw), (int)(ab / cw));
                for (int y = srcH; y < 360; y++)
                {
                    float t = (float)(y - srcH) / (360 - srcH);
                    // raccordo morbido nelle prime righe verso il colore medio
                    float mix = Math.Min(1f, (y - srcH) / 14f);
                    for (int x = 0; x < cw; x++)
                    {
                        var top = mix < 1f ? Lerp(tile.GetPixel(x, srcH - 1), baseC, mix) : baseC;
                        var c = Lerp(top, deep, 0.2f + 0.8f * t);
                        int n = rng.Next(-7, 8);
                        c = Color.FromArgb(255,
                            Math.Max(0, Math.Min(255, c.R + n)),
                            Math.Max(0, Math.Min(255, c.G + n)),
                            Math.Max(0, Math.Min(255, c.B + n)));
                        tile.SetPixel(x, y, c);
                    }
                }
                // sassolini sparsi nella parte profonda
                for (int p = 0; p < 30; p++)
                {
                    int px = rng.Next(4, cw - 6), py = rng.Next(srcH + 10, 350);
                    var pc = rng.Next(2) == 0 ? Color.FromArgb(255, 132, 116, 88) : Color.FromArgb(255, 64, 54, 40);
                    for (int yy = 0; yy < 2; yy++)
                        for (int xx = 0; xx < 3; xx++)
                            tile.SetPixel(px + xx, py + yy, pc);
                }
                // il crop puo' catturare frange di mare in alto: sostituisce i
                // pixel bluastri delle prime righe con la sabbia sottostante
                for (int y = 0; y < 12; y++)
                    for (int x = 0; x < cw; x++)
                    {
                        var c = tile.GetPixel(x, y);
                        if (c.B > c.R + 14)
                            tile.SetPixel(x, y, tile.GetPixel(x, y + 14));
                    }
                // raccorda i bordi orizzontali per il tiling
                for (int y = 0; y < 360; y++)
                    for (int x = 0; x < 20; x++)
                    {
                        float t = 0.5f - 0.5f * ((float)x / 20);
                        var a = tile.GetPixel(x, y);
                        var b = tile.GetPixel(cw - 1 - x, y);
                        tile.SetPixel(x, y, Lerp(a, b, t));
                        tile.SetPixel(cw - 1 - x, y, Lerp(b, a, t));
                    }
                tile.Save(Path.Combine(outDir, "bg2_ground.png"), ImageFormat.Png);
            }
        }
        Console.WriteLine("LAKE BG DONE");
    }

    public static void Splash(string outPath)
    {
        const int SR = 22050;
        double dur = 0.5;
        int total = (int)(dur * SR);
        var buf = new double[total];
        var rng = new Random(11);
        double lp = 0;
        for (int i = 0; i < total; i++)
        {
            double t = (double)i / SR;
            // "plop" iniziale: sweep sinusoidale verso il basso
            double plop = 0;
            if (t < 0.09)
            {
                double f = 480 - 4200 * t;
                plop = Math.Sin(2 * Math.PI * f * t) * (1.0 - t / 0.09) * 0.55;
            }
            // scroscio: rumore filtrato con inviluppo a doppia gobba (impatto + goccioline)
            double env = Math.Exp(-7.0 * t) * 0.8 + (t > 0.10 ? Math.Exp(-9.0 * (t - 0.10)) * 0.35 : 0);
            double n = rng.NextDouble() * 2 - 1;
            lp += (n - lp) * 0.32;
            buf[i] = plop + lp * env;
        }
        using (var fs = new FileStream(outPath, FileMode.Create))
        using (var w = new BinaryWriter(fs))
        {
            int dataLen = total * 2;
            w.Write(new[] { 'R', 'I', 'F', 'F' }); w.Write(36 + dataLen);
            w.Write(new[] { 'W', 'A', 'V', 'E' });
            w.Write(new[] { 'f', 'm', 't', ' ' }); w.Write(16);
            w.Write((short)1); w.Write((short)1); w.Write(SR); w.Write(SR * 2);
            w.Write((short)2); w.Write((short)16);
            w.Write(new[] { 'd', 'a', 't', 'a' }); w.Write(dataLen);
            for (int i = 0; i < total; i++)
            {
                double v = Math.Max(-0.95, Math.Min(0.95, buf[i]));
                w.Write((short)(v * 32767));
            }
        }
        Console.WriteLine("SPLASH DONE");
    }
}
