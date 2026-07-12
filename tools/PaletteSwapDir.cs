using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;

// Rigenera assets/sprites/z2 (CPU gialla) da assets/sprites/z1: applica a ogni
// PNG lo stesso hue shift blu->giallo usato da Extract.cs, mantenendo i nomi.
// Uso (PowerShell):
//   Add-Type -TypeDefinition (Get-Content tools\PaletteSwapDir.cs -Raw) -ReferencedAssemblies System.Drawing
//   [PaletteSwapDir]::Run("assets\sprites\z1", "assets\sprites\z2")
public static class PaletteSwapDir
{
    static Color Shift(Color c)
    {
        float h = c.GetHue(), s = c.GetSaturation(), l = c.GetBrightness();
        if (h >= 170 && h <= 285 && s > 0.10f)
        {
            float nh = 50 + (h - 210) * 0.35f;
            if (nh < 28) nh = 28; if (nh > 85) nh = 85;
            return FromHsl(c.A, nh, Math.Min(1f, s * 1.05f), Math.Min(1f, l * 1.08f));
        }
        return c;
    }

    static Color FromHsl(int a, float h, float s, float l)
    {
        float c = (1 - Math.Abs(2 * l - 1)) * s;
        float x = c * (1 - Math.Abs((h / 60f) % 2 - 1));
        float m = l - c / 2;
        float r = 0, g = 0, b = 0;
        if (h < 60) { r = c; g = x; }
        else if (h < 120) { r = x; g = c; }
        else if (h < 180) { g = c; b = x; }
        else if (h < 240) { g = x; b = c; }
        else if (h < 300) { r = x; b = c; }
        else { r = c; b = x; }
        return Color.FromArgb(a, (int)((r + m) * 255), (int)((g + m) * 255), (int)((b + m) * 255));
    }

    public static void Run(string srcDir, string dstDir)
    {
        Directory.CreateDirectory(dstDir);
        foreach (var f in Directory.GetFiles(srcDir, "*.png"))
        {
            using (var im = new Bitmap(f))
            using (var outB = new Bitmap(im.Width, im.Height, PixelFormat.Format32bppArgb))
            {
                for (int y = 0; y < im.Height; y++)
                    for (int x = 0; x < im.Width; x++)
                    {
                        var p = im.GetPixel(x, y);
                        if (p.A == 0) continue;
                        outB.SetPixel(x, y, Shift(p));
                    }
                outB.Save(Path.Combine(dstDir, Path.GetFileName(f)), ImageFormat.Png);
            }
        }
        Console.WriteLine("SWAP DONE");
    }
}
