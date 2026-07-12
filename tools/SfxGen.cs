using System;
using System.IO;

public static class SfxGen
{
    const int SR = 22050;
    static Random Rng = new Random(42);

    static void Save(string path, float[] s)
    {
        // normalize
        float max = 0.0001f;
        foreach (var v in s) if (Math.Abs(v) > max) max = Math.Abs(v);
        float g = 0.86f / max;
        using (var fs = new FileStream(path, FileMode.Create))
        using (var w = new BinaryWriter(fs))
        {
            int dataLen = s.Length * 2;
            w.Write(new[] { 'R', 'I', 'F', 'F' }); w.Write(36 + dataLen);
            w.Write(new[] { 'W', 'A', 'V', 'E' });
            w.Write(new[] { 'f', 'm', 't', ' ' }); w.Write(16);
            w.Write((short)1); w.Write((short)1); w.Write(SR); w.Write(SR * 2); w.Write((short)2); w.Write((short)16);
            w.Write(new[] { 'd', 'a', 't', 'a' }); w.Write(dataLen);
            foreach (var v in s)
            {
                float c = v * g; if (c > 1) c = 1; if (c < -1) c = -1;
                w.Write((short)(c * 32760));
            }
        }
        Console.WriteLine("sfx " + Path.GetFileName(path) + " " + (s.Length / (float)SR).ToString("0.00") + "s");
    }

    static float[] Buf(double sec) { return new float[(int)(SR * sec)]; }
    static float Noise() { return (float)(Rng.NextDouble() * 2 - 1); }
    static float Square(double ph) { return (ph % 1.0) < 0.5 ? 1f : -1f; }
    static float Saw(double ph) { return (float)((ph % 1.0) * 2 - 1); }

    static void Lowpass(float[] s, int passes)
    {
        for (int p = 0; p < passes; p++)
            for (int i = 1; i < s.Length; i++) s[i] = (s[i] + s[i - 1]) * 0.5f;
    }

