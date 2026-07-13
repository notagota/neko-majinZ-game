using System;
using System.Drawing;
using System.Drawing.Imaging;
using System.IO;

// Asset della mappa "forest" (foresta di sequoie giganti):
//   bg3_sky.png         - cielo fisso a schermo (gradiente + sole)
//   bg3_ground.png      - tile 256x160 di sottobosco (muschio, aghi, radici)
//   forest_far.png      - silhouette lontana e nebbiosa della foresta (tile 512)
//   forest_mid.png      - sequoie di media distanza con varchi (tile 512)
//   forest_front.png    - fogliame/rami in primo piano che pendono dall'alto
//   sequoia_trunk.png   - fusto 128x640 dell'albero interattivo
//   sequoia_canopy.png  - chioma 384x300 dell'albero interattivo
// E la musica chiptune della mappa (stile BattleGen, loop perfetto):
//   battle_forest.wav   - Mi minore, 150 BPM, arpeggi tra i rami con eco
// Uso (PowerShell):
//   Add-Type -Path tools\ForestGen.cs -ReferencedAssemblies System.Drawing
//   [ForestGen]::Run("assets\bg"); [ForestGen]::Music("assets\music\battle_forest.wav")
public static class ForestGen
{
    // ---------------------------------------------------------------- utils

    static Color Lerp(Color a, Color b, float t)
    {
        if (t < 0) t = 0; if (t > 1) t = 1;
        return Color.FromArgb(
            (int)(a.A + (b.A - a.A) * t),
            (int)(a.R + (b.R - a.R) * t),
            (int)(a.G + (b.G - a.G) * t),
            (int)(a.B + (b.B - a.B) * t));
    }

    static Color Jit(Random rng, Color c, int n)
    {
        int d = rng.Next(-n, n + 1);
        return Color.FromArgb(c.A,
            Math.Max(0, Math.Min(255, c.R + d)),
            Math.Max(0, Math.Min(255, c.G + d)),
            Math.Max(0, Math.Min(255, c.B + d)));
    }

    // rumore periodico in x (periodo = w): somma di seni a numero d'onda intero,
    // cosi' il bordo destro combacia col sinistro e il tile e' senza cuciture
    static float PNoise(float x, float w, int k1, int k2, int k3, float p1, float p2, float p3)
    {
        double u = x / w * Math.PI * 2.0;
        return (float)(Math.Sin(u * k1 + p1) * 0.5 + Math.Sin(u * k2 + p2) * 0.33 + Math.Sin(u * k3 + p3) * 0.17);
    }

    // Profilo di una fila di chiome CONICHE (una guglia per sequoia): per ogni
    // x la quota piu' alta tra le guglie che lo coprono, avvolgendo il bordo
    // del tile (niente cuciture). Serve perche' viste dall'alto — volando sopra
    // le chiome — le fasce di sfondo non devono leggersi come dolci colline ma
    // come punte d'albero.
    static float[] CrownProfile(int w, Random rng, int n, float baseY,
                                float minH, float maxH, float minHW, float maxHW)
    {
        var top = new float[w];
        for (int x = 0; x < w; x++) top[x] = baseY;
        for (int i = 0; i < n; i++)
        {
            float cx = (i + 0.5f) * w / n + (float)(rng.NextDouble() - 0.5) * (w / (float)n) * 0.8f;
            float hh = minH + (float)rng.NextDouble() * (maxH - minH);
            float hw = minHW + (float)rng.NextDouble() * (maxHW - minHW);
            float apex = baseY - hh;
            for (int dx = (int)-hw; dx <= (int)hw; dx++)
            {
                int xx = (((int)cx + dx) % w + w) % w;
                float k = Math.Abs(dx) / hw;
                // fianchi appena concavi + dentellatura dei rami
                float y = apex + (baseY - apex) * (float)Math.Pow(k, 1.4)
                        + (float)Math.Abs(Math.Sin(dx * 0.9)) * 3.5f;
                if (y < top[xx]) top[xx] = y;
            }
        }
        return top;
    }

