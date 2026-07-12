using System;
using System.IO;

// Genera assets/music/menu.wav: musichetta chiptune allegra in Do maggiore,
// 132 BPM, 8 battute in loop perfetto (melodia square, basso triangle, hat noise).
// Uso (PowerShell):
//   Add-Type -Path tools\MusicGen.cs
//   [MusicGen]::Run("assets\music\menu.wav")
public static class MusicGen
{
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
            double ph = f * tt;
            double s = square ? Square(ph) : Triangle(ph);
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

    public static void Run(string outPath)
    {
        double e8 = 60.0 / 132.0 / 2.0;           // durata di una croma
        int total = (int)(64 * e8 * SR);           // 8 battute da 8 crome
        var buf = new double[total];
        var rng = new Random(7);

        // melodia (croma per croma, 0 = pausa) — prog.: C G Am F / C G F G
        int[] mel = {
            76,79,84,79, 76,72,76,79,   74,79,83,79, 74,71,74,79,
            72,76,81,76, 72,69,72,76,   72,77,81,77, 74,77,81,84,
            84,83,84,79, 76,79,84,88,   86,83,79,83, 86,83,79,74,
            84,81,77,81, 84,81,84,81,   83,79,83,84, 86, 0,83, 0,
        };
        // basso: fondamentale per battuta, disegno con salti d'ottava
        int[] roots = { 48, 43, 45, 41, 48, 43, 41, 43 };
        int[] bpat = { 0, 12, 0, 12, 0, 12, 7, 12 };

        for (int i = 0; i < 64; i++)
        {
            double t0 = i * e8;
            AddNote(buf, t0, e8 * 0.92, mel[i], 0.16, true);
            AddNote(buf, t0, e8 * 0.85, roots[i / 8] + bpat[i % 8], 0.22, false);
            if (i % 2 == 1) AddHat(buf, rng, t0, 0.05);
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
                double v = Math.Max(-0.98, Math.Min(0.98, buf[i]));
                w.Write((short)(v * 32767));
            }
        }
        Console.WriteLine("MUSIC DONE " + total + " campioni");
    }
}
