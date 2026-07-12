using System;
using System.IO;

// Genera le musichette chiptune di battaglia (loop perfetto, mono 16 bit):
//   assets/music/battle_desert.wav — La minore, 160 BPM, riff martellante
//   assets/music/battle_lake.wav   — Re minore, 140 BPM, arpeggi con eco
// Uso (PowerShell):
//   Add-Type -Path tools\BattleGen.cs
//   [BattleGen]::Run("assets\music")
public static class BattleGen
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

    // cassa: seno che scivola da 110 a 40 Hz
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

    // rullante: rumore + corpo triangolare a 180 Hz
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
        Console.WriteLine("BATTLE MUSIC DONE " + path + " (" + buf.Length + " campioni)");
    }

    // Compone 16 battute da 8 crome: per ogni battuta un riff di 8 note
    // (indice in riffs) e una fondamentale di basso; ritorno il buffer.
    static double[] Compose(double bpm, int[][] riffs, int[] barRiff, int[] roots,
                            int[] bassPat, double melVol, double bassVol,
                            bool drums, int seed)
    {
        double e8 = 60.0 / bpm / 2.0;
        int total = (int)Math.Round(128 * e8 * SR);
        var buf = new double[total];
        var rng = new Random(seed);
        for (int bar = 0; bar < 16; bar++)
        {
            int[] riff = riffs[barRiff[bar]];
            for (int i = 0; i < 8; i++)
            {
                double t0 = (bar * 8 + i) * e8;
                AddNote(buf, t0, e8 * 0.92, riff[i], melVol, true);
                AddNote(buf, t0, e8 * 0.88, roots[bar] + bassPat[i], bassVol, false);
                if (drums)
                {
                    if (i == 0 || i == 4) AddKick(buf, t0, 0.30);
                    if (i == 2 || i == 6) AddSnare(buf, rng, t0, 0.16);
                    AddHat(buf, rng, t0, i % 2 == 1 ? 0.055 : 0.03);
                }
                else
                {
                    if (i == 0 || i == 4) AddKick(buf, t0, 0.22);
                    if (i == 6) AddSnare(buf, rng, t0, 0.10);
                    if (i % 2 == 1) AddHat(buf, rng, t0, 0.035);
                }
            }
        }
        return buf;
    }

    // eco corta con avvolgimento sulla coda del loop: da' aria "acquatica"
    // alla traccia del lago senza rompere il loop perfetto
    static void Echo(double[] buf, double delaySec, double fb)
    {
        int d = (int)(delaySec * SR);
        for (int i = 0; i < buf.Length; i++)
            buf[i] += buf[((i - d) % buf.Length + buf.Length) % buf.Length] * fb;
    }

    public static void Run(string outDir)
    {
        // ---------------- DESERTO: La minore, 160 BPM, incalzante ----------------
        int[][] dr = {
            new[] { 69, 0, 72, 74, 76, 74, 72, 69 },   // 0: riff Am
            new[] { 69, 0, 72, 74, 76, 77, 76, 74 },   // 1: riff Am variato
            new[] { 77, 0, 74, 72, 69, 72, 74, 77 },   // 2: riff F
            new[] { 77, 81, 77, 74, 72, 74, 77, 81 },  // 3: riff F variato
            new[] { 76, 0, 72, 76, 79, 76, 72, 76 },   // 4: riff C
            new[] { 68, 0, 71, 76, 75, 76, 71, 68 },   // 5: riff E (senso di attesa)
            new[] { 74, 0, 77, 74, 81, 77, 74, 71 },   // 6: riff Dm
            new[] { 69, 71, 72, 74, 76, 77, 79, 81 },  // 7: scala in salita
            new[] { 81, 79, 77, 76, 74, 72, 71, 68 },  // 8: discesa verso il Mi
        };
        int[] dBars  = { 0, 1, 2, 3, 4, 4, 5, 5, 0, 1, 2, 3, 6, 5, 7, 8 };
        int[] dRoots = { 45, 45, 41, 41, 48, 48, 40, 40, 45, 45, 41, 41, 38, 40, 45, 40 };
        int[] dBass  = { 0, 0, 12, 0, 0, 12, 0, 12 };
        var desert = Compose(160.0, dr, dBars, dRoots, dBass, 0.15, 0.22, true, 11);
        Save(Path.Combine(outDir, "battle_desert.wav"), desert);

        // ---------------- LAGO: Re minore, 140 BPM, arpeggi con eco ----------------
        int[][] lr = {
            new[] { 74, 77, 81, 77, 74, 77, 81, 86 },  // 0: arpeggio Dm
            new[] { 70, 74, 77, 82, 77, 74, 70, 74 },  // 1: arpeggio Bb
            new[] { 77, 72, 69, 72, 77, 81, 77, 72 },  // 2: arpeggio F
            new[] { 67, 72, 76, 72, 67, 72, 76, 79 },  // 3: arpeggio C
            new[] { 67, 70, 74, 70, 67, 70, 74, 79 },  // 4: arpeggio Gm
            new[] { 69, 73, 76, 73, 69, 73, 76, 81 },  // 5: arpeggio A (dominante)
            new[] { 74, 77, 81, 86, 81, 77, 74, 77 },  // 6: Dm che si apre in alto
            new[] { 86, 84, 81, 79, 77, 76, 74, 73 },  // 7: discesa che riporta al Re
        };
        int[] lBars  = { 0, 6, 1, 1, 2, 2, 3, 3, 0, 6, 1, 1, 4, 5, 6, 7 };
        int[] lRoots = { 38, 38, 46, 46, 41, 41, 36, 36, 38, 38, 46, 46, 43, 45, 38, 45 };
        int[] lBass  = { 0, 12, 0, 7, 0, 12, 7, 12 };
        var lake = Compose(140.0, lr, lBars, lRoots, lBass, 0.13, 0.20, false, 23);
        Echo(lake, 60.0 / 140.0 / 2.0 * 3.0, 0.28);   // eco a 3 crome
        Save(Path.Combine(outDir, "battle_lake.wav"), lake);
    }
}