    // -------------------------------------------------------------- immagini

    public static void Run(string outDir)
    {
        Sky(Path.Combine(outDir, "bg3_sky.png"));
        Ground(Path.Combine(outDir, "bg3_ground.png"));
        FarForest(Path.Combine(outDir, "forest_far.png"));
        MidForest(Path.Combine(outDir, "forest_mid.png"));
        FrontFoliage(Path.Combine(outDir, "forest_front.png"));
        Trunk(Path.Combine(outDir, "sequoia_trunk.png"));
        Canopy(Path.Combine(outDir, "sequoia_canopy.png"));
        Console.WriteLine("FOREST BG DONE");
    }

    // cielo: azzurro intenso in alto, foschia calda verso l'orizzonte, sole
    static void Sky(string path)
    {
        int w = 480, h = 270;
        var top = Color.FromArgb(255, 62, 118, 196);
        var mid = Color.FromArgb(255, 126, 176, 224);
        var low = Color.FromArgb(255, 208, 226, 232);
        using (var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb))
        {
            for (int y = 0; y < h; y++)
            {
                float t = (float)y / h;
                var c = t < 0.55f ? Lerp(top, mid, t / 0.55f) : Lerp(mid, low, (t - 0.55f) / 0.45f);
                for (int x = 0; x < w; x++) bmp.SetPixel(x, y, c);
            }
            // sole morbido in alto a destra (dischi concentrici sempre piu' densi)
            int sx = 388, sy = 46;
            for (int r = 34; r >= 8; r -= 2)
            {
                int a = 12 + (34 - r) * 6;
                var sc = Color.FromArgb(Math.Min(235, a), 255, 250, 224);
                using (var g = Graphics.FromImage(bmp))
                using (var b = new SolidBrush(sc))
                    g.FillEllipse(b, sx - r, sy - r, r * 2, r * 2);
            }
            bmp.Save(path, ImageFormat.Png);
        }
    }

    // tile 256x160 del suolo: muschio in cima, poi terra con aghi e radici
    static void Ground(string path)
    {
        int w = 256, h = 160;
        var rng = new Random(777);
        var moss = Color.FromArgb(255, 74, 108, 52);
        var soil = Color.FromArgb(255, 92, 66, 44);
        var deep = Color.FromArgb(255, 48, 34, 24);
        using (var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb))
        {
            for (int y = 0; y < h; y++)
            {
                float t = (float)y / h;
                for (int x = 0; x < w; x++)
                {
                    // bordo erboso irregolare (periodico in x) nelle prime righe
                    float edge = 6f + 3f * PNoise(x, w, 3, 7, 11, 0.4f, 1.7f, 3.1f);
                    Color c;
                    if (y < edge) c = Jit(rng, moss, 10);
                    else if (y < edge + 8) c = Jit(rng, Lerp(moss, soil, (y - edge) / 8f), 8);
                    else c = Jit(rng, Lerp(soil, deep, (t - 0.1f) / 0.9f), 7);
                    bmp.SetPixel(x, y, c);
                }
            }
            // aghi di sequoia caduti: trattini rossicci vicino alla superficie
            for (int i = 0; i < 90; i++)
            {
                int px = rng.Next(0, w - 4), py = rng.Next(10, 40);
                var pc = Color.FromArgb(255, 128 + rng.Next(30), 76 + rng.Next(20), 40);
                for (int k = 0; k < 3; k++) bmp.SetPixel((px + k) % w, py, pc);
            }
            // radici affioranti: archi scuri orizzontali
            for (int i = 0; i < 7; i++)
            {
                int cx = rng.Next(0, w), cy = rng.Next(24, 90), len = 24 + rng.Next(30);
                var pc = Color.FromArgb(255, 66, 46, 30);
                for (int k = -len / 2; k <= len / 2; k++)
                {
                    int yy = cy - (int)(3.0 * Math.Cos(k * Math.PI / len));
                    int xx = ((cx + k) % w + w) % w;
                    bmp.SetPixel(xx, yy, pc);
                    bmp.SetPixel(xx, yy + 1, pc);
                }
            }
            // sassolini e funghetti sparsi
            for (int i = 0; i < 16; i++)
            {
                int px = rng.Next(2, w - 4), py = rng.Next(30, h - 8);
                var pc = rng.Next(2) == 0 ? Color.FromArgb(255, 120, 112, 100) : Color.FromArgb(255, 40, 30, 22);
                for (int yy = 0; yy < 2; yy++)
                    for (int xx = 0; xx < 3; xx++)
                        bmp.SetPixel(px + xx, py + yy, pc);
            }
            bmp.Save(path, ImageFormat.Png);
        }
    }

    // silhouette lontana 512x900: massa nebbiosa verde-azzurra, cima bombata,
    // trasparente sopra le chiome (il cielo del volo si vede attraverso)
    static void FarForest(string path)
    {
        int w = 512, h = 900;
        var rng = new Random(31);
        var hazeTop = Color.FromArgb(255, 96, 128, 124);   // chiome lontane
        var hazeLow = Color.FromArgb(255, 128, 156, 146);  // foschia verso terra
        using (var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb))
        {
            // due file di guglie FITTE e sottili: da lontano (e dall'alto) la
            // foresta e' una sega di punte, non un profilo di colline
            var backP = CrownProfile(w, rng, 28, 152f, 24f, 58f, 8f, 15f);
            var frontP = CrownProfile(w, rng, 21, 256f, 30f, 74f, 11f, 21f);
            for (int x = 0; x < w; x++)
            {
                float topBack = backP[x] + 4f * PNoise(x, w, 7, 13, 21, 0.7f, 2.1f, 4.4f);
                float topFront = frontP[x] + 5f * PNoise(x, w, 6, 11, 19, 1.9f, 0.3f, 5.2f);
                for (int y = 0; y < h; y++)
                {
                    float t = (float)y / h;
                    if (y >= topBack && y < topFront)
                        bmp.SetPixel(x, y, Jit(rng, Lerp(hazeTop, hazeLow, 0.35f), 4));
                    else if (y >= topFront)
                    {
                        var c = Lerp(Lerp(hazeTop, hazeLow, 0.15f), hazeLow, t);
                        // colonne piu' scure: tronchi lontani intravisti nella nebbia
                        float col = PNoise(x, w, 11, 17, 23, 0.2f, 2.8f, 1.1f);
                        if (col > 0.42f && y > topFront + 60) c = Lerp(c, Color.FromArgb(255, 70, 96, 92), 0.5f);
                        bmp.SetPixel(x, y, Jit(rng, c, 3));
                    }
                }
            }
            bmp.Save(path, ImageFormat.Png);
        }
    }

    // sequoie medie 512x820: chioma piena in alto e 3 fusti con varchi
    // trasparenti (da li' si vede la silhouette lontana)
    static void MidForest(string path)
    {
        int w = 512, h = 820;
        var rng = new Random(57);
        var leafD = Color.FromArgb(255, 38, 66, 44);
        var leafL = Color.FromArgb(255, 54, 88, 54);
        var barkD = Color.FromArgb(255, 58, 42, 34);
        var barkL = Color.FromArgb(255, 76, 54, 42);
        using (var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb))
        {
            // fascia di chiome: in cima le guglie delle sequoie (viste dal volo),
            // sotto il bordo sfrangiato da cui spuntano i fusti
            var crown = CrownProfile(w, rng, 11, 88f, 30f, 72f, 16f, 30f);
            for (int x = 0; x < w; x++)
            {
                float top = Math.Max(1f, crown[x] + 4f * PNoise(x, w, 5, 11, 17, 0.2f, 1.4f, 3.9f));
                float bot = 236f + 44f * PNoise(x, w, 2, 6, 10, 2.2f, 4.0f, 0.8f);
                for (int y = (int)top; y < bot; y++)
                {
                    float t = (y - top) / (bot - top);
                    bmp.SetPixel(x, y, Jit(rng, Lerp(leafL, leafD, t), 7));
                }
            }
            // tre fusti per tile, larghi e rastremati, con scanalature
            int[] cxs = { 84, 278, 452 };
            for (int i = 0; i < 3; i++)
            {
                for (int y = 190; y < h; y++)
                {
                    float t = (float)(y - 190) / (h - 190);
                    int hw = (int)(20 + 16 * t + (i == 1 ? 6 : 0));
                    for (int dx = -hw; dx <= hw; dx++)
                    {
                        int xx = ((cxs[i] + dx) % w + w) % w;
                        float sh = 1f - Math.Abs((float)dx / hw);           // ombra cilindrica
                        float groove = PNoise(dx + i * 37, hw * 2f, 5, 9, 3, 1f, 2f, 3f);
                        var c = Lerp(barkD, barkL, sh * 0.8f + (groove > 0.3f ? -0.15f : 0.06f));
                        bmp.SetPixel(xx, y, Jit(rng, c, 5));
                    }
                }
                // ciuffi di rami lungo il fusto
                for (int b = 0; b < 5; b++)
                {
                    int by = 260 + b * 96 + rng.Next(-14, 14);
                    int side = (b % 2 == 0) ? 1 : -1;
                    int bw = 30 + rng.Next(18);
                    for (int k = 0; k < 40; k++)
                    {
                        int px = cxs[i] + side * (16 + rng.Next(bw));
                        int py = by + rng.Next(-10, 12);
                        int xx = ((px % w) + w) % w;
                        if (py >= 0 && py < h) bmp.SetPixel(xx, py, Jit(rng, leafD, 8));
                    }
                }
            }
            bmp.Save(path, ImageFormat.Png);
        }
    }

    // primo piano 512x120: una frangia LEGGERA di fronde che pende dal bordo
    // alto dello schermo — corta e rada, per non coprire i lottatori.
    // ANCHE il bordo superiore e' frastagliato: quando la camera scavalca la
    // frangia (zoom out a terra, volo sopra le chiome) il profilo si deve
    // leggere come fogliame, mai come la riga di taglio della texture.
    static void FrontFoliage(string path)
    {
        int w = 512, h = 120;
        var rng = new Random(93);
        var dark = Color.FromArgb(255, 18, 34, 24);
        var mid = Color.FromArgb(255, 28, 48, 32);
        using (var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb))
        using (var g = Graphics.FromImage(bmp))
        {
            // fascia piena con profilo irregolare sia sopra che sotto
            for (int x = 0; x < w; x++)
            {
                float top = 9f + 7f * PNoise(x, w, 5, 12, 19, 2.3f, 0.6f, 4.1f);
                float bot = 30f + 9f * PNoise(x, w, 4, 9, 15, 0.9f, 2.6f, 5.0f);
                for (int y = (int)Math.Max(0f, top); y < bot; y++)
                    bmp.SetPixel(x, y, Jit(rng, dark, 6));
            }
            // creste tondeggianti che sbordano dal profilo superiore
            for (int c = 0; c < 26; c++)
            {
                int cx = rng.Next(0, w), cy = 8 + rng.Next(9), r = 3 + rng.Next(5);
                using (var b = new SolidBrush(Jit(rng, dark, 6)))
                {
                    g.FillEllipse(b, cx - r, cy - r, r * 2, r * 2);
                    // copia sul bordo opposto: il tile resta senza cuciture
                    if (cx < r * 2) g.FillEllipse(b, cx + w - r, cy - r, r * 2, r * 2);
                    if (cx > w - r * 2) g.FillEllipse(b, cx - w - r, cy - r, r * 2, r * 2);
                }
            }
            // pochi ciuffi d'ago corti (x periodiche sul tile)
            for (int c = 0; c < 14; c++)
            {
                float bx = (float)(c * (w / 14.0) + rng.Next(-10, 10));
                float depth = 26 + rng.Next(60);
                for (int k = 0; k < (int)depth / 6; k++)
                {
                    float t = k * 6f / depth;
                    float px = bx + (float)Math.Sin(t * 3.0 + c) * 7f;
                    float py = 24 + t * depth;
                    int r = (int)(7 * (1f - t * 0.55f));
                    int xx = (((int)px % w) + w) % w;
                    using (var b = new SolidBrush(Jit(rng, t < 0.4f ? dark : mid, 6)))
                    {
                        g.FillEllipse(b, xx - r, (int)py - r, r * 2, r * 2);
                        // copia sul bordo opposto per non tagliare i grappoli
                        if (xx < r * 2) g.FillEllipse(b, xx + w - r, (int)py - r, r * 2, r * 2);
                        if (xx > w - r * 2) g.FillEllipse(b, xx - w - r, (int)py - r, r * 2, r * 2);
                    }
                }
            }
            bmp.Save(path, ImageFormat.Png);
        }
    }

    // fusto 128x640 dell'albero interattivo: corteccia rossiccia scanalata,
    // rastremato in alto e svasato alla base (origine ai piedi dell'albero)
    static void Trunk(string path)
    {
        int w = 128, h = 640;
        var rng = new Random(12);
        var barkD = Color.FromArgb(255, 96, 52, 34);
        var barkM = Color.FromArgb(255, 134, 74, 46);
        var barkL = Color.FromArgb(255, 168, 102, 62);
        using (var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb))
        {
            for (int y = 0; y < h; y++)
            {
                float t = (float)y / h;                       // 0 in cima, 1 alla base
                float hw = 29f + 28f * (float)Math.Pow(t, 2.4);  // svasatura alla base
                for (int dx = (int)-hw; dx <= (int)hw; dx++)
                {
                    int x = 64 + dx;
                    if (x < 0 || x >= w) continue;
                    float sh = 1f - Math.Abs(dx / hw);        // luce cilindrica
                    // scanalature verticali della corteccia che serpeggiano appena
                    double gph = dx * 0.55 + Math.Sin(y * 0.020) * 2.6;
                    float groove = (float)Math.Sin(gph);
                    var c = Lerp(barkD, barkM, sh);
                    if (groove > 0.55f) c = Lerp(c, barkD, 0.55f);
                    else if (groove < -0.62f) c = Lerp(c, barkL, 0.4f);
                    // bande orizzontali tenui (crescita) e rumore
                    if ((y / 46) % 2 == 0) c = Lerp(c, barkD, 0.06f);
                    bmp.SetPixel(x, y, Jit(rng, c, 6));
                }
            }
            // qualche nodo scuro
            for (int i = 0; i < 6; i++)
            {
                int nx = 64 + rng.Next(-20, 20), ny = 60 + rng.Next(h - 120), nr = 3 + rng.Next(4);
                using (var g = Graphics.FromImage(bmp))
                using (var b = new SolidBrush(Color.FromArgb(255, 70, 38, 26)))
                    g.FillEllipse(b, nx - nr, ny - nr / 2, nr * 2, nr);
            }
            bmp.Save(path, ImageFormat.Png);
        }
    }

    // chioma 384x300: grappoli di fogliame sovrapposti, piu' chiari in alto
    static void Canopy(string path)
    {
        int w = 384, h = 300;
        var rng = new Random(29);
        var leafD = Color.FromArgb(255, 30, 74, 40);
        var leafM = Color.FromArgb(255, 44, 100, 50);
        var leafL = Color.FromArgb(255, 74, 132, 62);
        using (var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb))
        using (var g = Graphics.FromImage(bmp))
        {
            // dal basso (scuro) verso l'alto (chiaro): blob ellittici a piramide
            for (int layer = 0; layer < 3; layer++)
            {
                var col = layer == 0 ? leafD : (layer == 1 ? leafM : leafL);
                int n = 26 - layer * 6;
                for (int i = 0; i < n; i++)
                {
                    double a = rng.NextDouble() * Math.PI * 2.0;
                    double rr = rng.NextDouble();
                    // distribuzione a cono: base larga, cima stretta
                    float py = h * (0.82f - layer * 0.26f) + (float)(rng.NextDouble() - 0.5) * 46f;
                    float widthAt = (0.46f - 0.11f * layer) * w;
                    float px = w / 2f + (float)(Math.Cos(a) * rr) * widthAt;
                    int r = 26 + rng.Next(26 - layer * 6);
                    using (var b = new SolidBrush(Jit(rng, col, 8)))
                        g.FillEllipse(b, px - r, py - r * 0.8f, r * 2, r * 1.6f);
                }
            }
            bmp.Save(path, ImageFormat.Png);
        }
    }

    // ---------------------------------------------------------------- musica
    // Stessa "orchestra" di BattleGen: quadra+triangolo, kick/snare/hat,
    // 16 battute da 8 crome in loop perfetto.

    const int SR = 22050;

    static double Freq(int midi) { return 440.0 * Math.Pow(2.0, (midi - 69) / 12.0); }
    static double Square(double ph) { return (ph % 1.0) < 0.5 ? 1.0 : -1.0; }
    static double Triangle(double ph)
    {
        double p = ph % 1.0;
        return p < 0.5 ? 4.0 * p - 1.0 : 3.0 - 4.0 * p;
    }

    static void AddNote(double[] buf, double t0, double dur, int midi, double vol, bool square)
    {
        if (midi <= 0) return;
        double f = Freq(midi);
        int i0 = (int)(t0 * SR), n = (int)(dur * SR);
        for (int i = 0; i < n; i++)
        {
            int idx = i0 + i;
            if (idx < 0 || idx >= buf.Length) continue;
            double tt = (double)i / SR;
            double env = Math.Min(1.0, tt / 0.008) * Math.Exp(-2.2 * tt / dur);
            double s = square ? Square(f * tt) : Triangle(f * tt);
            buf[idx] += s * vol * env;
        }
    }

    static void AddHat(double[] buf, Random rng, double t0, double vol)
    {
        int i0 = (int)(t0 * SR), n = (int)(0.03 * SR);
        for (int i = 0; i < n; i++)
        {
            int idx = i0 + i;
            if (idx < 0 || idx >= buf.Length) continue;
            double env = 1.0 - (double)i / n;
            buf[idx] += (rng.NextDouble() * 2 - 1) * vol * env * env;
        }
    }

    static void AddKick(double[] buf, double t0, double vol)
    {
        int i0 = (int)(t0 * SR), n = (int)(0.09 * SR);
        double ph = 0.0;
        for (int i = 0; i < n; i++)
        {
            int idx = i0 + i;
            if (idx < 0 || idx >= buf.Length) continue;
            double tt = (double)i / n;
            ph += (110.0 - 70.0 * tt) / SR;
            buf[idx] += Math.Sin(ph * Math.PI * 2.0) * vol * (1.0 - tt);
        }
    }

    static void AddSnare(double[] buf, Random rng, double t0, double vol)
    {
        int i0 = (int)(t0 * SR), n = (int)(0.07 * SR);
        for (int i = 0; i < n; i++)
        {
            int idx = i0 + i;
            if (idx < 0 || idx >= buf.Length) continue;
            double tt = (double)i / n;
            double env = (1.0 - tt) * (1.0 - tt);
            buf[idx] += ((rng.NextDouble() * 2 - 1) * 0.75 + Triangle(180.0 * i / (double)SR) * 0.25) * vol * env;
        }
    }

    static void Echo(double[] buf, double delaySec, double fb)
    {
        int d = (int)(delaySec * SR);
        for (int i = 0; i < buf.Length; i++)
            buf[i] += buf[((i - d) % buf.Length + buf.Length) % buf.Length] * fb;
    }

    static void Save(string path, double[] buf)
    {
        using (var fs = new FileStream(path, FileMode.Create))
        using (var w = new BinaryWriter(fs))
        {
            int dataLen = buf.Length * 2;
            w.Write(new[] { 'R', 'I', 'F', 'F' }); w.Write(36 + dataLen);
            w.Write(new[] { 'W', 'A', 'V', 'E' });
            w.Write(new[] { 'f', 'm', 't', ' ' }); w.Write(16);
            w.Write((short)1); w.Write((short)1); w.Write(SR); w.Write(SR * 2);
            w.Write((short)2); w.Write((short)16);
            w.Write(new[] { 'd', 'a', 't', 'a' }); w.Write(dataLen);
            for (int i = 0; i < buf.Length; i++)
            {
                double v = Math.Max(-0.98, Math.Min(0.98, buf[i]));
                w.Write((short)(v * 32767));
            }
        }
        Console.WriteLine("FOREST MUSIC DONE " + path + " (" + buf.Length + " campioni)");
    }

    // Mi minore, 150 BPM: riff che "si arrampicano" come tra i rami,
    // dominante Si7 per la tensione, eco corta boschiva sul loop.
    public static void Music(string outPath)
    {
        int[][] fr = {
            new[] { 76, 0, 79, 81, 83, 81, 79, 76 },   // 0: riff Em
            new[] { 76, 79, 83, 79, 84, 83, 79, 76 },  // 1: Em che si apre
            new[] { 72, 0, 76, 79, 84, 79, 76, 72 },   // 2: arpeggio C
            new[] { 79, 0, 74, 71, 79, 74, 71, 67 },   // 3: discesa G
            new[] { 74, 0, 77, 81, 86, 81, 77, 74 },   // 4: arpeggio Dm-ish (modale)
            new[] { 71, 0, 75, 78, 81, 78, 75, 71 },   // 5: Si7 (attesa)
            new[] { 69, 0, 72, 76, 81, 76, 72, 69 },   // 6: arpeggio Am
            new[] { 64, 67, 69, 71, 72, 74, 76, 79 },  // 7: scala in salita
            new[] { 88, 86, 84, 83, 81, 79, 76, 75 },  // 8: discesa verso il Mi
        };
        int[] bars  = { 0, 1, 2, 2, 3, 3, 5, 5, 0, 1, 6, 6, 4, 4, 7, 8 };
        int[] roots = { 40, 40, 36, 36, 43, 43, 35, 35, 40, 40, 45, 45, 38, 38, 40, 35 };
        int[] bass  = { 0, 0, 12, 0, 0, 12, 0, 7 };

        double bpm = 150.0;
        double e8 = 60.0 / bpm / 2.0;
        int total = (int)Math.Round(128 * e8 * SR);
        var buf = new double[total];
        var rng = new Random(31);
        for (int bar = 0; bar < 16; bar++)
        {
            int[] riff = fr[bars[bar]];
            for (int i = 0; i < 8; i++)
            {
                double t0 = (bar * 8 + i) * e8;
                AddNote(buf, t0, e8 * 0.92, riff[i], 0.14, true);
                AddNote(buf, t0, e8 * 0.88, roots[bar] + bass[i], 0.21, false);
                if (i == 0 || i == 4) AddKick(buf, t0, 0.27);
                if (i == 2 || i == 6) AddSnare(buf, rng, t0, 0.14);
                AddHat(buf, rng, t0, i % 2 == 1 ? 0.05 : 0.028);
            }
        }
        Echo(buf, e8 * 3.0, 0.20);   // eco a 3 crome: aria tra gli alberi
        Save(outPath, buf);
    }
}