    public static void Run(string outDir)
    {
        Directory.CreateDirectory(outDir);

        // hit: sharp noise burst + thump
        var s = Buf(0.10);
        for (int i = 0; i < s.Length; i++)
        {
            double t = (double)i / SR;
            s[i] = Noise() * (float)Math.Exp(-t * 38) + (float)(Math.Sin(2 * Math.PI * 155 * t) * Math.Exp(-t * 26)) * 0.8f;
        }
        Lowpass(s, 1); Save(Path.Combine(outDir, "hit.wav"), s);

        // kick: deeper
        s = Buf(0.14);
        for (int i = 0; i < s.Length; i++)
        {
            double t = (double)i / SR;
            s[i] = Noise() * (float)Math.Exp(-t * 26) * 0.8f + (float)(Math.Sin(2 * Math.PI * 95 * t) * Math.Exp(-t * 15));
        }
        Lowpass(s, 2); Save(Path.Combine(outDir, "kick.wav"), s);

        // blast: descending square pew
        s = Buf(0.24);
        double ph = 0;
        for (int i = 0; i < s.Length; i++)
        {
            double t = (double)i / SR;
            double f = 950 * Math.Pow(0.34, t / 0.24);
            ph += f / SR;
            s[i] = Square(ph) * (float)Math.Exp(-t * 11) * 0.6f + Noise() * (float)Math.Exp(-t * 30) * 0.3f;
        }
        Save(Path.Combine(outDir, "blast.wav"), s);

        // beam: long roaring swell
        s = Buf(1.35);
        ph = 0; double ph2 = 0;
        var n = Buf(1.35);
        for (int i = 0; i < n.Length; i++) n[i] = Noise();
        Lowpass(n, 3);
        for (int i = 0; i < s.Length; i++)
        {
            double t = (double)i / SR;
            double env = Math.Min(1.0, t / 0.09);
            if (t > 1.05) env *= Math.Max(0, 1 - (t - 1.05) / 0.30);
            double trem = 1 + 0.18 * Math.Sin(2 * Math.PI * 27 * t);
            ph += 172.0 / SR; ph2 += 229.0 / SR;
            s[i] = (float)((n[i] * 0.55 + Saw(ph) * 0.33 + Saw(ph2) * 0.2) * env * trem);
        }
        Save(Path.Combine(outDir, "beam.wav"), s);

        // charge: rising shimmer
        s = Buf(0.62);
        ph = 0;
        for (int i = 0; i < s.Length; i++)
        {
            double t = (double)i / SR;
            double f = 240 + (900 - 240) * Math.Pow(t / 0.62, 1.4) + Math.Sin(2 * Math.PI * 31 * t) * 22;
            ph += f / SR;
            double env = Math.Min(1.0, t / 0.05) * (0.5 + 0.5 * t / 0.62);
            s[i] = (float)(Math.Sin(2 * Math.PI * ph) * env * 0.6 + Square(ph * 0.5) * env * 0.12);
        }
        Save(Path.Combine(outDir, "charge.wav"), s);

        // dash: whoosh
        s = Buf(0.18);
        var n2 = Buf(0.18);
        for (int i = 0; i < n2.Length; i++) n2[i] = Noise();
        Lowpass(n2, 2);
        for (int i = 1; i < s.Length; i++)
        {
            double t = (double)i / SR;
            double env = Math.Sin(Math.PI * t / 0.18);
            s[i] = (n2[i] - n2[i - 1]) * 4f * (float)env + n2[i] * (float)env * 0.35f;
        }
        Save(Path.Combine(outDir, "dash.wav"), s);

        // guard: clank
        s = Buf(0.08);
        ph = 0;
        for (int i = 0; i < s.Length; i++)
        {
            double t = (double)i / SR;
            ph += 470.0 / SR;
            s[i] = Square(ph) * (float)Math.Exp(-t * 55) * 0.7f + Noise() * (float)Math.Exp(-t * 75) * 0.5f;
        }
        Save(Path.Combine(outDir, "guard.wav"), s);

        // ko: big boom
        s = Buf(0.60);
        ph = 0;
        for (int i = 0; i < s.Length; i++)
        {
            double t = (double)i / SR;
            double f = 130 * Math.Pow(0.32, t / 0.6);
            ph += f / SR;
            s[i] = (float)(Math.Sin(2 * Math.PI * ph) * Math.Exp(-t * 5.5)) + Noise() * (float)Math.Exp(-t * 16) * 0.55f;
        }
        Lowpass(s, 1); Save(Path.Combine(outDir, "ko.wav"), s);

        // bounce: low thud
        s = Buf(0.12);
        for (int i = 0; i < s.Length; i++)
        {
            double t = (double)i / SR;
            s[i] = (float)(Math.Sin(2 * Math.PI * 72 * t) * Math.Exp(-t * 18)) + Noise() * (float)Math.Exp(-t * 40) * 0.3f;
        }
        Lowpass(s, 2); Save(Path.Combine(outDir, "bounce.wav"), s);

        // round: gong-ish two tone
        s = Buf(0.34);
        ph = 0; ph2 = 0;
        for (int i = 0; i < s.Length; i++)
        {
            double t = (double)i / SR;
            double f1 = t < 0.16 ? 660 : 990;
            ph += f1 / SR;
            double loc = t < 0.16 ? t : t - 0.16;
            s[i] = Square(ph) * (float)Math.Exp(-loc * 14) * 0.6f;
        }
        Save(Path.Combine(outDir, "round.wav"), s);

        // select: blip
        s = Buf(0.08);
        ph = 0;
        for (int i = 0; i < s.Length; i++)
        {
            double t = (double)i / SR;
            ph += 880.0 / SR;
            s[i] = Square(ph) * (float)Math.Exp(-t * 30) * 0.6f;
        }
        Save(Path.Combine(outDir, "select.wav"), s);

        Console.WriteLine("SFX DONE");
    }
}
